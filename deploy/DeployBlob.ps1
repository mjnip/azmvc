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
	$ResourceGroupName = $ResourceGroupName + 'stg'
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
	$ResourceGroupName = $ResourceGroupName + 'stg'
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
