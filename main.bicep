

param location string = resourceGroup().location


// Hub VNet for NVAs e.g. Bastion, Firewall, etc.

resource vnetHub 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'vnetHub'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.1.0/27'
        }
      }
    ]
  }
}

resource subnetBastion 'Microsoft.Network/virtualNetworks/subnets@2023-04-01' = {
  name: 'subnetBastion'
  parent: vnetHub
  properties: {
    addressPrefix: '10.0.1.0/27'
  }
}

// Resources
resource vnetSpoke 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'vnetSpoke'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.33.0.0/16'
      ]
    }
    subnets: [
      // see subnet definitions below
      // {
      //   name: 'appServiceSubnet'
      //   properties: {
      //     addressPrefix: '10.33.1.0/24'
      //     networkSecurityGroup:appServiceNSG
      //     serviceEndpoints: [
      //       {
      //         service: 'Microsoft.Web'
      //       }
      //     ]
      //   }
      // }
      // {
      //   name: 'blobStorageSubnet'
      //   properties: {
      //     addressPrefix: '10.33.2.0/24'
      //     networkSecurityGroup: blobStorageNSG
      //     serviceEndpoints: [
      //       {
      //         service: 'Microsoft.Storage'
      //       }
      //     ]
      //   }
      // }
    ]
  }
}


resource subnetAppService 'Microsoft.Network/virtualNetworks/subnets@2023-04-01' = {
  name: 'subnetAppService'
  parent: vnetSpoke
  properties: {
    addressPrefix: '10.33.1.0/24'
    networkSecurityGroup:nsgAppService
    serviceEndpoints: [
      {
        service: 'Microsoft.Web'
      }
    ]
  }
}


resource subnetBlob 'Microsoft.Network/virtualNetworks/subnets@2023-04-01' = {
  name: 'subnetBlob'
  parent: vnetSpoke
  properties: {
    addressPrefix: '10.33.2.0/24'
    networkSecurityGroup: nsgBlob
    serviceEndpoints: [
      {
        service: 'Microsoft.Storage'
      }
    ]
  }
}

resource nsgAppService 'Microsoft.Network/networkSecurityGroups@2021-02-01' = {
  name: 'nsgAppService'
  location: location
  properties: {
    securityRules: [
      // Define your security rules for App Service here
    ]
  }
}

resource nsgBlob 'Microsoft.Network/networkSecurityGroups@2021-02-01' = {
  name: 'nsgBlob'
  location: location
  properties: {
    securityRules: [
      // Define your security rules for Blob Storage here
    ]
  }
}




// Peering from hub to spoke (VNet1)
resource hubToSpokePeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-02-01' = {
  name: 'hubToSpoke'
  parent: vnetHub
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: vnetSpoke.id
    }
  }
}

resource spokeToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-02-01' = {
  name: 'SpokeToHub'
  parent: vnetSpoke
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: vnetHub.id
    }
  }
}



// ASE
resource aseApi 'Microsoft.Web/sites@2022-09-01' = {
  name: 'aseApi'
  location: 'Global'
  kind: 'ASEV3'
  properties: {
    //virtualNetworkSubnetId: filter(vnetSpoke.properties.subnets, s => s.name == 'AppServiceSubnet')[0].id
    virtualNetworkSubnetId: subnetAppService.id
    siteConfig: {
      
      ipSecurityRestrictions: [
        {
          ipAddress: '195.100.100.100/32'
          action: 'Allow'
          priority: 100
          name: 'AllowSpecificIP'
          description: 'Allow access only from x.y.z'
        }
      ]
    }
  }
}

// Public IP for ASE
resource asePublicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'asePublicIp'
  location: location
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Managed Certificate for ASE (for this example, assuming a certificate is uploaded)
resource managedCertificate 'Microsoft.Web/certificates@2022-09-01' = {
  name: 'myManagedCert'
  location: location
  properties: {
    //cerBlob: '<Base64-encoded-certificate-blob>'
    //hostingEnvironment: aseApi.name
  }
}

