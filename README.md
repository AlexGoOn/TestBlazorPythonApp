# TestBlazorPythonApp

Blazor Web App (.NET 10), Python FastAPI service, and SQL Server.

```text
Browser -> Blazor server -> SQL Server
                        -> Python HTTP service -> the same SQL Server
```

Both applications save and read notes in the same database. SQL access stays on
the servers, not in the browser.

## Local development on Windows

Prerequisites: .NET 10 SDK, Python 3.12 or newer (64-bit), a running SQL Server
Developer/Express instance, `sqlcmd`, and Microsoft ODBC Driver 18 for SQL Server
(64-bit). Browser tests use Microsoft Edge.

Open this folder as the repository/workspace root. Restore dependencies:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r .\src\backend\requirements.txt -r .\tests\requirements.txt
dotnet restore .\src\blazor\BlazorApp.csproj
```

In the first PowerShell terminal:

```powershell
. .\scripts\configure-local.ps1
.\.venv\Scripts\python.exe -m uvicorn web_app:app --app-dir .\src\backend --host 127.0.0.1 --port 3200
```

In a second terminal:

```powershell
. .\scripts\configure-local.ps1
dotnet run --project .\src\blazor --launch-profile http
```

Open **http://localhost:5080**. Python API documentation is at
**http://127.0.0.1:3200/docs**.

The leading `. ` configures the current terminal. The script uses Windows
authentication and creates `BlazorLab` and `dbo.Notes` only if missing. It does not
delete existing notes or install/start/stop SQL Server. For a named instance, use
`. .\scripts\configure-local.ps1 -Server '.\SQLEXPRESS'` in each terminal.

With both services running, use a third terminal:

```powershell
. .\scripts\configure-local.ps1
.\.venv\Scripts\python.exe .\tests\test_local_stack.py -v
```

Tests cover both writers, cross-service reads, SQL persistence, input validation,
and browser buttons. They remove only their own notes. VS Code tasks provide
equivalent startup and test commands.

Press **Ctrl+C** in each application terminal to stop the services. SQL Server
remains running.

For a different database/authentication setup, configure `ConnectionStrings__Sql`
for .NET, `SQL_CONNECTION_STRING` (ODBC format) for Python, and optionally
`PythonService__BaseUrl`. Initialize the same table; do not run
`configure-local.ps1`, which selects local Windows authentication.

## Azure

See [personal Azure setup](AZURE-PERSONAL-SETUP.md). This repository contains no
deployment workflow or infrastructure from the original React/Functions
template. Publishing to GitHub does not deploy the application to Azure.

Cloud deployment still requires the .NET managed-identity Azure extension,
verification of the Python runtime's system ODBC Driver 18, and deployment/authentication
configuration. The current demo is unauthenticated and must remain local until
cloud access controls are configured. .NET integration API endpoints are enabled
only in Development.

## Initial GitHub upload

Run from this folder. If Git is not initialized yet, first run `git init -b dev`.
Then, after reviewing the files:

```powershell
git add .
git commit -m "Add Blazor and Python application"
git remote add origin https://github.com/AlexGoOn/TestBlazorPythonApp.git
git push -u origin dev
```

These commands assume the remote is not configured yet and its `dev` branch has
no conflicting history. Do not force-push over existing work.
