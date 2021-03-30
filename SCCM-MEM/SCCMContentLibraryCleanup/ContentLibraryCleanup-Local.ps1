<# 
.SYNOPSIS: Script used to automate the ContentLibraryCleanup.exe and log the output. 
.DESCRIPTION: Will identify the hostname and run contentlibrarycleanup.exe with approrpiate switches.  It will run in WhatIf mode
 first and then run in DELETE mode if WhatIF mode was successful. 
.NOTES: Will Retry 4 times on each section (WhatIF and DELETE modes)  Will Log output to C:\Windows\Logs\ContentLibraryCleanup\ 
.COMPONENT: ContentLibraryCleanup.exe and this script need to reside in the same directory. 
.LINK 
 https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/hierarchy/content-library-cleanup-tool
 https://fritscheonline.blogspot.com
.EXAMPLE: powershell.exe -executionpolicy bypass -file ".\ContentLibraryCleanup.ps1" 
.CREATOR: Tom Fritsche 
#>

#FQDN of DP
$HostName = [System.Net.Dns]::GetHostByName(($env:computerName)).HostName

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


#Set Error Variables for Logging
$ErrorWriteWhatIF = "YES"
$ErrorWriteDelete = "YES"

#Find and delete all log files in script root folder
write-host $PSScriptRoot
$Logs = Get-ChildItem $PSScriptRoot -filter *.log
ForEach ($Log in $Logs){
    write-host "Deleting $Log"
    Remove-Item $Log
}

$TimeoutWhatIf = 1
Do {
    write-host "Information: Preparing to start $Hostname cleanup - WhatIF"
    & $PSScriptRoot\ContentLibraryCleanup.exe /q /dp $Hostname /log $PSScriptRoot
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
                write-host "Success: $LogreadWhatIf Running Delete Mode Now!"
                $ErrorWriteWhatIF = "NO"
                $TimeoutWhatIf = 5
                $TimeoutDelete = 1
                Do{
                    & $PSScriptRoot\ContentLibraryCleanup.exe /q /dp $Hostname /log $PSScriptRoot /delete
                    $TimeoutDelete = $TimeoutDelete + 1
                    #Import Log file and find last index item in loggetdeleted array
                    $LogGetDeleted = Get-ChildItem $PSScriptRoot -filter Deleted*.log
                    If ($LogGetDeleted){
                        $logreaddelete = Get-Content $PSScriptroot\$LogGetDeleted
                        $logcountdelete = $logreaddelete.count-1
                    #Retuns last line of log file
                        $logreaddelete = (Get-Content $PSScriptroot\$LogGetDeleted)[$logcountdelete]
                        If ($logreaddelete.StartsWith("Approximately")){
                            Write-Host "Success: $logreaddelete"
                            $ErrorWriteDelete = "NO"
                            $TimeoutDelete = 5
                        }
                        Else{
                            write-host "Warning: Re-Running Delete Mode"
                        }
                    }
                    Else {
                        write-host "Warning: Re-Running Delete Mode"
                    }
                }           
                While ($TimeoutDelete -lt 5)
            }
            Else {
                write-host "Success: $LogreadWhatIf...Bypass Delete Mode!"
                $TimeoutWhatIF = 5
            }
    
        }
        Else{
            write-host "Warning: $LogreadWhatIf - Will Retry WhatIF Mode!"
        }
    }
    Else{
        write-host "Warning: Re-Running WhatIf Mode!"
    }
}
While($TimeoutWhatIf -lt 5)
If ($ErrorWriteWhatIF -eq "YES"){
    write-host "ERROR: What-IF cleanup timed-out."
}
ElseIf ($ErrorWriteDelete -eq "YES"){
    write-host "ERROR: Delete cleanup timed-out."
}

Stop-Transcript    