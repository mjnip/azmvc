#Set parameters

Param(
    [Parameter(Mandatory=$true)][string]$ApplicationName,
    [Parameter(Mandatory=$true)][string]$BranchName,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true,
                HelpMessage="Enter a valid subscription code as four lowercase alphanumeric characters")]
    [ValidatePattern('^[a-z0-9]{4}$',Options=0)]$SubscriptionCode,
    [Parameter(Mandatory=$false)][string]$AzurePipelineModulePath = "./Azure.Pipeline",
	[switch]$UploadArtifacts
)

# Initialise variables

$scriptName = ($($MyInvocation.MyCommand.Name) -Split(".ps1"))[0]
$startTime = Get-Date -format yyyyMMddmmss

# The below values are intended for the management KeyVaults in each service tier
# If set incorrectly, deployments will fail
$keyVault = @{ "lab" = @{ "canadacentral" = "l0001sjr3viddymnfqo"; "eastus2" = "l0001sq5marmxanuzgs" } },
            @{ "nonproduction" = @{ "canadacentral" = "n0001swcnaueaohfmwo"; "eastus2" = "n0001s5zaztp56xuoqm" } },
            @{ "production" = @{ "canadacentral" = "p0001sl7aohr7rcbg7i"; "eastus2" = "p0001s2cy5qlvuspjss" } };


function Write-PipelineLog {
    Param(
        [Parameter(Mandatory=$true)][string]$LogFileDate,
        [Parameter(Mandatory=$true)][string]$LogName,
        [Parameter(Mandatory=$true)][string]$Message
    )
}


#FUNCTION Set-DeployParametersRepository
# Checks out the parameters repository




Function Set-DeployParametersRepository {
    try {
        git checkout -f "origin1/$($BranchName)"
        if ($LASTEXITCODE -ne 0) {
            throw { "Could not checkout parameter repository commit" }
        }
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "SUCCESS - $($MyInvocation.MyCommand.Name)"
    }
    catch {
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "FAIL - $($MyInvocation.MyCommand.Name) $($_.Exception)"
        exit(1)
    }
}


#FUNCTION Set-DeployServiceTierVariables
# Determines the Service Tier that's being deployed based on the branch and sets the appropriate variables globally

Function Set-DeployServiceTierVariables {
    try {
        $deployProperties = @{}
        switch (($BranchName -Split "-")[0]) {
            "lab" { $deployProperties.Add("serviceTier", "lab") }
            "nonproduction" { $deployProperties.Add("serviceTier", "nonproduction") }
            "production" { $deployProperties.Add("serviceTier", "production") }
            default { throw "Invalid service tier selected" }
        }
        $deployProperties.Add("environmentName", ($BranchName -Split "-")[1])
        $deployProperties.Add("subscriptionName", "$($deployProperties.serviceTier[0])$($SubscriptionCode)d")
        $deployProperties.Add("applicationName", "$($ApplicationName)")
        $deployProperties.Add("resourceGroupName", "$($ResourceGroupName)")
        $deployProperties.Add("parameters", (Get-Content "$($deployProperties.applicationName)-arm-parameters.json" | Out-String | ConvertFrom-Json))
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "SUCCESS - $($MyInvocation.MyCommand.Name)"
        return $deployProperties
    }
    catch {
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "FAIL - $($MyInvocation.MyCommand.Name) $($_.Exception)"
        exit(1)
    }
}


#FUNCTION Connect-DeployAzure
# Connects to the Azure Account with the appropriate Service Principal


Function Connect-DeployAzure {
    Param(
    [Parameter(Mandatory=$true)][string]$ServiceTier,
    [Parameter(Mandatory=$true)][string]$SubscriptionName
    )
    try {
        $credentials = [environment]::GetEnvironmentVariable("azure_$ServiceTier")
        Connect-PipelineAzure -ClientId ($credentials -Split (':'))[0] -Key ($credentials -Split (':'))[1]
        Select-AzureRmSubscription -SubscriptionName $SubscriptionName
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "SUCCESS - $($MyInvocation.MyCommand.Name)"
    }
    catch {
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "FAIL - $($MyInvocation.MyCommand.Name) $($_.Exception)"
        exit(1)
    }
}


#FUNCTION New-DeployResourceGroup
# Creates a new Resource Group and tags it appropriately


