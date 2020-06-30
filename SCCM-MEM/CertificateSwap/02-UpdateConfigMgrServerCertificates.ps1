#---------Functions CODE--------------
Function RequestExport-DPCertificate {
#SCCM Client Distribution Point Certificate
    #Certificate Enrollment 
    $CertOld = Get-ChildItem Cert:\LocalMachine\My -Recurse #Capture Old Certificate List
    Get-Certificate -Template "<ConfigMgrClientDistributionPointCertificateTemplate>" -CertStoreLocation Cert:\localmachine\My #Enroll Certificate
    $CertNew = Get-ChildItem Cert:\LocalMachine\My -Recurse #Capture New Certificate List
    #Certificate Export
    $mypwd = ConvertTo-SecureString -String "<Password>" -Force -AsPlainText
    $ExportCert = Compare-Object -ReferenceObject $CertOld -DifferenceObject $CertNew -PassThru
    $ExportThumb = $ExportCert.Thumbprint
    $ExportSubject = $ExportCert.Subject.Split("=")[1]
    $MyCert = Get-ChildItem -Path cert:\localMachine\my\$ExportThumb 
    $MyCert.FriendlyName = "SCCM Distribution Point Certificate"
    $MyCert | Export-PfxCertificate -FilePath "<PathToCert>\$exportsubject.pfx" -Password $mypwd -Force
}

Function Request-WorkstationAuthCertificate {
#SCCM Workstation Authentication Certificate
    $CertOld = Get-ChildItem Cert:\LocalMachine\My -Recurse #Capture Old Certificate List
    Get-Certificate -Template "<WorkstationAuthenticationCertificateTemplate>" -CertStoreLocation Cert:\localmachine\My
    $CertNew = Get-ChildItem Cert:\LocalMachine\My -Recurse #Capture New Certificate List
    $ExportCert = Compare-Object -ReferenceObject $CertOld -DifferenceObject $CertNew -PassThru
    $ExportThumb = $ExportCert.Thumbprint
    $ExportSubject = $ExportCert.Subject.Split("=")[1]
    $MyCert = Get-ChildItem -Path cert:\localMachine\my\$ExportThumb 
    $MyCert.FriendlyName = "Workstation Authentication Certificate"
}

Function RequestUpdate-WebServerCertificate {
#SCCM Web Server Certificate
    $CertOld = Get-ChildItem Cert:\LocalMachine\My -Recurse #Capture Old Certificate List
    Get-Certificate -Template "<ConfigMgrWebServerCertificateTemplate>" -CertStoreLocation Cert:\localmachine\My
    $CertNew = Get-ChildItem Cert:\LocalMachine\My -Recurse #Capture New Certificate List
    $ExportCert = Compare-Object -ReferenceObject $CertOld -DifferenceObject $CertNew -PassThru
    $ExportThumb = $ExportCert.Thumbprint
    $ExportSubject = $ExportCert.Subject.Split("=")[1]
    $MyCert = Get-ChildItem -Path cert:\localMachine\my\$ExportThumb 
    $MyCert.FriendlyName = "ConfigMgr IIS WebServer Certificate" #Set Friendly Name
#Update IIS Site Certificate with SCCM Web Server Certificate 
#Must be directly after SCCM Web Server Certificate section   
    $Websites = Get-website | ForEach-Object {$_.Name}
    ForEach ($Website in $Websites){
        If ($Website -like "Default Web Site"){
            $binding = Get-WebBinding -Name $Website -Protocol "https" #get the web binding of the site
            $binding.AddSslCertificate("$ExportThumb", "my") #set the ssl certificate
        }
        Else {
        }
        IF ($Website -like "WSUS Administration"){
            $binding = Get-WebBinding -Name $Website -Protocol "https" #get the web binding of the site
            $binding.AddSslCertificate("$ExportThumb", "my") #set the ssl certificate
        }
        Else {
        }
    }
}

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
$Logfile = $MyInvocation.MyCommand.Path -replace '\.ps1$', '.log'
Start-Transcript -Path $Logfile -Append
$Cred = Get-Credential

