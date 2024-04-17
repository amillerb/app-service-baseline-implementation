var vnetDeploymentName = 'vnet-hub-deployment'
var vnetName = 'vnet-hub'
var privateEndpointsSubnetName = 'snet-sharedPrivateEndpoints'
var workerSubnetName = 'snet-workload'
param location string
param fwAddressPrefix string = '10.1.0.0/26'


module hubvnet 'br/public:avm/res/network/virtual-network:0.1.1' = {
  name: vnetDeploymentName
  params: {
    name: vnetName
    location: location
    addressPrefixes: [
      '10.1.0.0/23'
    ]
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        addressPrefix: fwAddressPrefix
      }
      {
        name: privateEndpointsSubnetName
        addressPrefix: '10.1.0.64/26'
      }
      {
        name: 'AzureBastionSubnet'
        addressPrefix: '10.1.0.128/26'
      }
      {
        name: workerSubnetName
        addressPrefix: '10.1.1.0/26'
      }
    ]
  }
}


output vnetId string =  resourceId('Microsoft.Network/virtualNetworks', 'vnet-hub')
output peSubnetId string = resourceId('Microsoft.Network/VirtualNetworks/subnets', 'vnet-hub', '${privateEndpointsSubnetName}')
output workloadSubnetId string = resourceId('Microsoft.Network/VirtualNetworks/subnets', 'vnet-hub', '${workerSubnetName}')
output azfwPrefix string = fwAddressPrefix

// output vnetId string = hubvnet.outputs.resourceId
// output peSubnetId string = hubvnet.outputs.subnetResourceIds[1]
// output workloadSubnetId string = hubvnet.outputs.subnetResourceIds[3]
// output azfwPrefix string = fwAddressPrefix

