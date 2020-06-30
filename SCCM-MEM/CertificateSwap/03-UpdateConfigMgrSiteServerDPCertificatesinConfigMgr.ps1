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



#Action Code
$Logfile = $MyInvocation.MyCommand.Path -replace '\.ps1$', '.log'
Start-Transcript -Path $Logfile -Append
$AllCMServerList = Get-cmsiterole
$DPList = $AllCMServerList | Where-Object {($_.RoleName -eq "SMS Distribution Point") -and ($_.NALType -ne "Windows Azure")}| ForEach-Object {$_.NetworkOSPath -replace "\\"} #Used for Production COMMENT LINE when Testing

# Start Installing a new DP certificate
ForEach ($DP in $DPList){
    $DPServerName = "$DP"
    $CertificatePath = "<PathToCertificates>\$DPServerName.pfx"
    #write-host $certificatepath
    "$DPServerName - Testing connection"
    If (Test-Path filesystem::$CertificatePath){
        Write-Host -ForegroundColor Green  "$CertificatePath found on network"
        $CertificatePassword = '<CertificatePassword>' | ConvertTo-SecureString -AsPlainText -Force
        Write-Host -ForegroundColor Green "Installing certificate for server $DPServerName"
        Set-CMDistributionPoint -SiteSystemServerName $DPServerName -CertificatePassword $CertificatePassword -CertificatePath $CertificatePath
        #Start-Sleep -Seconds 5 #Wait for the DP installation process to finish.
    }
    ELSE {
        Write-Host -ForegroundColor Red "$DPServerName certificate not found"
    }
}
Stop-Transcript