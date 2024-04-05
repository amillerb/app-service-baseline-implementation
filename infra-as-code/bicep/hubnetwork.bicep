var vnetDeploymentName = 'vnet-hub-deployment'
var vnetName = 'vnet-hub'
var privateEndpointsSubnetName = 'snet-sharedPrivateEndpoints'
var location = 'EastUS'


module hubvnet 'br/public:network/virtual-network:1.1.3' = {
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
        addressPrefix: '10.1.0.0/26'
      }
      {
        name: privateEndpointsSubnetName
        addressPrefix: '10.1.0.64/26'
      }
      {
        name: 'AzureBastionSubnet'
        addressPrefix: '10.1.0.128/26'
      }

      // worker vm subnet 
    ]
  }
}
output vnetId string = hubvnet.outputs.resourceId
