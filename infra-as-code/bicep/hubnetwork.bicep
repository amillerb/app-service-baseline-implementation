var vnetDeploymentName = 'vnet-hub-deployment'
var vnetName = 'vnet-hub'
var privateEndpointsSubnetName = 'snet-sharedPrivateEndpoints'

var nsgDeploymentName = 'sharedPE-nsg-hub-deployment'
var rtDeploymentPEName = 'udr-sharedPrivateEndpoints-deployment'

var rtSharedPEName = 'udr-sharedPrivateEndpoints'
var nsgSharedPrivateEndpointsName = 'nsg-sharedPrivateEndpointsSubnet'


param location string
param fwPrivateIP string = '10.1.1.4'
param fwAddressPrefix string = '10.1.1.0/26'


module rtSharedPE 'br/public:avm/res/network/route-table:0.2.1' = {
  name: rtDeploymentPEName
  params: {
    name: rtSharedPEName
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
output rtId string = rtSharedPE.outputs.resourceId

module hubvnet 'br/public:avm/res/network/virtual-network:0.1.1' = {
  name: vnetDeploymentName
  params: {
    name: vnetName
    location: location
    addressPrefixes: [
      '10.1.0.0/16'
    ]
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        addressPrefix: fwAddressPrefix
      }
      {
        name: privateEndpointsSubnetName
        addressPrefix: '10.1.2.0/24'
        routeTableResourceId: rtSharedPE.outputs.resourceId
        networkSecurityGroupResourceId: nsgSharedPrivateEndpoints.outputs.resourceId
      }
    ]
  }
}


module nsgSharedPrivateEndpoints 'br/public:avm/res/network/network-security-group:0.1.2' = {
  name: nsgDeploymentName
  params: {
    name: nsgSharedPrivateEndpointsName
    location: location
  }
}


output vnetId string =  resourceId('Microsoft.Network/virtualNetworks', 'vnet-hub')
output peSubnetId string = resourceId('Microsoft.Network/VirtualNetworks/subnets', 'vnet-hub', '${privateEndpointsSubnetName}')
output azfwPrefix string = fwAddressPrefix