Function New-DeployResourceGroup {
    Param(
    [Parameter(Mandatory=$true)][string]$ApplicationName,
    [Parameter(Mandatory=$true)][string]$SubscriptionCode,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true)][string]$ResourceGroupRegion,
    [Parameter(Mandatory=$true)][string]$BranchName
    )
    try {
        $resourceGroupTags = @{
          "subscription_code" = $SubscriptionCode;
          "application_id" = $env:application_id;
          "git_commit" = $env:GIT_COMMIT;
          "application_name" = $ApplicationName;
          "git_branch" = $BranchName;
          "build_number" = $env:BUILD_NUMBER;
          "owner" = ($env:BITBUCKET_PAYLOAD | Out-String | ConvertFrom-Json).actor.username;
          "creation_time" = [Math]::Floor([decimal](Get-Date(Get-Date).ToUniversalTime()-uformat "%s"));
        }
        New-AzureRmResourceGroup -ResourceGroupName $ResourceGroupName -Location $ResourceGroupRegion -Tag $resourceGroupTags
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "SUCCESS - $($MyInvocation.MyCommand.Name)"
    }
    catch {
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "FAIL - $($MyInvocation.MyCommand.Name) $($_.Exception)"
        exit(1)
    }
}

Function New-DeployResourceGroupNested {
    Param(
    [Parameter(Mandatory=$true)][string]$ApplicationName,
    [Parameter(Mandatory=$true)][string]$SubscriptionCode,
    [Parameter(Mandatory=$true)][string[]]$ResourceGroupNames,
    [Parameter(Mandatory=$true)][string]$ResourceGroupRegion,
    [Parameter(Mandatory=$true)][string]$BranchName
    )
    try {
        $resourceGroupTags = @{
          "subscription_code" = $SubscriptionCode;
          "application_id" = $env:application_id;
          "git_commit" = $env:GIT_COMMIT;
          "application_name" = $ApplicationName;
          "git_branch" = $BranchName;
          "build_number" = $env:BUILD_NUMBER;
          "owner" = ($env:BITBUCKET_PAYLOAD | Out-String | ConvertFrom-Json).actor.username;
          "creation_time" = [Math]::Floor([decimal](Get-Date(Get-Date).ToUniversalTime()-uformat "%s"));
        }
		ForEach ($resourceGroupName in $resourceGroupNames)
		{
			New-AzureRmResourceGroup -ResourceGroupName $ResourceGroupName -Location $ResourceGroupRegion -Tag $resourceGroupTags
			Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "SUCCESS - $($MyInvocation.MyCommand.Name)"
		}        
    }
    catch {
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "FAIL - $($MyInvocation.MyCommand.Name) $($_.Exception)"
        exit(1)
    }
}

#FUNCTION Set-DeployTemplateRepository
# Checks out the deployment template repository


Function Set-DeployTemplateRepository {
    Param(
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true)][string]$ServiceTier,
    [Parameter(Mandatory=$true)][string]$SubscriptionName,
    [Parameter(Mandatory=$false)][string]$TemplateBranch,
    [Parameter(Mandatory=$false)][string]$TemplateCommit

    )
    try {
        # Allow only lab deployments to deploy off a feature branch of the templates repository
        # If no templateBranch is present, build using the serviceTier
        # All nonproduction and production builds will use their respective branch
        switch ($ServiceTier) {
            "lab" { 
                if ( $TemplateBranch ) {
                    $templateCheckout = "origin2/$TemplateBranch"
                } else {
                    $templateCheckout = "origin2/lab"
                }
            }
            "nonproduction" { $templateCheckout = "origin2/nonproduction" }
            "production" { $templateCheckout = "origin2/production" }
        }

        # If TemplateCommit has been passed in parameters, override branch and checkout that specific commit
        if( $TemplateCommit ) {
            $templateCheckout = $TemplateCommit
        }

        git checkout -f "$templateCheckout"
        if ($LASTEXITCODE -ne 0) {
            throw { "Could not checkout template repository commit: $templateCheckout" }
        }
        $templateCommitId = git rev-parse HEAD
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "INFO - Building from: $templateCheckout"
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "INFO - Template commit ID is: $templateCommitId"
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "SUCCESS - $($MyInvocation.MyCommand.Name)"
    }
    catch {
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "FAIL - $($MyInvocation.MyCommand.Name) $($_.Exception)"
        # Deployment failed, delete the Resource Group if not lab
        Clear-DeployResourceGroup -ResourceGroupName $ResourceGroupName -ServiceTier $ServiceTier -SubscriptionName $SubscriptionName
        exit(1)
    }
}


#FUNCTION Set-DeployMandatoryParameters
# Determines the existence of mandatory parameters when the ARM template containts a Virtual Machine or Virtual Machine Scaleset


