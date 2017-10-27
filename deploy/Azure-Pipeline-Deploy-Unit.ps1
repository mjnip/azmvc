function Write-PipelineLog {
    Param(
       [string]$LogFileDate,
      [string]$LogName,
   [string]$Message
    )
    
}

Function Connect-PipelineAzure {
    Param(
       [string]$ClientID,
      [string]$Key,
      [string]$Tenant
    )
 
}


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


Function Remove-DeployStorageBlobResourceGroup {
	Param(
    [Parameter(Mandatory=$true)][string]$ServiceTier,
    [Parameter(Mandatory=$true)][string]$SubscriptionName,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName
    )
	$ResourceGroupName = $ResourceGroupName + 'stage'
	Clear-DeployResourceGroup -ServiceTier $ServiceTier -SubscriptionName $SubscriptionName -ResourceGroupName $ResourceGroupName
}


Function New-DeployStorageBlob {
	Param(
    [Parameter(Mandatory=$true)][string]$ServiceTier,
    [Parameter(Mandatory=$true)][string]$SubscriptionName,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
	[Parameter(Mandatory=$true)][string]$ApplicationName,
	[Parameter(Mandatory=$true)][string]$ArtifactsStagingDirectory,
	[Parameter(Mandatory=$true)][string]$TemplateParameters

    )	

    $PSScriptRoot = "C:\dev\projects\td\mvc\deploy"
	Select-AzureRmSubscription -SubscriptionName $SubscriptionName

	# Convert relative paths to absolute paths if needed
	$ArtifactStagingDirectory = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $ArtifactStagingDirectory))
		
	# Parse the parameter file and update the values of artifacts location and artifacts location SAS token if they are present
	$JsonParameters = $TemplateParameters
	if (($JsonParameters | Get-Member -Type NoteProperty 'parameters') -ne $null) {
		$JsonParameters = $JsonParameters.parameters
	}
    $OptionalParameters = New-Object -TypeName Hashtable

	$ArtifactsLocationName = '_artifactsLocation'
	$ArtifactsLocationSasTokenName = '_artifactsLocationSasToken'
	$OptionalParameters[$ArtifactsLocationName] = $JsonParameters | Select -Expand $ArtifactsLocationName -ErrorAction Ignore | Select -Expand 'value' -ErrorAction Ignore
	$OptionalParameters[$ArtifactsLocationSasTokenName] = $JsonParameters | Select -Expand $ArtifactsLocationSasTokenName -ErrorAction Ignore | Select -Expand 'value' -ErrorAction Ignore

	
	# Create a storage account name if none was provided
	if ($StorageAccountName -eq '') {
		$StorageAccountName = $ApplicationName + 'stage' + ((Get-AzureRmContext).Subscription.SubscriptionId).Replace('-', '').substring(0, 19)
	}

	$StorageAccount = (Get-AzureRmStorageAccount | Where-Object{$_.StorageAccountName -eq $StorageAccountName})

	# Create the storage account if it doesn't already exist
	if ($StorageAccount -eq $null) {
		$ResourceGroupName = $ResourceGroupName + 'stage'
		New-AzureRmResourceGroup -Location "$ResourceGroupLocation" -Name $ResourceGroupName -Force
		$StorageAccount = New-AzureRmStorageAccount -StorageAccountName $StorageAccountName -Type 'Standard_LRS' -ResourceGroupName $ResourceGroupName -Location "$ResourceGroupLocation"
	}

	# Generate the value for artifacts location if it is not provided in the parameter file
	if ($OptionalParameters[$ArtifactsLocationName] -eq $null) {
		$OptionalParameters[$ArtifactsLocationName] = $StorageAccount.Context.BlobEndPoint + $StorageContainerName
	}

	# Copy files from the local storage staging location to the storage account container
	New-AzureStorageContainer -Name $StorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue *>&1

	$ArtifactFilePaths = Get-ChildItem $ArtifactStagingDirectory -Recurse -File | ForEach-Object -Process {$_.FullName}	
		
	foreach ($SourcePath in $ArtifactFilePaths) {
		Set-AzureStorageBlobContent -File $SourcePath -Blob $SourcePath.Substring($ArtifactStagingDirectory.length + 1) `
			-Container $StorageContainerName -Context $StorageAccount.Context -Force
	}
	

	# Generate a 4 hour SAS token for the artifacts location if one was not provided in the parameters file
	if ($OptionalParameters[$ArtifactsLocationSasTokenName] -eq $null) {
		$OptionalParameters[$ArtifactsLocationSasTokenName] = ConvertTo-SecureString -AsPlainText -Force `
			(New-AzureStorageContainerSASToken -Container $StorageContainerName -Context $StorageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(4))	
	}	
	return $OptionalParameters
}



