
param location string = 'EastUS'
param keyVaultName string
// param keyVaultName string = 'azfw-tls-kv-7'
var uaiName = 'azfw-uai-tls'
// param vnetRef string = '/subscriptions/c07bd8d6-a57c-4abc-b280-9b1771d0c4b3/resourceGroups/rg-test-azfw/providers/Microsoft.Network/virtualNetworks/vnet-hub'
param vnetRef string
var kvPEName = 'pe-fw-cert-kv'
var keyVaultCASecretName = 'CACert'
var vaultDNSZoneName = 'privatelink.vaultcore.azure.net'

// Variables for the VM that is used for the TLS Certificate
var vmSize = 'Standard_B2s'
var remoteAccessUsername = 'fta-admin'

@secure()
param remoteAccessPassword string 
@description('Secure Boot setting of the virtual machine.')
var secureBoot = true

@description('vTPM setting of the virtual machine.')
var vTPM = true
var OSVersion = '2022-datacenter-azure-edition'
var extensionName = 'GuestAttestation'
var extensionPublisher = 'Microsoft.Azure.Security.WindowsAttestation'
var extensionVersion = '1.0'
var maaTenantName = 'GuestAttestation'

// Log Analytics Workspaces
param logAnalyticsWorkspaceName string = '${uniqueString(resourceGroup().id)}la'


resource CreateAndDeployCertificates 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'CreateAndDeployCertificates'
  location: location
  kind: 'AzurePowerShell'
  properties: {
    forceUpdateTag: '2'
    azPowerShellVersion: '3.0'
    scriptContent: '# Write the config to file\n$opensslConfig=@\'\n[ req ]\ndefault_bits        = 4096\ndistinguished_name  = req_distinguished_name\nstring_mask         = utf8only\ndefault_md          = sha512\n\n[ req_distinguished_name ]\ncountryName                     = Country Name (2 letter code)\nstateOrProvinceName             = State or Province Name\nlocalityName                    = Locality Name\n0.organizationName              = Organization Name\norganizationalUnitName          = Organizational Unit Name\ncommonName                      = Common Name\nemailAddress                    = Email Address\n\n[ rootCA_ext ]\nsubjectKeyIdentifier = hash\nauthorityKeyIdentifier = keyid:always,issuer\nbasicConstraints = critical, CA:true\nkeyUsage = critical, digitalSignature, cRLSign, keyCertSign\n\n[ interCA_ext ]\nsubjectKeyIdentifier = hash\nauthorityKeyIdentifier = keyid:always,issuer\nbasicConstraints = critical, CA:true, pathlen:1\nkeyUsage = critical, digitalSignature, cRLSign, keyCertSign\n\n[ server_ext ]\nsubjectKeyIdentifier = hash\nauthorityKeyIdentifier = keyid:always,issuer\nbasicConstraints = critical, CA:false\nkeyUsage = critical, digitalSignature\nextendedKeyUsage = serverAuth\n\'@\n\nSet-Content -Path openssl.cnf -Value $opensslConfig\n\n# Create root CA\nopenssl req -x509 -new -nodes -newkey rsa:4096 -keyout rootCA.key -sha256 -days 3650 -out rootCA.crt -subj \'/C=US/ST=US/O=Self Signed/CN=Self Signed Root CA\' -config openssl.cnf -extensions rootCA_ext\n\n# Create intermediate CA request\nopenssl req -new -nodes -newkey rsa:4096 -keyout interCA.key -sha256 -out interCA.csr -subj \'/C=US/ST=US/O=Self Signed/CN=Self Signed Intermediate CA\'\n\n# Sign on the intermediate CA\nopenssl x509 -req -in interCA.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out interCA.crt -days 3650 -sha256 -extfile openssl.cnf -extensions interCA_ext\n\n# Export the intermediate CA into PFX\nopenssl pkcs12 -export -out interCA.pfx -inkey interCA.key -in interCA.crt -password \'pass:\'\n\n# Convert the PFX and public key into base64\n$interCa = [Convert]::ToBase64String((Get-Content -Path interCA.pfx -AsByteStream -Raw))\n$rootCa = [Convert]::ToBase64String((Get-Content -Path rootCA.crt -AsByteStream -Raw))\n\n# Assign outputs\n$DeploymentScriptOutputs = @{}\n$DeploymentScriptOutputs[\'interca\'] = $interCa\n$DeploymentScriptOutputs[\'rootca\'] = $rootCa\n'
    timeout: 'PT5M'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
  }
}// revisit script

resource tlsIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: uaiName
  location: location
}

output kvUAIName string = tlsIdentity.name

