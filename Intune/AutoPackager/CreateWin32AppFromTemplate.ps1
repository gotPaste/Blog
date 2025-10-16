#requires -Version 5.1
<#
CreateWin32AppFromTemplate.ps1
Creates an Intune Win32 app using IntuneWin32App module following the sample in newapp.ps1.
Inputs:
- DisplayName (from winget show)
- Publisher   (from winget show)
- IconPath    (from GUI)

All other values are hard-coded to mirror the sample code:
- Description: "PlaceHolder for AutoPackager"
- InstallCommandLine: powershell.exe -ExecutionPolicy Bypass -File "install.ps1"
- UninstallCommandLine: powershell.exe -ExecutionPolicy Bypass -File "uninstall.ps1"
- DetectionRule: File exists at c:\program files\MyApplication\Myapplication.exe
- InstallExperience: system
- RestartBehavior: basedOnReturnCode
- FilePath (.intunewin): .\Temp\install.intunewin (relative to repo root)
- Auth: Reads from AutoPackager.config.json (AzureAuth) or AZInfo.csv; ClientSecret preferred
Outputs:
- Writes "AppId: <guid>" to stdout when creation succeeds
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$DisplayName,
  [Parameter(Mandatory = $true)][string]$Publisher,
  [Parameter()][string]$IconPath,
  [Parameter()][string]$AppVersion = '0.1',
  [Parameter()][bool]$AllowAvailableUninstall = $false
)

$ErrorActionPreference = 'Stop'

