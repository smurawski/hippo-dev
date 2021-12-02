#requires -module Az
param (
    [Parameter(ValueFromPipelineByPropertyName)]
    [string]
    $SubscriptionId = (Get-AzContext).Subscription.Id, 
    [Parameter(ValueFromPipelineByPropertyName)]
    [string]
    $ResourceGroupName = 'hippodev', 
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string]
    $VMName,
    [Parameter(ValueFromPipelineByPropertyName)]
    [string] 
    $Location = 'westus2',
    [string]
    $SourceIpAddress = (invoke-restmethod https://ifconfig.me/all.json -headers @{'Content-Type' = 'application/json'}).ip_addr,
    [string]
    $GitHubProjectOrg = 'smurawski',
    [string]
    $GitHubProjectName = 'hippo-dev',
    [string]
    $GitHubProjectBranch = 'main',
    [switch]
    $Force
)

begin {
    if ($Force) {
        Write-Verbose "Removing any previous resource group."
        Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue | Remove-AzResourceGroup -Force
    }
    if ((-not (test-path ./id_rsa.pub)) -and (test-path ~/.ssh/id_rsa.pub) ) {
        copy-item ~/.ssh/id_rsa.pub
    }

    foreach ($file in ('cloud-init.yaml', 'vm.bicep', 'main.bicep')) {
        if ((-not (Test-Path $file)) -or ($Force)) {
            Invoke-RestMethod -OutFile $file -Uri "https://raw.githubusercontent.com/$GitHubProjectOrg/$GitHubProjectName/$GitHubProjectBranch/$file"
        }
    }    

    $OldPath = $env:Path

    if (get-command bicep -ErrorAction SilentlyContinue)  {
        Write-Verbose "Found the Bicep CLI.  Proceeding..."
    }
    elseif (get-command az -ErrorAction SilentlyContinue){
        az bicep install | out-null
        $BicepPath = (Resolve-Path '~/.azure/bin').ProviderPath
        $env:Path += [System.IO.Path]::PathSeparator + $BicepPath + [System.IO.Path]::PathSeparator
    }
    else {
        throw "The Bicep CLI is required to deploy this solution."
    }
}

process {
    Set-AzContext -SubscriptionId $SubscriptionId
    $location = $Location.ToLower()

    $Parameters = @{
        rgName = $ResourceGroupName
        vmName = $VMName
        location = $Location
    }
    
    $DeploymentName = $ResourceGroupName + $VMName 
    try {
        $Deployment = New-AzSubscriptionDeployment -Name $DeploymentName -Location $Location -TemplateFile './main.bicep' -TemplateParameterObject $Parameters -ErrorAction Stop
        $VMDNSNAME = $Deployment.Outputs['fqdn'].Value
    }
    catch {
        $env:Path = $OldPath
        remove-item ./id_rsa.pub
        throw $_
    }

    $JitRequestBody = @"
{
    "virtualMachines": [
        {
            "id": "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Compute/virtualMachines/$VMName",
            "ports": [
                {
                    "number": 22,
                    "protocol": "*",
                    "allowedSourceAddressPrefix": "$SourceIPAddress",
                    "duration": "PT3H"
                }
            ]
        }
    ]
}
"@

    $InitiateParameters = @{
        Method = 'POST'
        ResourceGroupName = $ResourceGroupName
        SubscriptionId = $SubscriptionId
        ResourceProviderName = 'Microsoft.Security'
        ResourceType = "locations/$location/jitNetworkAccessPolicies"
        Name = "default/initiate"
        ApiVersion = '2015-06-01-preview'
        Payload = $JitRequestBody
    }

    $Result = Invoke-AzRestMethod @InitiateParameters |
                            Select-Object -ExpandProperty Content |
                            ConvertFrom-Json -Depth 100


    Write-Host "Access your vm with  ssh ubuntu@$VMDNSNAME"
    Write-Host ""
    Write-Host "To access the Hippo dashboard https://${VMDNSNAME}:5001"
    Write-Host ""
    Write-Host "To access the Bindle API https://${VMDNSNAME}:8080/v1"
    Write-Host ""
    Write-Host "Please note the dashboard will take a few minutes as we are building it from source"

    Write-Host "You can start a new WASM project with:"
    Write-Host "  `$env:USER = 'admin'"
    Write-Host "  `$env:HIPPO_USERNAME ='admin'"
    Write-Host "  `$env:HIPPO_PASSWORD = 'Passw0rd!'"
    Write-Host "  `$env:HIPPO_URL = 'https://${VMDNSNAME}:5001'"
    Write-Host "  `$env:BINDLE_URL = 'http://${VMDNSNAME}:8080/v1'"
    Write-Host "  `$env:GLOBAL_AGENT_FORCE_GLOBAL_AGENT = 'false'"
    Write-Host "  yo wasm"
}
end {
    $env:Path = $OldPath
    remove-item ./id_rsa.pub
}