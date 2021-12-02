targetScope = 'subscription'

param location string 
param rgName string 
param vmName string 
param vmDnsName string = vmName
param customData string = loadTextContent('./cloud-init.yaml')

var publicSSHKey = loadTextContent('./id_rsa.pub')


resource rg 'Microsoft.Resources/resourceGroups@2020-06-01' = {
  name: rgName
  location: location
}

module vm './vm.bicep' = {
  name: vmName
  scope: resourceGroup(rg.name)
  params: {
    vmName: vmName
    location: location
    adminUsername: 'ubuntu'
    dnsLabelPrefix: vmDnsName
    adminPasswordOrKey: publicSSHKey
    customData: customData
  }
}

output fqdn string = vm.outputs.fqdn
