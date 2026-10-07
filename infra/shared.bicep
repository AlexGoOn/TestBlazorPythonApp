param sharedSubscriptionId string
param sharedResourceGroupName string
param monitoringSubscriptionId string
param monitoringResourceGroupName string
param appInsightsName string
param vnetName string
param integrationSubnetName string
param sqlServerName string
param sqlDatabaseName string
param keyVaultName string

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(sharedSubscriptionId, sharedResourceGroupName)
}
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: vnet
  name: integrationSubnetName
}
resource sqlServer 'Microsoft.Sql/servers@2023-08-01' existing = {
  name: sqlServerName
  scope: resourceGroup(sharedSubscriptionId, sharedResourceGroupName)
}
resource database 'Microsoft.Sql/servers/databases@2023-08-01' existing = {
  parent: sqlServer
  name: sqlDatabaseName
}
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
  scope: resourceGroup(sharedSubscriptionId, sharedResourceGroupName)
}
resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
  scope: resourceGroup(monitoringSubscriptionId, monitoringResourceGroupName)
}

output subnetResourceId string = subnet.id
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseId string = database.id
output keyVaultUri string = keyVault.properties.vaultUri
output appInsightsConnectionString string = appInsights.properties.ConnectionString
