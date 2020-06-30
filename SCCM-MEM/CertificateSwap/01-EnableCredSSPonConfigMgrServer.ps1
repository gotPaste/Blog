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

#---------ACTION CODE--------------
$Logfile = $MyInvocation.MyCommand.Path -replace '\.ps1$', '.log'
Start-Transcript -Path $Logfile -Append
$Cred = Get-Credential

#CMServerList = "<ServerName>" #Used for Testing
$CMServerList = Get-CMSiteRole | Where-Object {$_.NALType -ne "Windows Azure"}| ForEach-Object {$_.NetworkOSPath -replace "\\"} | Sort-Object -Unique #Used for Production COMMENT LINE when Testing
#$CMServerList = $CMServerList | Sort-Object -Unique

ForEach ($CMServer in $CMServerList){
    $CMServerName = "$CMServer"
    "$CMServerName - Testing connection"
    IF (Test-Connection -ComputerName $CMServerName -Count 1 ){     #Check if the DP server is online.
        Write-Host -ForegroundColor Green  "$CMServerName is on network"
        $TempScriptBlock = [scriptblock]::Create("Enable-WSManCredSSP Server -Force")
        Invoke-Command -ComputerName $CMServer -Credential $Cred -ScriptBlock $TempScriptBlock -ErrorAction 'Stop'
    }
    Else{
        write-host -ForegroundColor Red "$CMServerName Host Offline"
    }
}
Stop-Transcript