resource fwKeyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableRbacAuthorization: false
    tenantId: subscription().tenantId
    enableSoftDelete: false
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Disabled'
    accessPolicies: [
      {
        objectId: tlsIdentity.properties.principalId
        tenantId: tlsIdentity.properties.tenantId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
          certificates: ['get', 'list', 'create']
        }
      }
    ]
    sku: {
      name: 'standard'
      family: 'A'
    }
  }
}


resource kvSecretCert 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  parent: fwKeyVault
  name: keyVaultCASecretName
  location: location
  properties: {
    value: CreateAndDeployCertificates.properties.outputs.interca
  }
}

resource kvPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: kvPEName
  location: location

  properties: {
    privateLinkServiceConnections: [
      {
        name: kvPEName
        properties: {
          privateLinkServiceId: fwKeyVault.id
          groupIds: ['vault']
        }
      }
    ]
    customNetworkInterfaceName: '${kvPEName}-nic'
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', 'vnet-hub', 'snet-sharedPrivateEndpoints')
    }
  }
}

resource vaultDNSZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: vaultDNSZoneName
  location: 'global'
}

resource privateEndpointDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-01-01' = {
  name: '${kvPrivateEndpoint.name}/vault-PrivateDnsZoneGroup'
  properties:{
    privateDnsZoneConfigs: [
      {
        name: vaultDNSZoneName
        properties:{
          privateDnsZoneId: vaultDNSZone.id
        }
      }
    ]
  }
}

resource vnetLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: vaultDNSZone
  name: '${vaultDNSZoneName}-link.hub'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetRef
    }
  }
}

// Worker VM for Deployment

resource WorkerNIC 'Microsoft.Network/networkInterfaces@2020-07-01' = {
  name: 'WorkerNIC'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'WorkerIPConfiguration'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', 'vnet-hub', 'snet-sharedPrivateEndpoints')
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource WorkerVM 'Microsoft.Compute/virtualMachines@2021-03-01' = {
  name: 'WorkerVM'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: OSVersion
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
      }
    }
    osProfile: {
      computerName: 'WorkerVM'
      adminUsername: remoteAccessUsername
      adminPassword: remoteAccessPassword
    }
    securityProfile: {
      uefiSettings: {
        secureBootEnabled: secureBoot
        vTpmEnabled: vTPM
      }
      securityType: 'TrustedLaunch'
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: WorkerNIC.id
        }
      ]
    }
  }
}


resource WorkerVM_extension 'Microsoft.Compute/virtualMachines/extensions@2022-03-01' = if (vTPM && secureBoot) {
  parent: WorkerVM
  name: extensionName
  location: location
  properties: {
    publisher: extensionPublisher
    type: extensionName
    typeHandlerVersion: extensionVersion
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    settings: {
      AttestationConfig: {
        MaaSettings: {
          maaEndpoint: ''
          maaTenantName: maaTenantName
        }
        AscSettings: {
          ascReportingEndpoint: ''
          ascReportingFrequency: ''
        }
        useCustomToken: 'false'
        disableAlerts: 'false'
      }
    }
  }
}

resource WorkerVM_Bootstrap 'Microsoft.Compute/virtualMachines/extensions@2022-03-01' = {
  parent: WorkerVM
  name: 'Bootstrap'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.7'
    autoUpgradeMinorVersion: true
    settings: {
      commandToExecute: 'echo ${CreateAndDeployCertificates.properties.outputs.rootca} > c:\\root.pem.base64 && powershell "Set-Content -Path c:\\root.pem -Value ([Text.Encoding]::UTF8.GetString([convert]::FromBase64String((Get-Content -Path c:\\root.pem.base64))))" && certutil -addstore root c:\\root.pem'
    }
  }
}

resource BastionPublicIP 'Microsoft.Network/publicIpAddresses@2020-07-01' = {
  name: 'BastionPublicIP'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource DemoBastion 'Microsoft.Network/bastionHosts@2020-07-01' = {
  name: 'DemoBastion'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'BastionIpConfiguration'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', 'vnet-hub', 'AzureBastionSubnet')
          }
          publicIPAddress: {
            id: BastionPublicIP.id
          }
        }
      }
    ]
  }
}


resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

//Key Vault diagnostic settings
resource fwkeyVaultDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${fwKeyVault.name}-diagnosticSettings'
  scope: fwKeyVault
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
        {
            categoryGroup: 'allLogs'
            enabled: true
            retentionPolicy: {
                enabled: false
                days: 0
            }
        }
    ]
  }
}

// resource kvlogAnalyticsLinkedService 'Microsoft.KeyVault/vaults/linkedServices@2021-06-01-preview' = {
//   parent: fwKeyVault
//   name: 'logAnalyticsLinkedService'
//   properties: {
//     resourceId: logAnalyticsWorkspace.id
//   }
// }

