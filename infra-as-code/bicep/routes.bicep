var rtDeploymentAppGWName = 'udr-appGatewaySubnet-deployment'
var rtDeploymentAppServicesName = 'udr-appServicesSubnet-deployment'
var rtDeploymentJumpboxName = 'udr-jumpboxSubnet-deployment'
var rtDeploymentPEName = 'udr-privateEndpointsSubnet-deployment'

// Route Tables
var rtAppGWName = 'udr-appGatewaySubnet'
var rtAppServicesName = 'udr-appServicesSubnet'
var rtJumpboxName = 'udr-jumpboxSubnet'
var rtPEName = 'udr-privateEndpointsSubnet'
param location string
param fwPrivateIP string
param azfwPrefix string


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
// app service plan subnet association
}

module rtJumpbox 'br/public:avm/res/network/route-table:0.2.1' = {
  name: rtDeploymentJumpboxName
  params: {
    name: rtJumpboxName
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

