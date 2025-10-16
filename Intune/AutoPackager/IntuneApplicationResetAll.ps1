#Install-Module IntuneWin32App
[CmdletBinding()]
param(
  [Parameter()]
  [Alias('Id')]
  [string]$AppId
)
Import-Module IntuneWin32App

Get-Module
write-host $PSScriptRoot
function Get-AzureAuthFromSources([string]$Root) {
    try {
        $cfgPath = Join-Path $Root 'AutoPackager.config.json'
        if (Test-Path -LiteralPath $cfgPath) {
            $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
            if ($cfg -and $cfg.AzureAuth) {
                $tid = [string]$cfg.AzureAuth.TenantId
                $cid = [string]$cfg.AzureAuth.ClientId
                $sec = [string]$cfg.AzureAuth.ClientSecret
                if ($tid -and $cid -and $sec) {
                    return [pscustomobject]@{ TenantId=$tid; ClientId=$cid; ClientSecret=$sec; Source='AutoPackager.config.json' }
                }
            }
        }
    } catch {}

    try {
        $csvPath = Join-Path $Root 'AZInfo.csv'
        if (Test-Path -LiteralPath $csvPath) {
            $rows = Import-Csv -LiteralPath $csvPath
            $row = $rows | Select-Object -First 1
            if ($row) {
                $tid = [string]$row.TenantId
                $cid = [string]$row.ClientId
                $sec = [string]$row.ClientSecret
                if ($tid -and $cid -and $sec) {
                    return [pscustomobject]@{ TenantId=$tid; ClientId=$cid; ClientSecret=$sec; Source='AZInfo.csv' }
                }
            }
        }
    } catch {}

    return $null
}

$auth = Get-AzureAuthFromSources -Root $PSScriptRoot
if (-not $auth -or (-not $auth.TenantId) -or (-not $auth.ClientId) -or (-not $auth.ClientSecret)) {
    throw "Azure credentials not found. Provide TenantId, ClientId, ClientSecret in AutoPackager.config.json (AzureAuth) or AZInfo.csv at: $PSScriptRoot"
}
$TenantId = [string]$auth.TenantId
$ClientId = [string]$auth.ClientId
$plain    = [string]$auth.ClientSecret
Write-Host ("Auth source: " + $auth.Source)

if (-not $AppId -or -not $AppId.Trim()) {
    $AppId = Read-Host 'Input the Intune Application GUID for Intune Placeholder - Required Update'
}
$AppVersion = '0.1'

Connect-MSIntuneGraph -TenantID $TenantId -ClientID $ClientId -ClientSecret $plain -ErrorAction Stop | Out-Null 

$precheck = Get-IntuneWin32App -Id $AppId

Update-IntuneWin32AppPackageFile -Id $AppId -FilePath "$PSScriptRoot\Temp\install.intunewin"

$postCheck = Get-IntuneWin32App -Id $AppId
IF ($postCheck.committedContentVersion -gt $precheck.committedContentVersion){
    Write-Host "Commited Content Version Updated"
    IF ($postCheck.size -ne $precheck.size){
        Write-Host "new intunewin file uploaded"
        Set-IntuneWin32App -Id $AppId -AppVersion $AppVersion
        $verifyCheck = Get-IntuneWin32App -Id $AppId
        IF ($AppVersion -eq $verifyCheck.displayversion){
            write-host "Update Successful"
            
            }
        Else{
            Write-Host "Update Failed"
            Exit 1
        }
    }
    Else {
    Write-host "ERROR Content not updated, updating version"
    Set-IntuneWin32App -Id $AppId -AppVersion $AppVersion
    Exit 0
    }
}
Else{
Write-Host "ERROR Content Version not updated"
Exit 1
}