Function Set-DeployMandatoryParameters {
    Param(
    [Parameter(Mandatory=$true)][System.Object]$Parameters,
    [Parameter(Mandatory=$true)][string]$ApplicationName,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true)][string]$SubscriptionName,
    [Parameter(Mandatory=$true)][string]$ServiceTier
    )
    try {
        # Set some enforcement variables. If these are set to true, further down we're going to override these template parameters when we deploy
        $enforceVirtualMachineAdminPassword = $false
        $enforcePuppetMaster = $false

        $template = Get-Content "$($ApplicationName)-main.json" | Out-String | ConvertFrom-Json
        foreach ($resource in $template.Resources) {
            # Check if the Template has an Azure VM
            if ($resource.type -eq "Microsoft.Compute/virtualMachines") {
                # Azure VM detected, so lets make sure the appropriate template parameters are being enforced
                $enforceVirtualMachineAdminPassword = $true
                $enforcePuppetMaster = $true

                # If the template has a VM, but the admin password is not being set by the parameter "virtual_machine_admin_password" fail the build
                if ($resource.properties.osProfile.adminPassword -ne "[parameters('adminPassword')]") {
                    throw "Template contains an Azure VM which is setting an invalid admin password. Admin password must be set to ""[parameters('adminPassword')]"""
                }
            }

            # Check if the template has a Virtual Machine ScaleSet
            if ($resource.type -eq "Microsoft.Compute/virtualMachineScaleSets") {
                # Virtual Machine Scale Sets detected, so lets make sure the appropriate template parameters are being enforced
                $enforceVirtualMachineAdminPassword = $true
                $enforcePuppetMaster = $true

                # If the template has a VM, but the admin password is not being set by the parameter "virtual_machine_admin_password" fail the build
                if ($resource.properties.virtualMachineProfile.osProfile.adminPassword -ne "[parameters('adminPassword')]") {
                    throw "Template contains an Virtual Machine Scale Set which is setting an invalid admin password. Admin password must be set to ""[parameters('adminPassword')]"""
                }
            }
        }
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "SUCCESS - $($MyInvocation.MyCommand.Name)"
        return @{ "adminPassword" = $enforceVirtualMachineAdminPassword; "Puppet_master" = $enforcePuppetMaster}
    }
    catch {
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "FAIL - $($MyInvocation.MyCommand.Name) $($_.Exception)"
        # Deployment failed, delete the Resource Group if not lab
        Clear-DeployResourceGroup -ResourceGroupName $ResourceGroupName -ServiceTier $ServiceTier -SubscriptionName $SubscriptionName
        exit(1)
    }
}


#FUNCTION New-VirtualMachineAdministratorPassword
# Generates a new virtual machine administrator password and saves it in Key Vault


Function New-DeployVirtualMachineAdministratorPassword {
    Param(
    [Parameter(Mandatory=$true)][object]$Parameters,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true)][string]$SubscriptionName,
    [Parameter(Mandatory=$true)][string]$ServiceTier
    )
    try {
        # Generate the password
        $virtualMachineAdminPassword = $([System.Web.Security.Membership]::GeneratePassword(32,8))
        $secureVirtualMachineAdminPassword = ConvertTo-SecureString $virtualMachineAdminPassword -AsPlainText -Force


        # Make sure we have access to the management KeyVaults
        $pipelineSP = (([environment]::GetEnvironmentVariable("azure_$ServiceTier")) -Split (':'))[0]
        Select-AzureRmSubscription -SubscriptionName "$($ServiceTier[0])0001s" | Out-Null
        Set-AzureRmKeyVaultAccessPolicy -VaultName $keyVault."$ServiceTier".canadacentral -ServicePrincipalName $pipelineSP -PermissionsToSecrets get,set
        Set-AzureRmKeyVaultAccessPolicy -VaultName $keyVault."$ServiceTier".eastus2 -ServicePrincipalName $pipelineSP -PermissionsToSecrets get,set

        # Add the virtual machine admin password to both key vaults. Use the git commit as the key as keys must only contain alphanumeric characters. Resource group name and subscription code stored as tags on the key
        Set-AzureKeyVaultSecret -VaultName $keyVault."$ServiceTier".canadacentral -Name "virtualMachineAdminPassword$($env:GIT_COMMIT)" -SecretValue $secureVirtualMachineAdminPassword -Tags @{ "subscription_code" = $SubscriptionCode; "resource_group_name" = $ResourceGroupName } | Out-Null
        Set-AzureKeyVaultSecret -VaultName $keyVault."$ServiceTier".eastus2 -Name "virtualMachineAdminPassword$($env:GIT_COMMIT)" -SecretValue $secureVirtualMachineAdminPassword -Tags @{ "subscription_code" = $SubscriptionCode; "resource_group_name" = $ResourceGroupName } | Out-Null

         # For a lab/nonprod/prod deployment, ensure we write the virtual machine admin password to the business keyvault as well
        foreach ($businessKeyVault in $Parameters.KeyVault) {
        Set-AzureRmKeyVaultAccessPolicy -VaultName $businessKeyVault -ServicePrincipalName $pipelineSP -PermissionsToSecrets get,set
        Set-AzureKeyVaultSecret -VaultName $businessKeyVault -Name "virtualMachineAdminPassword$($env:GIT_COMMIT)" -SecretValue $secureVirtualMachineAdminPassword -Tags @{ "subscription_code" = $SubscriptionCode;"resource_group_name" = $ResourceGroupName} | Out-Null
        }
        
        #Switch back to business subscription 
        Select-AzureRmSubscription -SubscriptionName $SubscriptionName | Out-Null

        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "SUCCESS - $($MyInvocation.MyCommand.Name)"
        return $virtualMachineAdminPassword
    }
    catch {
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "FAIL - $($MyInvocation.MyCommand.Name) $($_.Exception)"
        # Deployment failed, delete the Resource Group if not lab
        Clear-DeployResourceGroup -ResourceGroupName $ResourceGroupName -ServiceTier $ServiceTier -SubscriptionName $SubscriptionName
        exit(1)
    }
}


