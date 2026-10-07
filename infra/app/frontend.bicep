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
param pythonUrl string
param entraClientId string
param entraTenantId string
param entraSecretUri string

module site 'br/public:avm/res/web/site:0.24.0' = {
  name: 'frontend-webapp-avm'
  params: {
    name: name
    location: location
    kind: 'app,linux'
    serverFarmResourceId: planResourceId
    managedIdentities: { userAssignedResourceIds: [identityResourceId] }
    keyVaultAccessIdentityResourceId: identityResourceId
    virtualNetworkSubnetResourceId: subnetResourceId
    publicNetworkAccess: 'Enabled'
    httpsOnly: true
    clientAffinityEnabled: true
    tags: tags
    enableTelemetry: false
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|10.0'
      appCommandLine: 'dotnet BlazorApp.dll'
      alwaysOn: true
      webSocketsEnabled: true
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      ftpsState: 'Disabled'
      vnetRouteAllEnabled: true
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
          ASPNETCORE_ENVIRONMENT: 'Production'
          ASPNETCORE_FORWARDEDHEADERS_ENABLED: 'true'
          SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'
          PythonService__BaseUrl: '${pythonUrl}/'
          ConnectionStrings__Sql: 'Server=tcp:${sqlServerFqdn},1433;Database=${sqlDatabaseName};Authentication=Active Directory Managed Identity;User Id=${identityClientId};Encrypt=True;TrustServerCertificate=False;Connect Timeout=30;'
          MICROSOFT_PROVIDER_AUTHENTICATION_SECRET: '@Microsoft.KeyVault(SecretUri=${entraSecretUri})'
          APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
          OTEL_SERVICE_NAME: serviceName
        }
      }
      {
        name: 'authsettingsV2'
        properties: {
          platform: { enabled: true, runtimeVersion: '~1' }
          globalValidation: {
            requireAuthentication: true
            unauthenticatedClientAction: 'RedirectToLoginPage'
            redirectToProvider: 'azureActiveDirectory'
          }
          identityProviders: {
            azureActiveDirectory: {
              enabled: true
              registration: {
                clientId: entraClientId
                clientSecretSettingName: 'MICROSOFT_PROVIDER_AUTHENTICATION_SECRET'
                openIdIssuer: uri(environment().authentication.loginEndpoint, '${entraTenantId}/v2.0')
              }
              validation: {
                allowedAudiences: [entraClientId, 'api://${entraClientId}']
              }
              login: { loginParameters: ['scope=openid profile email'] }
            }
          }
          login: { tokenStore: { enabled: true } }
          httpSettings: {
            requireHttps: true
            forwardProxy: { convention: 'Standard' }
          }
        }
      }
    ]
  }
}

output url string = 'https://${site.outputs.defaultHostname}'
