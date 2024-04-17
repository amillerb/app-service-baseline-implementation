@description('The location in which all resources should be deployed.')
param location string = 'northcentralus'

@description('This is the base name for each Azure resource name (6-12 chars)')
@minLength(6)
@maxLength(12)
param baseName string

@description('The administrator username of the SQL server')
param sqlAdministratorLogin string

@description('The administrator password of the SQL server.')
@secure()
param sqlAdministratorLoginPassword string

@description('Domain name to use for App Gateway')
param customDomainName string = 'contoso.com'

@description('The certificate data for app gateway TLS termination. The value is base64 encoded')
@secure()
param appGatewayListenerCertificate string

@description('Optional. When true will deploy a cost-optimised environment for development purposes. Note that when this param is true, the deployment is not suitable or recommended for Production environments. Default = false.')
param developmentEnvironment bool = true

@description('The name of the web deploy file. The file should reside in a deploy container in the storage account. Defaults to SimpleWebApp.zip')
param publishFileName string = 'SimpleWebApp.zip'

// ---- Availability Zones ----
var availabilityZones = [ '1', '2', '3' ]
var logWorkspaceName = 'log-${baseName}'


@description('Specifies the password of the administrator account on the Windows jump box.\n\nComplexity requirements: 3 out of 4 conditions below need to be fulfilled:\n- Has lower characters\n- Has upper characters\n- Has a digit\n- Has a special character\n\nDisallowed values: "abc@123", "P@$$w0rd", "P@ssw0rd", "P@ssword123", "Pa$$word", "pass@word1", "Password!", "Password1", "Password22", "iloveyou!"')
@secure()
@minLength(8)
@maxLength(123)
param jumpBoxAdminPassword string

// ---- Log Analytics workspace ----
resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Deploy vnet with subnets and NSGs
module networkModule 'network.bicep' = {
  name: 'networkDeploy'
  params: {
    location: location
    baseName: baseName
    developmentEnvironment: developmentEnvironment
  }
}

// Deploy storage account with private endpoint and private DNS zone
module storageModule 'storage.bicep' = {
  name: 'storageDeploy'
  params: {
    location: location
    baseName: baseName
    vnetName: networkModule.outputs.vnetNName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
  }
}

// Deploy a SQL server with a sample database, a private endpoint and a DNS zone
module databaseModule 'database.bicep' = {
  name: 'databaseDeploy'
  params: {
    location: location
    baseName: baseName
    sqlAdministratorLogin: sqlAdministratorLogin
    sqlAdministratorLoginPassword: sqlAdministratorLoginPassword
    vnetName: networkModule.outputs.vnetNName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
  }
}

// Deploy a Key Vault with a private endpoint and DNS zone
module secretsModule 'secrets.bicep' = {
  name: 'secretsDeploy'
  params: {
    location: location
    baseName: baseName
    vnetName: networkModule.outputs.vnetNName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    appGatewayListenerCertificate: appGatewayListenerCertificate
    sqlConnectionString: databaseModule.outputs.sqlConnectionString
  }
}

// Deploy Hub VNet

module hubNetworkModule 'hubnetwork.bicep' = {
  name: 'hubVnetDeploy'
  params: {
    fwAddressPrefix:'10.1.0.0/26'
    location: location
  }
}

// Deploy TLS Inspection elements for the Azure Firewall
module tlsModule 'tls.bicep' = {
  name: 'tlsDeploy'
  params: {
    location: location
    vnetRef: hubNetworkModule.outputs.vnetId
    peSubnetId: hubNetworkModule.outputs.peSubnetId
    workloadSubnetId:hubNetworkModule.outputs.workloadSubnetId
    keyVaultName: 'azfwkv-${baseName}'
    remoteAccessPassword: jumpBoxAdminPassword  
    logAnalyticsWorkspaceId:logWorkspace.id
  }
}

// Deploy Azure Firewall

module firewallModule 'azurefirewall.bicep' = {
  name: 'firewallDeploy'
  params: {
    location: location
    keyVaultName: 'azfwkv-${baseName}'
    uaiName: tlsModule.outputs.kvUAIName
    logAnalyticsWorkspaceId:logWorkspace.id
  }
}


// Deploy Routes for the Azure Firewall

module routesModule 'routes.bicep' = {
  name: 'routesDeploy'
  params: {
    location: location
    fwPrivateIP: firewallModule.outputs.fwPrivateIP
    azfwPrefix: hubNetworkModule.outputs.azfwPrefix
  }
}


// Deploy a web app
module webappModule 'webapp.bicep' = {
  name: 'webappDeploy'
  params: {
    location: location
    baseName: baseName
    developmentEnvironment: developmentEnvironment
    publishFileName: publishFileName
    keyVaultName: secretsModule.outputs.keyVaultName
    storageName: storageModule.outputs.storageName
    vnetName: networkModule.outputs.vnetNName
    appServicesSubnetName: networkModule.outputs.appServicesSubnetName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    logWorkspaceName: logWorkspace.name
   } //depends on to add here
}

//Deploy an Azure Application Gateway with WAF v2 and a custom domain name.
module gatewayModule 'gateway.bicep' = {
  name: 'gatewayDeploy'
  params: {
    location: location
    baseName: baseName
    developmentEnvironment: developmentEnvironment
    availabilityZones: availabilityZones
    customDomainName: customDomainName
    appName: webappModule.outputs.appName
    vnetName: networkModule.outputs.vnetNName
    appGatewaySubnetName: networkModule.outputs.appGatewaySubnetName
    keyVaultName: secretsModule.outputs.keyVaultName
    gatewayCertSecretUri: secretsModule.outputs.gatewayCertSecretUri
    logWorkspaceName: logWorkspace.name
   }
}