## FUNCTION New-DeployTemplate
# Deployments ARM template into previously created Resource Group


Function New-DeployTemplate {
    Param(
    [Parameter(Mandatory=$true)][object]$Parameters,
    [Parameter(Mandatory=$true)][string]$ApplicationName,
    [Parameter(Mandatory=$true)][string]$EnvironmentName,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true)][string]$SubscriptionName,
    [Parameter(Mandatory=$true)][string]$ServiceTier,
    [Parameter(Mandatory=$true)][hashtable]$MandatoryParameters,
    [Parameter(Mandatory=$false)][string]$VirtualMachineAdminPassword,
    [Parameter(Mandatory=$false)][string]$PuppetMaster = "puppet.example.com"
    )
    try {
        # Prepare a splat for the template parameter overrides by updating the hashtable that has been passed in
        if ($MandatoryParameters.virtual_machine_admin_password -eq $true) {
            $MandatoryParameters.virtual_machine_admin_password = (ConvertTo-SecureString $VirtualMachineAdminPassword -AsPlainText -Force)
        }
        else {
            $MandatoryParameters.Remove("virtual_machine_admin_password")
        }
        if ($MandatoryParameters.puppet_master -eq $true) {
            $MandatoryParameters.puppet_master = $PuppetMaster
        }
        else {
            $MandatoryParameters.Remove("puppet_master")
        }
        # Generate a guid, output the template using the guid as a file name
        $paramGuid = ([guid]::NewGuid()).guid
        $Parameters.templateParameters | ConvertTo-Json -Depth 99 | Out-File "$($paramGuid).json"

        #Setup deployment Name 
        $deploymentName = $ResourceGroupName

        # Perform the deployment
        # -Name parameter is used for the deployment Name to assign a new deployment name for each deployed resource group so it won't reach out the 800 limit on resources.
        $deployment = New-AzureRmResourceGroupDeployment -Name $deploymentName -ResourceGroupName $ResourceGroupName -TemplateParameterFile "$($paramGuid).json" -TemplateFile "$($ApplicationName)-arm-template.json" @MandatoryParameters -Verbose -ErrorVariable deploymentError

        if( $deploymentError ) {
            throw("ARM template deployment generated errors:`n`n$($deploymentError)`n`n")
        }

        # Output back to the pipeline how the deployment went, minus the Outputs
        $deploymentResult = New-Object PSObject -Property @{ "DeploymentName" = $deployment.DeploymentName;
        "ResourceGroupName" = $deployment.ResourceGroupName;
        "ProvisioningState" = $deployment.ProvisioningState;
        "Timestamp" = $deployment.Timestamp}
        Write-Host $deploymentResult

        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "SUCCESS - $($MyInvocation.MyCommand.Name)"

        # Return the outputs back to the main
        return $deployment.Outputs
    }
    catch {
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "FAIL - $($MyInvocation.MyCommand.Name) $($_.Exception)"
        # Deployment failed, delete the Resource Group if not lab
        Clear-DeployResourceGroup -ResourceGroupName $ResourceGroupName -ServiceTier $ServiceTier -SubscriptionName $SubscriptionName
        exit(1)
    }
}


## FUNCTION Set-DeployOutput
# Will output back to Jenkins appropriate components, write to Azure Storage Tables the deployment outputs and write any output that contains 'key' or 'password' to the KeyVault


