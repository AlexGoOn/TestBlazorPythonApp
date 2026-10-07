param(
    [Parameter(Mandatory)]
    [ValidateSet('backend', 'frontend')]
    [string] $Service
)

. (Join-Path $PSScriptRoot 'common.ps1')
Import-AzdEnvironment
Assert-AzureContext

$name = if ($Service -eq 'backend') { $env:AZURE_BACKEND_NAME } else { $env:AZURE_FRONTEND_NAME }
if ([string]::IsNullOrWhiteSpace($name)) { throw "No Web App name is available for '$Service'." }
$siteId = "/subscriptions/$env:AZURE_SUBSCRIPTION_ID/resourceGroups/$env:AZURE_RESOURCE_GROUP/providers/Microsoft.Web/sites/$name"
$uri = "https://management.azure.com$siteId/containerlogs?api-version=2024-04-01"
$path = [System.IO.Path]::GetTempFileName()
try {
    Write-Host "Startup logs for $name (last 200 lines; not a runtime health check):"
    az rest --method post --url $uri --output-file $path --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "Cannot retrieve startup logs for '$name' through the Azure management API." }
    if ((Get-Item -LiteralPath $path).Length -eq 0) {
        Write-Warning "Azure returned no startup logs for '$name'. Check App Service Log stream in the Portal."
    } else {
        Get-Content -LiteralPath $path -Tail 200
    }
} finally {
    Remove-Item -LiteralPath $path
}
