// Azure Firewall 
var azfwName = 'azfw-hub'
var azfwPolicyName = 'azfw-hub-policy-test'
param location string
var appGWRuleName = 'azfw-ip-group-app-gwsnet'
var appRulesName = 'snet-appGateway-to-frontend-app-aoaizt'
var azfwPIPName = 'azfw-pip'

// Deployment Names
var ipGroupAppGWSnetDeploymentName = 'ipgr-snet-appGateway-deployment'
var ipGroupInboundFESnetDeploymentName = 'ipgr-ib-frontend-app-aoaizt-deployment'
var ipGroupOutboundFESnetDeploymentName = 'ipgr-ob-frontend-app-aoaizt-deployment'
var ipGroupBackendDeploymentName = 'ipgr-backend-app-aoaizt-deployment'
var ipGroupJumpBoxDeploymentName = 'ipgr-snet-jumpbox-deployment'
var azfwPolicyDeploymentName = 'azfw-hub-policy-deployment'
var azfwPIPDeploymentName = 'azfw-pip-deployment'

// Name of the IP Groups
var ipGroupAppGWSnetName = 'ipgr-snet-appGateway'
var ipGroupInboundFESnetName = 'ipgr-ib-frontend-app-aoaizt'
var ipGroupOutboundFESnetName = 'ipgr-ob-frontend-app-aoaizt'
var ipGroupBackendName = 'ipgr-backend-app-aoaizt'
var ipGroupJumpBoxName = 'ipgr-snet-jumpbox'

// Rule Collections
var appRuleCollectionGroupName = 'apprule-cg-app-aoaizt'
//var netRuleCollectionName = 'netrule-cg-app-aoaizt'
var appOBRuleName = 'frontend-app-aoaizt-to-Internet'
var appIBRuleCollectionName = 'ib-net-appaoaizt'
var appOBRuleCollectionName = 'ob-app-rc-appaoaizt'
param uaiName string
var keyVaultCASecretName = 'CACert'
param keyVaultName string
param logAnalyticsWorkspaceId string

// Key Vault & Identity reference for TLS

resource fwKeyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource tlsIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: uaiName
}

resource kvSecretCert 'Microsoft.KeyVault/vaults/secrets@2019-09-01' existing = {
  parent: fwKeyVault
  name: keyVaultCASecretName
}

// IP Groups
module ipGroupAppGWSnet 'br/public:avm/res/network/ip-group:0.1.0' = {
  name: ipGroupAppGWSnetDeploymentName
  params: {
    name: ipGroupAppGWSnetName
    ipAddresses: [ '10.1.1.0/24']
    location: location
  }
}

module ipGroupInboundFESnet 'br/public:avm/res/network/ip-group:0.1.0' = {
  name: ipGroupInboundFESnetDeploymentName
  params: {
    name: ipGroupInboundFESnetName
    ipAddresses: ['10.1.0.128/32']
    location: location
  }
}

module ipGroupOutboundFESnet 'br/public:avm/res/network/ip-group:0.1.0' = {
  name: ipGroupOutboundFESnetDeploymentName
  params: {
    name: ipGroupOutboundFESnetName
    ipAddresses: ['10.1.0.0/24']
    location: location
  }
}

module ipGroupBackend 'br/public:avm/res/network/ip-group:0.1.0' = {
  name: ipGroupBackendDeploymentName
  params: {
    name: ipGroupBackendName
    ipAddresses: ['10.1.1.7/32', '10.1.1.5/32' ]
    location: location
  }
}

module ipGroupJumpBox 'br/public:avm/res/network/ip-group:0.1.0' = {
  name: ipGroupJumpBoxDeploymentName
  params: {
    name: ipGroupJumpBoxName
    ipAddresses: ['10.1.1.192/28']
    location: location
  }
}

// Firewall Policy
module firewallPolicy 'br/public:avm/res/network/firewall-policy:0.1.2' = {
  name: azfwPolicyDeploymentName
  params: {
    name: azfwPolicyName
    location: location
    ruleCollectionGroups: [
      {
        name: appRuleCollectionGroupName
        priority: 300
        ruleCollections: [
          {
            action: {
              type: 'Allow'
            }
            name: appIBRuleCollectionName
            priority: 100
            ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
            rules: [
              {
                terminateTLS: true
                destinationAddresses: []
                targetFqdns: [
                  'app-aoaiztwk.azurewebsites.net'
                  'app-aoaiztwk.scm.azurewebsites.net'
                ]
                destinationIpGroups: []
                protocols: [
                  {
                    protocolType: 'Https'
                    port: 443
                  }
                ]
                name: appRulesName
                ruleType: 'ApplicationRule'
                sourceAddresses: []
                sourceIpGroups: [ipGroupAppGWSnet.outputs.resourceId]
              }
            ]
          }
          {
            action: {
              type: 'Allow'
            }
            name: appOBRuleCollectionName
            priority: 110
            ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
            rules: [
              {
                terminateTLS: true
                destinationAddresses: []
                targetFqdns: [
                  'dc.services.visualstudio.com'
                  'mcr.microsoft.com'
                ]
                destinationIpGroups: []
                protocols: [
                  {
                    protocolType: 'Https'
                    port: 443
                  }
                ]
                name: appOBRuleName
                ruleType: 'ApplicationRule'
                sourceAddresses: []
                sourceIpGroups: [ipGroupOutboundFESnet.outputs.resourceId]
              }
            ]
          }
        ]
      }
    ]
    threatIntelMode: 'Alert'
    tier: 'Premium'
    mode: 'Alert'
    certificateName: keyVaultCASecretName
    keyVaultSecretId: kvSecretCert.properties.secretUriWithVersion
    managedIdentities:{
      userAssignedResourceIds: [tlsIdentity.id]
    }
    defaultWorkspaceId: logAnalyticsWorkspaceId
   }
  }


// Public IP
module azfwPIP 'br/public:avm/res/network/public-ip-address:0.3.1' = {
  name: azfwPIPDeploymentName
  params: {
    name: azfwPIPName
    location: location
  }
}

// Azure Firewall
resource azureFirewall 'Microsoft.Network/azureFirewalls@2023-04-01' = {
  name: azfwName
  location: location
  properties: {
      ipConfigurations: [
          {
              name: 'azfwConfig'
              properties: {
                  subnet: {
                      id: resourceId('Microsoft.Network/virtualNetworks/subnets', 'vnet-hub', 'AzureFirewallSubnet')
                  }
                  publicIPAddress: {
                      id: azfwPIP.outputs.resourceId
                  }
              }
          }
      ]
      sku: {
        tier: 'Premium'
      }
   
        firewallPolicy: {
          id: firewallPolicy.outputs.resourceId
        }
      }
      dependsOn:[
        firewallPolicy
      ]
  }



//Firewall diagnostic settings
resource fwDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${azureFirewall.name}-diagnosticSettings'
  scope: azureFirewall
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
        {
            categoryGroup: 'allLogs'
            enabled: true
            retentionPolicy: {
                enabled: false
                days: 7
            }
        }
    ]
  }
}

output fwPrivateIP string = azureFirewall.properties.ipConfigurations[0].properties.privateIPAddress
output azfwPIPAddress string = azfwPIP.outputs.ipAddress