Function Set-DeployOutput {
    Param(
    [Parameter(Mandatory=$true)][object]$Parameters,
    [Parameter(Mandatory=$true)][object]$DeploymentOutputs,
    [Parameter(Mandatory=$true)][string]$ServiceTier,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true)][string]$SubscriptionName

    )
    try {
        # Prepare an Azure Storage Table Entity object
        Import-Module Azure.Storage
        $entity = New-Object -TypeName Microsoft.WindowsAzure.Storage.Table.DynamicTableEntity -ArgumentList "pipeline", $ResourceGroupName

        # Ensure the Service Principal can write secrets to the Key Vault
        $pipelineSP = (([environment]::GetEnvironmentVariable("azure_$ServiceTier")) -Split (':'))[0]
        # Filter through all of the outputs
        Write-Host "---- Deployment Outputs ----"
        foreach ($deploymentOutput in $DeploymentOutputs.GetEnumerator())
        {
            # If the output contains "password" or "key" we want to commit it to KeyVault
            if (($deploymentOutput.Key -like '*password*') -or ($deploymentOutput.Key -like '*key*')) {
                # If this is a password or secret, hash out the value
                Write-Host "$($deploymentOutput.key) : ********"

                # Create a guid, and add that to our entity, we'll use the guid to write the actual value to KeyVault
                $secretGuid = [guid]::NewGuid()
                $entity.Properties.Add($deploymentOutput.key, $secretGuid)

                # Check if we have a KeyVault instance, if we don't fail the deployment
                if ($Parameters.KeyVault -eq $NULL -or $Parameters.KeyVault -eq "") {
                    throw "Template outputs secrets, but no KeyVault was defined in the deployment parameters"
                }

                 # Commit the secret to all Key Vault's specified in the input parameters
                Select-AzureRmSubscription -SubscriptionName "$($ServiceTier[0])0001s" | Out-Null
                foreach ($businessKeyVault in $Parameters.KeyVault) {                    
                    Set-AzureRmKeyVaultAccessPolicy -VaultName $businessKeyVault -ServicePrincipalName $pipelineSP -PermissionsToSecrets get,set
                    Set-AzureKeyVaultSecret -VaultName $businessKeyVault -Name $secretGuid.Guid -SecretValue (ConvertTo-SecureString $deploymentOutput.value.value -AsPlainText -Force) -Tags @{ "subscription_code" = $SubscriptionCode;"resource_group_name" = $ResourceGroupName; "template_output_parameter" = $deploymentOutput.Key } | Out-Null
                }
                Select-AzureRmSubscription -SubscriptionName $SubscriptionName | Out-Null
            }
            else {
                # Just echo out the value if it's not a secret
                Write-Host "$($deploymentOutput.key) : $($deploymentOutput.value.value)"

                # Check if we have an array data type, flatten and store as a string
                if ($deploymentOutput.value.value -is [Newtonsoft.Json.Linq.JArray]) {
                    $deploymentOutputAsString = ($deploymentOutput.value.value | % { "$_" }) -join ';'
                    $entity.Properties.Add($deploymentOutput.key, $deploymentOutputAsString)
                }
                # Check if we have a null value or object data type, warn user these values will not be stored
                elseif (($deploymentOutput.value.value -is [Newtonsoft.Json.Linq.JObject]) -Or ($deploymentOutput.value.value -eq $null)) {
                    Write-Host "WARNING: $($deploymentOutput.key) is NULL or of data type 'object' and will not be stored..."
                }
                # Store all other data types
                else {
                    $entity.Properties.Add($deploymentOutput.key, $deploymentOutput.value.value)
                }
            }
        }

        # Get both Canada Central and East US 2 base Storage Accounts. Filter in place due to additional storage accounts having been created at time of writing
        $CanadaCentralStorage = (Get-AzureRmStorageAccount -ResourceGroupName base-canadacentral | where {$_.StorageAccountName -notmatch '^.*(nsg)|(vm)$'})[0].StorageAccountName
        $EastUS2Storage = (Get-AzureRmStorageAccount -ResourceGroupName base-eastus2 | where {$_.StorageAccountName -notmatch '^.*(nsg)|(vm)$'})[0].StorageAccountName
        $storageAccounts = @{"base-canadacentral" = $CanadaCentralStorage; "base-eastus2" = $EastUS2Storage }

        # Write the outputs to all regional Storage Accounts
        foreach ($storageAccount in $storageAccounts.GetEnumerator()) {
            $context = New-AzureStorageContext -StorageAccountName $storageAccount.Value -StorageAccountKey (Get-AzureRmStorageAccountKey -StorageAccountName $storageAccount.Value -ResourceGroupName $storageAccount.Name).value[0]

            # Check if pipeline table exists
            $tableName = 'pipeline'
            $table = Get-AzureStorageTable -Name $tableName -Context $context -ErrorAction 'Ignore'

            # Create new table if it does not exist
            if ($table -eq $null) {
                $table = New-AzureStorageTable -Name $tableName -Context $context
            }

            # Write the entity to the table
            $result = $table.CloudTable.Execute([Microsoft.WindowsAzure.Storage.Table.TableOperation]::Insert($entity))
        }
        # Write to the console a URL with a SAS signature for accessing the parameters in Azure Storage Tables
        Write-Host (New-AzureStorageTableSASToken -Context $context -Name $tableName -StartTime (Get-Date) -ExpiryTime (Get-Date).AddYears(1000) -StartPartitionKey 'pipeline' -EndPartitionKey 'pipeline' -StartRowKey $ResourceGroupName -EndRowKey $ResourceGroupName -Permission r -FullUri -Protocol HttpsOnly)

        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "SUCCESS - $($MyInvocation.MyCommand.Name)"
    }
    catch {
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "FAIL - $($MyInvocation.MyCommand.Name) $($_.Exception)"
        # Deployment failed, delete the Resource Group if not lab
        Clear-DeployResourceGroup -ResourceGroupName $ResourceGroupName -ServiceTier $ServiceTier -SubscriptionName $SubscriptionName
        exit(1)
    }
}


