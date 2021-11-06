#!/bin/bash

set -e
set -o pipefail

if [ -z "$SUB" ]
then
  read -p "Enter the subscription to use: "  SUB
fi

if [ -z "$LOCATION" ]
then
  read -p "Enter the location for the resource group: " LOCATION
fi

if [ -z "$RS" ]
then
  read -p "Enter the resource group for the vm: " RS
fi

if [ -z "$VMNAME" ]
then
  read -p "Enter the name for the vm: " VMNAME
fi


az account set --subscription "$SUB"

BASEURL='https://raw.githubusercontent.com/smurawski/hippo-dev/bicep'

if [ ! -f './cloud-init.yaml' ]
then
  curl -L -o cloud-init.yaml "$BASEURL/cloud-init.yaml"
fi

if [ ! -f './main.bicep' ]
then
  curl -L -o main.bicep "$BASEURL/main.bicep"
fi
if [ ! -f './vm.bicep' ]
then
  curl -L -o vm.bicep "$BASEURL/vm.bicep"
fi

if [ ! -f './id_rsa.pub' ]
then
  cp ~/.ssh/id_rsa.pub .
fi

VMDNSNAME=$(az deployment sub create --name "$RS_$VMNAME" --location $LOCATION --template-file ./main.bicep -o tsv --query 'properties.outputs.fqdn.value' --parameters rgName=$RS vmName=$VMNAME location=$LOCATION)

SOURCEIPADDRESS=$(curl 'ifconfig.me/ip')
INITIATEBODY=$(cat << EOF
{
    "virtualMachines": [
        {
            "id": "/subscriptions/$SUB/resourceGroups/$RS/providers/Microsoft.Compute/virtualMachines/$VMNAME",
            "ports": [
                {
                    "number": 22,
                    "protocol": "*",
                    "allowedSourceAddressPrefix": "$SOURCEIPADDRESS",
                    "duration": "PT3H"
                }
            ]
        }
    ]
}
EOF
)

az rest --method POST --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RS/providers/Microsoft.Security/locations/$LOCATION/jitNetworkAccessPolicies/default/initiate?api-version=2015-06-01-preview" --headers "Content-Type=application/json" --body "$INITIATEBODY"

echo "Access your vm with  ssh ubuntu@$VMDNSNAME"
echo ""
echo "To access the Hippo dashboard https://$VMDNSNAME:5001"
echo ""
echo "To access the Bindle API https://$VMDNSNAME:8080/v1"
echo ""
echo "Please note the dashboard will take a few minutes as we are building it from source"
