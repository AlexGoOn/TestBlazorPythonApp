param name string
param location string
param tags object
param planResourceId string
param identityResourceId string
param identityClientId string
param subnetResourceId string
param sqlServerFqdn string
param sqlDatabaseName string
param appInsightsConnectionString string
param serviceName string
param pythonVersion string

module site 'br/public:avm/res/web/site:0.24.0' = {
  name: 'backend-webapp-avm'
  params: {
    name: name
    location: location
    kind: 'app,linux'
    serverFarmResourceId: planResourceId
    managedIdentities: { userAssignedResourceIds: [identityResourceId] }
    virtualNetworkSubnetResourceId: subnetResourceId
    publicNetworkAccess: 'Enabled'
    httpsOnly: true
    tags: tags
    enableTelemetry: false
    siteConfig: {
      linuxFxVersion: 'PYTHON|${pythonVersion}'
      appCommandLine: 'python azure_startup.py'
      alwaysOn: true
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      ftpsState: 'Disabled'
      vnetRouteAllEnabled: true
      ipSecurityRestrictions: [
        {
          name: 'allow-blazor-subnet'
          action: 'Allow'
          priority: 100
          vnetSubnetResourceId: subnetResourceId
        }
      ]
      ipSecurityRestrictionsDefaultAction: 'Deny'
      scmIpSecurityRestrictionsUseMain: false
      scmIpSecurityRestrictionsDefaultAction: 'Allow'
    }
    basicPublishingCredentialsPolicies: [
      { name: 'ftp', allow: false }
      { name: 'scm', allow: false }
    ]
    configs: [
      {
        name: 'logs'
        properties: {
          applicationLogs: { fileSystem: { level: 'Information' } }
          httpLogs: { fileSystem: { enabled: true, retentionInMb: 35, retentionInDays: 3 } }
        }
      }
      {
        name: 'appsettings'
        retainCurrentAppSettings: false
        properties: {
          SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
          ENABLE_ORYX_BUILD: 'true'
          SQL_CONNECTION_STRING: 'Driver={ODBC Driver 18 for SQL Server};Server=tcp:${sqlServerFqdn},1433;Database=${sqlDatabaseName};Authentication=ActiveDirectoryMsi;UID=${identityClientId};Encrypt=yes;TrustServerCertificate=no;'
          SQL_CONNECT_TIMEOUT: '30'
          APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
          OTEL_SERVICE_NAME: serviceName
          OTEL_RESOURCE_ATTRIBUTES: 'service.namespace=dxazure'
        }
      }
    ]
  }
}

output url string = 'https://${site.outputs.defaultHostname}'