# Resolve script root / repo root
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot -or [string]::IsNullOrWhiteSpace($ScriptRoot)) {
  if ($PSCommandPath) { $ScriptRoot = Split-Path -Parent $PSCommandPath }
  elseif ($MyInvocation.MyCommand.Path) { $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
  else { $ScriptRoot = (Get-Location).Path }
}
$RepoRoot = $ScriptRoot

function Write-Err([string]$m) { [Console]::Error.WriteLine("[ERROR] $m") }

# Auth material
$TenantId = $null
$ClientId = $null
$ClientSecret = $null
$CertificateThumbprint = $null

# Load from AutoPackager.config.json if present
try {
  $cfgPath = Join-Path $RepoRoot 'AutoPackager.config.json'
  if (Test-Path -LiteralPath $cfgPath) {
    $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
    if ($cfg -and $cfg.AzureAuth) {
      if ($cfg.AzureAuth.TenantId) { $TenantId = [string]$cfg.AzureAuth.TenantId }
      if ($cfg.AzureAuth.ClientId) { $ClientId = [string]$cfg.AzureAuth.ClientId }
      if ($cfg.AzureAuth.ClientSecret) { $ClientSecret = [string]$cfg.AzureAuth.ClientSecret }
      if ($cfg.AzureAuth.CertificateThumbprint) { $CertificateThumbprint = [string]$cfg.AzureAuth.CertificateThumbprint }
    }
  }
} catch {}

# Load from AZInfo.csv if still missing
try {
  if (-not $TenantId -or -not $ClientId -or (-not $ClientSecret -and -not $CertificateThumbprint)) {
    $csvPath = Join-Path $RepoRoot 'AZInfo.csv'
    if (Test-Path -LiteralPath $csvPath) {
      $rows = Import-Csv -LiteralPath $csvPath -ErrorAction Stop
      $row = $rows | Select-Object -First 1
      if ($row) {
        function __GetCsvVal([object]$o, [string]$name) {
          try {
            if ($o.PSObject.Properties.Name -contains $name) {
              $v = [string]$o.$name
              if ($v -and $v.Trim()) { return $v.Trim() }
            } else {
              $prop = $o.PSObject.Properties | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
              if ($prop -and $prop.Value) {
                $v = [string]$prop.Value
                if ($v -and $v.Trim()) { return $v.Trim() }
              }
            }
          } catch {}
          return $null
        }
        if (-not $TenantId) { $TenantId = __GetCsvVal $row 'TenantId' }
        if (-not $ClientId) { $ClientId = __GetCsvVal $row 'ClientId' }
        if (-not $ClientSecret) { $ClientSecret = __GetCsvVal $row 'ClientSecret' }
        if (-not $CertificateThumbprint) { $CertificateThumbprint = __GetCsvVal $row 'CertificateThumbprint' }
      }
    }
  }
} catch {}

# Ensure module installed and import it
try {
  if (-not (Get-Module -ListAvailable -Name 'IntuneWin32App')) {
    Install-Module IntuneWin32App -Scope CurrentUser -Force -ErrorAction Stop
  }
  Import-Module IntuneWin32App -ErrorAction Stop | Out-Null
} catch {
  Write-Err "IntuneWin32App module not available: $($_.Exception.Message)"
  exit 1
}

# Connect using available app-only credentials (ClientSecret preferred)
try {
  if ($TenantId -and $ClientId -and $ClientSecret) {
    Connect-MSIntuneGraph -TenantID $TenantId -ClientID $ClientId -ClientSecret $ClientSecret -ErrorAction Stop | Out-Null
  } elseif ($TenantId -and $ClientId -and $CertificateThumbprint) {
    Connect-MSIntuneGraph -TenantID $TenantId -ClientID $ClientId -CertificateThumbprint $CertificateThumbprint -ErrorAction Stop | Out-Null
  } else {
    throw "Missing TenantId/ClientId and ClientSecret/CertificateThumbprint (provide in AutoPackager.config.json AzureAuth or AZInfo.csv)."
  }
} catch {
  Write-Err "Failed to connect to Intune Graph: $($_.Exception.Message)"
  exit 1
}

# Validate .intunewin file path from sample code (Temp\install.intunewin)
$setupFile = Join-Path $RepoRoot 'Temp\install.intunewin'
if (-not (Test-Path -LiteralPath $setupFile)) {
  Write-Err "Required .intunewin not found at: $setupFile"
  exit 1
}

# Icon (optional)
$appIcon = $null
if ($IconPath -and $IconPath.Trim()) {
  if (-not (Test-Path -LiteralPath $IconPath)) {
    Write-Err "Icon file not found: $IconPath"
    exit 1
  }
  try {
    $appIcon = New-IntuneWin32AppIcon -FilePath $IconPath -ErrorAction Stop
  } catch {
    Write-Err "Failed to load icon: $($_.Exception.Message)"
    exit 1
  }
}

# Hard-coded values per sample newapp.ps1
$Description = "PlaceHolder for AutoPackager"
$InstallCommand = 'powershell.exe -ExecutionPolicy Bypass -File "install.ps1"'
$UninstallCommand = 'powershell.exe -ExecutionPolicy Bypass -File "uninstall.ps1"'
$InstallExperience = 'system'
$RestartBehavior = 'basedOnReturnCode'
# Sample detection rule (file exists)
$detectionRule = New-IntuneWin32AppDetectionRuleFile -DetectionType exists -Existence -FileOrFolder 'Myapplication.exe' -Path 'c:\program files\MyApplication'

# Add app
try {
  $params = @{
    DisplayName          = $DisplayName
    Description          = $Description
    Publisher            = $Publisher
    AppVersion           = $AppVersion
    FilePath             = $setupFile
    InstallCommandLine   = $InstallCommand
    UninstallCommandLine = $UninstallCommand
    DetectionRule        = $detectionRule
    InstallExperience    = $InstallExperience
    RestartBehavior      = $RestartBehavior
  }
  if ($appIcon) { $params['Icon'] = $appIcon }
  # Allow available uninstall (from GUI/config)
  $params['AllowAvailableUninstall'] = [bool]$AllowAvailableUninstall

  try {
    $app = Add-IntuneWin32App @params
  } catch {
    if ($_.Exception.Message -match "parameter.*AllowAvailableUninstall") {
      $null = $params.Remove('AllowAvailableUninstall')
      $app = Add-IntuneWin32App @params
    } else { throw }
  }
  $id = $null
  try { $id = [string]$app.id } catch {}
  if ($id -and $id.Trim()) {
    Write-Host ("AppId: {0}" -f $id.Trim())
    exit 0
  } else {
    Write-Err "Create succeeded but no Id was returned."
    exit 1
  }
} catch {
  Write-Err "Add-IntuneWin32App failed: $($_.Exception.Message)"
  exit 1
}
