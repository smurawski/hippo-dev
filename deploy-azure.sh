#!/bin/bash

set -e
set -o pipefail

if [ ! -v SUB]
then
  read -p "Enter the subscription to use: "  SUB
fi

if [ ! -v LOCATION]
then
  read -p "Enter the location for the resource group: " LOCATION
fi

if [ ! -v RS]
then
  read -p "Enter the resource group for the vm: " RS
fi

if [ ! -v VMNAME]
then
  read -p "Enter the name for the vm: " VMNAME
fi


az account set --subscription "$SUB"

curl -L -o cloud-init.txt 'https://raw.githubusercontent.com/smurawski/hippo-dev/main/cloud-init.yaml'

$VMDNSNAME = az deployment sub create --location eastus --template-file ./main.bicep -o tsv --query 'properties.outputs.fqdn.value' --parameters rgName=$RS vmName=$VMNAME location=$LOCATION

echo "Access your vm with  ssh ubuntu@$VMDNSNAME"
echo ""
echo "To access the Hippo dashboard https://$VMDNSNAME:5001"
echo ""
echo "To access the Bindle API https://$VMDNSNAME:8080/v1"
echo ""
echo "Please note the dashboard will take a few minutes as we are building it from source"
