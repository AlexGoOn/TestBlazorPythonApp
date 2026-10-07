param(
    [ValidateNotNullOrEmpty()]
    [string] $Server = 'localhost'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    throw 'Install SQL Server command-line tools (sqlcmd), then run this script again.'
}

if (-not (Get-OdbcDriver -Name 'ODBC Driver 18 for SQL Server' -Platform '64-bit' -ErrorAction SilentlyContinue)) {
    throw 'Install the 64-bit Microsoft ODBC Driver 18 for SQL Server, then run this script again.'
}

sqlcmd -S $Server -E -C -l 5 -b -i (Join-Path $root 'database\init.sql')
if ($LASTEXITCODE -ne 0) {
    throw "Cannot initialize BlazorLab on '$Server'. Check that SQL Server is running and your Windows account can create the database and table."
}

$env:ConnectionStrings__Sql = "Server=$Server;Database=BlazorLab;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Connect Timeout=5"
$env:SQL_CONNECTION_STRING = "Driver={ODBC Driver 18 for SQL Server};Server=$Server;Database=BlazorLab;Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes"
$env:PythonService__BaseUrl = 'http://127.0.0.1:3200/'

Write-Host "SQL Server '$Server' is ready. BlazorLab uses your Windows account; no SQL password is required."
Write-Host 'Connection settings are configured for this PowerShell session.'
