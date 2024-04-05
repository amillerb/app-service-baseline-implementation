var rtDeploymentAppGWName = 'udr-appGatewaySubnet-deployment'
var rtDeploymentAppServicesName = 'udr-appServicesSubnet-deployment'
var rtDeploymentJumpboxName = 'udr-jumpboxSubnet-deployment'
var rtDeploymentPEName = 'udr-privateEndpointsSubnet-deployment'

// Route Tables
var rtAppGWName = 'udr-appGatewaySubnet'
var rtAppServicesName = 'udr-appServicesSubnet'
var rtJumpboxName = 'udr-jumpboxSubnet'
var rtPEName = 'udr-privateEndpointsSubnet'
param azfwIP string
param location string
param fwPrivateIP string

module rtAppGW 'br/public:avm/res/network/route-table:0.2.1' = {
  name: rtDeploymentAppGWName
  params: {
    name: rtAppGWName
    location: location
    routes: [
      {
        name: 'PrivateEndpointsSubnet'
        properties: {
          addressPrefix: '10.1.2.0/27'
          nextHopIpAddress: fwPrivateIP
          nextHopType: 'VirtualAppliance'
        }
      }
    ]
  }
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
          nextHopIpAddress: azfwIP
          nextHopType: 'VirtualAppliance'
        }
      }
    ]
  }
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
          nextHopIpAddress: azfwIP
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
          nextHopIpAddress: azfwIP
          nextHopType: 'VirtualAppliance'
        }
      }
    ]
  }
}

