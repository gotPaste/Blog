<# 
.SYNOPSIS: Script used to automate the ContentLibraryCleanup.exe and log the output. 
.DESCRIPTION: Will identify the DPs in the environment and run contentlibrarycleanup.exe with approrpiate switches.  It will run in WhatIf mode
 first and then run in DELETE mode if WhatIF mode was successful. 
.NOTES: Will Retry 4 times on each section (WhatIF and DELETE modes)  Will Log output to C:\Windows\Logs\ContentLibraryCleanup\ 
.COMPONENT: ContentLibraryCleanup.exe and this script need to reside in the same directory. SCCM Console needs to be installed on same machine.
.LINK 
 https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/hierarchy/content-library-cleanup-tool
 https://fritscheonline.blogspot.com
.EXAMPLE: powershell.exe -executionpolicy bypass -file ".\ContentLibraryCleanup.ps1" 
.CREATOR: Tom Fritsche 
#>

#------------SCCM Module Code-------------------------
#
# Press 'F5' to run this script. Running this script will load the ConfigurationManager
# module for Windows PowerShell and will connect to the site.
#
# Uncomment the line below if running in an environment where script signing is 
# required.
#Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# Site configuration
$SiteCode = Read-Host -Prompt 'Input your 3 character site code' # Site code 
$ProviderMachineName = Read-Host -Prompt 'Input the FQDN of your primary site server name' # SMS Provider machine name

# Customizations
$initParams = @{}
#$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

# Do not change anything below this line

# Import the ConfigurationManager.psd1 module 
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}

# Set the current location to be the site code.
Set-Location "$($SiteCode):\" @initParams

#-----------------Action Code------------------------
#Prepare for Logging
$LogTime = Get-Date -Format "MM-dd-yyyy_hh-mm-ss"
$LogFolder = "C:\Windows\Logs\ContentLibraryCleanup\"
$scriptName = $MyInvocation.MyCommand.Name
$LogFile = "$scriptName-$LogTime.log"

#Test and Create Logging Folder
If (Test-path $LogFolder) {
}
Else {
    New-Item -ItemType Directory -Force -Path $LogFolder
}

#Start Logging
Start-Transcript -path "$LogFolder$LogFile"

# Find and Delete all previous log files
$CleanUpLogs = Get-ChildItem $LogFolder* -filter *.log -exclude *$logtime.log
ForEach ($CleanUpLog in $CleanUpLogs){
    write-host "Deleting $CleanUpLog"
    Remove-Item $CleanUpLog
}


#Get a List of all DPs that are not on the Primary Site Server.
$AllCMServerList = Get-cmsiterole
$DPList = $AllCMServerList | Where-Object {($_.RoleName -eq "SMS Distribution Point") -and ($_.NALType -ne "Windows Azure") -and ($_.NetworkOSPath -ne "\\$ProviderMachineName")}| ForEach-Object {$_.NetworkOSPath -replace "\\"} #Used for Production COMMENT LINE when Testing

ForEach ($DP in $DPList){
    $ErrorWriteWhatIF = "YES"
    $ErrorWriteDelete = "YES"
    $Logs = Get-ChildItem $PSScriptRoot -filter *.log
    # Delete all Log files
    ForEach ($Log in $Logs){
        write-host "Deleting $Log"
        Remove-Item $Log
    }
    $TimeoutWhatIf = 1
    Do {
        write-host "Preparing to start $DP cleanup - WhatIF"
        & $PSScriptRoot\ContentLibraryCleanup.exe /q /dp $DP /log $PSScriptRoot
        $TimeoutWhatIf = $TimeoutWhatIf + 1
       # write-host $Timeout

        #Import Log file and find last index item in loggetwhatif array
        $LogGetWhatIf = Get-ChildItem $PSScriptRoot -filter WhatIf*.log
        If ($LogGetWhatIf){
            $logreadWhatIf = Get-Content $PSScriptroot\$LogGetWhatIf
            $logcountWhatIf = $logreadWhatIf.count-1
        #Retuns last line of log file
            $logreadWhatIf = (Get-Content $PSScriptroot\$LogGetWhatIf)[$logcountWhatIf]
        #write-host $LogGetWhatIf
            If ($LogreadWhatIf.StartsWith("Approximately")){
                #write-host "Approximately Found"
                $split = $LogreadWhatIf.split(" ")[1]
                If ($split -gt "0"){
                    write-host "Success: $DP - $LogreadWhatIf Running Delete Mode Now!"
                    $TimeoutWhatIf = 5
                    $ErrorWriteWhatIF = "NO"
                    $TimeoutDelete = 1
                    Do{
                        & $PSScriptRoot\ContentLibraryCleanup.exe /q /dp $DP /log $PSScriptRoot /delete
                        $TimeoutDelete = $TimeoutDelete + 1
                        #Import Log file and find last index item in loggetdeleted array
                        $LogGetDeleted = Get-ChildItem $PSScriptRoot -filter Deleted*.log
                        If ($LogGetDeleted){
                            $logreaddelete = Get-Content $PSScriptroot\$LogGetDeleted
                            $logcountdelete = $logreaddelete.count-1
                        #Retuns last line of log file
                            $logreaddelete = (Get-Content $PSScriptroot\$LogGetDeleted)[$logcountdelete]
                            If ($logreaddelete.StartsWith("Approximately")){
                                Write-Host "Success: $DP - $logreaddelete"
                                $ErrorWriteDelete = "NO"
                                $TimeoutDelete = 5
                            }
                            Else{
                                write-host "Warning: $DP - Re-Running Delete Mode"
                            }
                        }
                        Else {
                            write-host "Warning: $DP - Re-Running Delete Mode"
                        }
                    }           
                    While ($TimeoutDelete -lt 5)
                }
                Else {
                    write-host "Success: $DP - $LogreadWhatIf...Bypass Delete Mode!"
                    $TimeoutWhatIF = 5
                }
    
            }
            Else{
                write-host "Warning: $DP - $LogreadWhatIf - Will Retry WhatIF Mode!"
            }
        }
        Else{
            write-host "Warning: $DP - Re-Running WhatIf Mode!"
        }
    }
    While($TimeoutWhatIf -lt 5)
    If ($ErrorWriteWhatIF -eq "YES"){
    write-host "ERROR: What-IF cleanup timed-out."
    }
    ElseIf ($ErrorWriteDelete -eq "YES"){
        write-host "ERROR: Delete cleanup timed-out."
    }
}
Stop-Transcript


