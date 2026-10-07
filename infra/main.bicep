targetScope = 'resourceGroup'

@minLength(1)
param environmentName string
@minLength(1)
param location string
@minLength(1)
@maxLength(16)
param appId string = 'template'
param resourceNameSuffix string = ''
param sharedSubscriptionId string = subscription().subscriptionId
param sharedResourceGroupName string = 'rg-shared'
param monitoringSubscriptionId string = subscription().subscriptionId
param monitoringResourceGroupName string = 'rg-dx-monitoring'
param appInsightsName string = 'appi-dx-core'
param vnetName string
param integrationSubnetName string = 'snet-webapps'
param sqlServerName string
param sqlDatabaseName string
param keyVaultName string
@minLength(36)
@maxLength(36)
param entraClientId string
param entraSecretName string = '${environmentName}-entra-client-secret'
param appServicePlanName string = 'asp-${environmentName}'
param appServicePlanSku string = 'B1'
@allowed(['3.12', '3.13'])
param pythonVersion string = '3.13'

var suffix = endsWith(environmentName, '-prod') ? 'prod' : 'dev'
var uniqueSuffix = empty(resourceNameSuffix) ? '' : '-${resourceNameSuffix}'
var tags = { 'azd-env-name': environmentName }
var frontendName = 'app-${appId}${uniqueSuffix}-${suffix}'
var backendName = 'app-${appId}-python${uniqueSuffix}-${suffix}'

module shared './shared.bicep' = {
  name: 'shared-resource-references'
  params: {
    sharedSubscriptionId: sharedSubscriptionId
    sharedResourceGroupName: sharedResourceGroupName
    monitoringSubscriptionId: monitoringSubscriptionId
    monitoringResourceGroupName: monitoringResourceGroupName
    appInsightsName: appInsightsName
    vnetName: vnetName
    integrationSubnetName: integrationSubnetName
    sqlServerName: sqlServerName
    sqlDatabaseName: sqlDatabaseName
    keyVaultName: keyVaultName
  }
}

module frontendIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'frontend-managed-identity'
  params: {
    name: 'id-${environmentName}'
    location: location
    tags: tags
    enableTelemetry: false
  }
}

module backendIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'backend-managed-identity'
  params: {
    name: 'id-${appId}-python-${suffix}'
    location: location
    tags: tags
    enableTelemetry: false
  }
}

module plan 'br/public:avm/res/web/serverfarm:0.7.0' = {
  name: 'application-linux-plan'
  params: {
    name: appServicePlanName
    location: location
    kind: 'linux'
    reserved: true
    skuName: appServicePlanSku
    skuCapacity: 1
    zoneRedundant: false
    tags: tags
    enableTelemetry: false
  }
}

module backend './app/backend.bicep' = {
  name: 'application-backend'
  params: {
    name: backendName
    location: location
    tags: union(tags, { 'azd-service-name': 'backend' })
    planResourceId: plan.outputs.resourceId
    identityResourceId: backendIdentity.outputs.resourceId
    identityClientId: backendIdentity.outputs.clientId
    subnetResourceId: shared.outputs.subnetResourceId
    sqlServerFqdn: shared.outputs.sqlServerFqdn
    sqlDatabaseName: sqlDatabaseName
    appInsightsConnectionString: shared.outputs.appInsightsConnectionString
    serviceName: '${environmentName}-python'
    pythonVersion: pythonVersion
  }
}

module frontend './app/frontend.bicep' = {
  name: 'application-frontend'
  params: {
    name: frontendName
    location: location
    tags: union(tags, { 'azd-service-name': 'frontend' })
    planResourceId: plan.outputs.resourceId
    identityResourceId: frontendIdentity.outputs.resourceId
    identityClientId: frontendIdentity.outputs.clientId
    subnetResourceId: shared.outputs.subnetResourceId
    sqlServerFqdn: shared.outputs.sqlServerFqdn
    sqlDatabaseName: sqlDatabaseName
    appInsightsConnectionString: shared.outputs.appInsightsConnectionString
    serviceName: '${environmentName}-blazor'
    pythonUrl: backend.outputs.url
    entraClientId: entraClientId
    entraTenantId: tenant().tenantId
    entraSecretUri: '${shared.outputs.keyVaultUri}secrets/${entraSecretName}'
  }
}

output AZURE_RESOURCE_GROUP string = resourceGroup().name
output AZURE_FRONTEND_NAME string = frontendName
output AZURE_BACKEND_NAME string = backendName
output APP_WEB_URL string = frontend.outputs.url
output APP_API_URL string = backend.outputs.url
output ENTRA_CALLBACK_URL string = '${frontend.outputs.url}/.auth/login/aad/callback'
output ENTRA_AUTHORITY_URL string = uri(environment().authentication.loginEndpoint, '${tenant().tenantId}/')
output FRONTEND_IDENTITY_PRINCIPAL_ID string = frontendIdentity.outputs.principalId
output BACKEND_IDENTITY_PRINCIPAL_ID string = backendIdentity.outputs.principalId
output FRONTEND_IDENTITY_RESOURCE_ID string = frontendIdentity.outputs.resourceId
output BACKEND_IDENTITY_RESOURCE_ID string = backendIdentity.outputs.resourceId
output SQL_SERVER_FQDN string = shared.outputs.sqlServerFqdn