#unit testing of functions
$appName = 'vm'
$SubscriptionCode = 'test'
$rgName = 'vmunittest'
$serviceTier = "test"
$rgRegion = 'eastus2'
$branchName = 'master'
$subscriptionName = 'Microsoft Azure Internal Consumption'
$mandatoryParameters = @{ "adminPassword" = "password"; "Puppet_master" = "http://puppet.com"}
$deployParameters = Get-Content "vm-main.parameters.json" | Out-String | ConvertFrom-Json
$TemplateParameters = $deployParameters

$ResourceGroupName = $rgName
$ApplicationName = $appName
$ArtifactsStagingDirectory = "./"
$ResourceGroupLocation = $rgRegion





    $PSScriptRoot = "C:\dev\projects\td\mvc\deploy"
	Select-AzureRmSubscription -SubscriptionName $SubscriptionName

	# Convert relative paths to absolute paths if needed
	$ArtifactStagingDirectory = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $ArtifactStagingDirectory))
		
	# Parse the parameter file and update the values of artifacts location and artifacts location SAS token if they are present
	$JsonParameters = $TemplateParameters
	if (($JsonParameters | Get-Member -Type NoteProperty 'parameters') -ne $null) {
		$JsonParameters = $JsonParameters.parameters
	}
    
    $OptionalParameters = New-Object -TypeName Hashtable
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

	# Generate the value for artifacts location if it is not provided in the parameter file
	if ($OptionalParameters[$ArtifactsLocationName] -eq $null) {
		$OptionalParameters[$ArtifactsLocationName] = $StorageAccount.Context.BlobEndPoint + $StorageContainerName
	}

	# Copy files from the local storage staging location to the storage account container
	New-AzureStorageContainer -Name $StorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue *>&1

	$ArtifactFilePaths = Get-ChildItem $ArtifactStagingDirectory -Recurse -File | ForEach-Object -Process {$_.FullName}	
		
	foreach ($SourcePath in $ArtifactFilePaths) {
		Set-AzureStorageBlobContent -File $SourcePath -Blob $SourcePath.Substring($ArtifactStagingDirectory.length + 1) `
			-Container $StorageContainerName -Context $StorageAccount.Context -Force
	}
	

	# Generate a 4 hour SAS token for the artifacts location if one was not provided in the parameters file
	if ($OptionalParameters[$ArtifactsLocationSasTokenName] -eq $null) {
		$OptionalParameters[$ArtifactsLocationSasTokenName] = ConvertTo-SecureString -AsPlainText -Force `
			(New-AzureStorageContainerSASToken -Container $StorageContainerName -Context $StorageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(4))	
	}	



New-DeployStorageBlobResourceGroup -ApplicationName $appName -SubscriptionCode $SubscriptionCode -ResourceGroupName $rgName -resourceGroupRegion $rgRegion -BranchName $BranchName
$optionalParameters = New-DeployStorageBlob -ServiceTier $serviceTier -SubscriptionName $subscriptionName -ResourceGroupName $rgName -ApplicationName $appName -ArtifactsStagingDirectory './' -TemplateParameters $deployParameters
$mandatoryParameters = $mandatoryParameters + $optionalParameters