#$DPList = "<ServerName>" #Used for Testing UNCOMMENT LINE when Testing
#$MPList = "<ServerName>" #Used for Testing UNCOMMENT LINE when Testing
#$SUPList = "<ServerName>" #Used for Testing UNCOMMENT LINE when Testing
#$ReportServerList = "<ServerName>" #Used for Testing UNCOMMENT LINE when Testing
#$PrimarySiteServerList = "<ServerName>" #Used for Testing UNCOMMENT LINE when Testing
#$DBList = "<ServerName>" #Used for Testing UNCOMMENT LINE when Testing
#$SMPList = "<ServerName>" #Used for Testing UNCOMMENT LINE when Testing

$AllCMServerList = Get-cmsiterole
$DPList = $AllCMServerList | Where-Object {($_.RoleName -eq "SMS Distribution Point") -and ($_.NALType -ne "Windows Azure")}| ForEach-Object {$_.NetworkOSPath -replace "\\"} #Used for Production COMMENT LINE when Testing
$MPList = $AllCMServerList | Where-Object {($_.RoleName -eq "SMS Management Point") -and ($_.NALType -ne "Windows Azure")}| ForEach-Object {$_.NetworkOSPath -replace "\\"} #Used for Production COMMENT LINE when Testing
$SUPList = $AllCMServerList | Where-Object {($_.RoleName -eq "SMS Software Update Point") -and ($_.NALType -ne "Windows Azure")}| ForEach-Object {$_.NetworkOSPath -replace "\\"} #Used for Production COMMENT LINE when Testing
$ReportServerList = $AllCMServerList | Where-Object {($_.RoleName -eq "SMS SRS Reporting Point") -and ($_.NALType -ne "Windows Azure")}| ForEach-Object {$_.NetworkOSPath -replace "\\"} #Used for Production COMMENT LINE when Testing
$SiteServerList = $AllCMServerList | Where-Object {($_.RoleName -eq "SMS Site Server") -and ($_.NALType -ne "Windows Azure")}| ForEach-Object {$_.NetworkOSPath -replace "\\"} #Used for Production COMMENT LINE when Testing
$DBList = $AllCMServerList | Where-Object {($_.RoleName -eq "SMS SQL Server") -and ($_.NALType -ne "Windows Azure")}| ForEach-Object {$_.NetworkOSPath -replace "\\"} #Used for Production COMMENT LINE when Testing
$SMPList = $AllCMServerList | Where-Object {($_.RoleName -eq "SMS State Migration Point") -and ($_.NALType -ne "Windows Azure")}| ForEach-Object {$_.NetworkOSPath -replace "\\"} #Used for Production COMMENT LINE when Testing
$ComboIISList = $DPList + $MPList + $SMPList + $SUPList + $SiteServerList | Sort-Object -Unique
$CMServerList = $AllCMServerList | Where-Object {($_.NALType -ne "Windows Azure")}| ForEach-Object {$_.NetworkOSPath -replace "\\"} |  Sort-Object -Unique #Used for Production COMMENT LINE when Testing
#Uncomment Line below is to resume from a specific spot if the scirpt fails 
#$CMServerList = $AllCMServerList | Where-Object {($_.NALType -ne "Windows Azure") -AND ($_.NetworkOSPath -gt '<ServerName>')} | ForEach-Object {$_.NetworkOSPath -replace "\\"} | Sort-Object -Unique #Used for Production COMMENT LINE when Testing


ForEach ($CMServer in $CMServerList){
    IF (Test-Connection -ComputerName $CMServer -Count 1 ){     #Check if the server is online.
        Write-Host -ForegroundColor Green  "$CMServer is on network"
        Invoke-Command -ComputerName $CMServer -Credential $Cred -Authentication Credssp -ScriptBlock ${function:Request-WorkstationAuthCertificate} -ErrorAction 'Stop' # Request Workstation Certificate
# Request/Export DP Certificate
        IF ($CMServer -in $DPList){
            write-host "found $CMServer in DPList"
            Invoke-Command -ComputerName $CMServer -Credential $Cred -Authentication Credssp -ScriptBlock ${function:RequestExport-DPCertificate} -ErrorAction 'Stop'
        }
# Request/Update IIS Certificate
        IF ($CMServer -in $ComboIISList){
            write-host "found $CMServer in IISList"
            Invoke-Command -ComputerName $CMServer -Credential $Cred -Authentication Credssp -ScriptBlock ${function:RequestUpdate-WebServerCertificate} -ErrorAction 'Stop'
        }
    }
    Else{
        Write-Host -ForegroundColor Red  "$CMServer is offline, must update manually"
    }
}
Stop-Transcript