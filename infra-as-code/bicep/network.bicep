/*
  Deploy vnet with subnets and NSGs
*/

@description('This is the base name for each Azure resource name (6-12 chars)')
param baseName string

@description('The resource group location')
param location string = resourceGroup().location

param developmentEnvironment bool

// variables
var vnetName = 'vnet-${baseName}'
var ddosPlanName = 'ddos-${baseName}'

var vnetAddressPrefix = '10.0.0.0/16'
var appGatewaySubnetPrefix = '10.0.1.0/24'
var appServicesSubnetPrefix = '10.0.0.0/24'
var privateEndpointsSubnetPrefix = '10.0.2.0/27'
var agentsSubnetPrefix = '10.0.2.32/27'
var azureFirewallSubnetPrefix = '10.1.1.0/26'

var rtDeploymentAppGWName = 'udr-appGatewaySubnet-deployment'
var rtDeploymentAppServicesName = 'udr-appServicesSubnet-deployment'
var rtDeploymentAgentsName = 'udr-agentsSubnet-deployment'
var rtDeploymentPEName = 'udr-privateEndpointsSubnet-deployment'

var rtAppGWName = 'udr-appGatewaySubnet'
var rtAppServicesName = 'udr-appServicesSubnet'
var rtAgentsName = 'udr-agentsSubnet'
var rtPEName = 'udr-privateEndpointsSubnet'
param fwPrivateIP string
param azfwPrefix string
//Temp disable DDoS protection
var enableDdosProtection = !developmentEnvironment

// ---- Networking resources ----

// DDoS Protection Plan
resource ddosProtectionPlan 'Microsoft.Network/ddosProtectionPlans@2022-11-01' = if (enableDdosProtection) {
  name: ddosPlanName
  location: location
  properties: {}
}

//route tables
module rtAppGW 'br/public:avm/res/network/route-table:0.2.1' = {
  name: rtDeploymentAppGWName
  params: {
    name: rtAppGWName
    location: location
    routes: [
      {
        name: 'ib-frontend-app-aoaizt'
        properties: {
          addressPrefix: '10.0.2.14/32' //change to the right IP
          nextHopIpAddress: fwPrivateIP
          nextHopType: 'VirtualAppliance'
        }
      }
    ]
  } //appgw subnet association - do in vnet one
}

module rtAppServices 'br/public:avm/res/network/route-table:0.2.1' = {
  name: rtDeploymentAppServicesName
  params: {
    name: rtAppServicesName
    location: location
    routes: [
      {
        name: 'default'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopIpAddress: fwPrivateIP
          nextHopType: 'VirtualAppliance'
        }
      }
    ]
  }
}

module rtAgents 'br/public:avm/res/network/route-table:0.2.1' = {
  name: rtDeploymentAgentsName
  params: {
    name: rtAgentsName
    location: location
    routes: [
      {
        name: 'default'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopIpAddress: fwPrivateIP
          nextHopType: 'VirtualAppliance'
        }
      }
    ]
  }
}

module rtPE 'br/public:avm/res/network/route-table:0.2.1' = {
  name: rtDeploymentPEName
  params: {
    name: rtPEName
    location: location
    routes: [
      {
        name: 'default'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopIpAddress: fwPrivateIP
          nextHopType: 'VirtualAppliance'
        }
      }
      {
        name: 'AzureFirewallSubnetRoute'
        properties: {
          addressPrefix: azfwPrefix
          nextHopIpAddress: fwPrivateIP
          nextHopType: 'VirtualAppliance'
        }
      }
    ]
  }
}