## FUNCTION New-DeployDnsRecords
# Create DNS records for this deployment representing the applicaiton name and build number


Function New-DeployDnsRecords {
    Param(
    [Parameter(Mandatory=$true)][string]$PipelineDeploymentAddress,
    [Parameter(Mandatory=$true)][string]$SubscriptionName,
    [Parameter(Mandatory=$true)][string]$EnvironmentName,
    [Parameter(Mandatory=$true)][string]$ServiceTier
    )
    try {
        # Create A record in Azure DNS to represent this Resource Group
        $resourceGroupARecord = @()
        $resourceGroupARecord += New-AzureRmDnsRecordConfig -Ipv4Address $PipelineDeploymentAddress
        $resourceGroupRecordSet = New-AzureRmDnsRecordSet -Name $ResourceGroupName -RecordType A -Ttl 60 -ZoneName "$($SubscriptionName).00azr.net" -ResourceGroupName base-global -DnsRecords $resourceGroupARecord

        # Create CNAME with build information to represent this deployment
        $deploymentCnameRecord = @()
        $deploymentCnameRecord += New-AzureRmDnsRecordConfig -Cname "$($resourceGroupRecordSet.Name).$($resourceGroupRecordSet.ZoneName)"
        $deploymentCnameRecordSet = New-AzureRmDnsRecordSet -Name "$($ApplicationName)-$($EnvironmentName)-$($env:BUILD_NUMBER)" -RecordType CNAME -Ttl 60 -ZoneName "$($SubscriptionName).00azr.net" -ResourceGroupName base-global -DnsRecords $deploymentCnameRecord
        
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "SUCCESS - $($MyInvocation.MyCommand.Name)"
    } 
    catch {
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "FAIL - $($MyInvocation.MyCommand.Name) $($_.Exception)"
        # Deployment failed, delete the Resource Group if not lab
        Clear-DeployResourceGroup -ResourceGroupName $ResourceGroupName -ServiceTier $ServiceTier -SubscriptionName $SubscriptionName
        exit(1)
    }
}


## FUNCTION Set-DeployResourceGroupRBAC
# Assigns Reader role to AD groups created for the application team. These roles are assigned using the ObjectId
# The object ID's are hardcoded into the environment during onboarding
#
# NOTICE: This function contains no error checking as the expected output is an error due to a limitation using service principals to assign RBAC roles


Function Set-DeployResourceGroupRBAC {
    Param(
    [Parameter(Mandatory=$true)][string]$ServiceTier
    )
    if (($env:opsgroup_object_id -ne $NULL) -and ($env:devgroup_object_id -ne $NULL))  {
        switch ($ServiceTier) {
            "lab" { 
                New-AzureRmRoleAssignment -ObjectId $env:opsgroup_object_id -RoleDefinitionName "Application Owners" -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
                New-AzureRmRoleAssignment -ObjectId $env:devgroup_object_id -RoleDefinitionName "Application Owners" -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
             }
             "nonproduction" {
                New-AzureRmRoleAssignment -ObjectId $env:opsgroup_object_id -RoleDefinitionName "Reader" -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
                New-AzureRmRoleAssignment -ObjectId $env:devgroup_object_id -RoleDefinitionName "Reader" -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
             }
             "production" {
                 New-AzureRmRoleAssignment -ObjectId $env:opsgroup_object_id -RoleDefinitionName "Reader" -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
             }
        } 
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "SUCCESS - $($MyInvocation.MyCommand.Name)"
    }
    else {
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "INFO - $($MyInvocation.MyCommand.Name) - No action taken, AD groups not present for this application"
    }
}


## FUNCTION Clear-DeployResourceGroup
# Deletes the newly created Resource Group. To be executed if a deployment fails. Execute only in nonproduction and prodcution.


