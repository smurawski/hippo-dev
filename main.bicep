targetScope = 'subscription'

param location string = 'eastus'
param rgName string = 'hippodevdeploy'
param vmName string = 'hippodeploy'
param vmDnsName string = vmName

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
  }
}

output fqdn string = vm.outputs.fqdn
