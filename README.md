# ExpressionDB

In this project we will create a local postgres database for storing Expression data
from leaf samples in plants. Several API calls will be made to various databases to 
retrieve datasets of interest.

Local dev environment:
- Python: 3.13 (primary) and 3.9 (legacy)
- Postgres: Docker (ports: 5432:5432)
- VS Code: Python / Jupyter / Docker / GitHub Actions extensions

## Quick start
```bash
# create envs 
uv venv -p 3.13 .venv
uv venv -p 3.9  .venv39
# activate and install deps as needed