Function Clear-DeployResourceGroup {
    Param(
    [Parameter(Mandatory=$true)][string]$ServiceTier,
    [Parameter(Mandatory=$true)][string]$SubscriptionName,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName
    )
    if ($ServiceTier -ne "lab") {
        Select-AzureRmSubscription -SubscriptionName $SubscriptionName
        Remove-AzureRmResourceGroup -ResourceGroupName $ResourceGroupName -Verbose -Force
    }
}

## FUNCTION New-DeployStorageBlobResourceGroup
# Creates a resource group for the deployment storage account 

Function New-DeployStorageBlobResourceGroup {
	Param(
    [Parameter(Mandatory=$true)][string]$ApplicationName,
    [Parameter(Mandatory=$true)][string]$SubscriptionCode,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true)][string]$ResourceGroupRegion,
    [Parameter(Mandatory=$true)][string]$BranchName
    )
	$ResourceGroupName = $ResourceGroupName + 'stage'
	New-DeployResourceGroup -ApplicationName $ApplicationName -SubscriptionCode $SubscriptionCode -ResourceGroupName $ResourceGroupName -resourceGroupRegion $ResourceGroupRegion -BranchName $BranchName
}

## FUNCTION Remove-DeployStorageBlobResourceGroup
# Creates a resource group for the deployment storage account 

Function Remove-DeployStorageBlobResourceGroup {
	Param(
    [Parameter(Mandatory=$true)][string]$ServiceTier,
    [Parameter(Mandatory=$true)][string]$SubscriptionName,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName
    )
	$ResourceGroupName = $ResourceGroupName + 'stage'
	Clear-DeployResourceGroup -ServiceTier $ServiceTier -SubscriptionName $SubscriptionName -ResourceGroupName $ResourceGroupName
}

## FUNCTION New-DeployStorageBlob
# Creates a storage account blob to upload deployment artifacts into, includes custom scripts, nested templates, etc.


Function New-DeployStorageBlob {
	Param(
    [Parameter(Mandatory=$true)][string]$ServiceTier,
    [Parameter(Mandatory=$true)][string]$SubscriptionName,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
	[Parameter(Mandatory=$true)][string]$ApplicationName,
	[Parameter(Mandatory=$true)][string]$ArtifactsStagingDirectory,
	[Parameter(Mandatory=$true)][string]$TemplateParameters,
    [Parameter(Mandatory=$true)][hashtable]$OptionalParameters

    )	

    $StorageContainerName = "stage"
	Select-AzureRmSubscription -SubscriptionName $SubscriptionName
	
	# Parse the parameter file and update the values of artifacts location and artifacts location SAS token if they are present
	$JsonParameters = $TemplateParameters
	if (($JsonParameters | Get-Member -Type NoteProperty 'parameters') -ne $null) {
		$JsonParameters = $JsonParameters.parameters
	}
    
	$ArtifactsLocationName = '_artifactsLocation'
	$ArtifactsLocationSasTokenName = '_artifactsLocationSasToken'
	$OptionalParameters[$ArtifactsLocationName] = $JsonParameters | Select -Expand $ArtifactsLocationName -ErrorAction Ignore | Select -Expand 'value' -ErrorAction Ignore
	$OptionalParameters[$ArtifactsLocationSasTokenName] = $JsonParameters | Select -Expand $ArtifactsLocationSasTokenName -ErrorAction Ignore | Select -Expand 'value' -ErrorAction Ignore

	
	$StorageAccountName = $ApplicationName + 'stg' + ((Get-AzureRmContext).Subscription.Id).Replace('-', '').substring(0, 20)
	$storageAccountName = $storageAccountName.Substring(0, [System.Math]::Min(24, $StorageAccountName.length))


	$StorageAccount = (Get-AzureRmStorageAccount | Where-Object{$_.StorageAccountName -eq $StorageAccountName})

	# Create the storage account if it doesn't already exist
	if ($StorageAccount -eq $null) {
		$ResourceGroupName = $ResourceGroupName + 'stage'
		New-AzureRmResourceGroup -Location "$ResourceGroupLocation" -Name $ResourceGroupName -Force
		$StorageAccount = New-AzureRmStorageAccount -StorageAccountName $StorageAccountName.ToLower() -Type 'Standard_LRS' -ResourceGroupName $ResourceGroupName -Location "$ResourceGroupLocation"
	}
	
	# Copy files from the local storage staging location to the storage account container
	New-AzureStorageContainer -Name $StorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue *>&1

	$ArtifactFilePaths = Get-ChildItem $ArtifactStagingDirectory -Recurse -File | ForEach-Object -Process {$_.FullName}	
		
	foreach ($SourcePath in $ArtifactFilePaths) {
		Set-AzureStorageBlobContent -File $SourcePath -Blob $SourcePath.Substring($ArtifactStagingDirectory.length + 1) `
			-Container $StorageContainerName -Context $StorageAccount.Context -Force
	}

	# Generate the value for artifacts location if it is not provided in the parameter file
	if ($OptionalParameters[$ArtifactsLocationName] -eq $null) {
		$OptionalParameters[$ArtifactsLocationName] = $StorageAccount.Context.BlobEndPoint + $StorageContainerName
       
	}

	# Generate a 4 hour SAS token for the artifacts location if one was not provided in the parameters file
	if ($OptionalParameters[$ArtifactsLocationSasTokenName] -eq $null) {
		$OptionalParameters[$ArtifactsLocationSasTokenName] = ConvertTo-SecureString -AsPlainText -Force `
			(New-AzureStorageContainerSASToken -Container $StorageContainerName -Context $StorageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(4))	
	}	

}



