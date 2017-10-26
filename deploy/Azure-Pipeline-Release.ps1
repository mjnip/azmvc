<#
.SYNOPSIS
    Azure Pipeline "Release" phase script

.DESCRIPTION
    The following script is intended to be executed at the release phase of the Azure Pipeline. The script will execute the following functions:

    Connect-Azure
    Set-ReleaseCnameUpdate

    Each function is error controlled and will log by utilising the Write-PipelineLog cmdlet from the Azure.Pipeline module. Any failure will result in a failed build.

    As this script is intended to be executed as part of a Jenkins Job it utilises environment variables that are presented as part of the job execution.

.PARAMETER ServiceTier
    Name of the service tier this deployment is targeting

.PARAMETER SubscriptionName
    Name of the subscription the resource group is located 

.PARAMETER ResourceGroupName
    Name of the resource group to be cleared

.PARAMETER AzurePipelineModulePath
    Path where the Azure Pipeline PowerShell module can be found

.OUTPUTS
    NONE

.EXAMPLE
    PowerShell -f Azure-Pipeline-Release.ps1 -Parameter ServiceTier -Parameter SubscriptionName -Parameter ResourceGroupName

.LINK

.NOTES
    Pedram Sanayei, Sourced Group <pedram.sanayei@sourcedgroup.com>
    Zach Koncir, Sourced Group <zach.koncir@sourcedgroup.com>

    (c) Sourced Group, Canada. All rights reserved
#>

#Set parameters

Param(
    [Parameter(Mandatory=$true)][string]$ServiceTier,
    [Parameter(Mandatory=$true)][string]$SubscriptionName,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$false)][string]$AzurePipelineModulePath = "./Azure.Pipeline"
)

# Initialise variables

$scriptName = ($($MyInvocation.MyCommand.Name) -Split(".ps1"))[0]
$startTime = Get-Date -format yyyyMMddmmss


#FUNCTION Connect-Azure
# Connects to the Azure Account with the appropriate Service Principal


Function Connect-Azure {
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


#FUNCTION Set-ReleaseCnameUpdate
# Update corresponding application CNAME in Azure DNS to this current deployment


Function Set-ReleaseCnameUpdate {
    Param(
    [Parameter(Mandatory=$true)][string]$SubscriptionName,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName
    )
    try {
        $applicationName = ($ResourceGroupName -Split "_")[0]
        $branchName = ($ResourceGroupName -Split "_")[1]
        $buildId = ($ResourceGroupName -Split "_")[2]
        $environmentName = ($BranchName -Split "-")[1]

        $deploymentCname = "$($applicationName)-$($environmentName)-$($env:BUILD_NUMBER)"
        $branchCname = "$($applicationName)-$($environmentName)"

        # Update the branch CNAME, if the deployment CNAME exists
        if ( Get-AzureRmDnsRecordSet -Name $deploymentCname -RecordType CNAME -ZoneName "$($SubscriptionName).00azr.net" -ResourceGroupName base-global -ErrorAction SilentlyContinue ) {
            # Test if branch CNAME exists, create CNAME if it does not exist
            # If it does exist, update the CNAME value
            if ( -Not (Get-AzureRmDnsRecordSet -Name $branchCname -RecordType CNAME -ZoneName "$($SubscriptionName).00azr.net" -ResourceGroupName base-global -ErrorAction SilentlyContinue) ) {
                $branchCnameRecord = @()
                $branchCnameRecord += New-AzureRmDnsRecordConfig -Cname "$($deploymentCname)"
                $recordSet = New-AzureRmDnsRecordSet -Name "$($branchCname)" -RecordType CNAME -Ttl 60 -ZoneName "$($SubscriptionName).00azr.net" -ResourceGroupName base-global -DnsRecords $branchCnameRecord
                Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "INFO - Branch CNAME does not exist, creating: $($recordSet.Name).$($recordSet.ZoneName)"
            }
            # Update the release CNAME
            $recordSet = Get-AzureRmDnsRecordSet -Name $branchCname -RecordType CNAME -ZoneName "$($SubscriptionName).00azr.net" -ResourceGroupName base-global
            $recordSet.Records[0].Cname = "$($deploymentCname).$($SubscriptionName).00azr.net"
            Set-AzureRmDnsRecordSet -RecordSet $recordSet      
            Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "INFO - Build #$($buildId) for branch $($branchName) is available at $($recordSet.Name).$($recordSet.ZoneName)"
        } else {
            Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "INFO - Deployment CNAME does not exist, skipping release step"
        }
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "SUCCESS - $($MyInvocation.MyCommand.Name)"
    }
    catch {
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "FAIL - $($MyInvocation.MyCommand.Name) $($_.Exception)"
        exit(1)
    }
}

Function Set-ReleaseTag{
Param(
    [Parameter(Mandatory=$true)][string]$ResourceGroupName
    )
        try {
        #Set the Tag Name
        $releaseTagName  = "release_time"
        #Set the Tag with the value the timestamp when the release happened in the UNIX epoch time format.
        $releaseTagValue = [Math]::Floor([decimal](Get-Date(Get-Date).ToUniversalTime()-uformat "%s"))
        # Get the release resourcegroup, if the resourcegroup exist
        $ResourceGroup = Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
        # If the resource group exists
        if ($ResourceGroup){
        Write-Output "The released resource group is $($ResourceGroup.ResourceGroupName)"
        # Get all the tags associated with a resource group.       
        $setTags = $ResourceGroup.Tags
        # Add the release tag.
        Write-Output "Adding released Tag on resource group $($ResourceGroup.ResourceGroupName)"
        $setTags += @{$releaseTagName = $releaseTagValue}
        #Output all the tags with released tag also.
        Write-Output "The new tags will be \n $($setTags|Out-String)"
        # Set the release tag on the released resource group.
        Set-AzureRmResourceGroup -Tag $setTags -Name $ResourceGroup.ResourceGroupName 
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "INFO - Resource Group Name $($ResourceGroupName) for Build #$($buildId) for branch $($branchName) has been tagged with $($releaseTagName) : $($releaseTagValue) "        
        } else {
            Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "INFO - Provided resource group does not exist, cannot assign release tag"
        }
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "SUCCESS - $($MyInvocation.MyCommand.Name)"
    }
    catch {
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "FAIL - $($MyInvocation.MyCommand.Name) $($_.Exception)"
        exit(1)
    }

}

#MAIN
# Main script logic. Each function is wrapped in an if statement to provide idempotency

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
Connect-Azure -ServiceTier $ServiceTier -SubscriptionName $SubscriptionName
Set-ReleaseCnameUpdate -SubscriptionName $SubscriptionName -ResourceGroupName $ResourceGroupName
Set-ReleaseTag -ResourceGroupName $ResourceGroupName
Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "INFO - Completed $scriptName"
