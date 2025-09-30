# C:\ExpressionDB\run_etl.ps1
# Wait for Docker Postgres to be ready, load .Renviron into env, then run the ETL.
param(
  [int]$TimeoutSeconds = 600,
  [string]$RscriptPath = "C:\Program Files\R\R-4.5.1\bin\Rscript.exe",
  [string]$ProjectDir  = "C:\ExpressionDB",
  [string]$Container   = "expressiondb-pg",
  [string]$ScriptFile  = "geo_leaf_to_expressiondb.R"
)

$ErrorActionPreference = "Stop"
Set-Location $ProjectDir

# --- Load .Renviron in the project dir into current process env (so Rscript sees it) ---
$envFile = Join-Path $ProjectDir ".Renviron"
if (Test-Path $envFile) {
  Get-Content $envFile |
    Where-Object { $_ -match '^\s*[^#;]\S' } |      # skip blank/comments
    ForEach-Object {
      $pair = $_ -split '=', 2
      if ($pair.Count -eq 2) {
        $k = $pair[0].Trim()
        $v = $pair[1].Trim()
        if ($k) {
          # Remove surrounding quotes if present
          if ($v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Trim('"') }
          if ($v.StartsWith("'") -and $v.EndsWith("'")) { $v = $v.Trim("'") }
          [System.Environment]::SetEnvironmentVariable($k, $v, "Process")
        }
      }
    }
}

# Optional: also set libpq standard names so any libpq client can see them
if ($env:DB_HOST)      { $env:PGHOST     = $env:DB_HOST }
if ($env:DB_PORT)      { $env:PGPORT     = $env:DB_PORT }
if ($env:DB_USER)      { $env:PGUSER     = $env:DB_USER }
if ($env:DB_PASSWORD)  { $env:PGPASSWORD = $env:DB_PASSWORD }
if ($env:DB_NAME)      { $env:PGDATABASE = $env:DB_NAME }

# 1) Ensure DB container is up
docker compose up -d | Out-Null

# 2) Wait on pg_isready inside the container
Write-Host "Waiting for Postgres in '$Container' to accept connections..."
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$ready = $false
while ((Get-Date) -lt $deadline) {
  docker exec $Container bash -lc 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' | Out-Null
  if ($LASTEXITCODE -eq 0) { $ready = $true; break }
  Start-Sleep -Seconds 2
}
if (-not $ready) {
  Write-Warning "Postgres not ready after $TimeoutSeconds seconds. Recent logs:"
  docker logs --tail=200 $Container
  throw "Database did not become ready in time."
}

Write-Host "Postgres is ready. Launching ETL..."
& "$RscriptPath" --vanilla $ScriptFile