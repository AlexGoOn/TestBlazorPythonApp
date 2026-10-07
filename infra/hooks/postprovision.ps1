. (Join-Path $PSScriptRoot 'common.ps1')
Import-AzdEnvironment
Assert-AzureContext

$siteId = "/subscriptions/$env:AZURE_SUBSCRIPTION_ID/resourceGroups/$env:AZURE_RESOURCE_GROUP/providers/Microsoft.Web/sites/$env:AZURE_FRONTEND_NAME"
$uri = "https://management.azure.com$siteId/config/configreferences/appsettings/list?api-version=2024-04-01"
$resolved = $false
for ($attempt = 1; $attempt -le 12; $attempt++) {
    $references = Invoke-AzureJson -Arguments @('rest', '--method', 'post', '--url', $uri)
    $reference = $references.properties.MICROSOFT_PROVIDER_AUTHENTICATION_SECRET
    if ($reference.status -eq 'Resolved') {
        $resolved = $true
        break
    }
    Write-Host "Waiting for the Easy Auth Key Vault reference: $($reference.status) ($attempt/12)."
    if ($attempt -lt 12) { Start-Sleep -Seconds 10 }
}
if (-not $resolved) {
    throw 'Easy Auth secret was not resolved. Check the secret, Key Vault Secrets User assignment, reference identity and vault network access.'
}
Write-Host "Entra app $env:ENTRA_CLIENT_ID must contain this Web redirect URI: $env:ENTRA_CALLBACK_URL"
Write-Host 'No Microsoft Graph write permission is used; the registration and its secret are administrator-managed.'