// Outputs
output asePublicIpAddress string = asePublicIp.properties.ipAddress
output aseId string = aseApi.id
output certThumbprint string = managedCertificate.properties.thumbprint



// Public IP for Azure Bastion
resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: 'bastionPublicIp'
  location: location
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    sku: {
      name: 'Standard'
    }
  }
}



// Allow SSH traffic from Bastion subnet to the Linux VMs (adjusting the NSG)
resource sshFromBastionNSGRule 'Microsoft.Network/networkSecurityGroups/securityRules@2021-02-01' = {
  name: 'debugVM-nsg/AllowSSHFromBastion'
  properties: {
    protocol: 'Tcp'
    sourcePortRange: '*'
    destinationPortRange: '22'
    sourceAddressPrefix: '10.0.1.0/27' // Address range of the AzureBastionSubnet
    destinationAddressPrefix: '*'
    access: 'Allow'
    priority: 110
    direction: 'Inbound'
  }
}


// Azure Bastion Resource
resource bastion 'Microsoft.Network/bastionHosts@2021-02-01' = {
  name: 'bastionHost'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'bastionIpConfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetBastion.id
            //id: '${vnetHub.id}/subnets/AzureBastionSubnet'
            // id:  filter(vnetSpoke.properties.subnets, s => s.name == 'AzureBastionSubnet')[0].id
          }
          publicIPAddress: {
            id: bastionPublicIp.id
          }
        }
      }
    ]
  }
}


param bastionSubnetPrefix string = '10.2.0.0/27' // TODO make it reference the subnet

// NSG for Hub Network
resource hubNsg 'Microsoft.Network/networkSecurityGroups@2021-02-01' = {
  name: 'hubNsg'
  location: location
  properties: {
    securityRules: [
      // Deny all inbound traffic
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'Deny all inbound traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      // Deny all outbound traffic
      {
        name: 'DenyAllOutbound'
        properties: {
          description: 'Deny all outbound traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
      // Allow SSH from Bastion subnet
      {
        name: 'AllowSSHFromBastion'
        properties: {
          description: 'Allow SSH from Azure Bastion subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: bastionSubnetPrefix
          destinationAddressPrefix: '*' // Allowing SSH to all VNets, adjust as needed
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
    ]
  }
}




resource vmHub 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: 'vmHub'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_DS1_v2'
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '20.04-LTS'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
      }
    }
    osProfile: {
      computerName: 'vmHub'
      adminUsername: 'admin'
      adminPassword: 'SecurePassword123!' // Please use secure passwords and consider using Azure Key Vault
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic001.id
        }
      ]
    }
  }
}

resource nic001 'Microsoft.Network/networkInterfaces@2021-02-01' = {
  name: 'nic1'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnetHub.id
          }
        }
      }
    ]
  }
}

resource vmSpoke 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: 'vmSpoke'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_DS1_v2'
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '20.04-LTS'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
      }
    }
    osProfile: {
      computerName: 'debugVM1'
      adminUsername: 'admin'
      adminPassword: 'SecurePassword123!' // Please use secure passwords and consider using Azure Key Vault
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic002.id
        }
      ]
    }
  }
}



resource nic002 'Microsoft.Network/networkInterfaces@2021-02-01' = {
  name: 'nic002'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnetSpoke.id
          }
        }
      }
    ]
  }
}


param skuName string = 'Standard_GRS'
param vnetId string

// Resources
resource blob 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'blob'
  location: location
  sku: {
    name: skuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: [
        {          
          id: subnetAppService.id
          action: 'Allow'
        }
        {          
          id: vnetHub.id
          action: 'Allow'  //TODO remove after debugging
        }

      ]
      ipRules: []
      defaultAction: 'Deny'
    }
  }
}

// Outputs
output storageAccountId string = blob.id
output primaryBlobEndpoint string = blob.properties.primaryEndpoints['blob']




// Outputs
output nsgId string = hubNsg.id




// Outputs
output bastionPublicIpAddress string = bastionPublicIp.properties.ipAddress
output bastionId string = bastion.id
