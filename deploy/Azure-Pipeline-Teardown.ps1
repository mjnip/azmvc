<#
.SYNOPSIS
    Azure Pipeline "Teardown" phase script

.DESCRIPTION
    The following script is intended to be executed at the teardown phase of the Azure Pipeline. The script will execute the following functions:

    Connect-Azure
    Clear-ResourceGroup

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
    PowerShell -f Azure-Pipeline-Teardown.ps1 -Parameter ServiceTier -Parameter SubscriptionName -Parameter ResourceGroupName

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


#FUNCTION Clear-ResourceGroup
# Deletes the Resource Group created in previous deployment phase.


Function Clear-ResourceGroup {
    Param(
    [Parameter(Mandatory=$true)][string]$SubscriptionName,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName
    )
    try {
        Select-AzureRmSubscription -SubscriptionName $SubscriptionName
        Remove-AzureRmResourceGroup -ResourceGroupName $ResourceGroupName -Verbose -Force
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "SUCCESS - $($MyInvocation.MyCommand.Name)"
    }
    catch {
        Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "FAIL - $($MyInvocation.MyCommand.Name) $($_.Exception)"
        exit(1)
    }

}


#FUNCTION Clear-TeardownDeploymentDns
# Deletes the DNS records created during the deployment phase.


Function Clear-TeardownDeploymentDnsRecords {
    try {
        $applicationName = ($ResourceGroupName -Split "_")[0]
        $branchName = ($ResourceGroupName -Split "_")[1]
        $buildId = ($ResourceGroupName -Split "_")[2]
        $environmentName = ($BranchName -Split "-")[1]

        $zoneName = "$($SubscriptionName).00azr.net"
        $deploymentCname = "$($applicationName)-$($environmentName)-$($buildId)"

        $deploymentARecord = Get-AzureRmDnsRecordSet -Name $ResourceGroupName -RecordType A -ZoneName $zoneName -ResourceGroupName base-global -ErrorAction SilentlyContinue
        $deploymentCnameRecord = Get-AzureRmDnsRecordSet -Name $deploymentCname -RecordType CNAME -ZoneName $zoneName -ResourceGroupName base-global -ErrorAction SilentlyContinue

        # Check to see if A record was created during deployment
        if ( $deploymentARecord ) {
            Remove-AzureRmDnsRecordSet -RecordSet $deploymentARecord -Confirm:$False
            Remove-AzureRmDnsRecordSet -RecordSet $deploymentCnameRecord -Confirm:$False
        } else {
            Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "MESSAGE - No DNS entries were found, skipping DNS cleanup"
        }
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
Clear-ResourceGroup -SubscriptionName $SubscriptionName -ResourceGroupName $ResourceGroupName
Write-PipelineLog -LogFileDate $startTime -LogName $scriptName -Message  "INFO - Completed $scriptName"
