param(
    [Parameter(Mandatory)]
    [string] $ConfigPath,
    [switch] $GitHubActions
)

$ErrorActionPreference = 'Stop'
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$required = @(
    'APP_ID', 'AZURE_ENV_NAME', 'AZURE_SUBSCRIPTION_ID', 'AZURE_TENANT_ID',
    'AZURE_LOCATION', 'AZURE_RESOURCE_GROUP', 'VNET_NAME', 'SQL_SERVER_NAME',
    'SQL_DATABASE_NAME', 'KEY_VAULT_NAME', 'ENTRA_CLIENT_ID', 'ENTRA_SECRET_NAME',
    'APP_SERVICE_PLAN_NAME'
)
$allowed = $required + @(
    'AZURE_RESOURCE_NAME_SUFFIX', 'SHARED_SUBSCRIPTION_ID', 'SHARED_RESOURCE_GROUP',
    'MONITORING_SUBSCRIPTION_ID', 'MONITORING_RESOURCE_GROUP', 'APP_INSIGHTS_NAME',
    'INTEGRATION_SUBNET_NAME', 'APP_SERVICE_PLAN_SKU', 'PYTHON_VERSION'
)
foreach ($name in $required) {
    if ([string]::IsNullOrWhiteSpace($config.$name)) {
        throw "Missing configuration value: $name"
    }
}
foreach ($property in $config.PSObject.Properties) {
    if ($property.Name -notin $allowed -or $property.Value -isnot [string] -or
        $property.Value -match "[`r`n]") {
        throw "Unknown or invalid configuration value: $($property.Name)"
    }
}
foreach ($name in @('AZURE_SUBSCRIPTION_ID', 'AZURE_TENANT_ID', 'ENTRA_CLIENT_ID',
    'SHARED_SUBSCRIPTION_ID', 'MONITORING_SUBSCRIPTION_ID')) {
    if ($config.PSObject.Properties.Name -contains $name) {
        $parsed = [guid]::Empty
        if (-not [guid]::TryParse($config.$name, [ref] $parsed) -or $parsed -eq [guid]::Empty) {
            throw "$name must be a nonempty GUID, not a placeholder."
        }
    }
}
if ($config.APP_ID -notmatch '^[a-z][a-z0-9-]{0,15}$' -or
    $config.AZURE_ENV_NAME -notin @("$($config.APP_ID)-dev", "$($config.APP_ID)-prod")) {
    throw 'Use a lowercase APP_ID and AZURE_ENV_NAME=<APP_ID>-dev or <APP_ID>-prod.'
}
if ($config.AZURE_RESOURCE_NAME_SUFFIX -and
    $config.AZURE_RESOURCE_NAME_SUFFIX -notmatch '^[a-z0-9]{1,16}$') {
    throw 'AZURE_RESOURCE_NAME_SUFFIX must contain 1-16 lowercase letters/digits.'
}
if ($GitHubActions) {
    if (-not $env:GITHUB_ENV -or -not $env:AZURE_CLIENT_ID) {
        throw 'GitHub Actions requires GITHUB_ENV and AZURE_CLIENT_ID.'
    }
    $suffix = if ($env:GITHUB_REF_NAME -eq 'main') { 'prod' } else { 'dev' }
    if ($env:GITHUB_REF_NAME -notin @('dev', 'main') -or
        $config.AZURE_ENV_NAME -ne "$($config.APP_ID)-$suffix") {
        throw 'The selected configuration does not match the dev/main deployment branch.'
    }
    foreach ($name in @('AZURE_SUBSCRIPTION_ID', 'AZURE_TENANT_ID')) {
        if ([Environment]::GetEnvironmentVariable($name) -ne $config.$name) {
            throw "$name in configuration does not match the selected GitHub secret."
        }
    }
}

$defaults = @{
    AZURE_RESOURCE_NAME_SUFFIX = ''
    SHARED_SUBSCRIPTION_ID = $config.AZURE_SUBSCRIPTION_ID
    SHARED_RESOURCE_GROUP = 'rg-shared'
    MONITORING_SUBSCRIPTION_ID = $config.AZURE_SUBSCRIPTION_ID
    MONITORING_RESOURCE_GROUP = 'rg-dx-monitoring'
    APP_INSIGHTS_NAME = 'appi-dx-core'
    INTEGRATION_SUBNET_NAME = 'snet-webapps'
    APP_SERVICE_PLAN_SKU = 'B1'
    PYTHON_VERSION = '3.13'
}
foreach ($property in $config.PSObject.Properties) {
    $defaults[$property.Name] = $property.Value
}
Set-Location (Split-Path $PSScriptRoot -Parent)
if (Test-Path -LiteralPath ".azure\$($config.AZURE_ENV_NAME)\.env") {
    azd env select $config.AZURE_ENV_NAME
} else {
    azd env new $config.AZURE_ENV_NAME --subscription $config.AZURE_SUBSCRIPTION_ID `
        --location $config.AZURE_LOCATION --no-prompt
}
if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize the azd environment.' }
foreach ($name in ($defaults.Keys | Sort-Object)) {
    $value = [string] $defaults[$name]
    azd env set $name $value
    if ($LASTEXITCODE -ne 0) { throw "Cannot set azd configuration: $name" }
    [Environment]::SetEnvironmentVariable($name, $value, 'Process')
    if ($GitHubActions) {
        "$name=$value" | Out-File -LiteralPath $env:GITHUB_ENV -Append -Encoding utf8
    }
}
Write-Host "Configured $($config.AZURE_ENV_NAME) in subscription $($config.AZURE_SUBSCRIPTION_ID). No Azure resources were changed."