#MAIN
#Main script logic. Each function is wrapped in an if statement to provide idempotency

# Import the Azure Pipeline PowerShell module before we do anything
$ErrorActionPreference = 'Stop'
try {
    Import-Module $AzurePipelineModulePath
}
catch {
    Write-Error "Could not import Azure.Pipeline module. $_.Exception"
}

# Begin execution, execute functions wrapped in error checking

Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message "INFO - Starting $scriptName"
Set-DeployParametersRepository
$deployProperties = Set-DeployServiceTierVariables
Connect-DeployAzure -ServiceTier $deployProperties.serviceTier -SubscriptionName $deployProperties.subscriptionName
New-DeployResourceGroup -ApplicationName $deployProperties.applicationName -SubscriptionCode $SubscriptionCode -ResourceGroupName $deployProperties.resourceGroupName -resourceGroupRegion $deployProperties.parameters.resourceGroupRegion -BranchName $BranchName
Set-DeployResourceGroupRBAC -ServiceTier $deployProperties.serviceTier
Set-DeployTemplateRepository -ResourceGroupName $deployProperties.resourceGroupName -ServiceTier $deployProperties.serviceTier -SubscriptionName $deployProperties.subscriptionName -TemplateBranch $deployProperties.parameters.templateBranch -TemplateCommit $deployProperties.parameters.templateCommit

$mandatoryParameters = Set-DeployMandatoryParameters -Parameters $deployProperties.parameters -ApplicationName $deployProperties.applicationName -ResourceGroupName $deployProperties.resourceGroupName -ServiceTier $deployProperties.serviceTier -SubscriptionName $deployProperties.subscriptionName
if ($mandatoryParameters.virtual_machine_admin_password -eq $true) {
    $virtualMachineAdminPassword = New-DeployVirtualMachineAdministratorPassword -Parameters $deployProperties.parameters -ResourceGroupName $deployProperties.resourceGroupName -ServiceTier $deployProperties.serviceTier -SubscriptionName $deployProperties.subscriptionName
}

# Set storage blob and upload artifacts
if ($UploadArtifacts) {
	New-DeployStorageBlobResourceGroup -ApplicationName $deployProperties.applicationName -SubscriptionCode $SubscriptionCode -ResourceGroupName $deployProperties.resourceGroupName -resourceGroupRegion $deployProperties.parameters.resourceGroupRegion -BranchName $BranchName
	$outParameters = @{}
	New-DeployStorageBlob -ServiceTier $deployProperties.serviceTier -SubscriptionName $deployProperties.subscriptionName -ResourceGroupName $deployProperties.resourceGroupName -ApplicationName $deployProperties.applicationName -ArtifactsStagingDirectory '/' -TemplateParameters $deployProperties.parameters -OptionalParameters $optionalParameters
	$mandatoryParameters = $mandatoryParameters + $outParameters
}
$deploymentOutputs = New-DeployTemplate -Parameters $deployProperties.parameters -ApplicationName $deployProperties.applicationName -EnvironmentName $deployProperties.environmentName -ResourceGroupName $deployProperties.resourceGroupName -ServiceTier $deployProperties.serviceTier -VirtualMachineAdminPassword $virtualMachineAdminPassword -SubscriptionName $deployProperties.subscriptionName -MandatoryParameters $mandatoryParameters


if ( $deploymentOutputs ) {
    Set-DeployOutput -DeploymentOutputs $deploymentOutputs -ResourceGroupName $deployProperties.resourceGroupName -ServiceTier $deployProperties.serviceTier -Parameters $deployProperties.parameters -SubscriptionName $deployProperties.subscriptionName
}

#clean up deployment storage account
if ($UploadArtifacts) {
	Remove-DeployStorageBlobResourceGroup -ServiceTier $deployProperties.serviceTier -SubscriptionName $deployProperties.subscriptionName -ResourceGroupName $deployProperties.resourceGroupName
	Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "INFO - Removed Deployment Storage Account"
}
Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "INFO - Completed $scriptName"
