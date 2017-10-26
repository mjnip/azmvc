function Write-PipelineLog {
    Param(
        [Parameter(Mandatory=$true)][string]$LogFileDate,
        [Parameter(Mandatory=$true)][string]$LogName,
        [Parameter(Mandatory=$true)][string]$Message
    )
    $logFile = "$($LogName)-" + $LogFileDate + ".log"

    $logDate = Get-Date -Format u
    $logDate = $logDate.Substring(0,$logDate.length-1)
    

    $logStamp = $logDate + "`t" + $Message
    Write-Host $logStamp

    if ($Message -like "*FAIL*")
    {
        Write-Output $logStamp | Out-File $logFile -Encoding ASCII -append
    }
    else
    {
        Write-Output $logStamp | Out-File $logFile -Encoding ASCII -append
    }
}

Function Connect-PipelineAzure {
    Param(
        [Parameter(Mandatory=$true)][string]$ClientID,
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$false)][string]$Tenant
    )
    $securePassword = ConvertTo-SecureString $Key -AsPlainText -Force
    $mycreds = New-Object System.Management.Automation.PSCredential ($ClientID, $securePassword)

    Login-AzureRmAccount -ServicePrincipal -Tenant $Tenant -Credential $mycreds
}

Export-ModuleMember -Function *