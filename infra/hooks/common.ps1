$ErrorActionPreference = 'Stop'

function Import-AzdEnvironment {
    $values = azd env get-values --output json
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read the azd environment.' }
    $values = $values | ConvertFrom-Json
    foreach ($property in $values.PSObject.Properties) {
        [Environment]::SetEnvironmentVariable($property.Name, [string] $property.Value, 'Process')
    }
}

function Invoke-AzureJson {
    param([Parameter(Mandatory)] [string[]] $Arguments)
    $result = & az @Arguments --output json --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed: az $($Arguments -join ' ')" }
    return ($result | ConvertFrom-Json)
}

function Assert-AzureContext {
    $account = Invoke-AzureJson -Arguments @('account', 'show')
    if ($account.id -ne $env:AZURE_SUBSCRIPTION_ID -or $account.tenantId -ne $env:AZURE_TENANT_ID) {
        throw 'Azure CLI subscription/tenant differs from the configured azd environment. Log in to the intended tenant and run az account set before deploying.'
    }
}
