param vmName string = 'hippo-dev'

@description('Unique DNS Name for the Storage Account where the Virtual Machine\'s disks will be placed.')
param dnsLabelPrefix string

@description('User name for the Virtual Machine.')
param adminUsername string = 'ubuntu'

@description('String passed down to the Virtual Machine.')
param customData string = loadTextContent('./cloud-init.yaml')

@description('VM size')
param vmSize string = 'Standard_D2_v3'

@description('The Ubuntu version for the VM. This will pick a fully patched image of this given Ubuntu version. Allowed values: 14.04-LTS,16.04-LTS,18.04-LTS,20.04-LTS.')
@allowed([
  '20_04-lts'
])
param ubuntuOSVersion string = '20_04-lts'

@description('Location for all resources.')
param location string

@description('Type of authentication to use on the Virtual Machine. SSH key is recommended.')
@allowed([
  'sshPublicKey'
  'password'
])
param authenticationType string = 'sshPublicKey'

@description('SSH Key or password for the Virtual Machine. SSH key is recommended.')
@secure()
param adminPasswordOrKey string

var storageAccountName_var = '${uniqueString(resourceGroup().id)}sacustmdata'
var imagePublisher = 'Canonical'
var imageOffer = '0001-com-ubuntu-server-focal'
var nicName_var = 'networkInterface1'
var virtualNetworkName_var = 'virtualNetwork1'
var publicIPAddressName_var = 'publicIp1'
var addressPrefix = '10.0.0.0/16'
var subnet1Name = 'Subnet-1'
var subnet1Prefix = '10.0.0.0/24'
var publicIPAddressType = 'Dynamic'
var storageAccountType = 'Standard_LRS'
var apiVersion = '2015-06-15'
var linuxConfiguration = {
  disablePasswordAuthentication: true
  ssh: {
    publicKeys: [
      {
        path: '/home/${adminUsername}/.ssh/authorized_keys'
        keyData: adminPasswordOrKey
      }
    ]
  }
}
var networkSecurityGroupName_var = 'default-NSG'

resource storageAccountName 'Microsoft.Storage/storageAccounts@2021-01-01' = {
  name: storageAccountName_var
  kind: 'StorageV2' 
  location: location
  sku: {
    name: storageAccountType
  }
  properties: {
    accessTier: 'Hot'
  }
}

resource publicIPAddressName 'Microsoft.Network/publicIPAddresses@2015-06-15' = {
  name: publicIPAddressName_var
  location: location
  properties: {
    publicIPAllocationMethod: publicIPAddressType
    dnsSettings: {
      domainNameLabel: dnsLabelPrefix
    }
  }
}

resource networkSecurityGroupName 'Microsoft.Network/networkSecurityGroups@2019-08-01' = {
  name: networkSecurityGroupName_var
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-hippo'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '5000-5004'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'allow-bindle'
        properties: {
          priority: 1010
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '8080-8081'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource virtualNetworkName 'Microsoft.Network/virtualNetworks@2015-06-15' = {
  name: virtualNetworkName_var
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: subnet1Name
        properties: {
          addressPrefix: subnet1Prefix
          networkSecurityGroup: {
            id: networkSecurityGroupName.id
          }
        }
      }
    ]
  }
}

resource nicName 'Microsoft.Network/networkInterfaces@2015-06-15' = {
  name: nicName_var
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIPAddressName.id
          }
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName_var, subnet1Name)
          }
        }
      }
    ]
  }
  dependsOn: [
    virtualNetworkName
  ]
}

resource vm 'Microsoft.Compute/virtualMachines@2016-04-30-preview' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
      customData: base64(customData)
      linuxConfiguration: ((authenticationType == 'password') ? json('null') : linuxConfiguration)
    }
    storageProfile: {
      imageReference: {
        publisher: imagePublisher
        offer: imageOffer
        sku: ubuntuOSVersion
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicName.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: reference(storageAccountName_var, apiVersion).primaryEndpoints.blob
      }
    }
  }
  dependsOn: [
    storageAccountName
  ]
}

resource jit 'Microsoft.Security/locations/jitNetworkAccessPolicies@2015-06-01-preview' = {
  name: '${location}/default'
  kind: 'Basic'
  properties: {
    virtualMachines: [
        {
          id: vm.id
          ports: [
              {
                  number: 22
                  protocol: '*'
                  allowedSourceAddressPrefix: '*'
                  allowedSourceAddressPrefixes: null
                  maxRequestAccessDuration: 'PT3H'
              }
          ]
      }
    ]
  }
}

output fqdn string = publicIPAddressName.properties.dnsSettings.fqdn