//vnet and subnets
resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' = {
  name: vnetName
  location: location
  properties: {
    enableDdosProtection: enableDdosProtection
    ddosProtectionPlan: enableDdosProtection ? { id: ddosProtectionPlan.id } : null
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        //App services plan subnet
        name: 'snet-appServicePlan'
        properties: {
          addressPrefix: appServicesSubnetPrefix
          networkSecurityGroup: {
            id: appServiceSubnetNsg.id
          }
          routeTable: {
            id: rtAppServices.outputs.resourceId
          }
          delegations: [
            {
              name: 'delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        //App Gateway subnet
        name: 'snet-appGateway'
        properties: {
          addressPrefix: appGatewaySubnetPrefix
          networkSecurityGroup: {
            id: appGatewaySubnetNsg.id
          }
          routeTable: {
            id: rtAppGW.outputs.resourceId
          }
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        //Private endpoints subnet
        name: 'snet-privateEndpoints'
        properties: {
          addressPrefix: privateEndpointsSubnetPrefix
          networkSecurityGroup: {
            id: privateEndpointsSubnetNsg.id
          }
          routeTable: {
            id: rtPE.outputs.resourceId
          }
        }
      }
      {
        // Build agents subnet
        name: 'snet-agents'
        properties: {
          addressPrefix: agentsSubnetPrefix
          networkSecurityGroup: {
            id: agentsSubnetNsg.id
          }
          routeTable: {
            id: rtAgents.outputs.resourceId
          }
        }
      }
    ]
  }

  resource appGatewaySubnet 'subnets' existing = {
    name: 'snet-appGateway'
  }

  resource appServiceSubnet 'subnets' existing = {
    name: 'snet-appServicePlan'
  }

  resource privateEnpointsSubnet 'subnets' existing = {
    name: 'snet-privateEndpoints'
  }

  resource agentsSubnet 'subnets' existing = {
    name: 'snet-agents'
  }  
}

//App Gateway subnet NSG
resource appGatewaySubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-appGatewaySubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AppGw.In.Allow.ControlPlane'
        properties: {
          description: 'Allow inbound Control Plane (https://docs.microsoft.com/azure/application-gateway/configuration-infrastructure#network-security-groups)'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AppGw.In.Allow443.Internet'
        properties: {
          description: 'Allow ALL inbound web traffic on port 443'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: appGatewaySubnetPrefix
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }  
    ]
  }
}

//App service subnet nsg
resource appServiceSubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-appServicesSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'DenyVnetInBound'
        properties: {
          description: 'Deny inbound traffic from other subnets to the training subnet. Note: adjust rules as needed after adding resources to the subnet.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AppPlan.Out.Allow.PrivateEndpoints'
        properties: {
          description: 'Allow outbound traffic from the app service subnet to the private endpoints subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: appServicesSubnetPrefix
          destinationAddressPrefix: privateEndpointsSubnetPrefix
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AppPlan.Out.Allow.HTTPsInternet'
        properties: {
          description: 'Allow outbound traffic from the app service subnet to the Internet over HTTPs.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: appServicesSubnetPrefix
          destinationAddressPrefix: 'Internet'
          access: 'Allow'
          priority: 500
          direction: 'Outbound'
        }
      }
      {
        name: 'DenyAllOutBound'
        properties: {
          description: 'Deny outbound traffic from the app services (vnet integration) subnet. Note: adjust rules as needed after adding resources to the subnet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: appServicesSubnetPrefix
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
      
    ]
  }
}

//Private endpoints subnets NSG
resource privateEndpointsSubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-privateEndpointsSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'PrivateEndpoints.In.Allow.AppGateway'
        properties: {
          description: 'Allow inbound from the Application Gateway Subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: appServicesSubnetPrefix
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'PrivateEndpoints.In.Allow.AppServicesPlan'
        properties: {
          description: 'Allow inbound from the App Services Plan Integration subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: appServicesSubnetPrefix
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'PrivateEndpoints.In.Allow.AzureFirewall'
        properties: {
          description: 'Allow inbound from the AzureFirewallSubnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: azureFirewallSubnetPrefix
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 130
          direction: 'Inbound'
        }
      }
      {
        name: 'PE.Out.Deny.All'
        properties: {
          description: 'Deny outbound traffic from the private endpoints subnet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: privateEndpointsSubnetPrefix
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 100
          direction: 'Outbound'
        }
      }      
    ]
  }
}

//Build agents subnets NSG
resource agentsSubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-agentsSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'DenyVnetInBound'
        properties: {
          description: 'Deny inbound traffic from other subnets to the training subnet. Note: adjust rules as needed after adding resources to the subnet.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Deny'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllOutBound'
        properties: {
          description: 'Deny outbound traffic from the build agents subnet. Note: adjust rules as needed after adding resources to the subnet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: appGatewaySubnetPrefix
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

@description('The name of the vnet.')
output vnetNName string = vnet.name

@description('The name of the app service plan subnet.')
output appServicesSubnetName string = vnet::appServiceSubnet.name

@description('The name of the app gatewaysubnet.')
output appGatewaySubnetName string = vnet::appGatewaySubnet.name

@description('The name of the private endpoints subnet.')
output privateEndpointsSubnetName string = vnet::privateEnpointsSubnet.name
