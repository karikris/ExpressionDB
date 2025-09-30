# run_etl.ps1 — Wait for Docker Postgres to be ready, then run the ETL.
param(
  [int]$TimeoutSeconds = 600,  # give it more headroom on first boot
  [string]$RscriptPath = "C:\Program Files\R\R-4.5.1\bin\Rscript.exe",
  [string]$ProjectDir  = "C:\ExpressionDB",
  [string]$Container   = "expressiondb-pg",
  [string]$ScriptFile  = "geo_leaf_to_expressiondb.R"
)

$ErrorActionPreference = "Stop"
Set-Location $ProjectDir

# 1) Ensure DB container is up
docker compose up -d | Out-Null

# 2) Wait on a real readiness check (inside container), not the health flag
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
# 3) Run the ETL
& "$RscriptPath" --vanilla $ScriptFile