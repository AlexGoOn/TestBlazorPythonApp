. (Join-Path $PSScriptRoot 'common.ps1')
Import-AzdEnvironment
Assert-AzureContext

$null = Invoke-AzureJson -Arguments @(
    'group', 'show', '--name', $env:AZURE_RESOURCE_GROUP,
    '--subscription', $env:AZURE_SUBSCRIPTION_ID
)
$subnet = Invoke-AzureJson -Arguments @(
    'network', 'vnet', 'subnet', 'show', '--resource-group', $env:SHARED_RESOURCE_GROUP,
    '--vnet-name', $env:VNET_NAME, '--name', $env:INTEGRATION_SUBNET_NAME,
    '--subscription', $env:SHARED_SUBSCRIPTION_ID
)
if ('Microsoft.Web/serverFarms' -notin $subnet.delegations.serviceName -or
    'Microsoft.Web' -notin $subnet.serviceEndpoints.service) {
    throw 'The integration subnet needs Microsoft.Web/serverFarms delegation and the Microsoft.Web service endpoint.'
}
$vnet = Invoke-AzureJson -Arguments @(
    'network', 'vnet', 'show', '--resource-group', $env:SHARED_RESOURCE_GROUP,
    '--name', $env:VNET_NAME, '--subscription', $env:SHARED_SUBSCRIPTION_ID
)
if ($vnet.location -ne $env:AZURE_LOCATION) {
    throw 'The VNet and both Web Apps must use the same Azure region.'
}
$server = Invoke-AzureJson -Arguments @(
    'sql', 'server', 'show', '--resource-group', $env:SHARED_RESOURCE_GROUP,
    '--name', $env:SQL_SERVER_NAME, '--subscription', $env:SHARED_SUBSCRIPTION_ID
)
if ($server.publicNetworkAccess -ne 'Disabled') {
    throw 'Disable SQL public network access after preparing the private endpoint and SQL users.'
}
$null = Invoke-AzureJson -Arguments @(
    'sql', 'db', 'show', '--resource-group', $env:SHARED_RESOURCE_GROUP,
    '--server', $env:SQL_SERVER_NAME, '--name', $env:SQL_DATABASE_NAME,
    '--subscription', $env:SHARED_SUBSCRIPTION_ID
)
Write-Host 'Shared-resource prerequisites verified. SQL users, DNS, Key Vault access and the Entra Web callback must already be prepared by an administrator.'
