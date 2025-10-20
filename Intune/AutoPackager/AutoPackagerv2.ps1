<# 
AutoPackager Winget → Intune
USAGE / EXAMPLES

Prereqs:
- Azure AD App Registration with Application Graph perms: DeviceManagementApps.ReadWrite.All (admin consent)
- IntuneWin32App PowerShell module (script will install if missing)
- winget (App Installer) on host
- Recipes folder with one or more WingetId.json recipes

Credential sourcing (AZInfo.csv):
- Optional file placed next to this script: <script folder>\AZInfo.csv (case-insensitive on Windows)
- Schema (only the first row is read; headers are case-insensitive):
  TenantId, ClientId, ClientSecret, CertificateThumbprint
- Behavior: If AZInfo.csv is present, any non-empty values override CLI parameters (blank cells are ignored).
- Precedence: If both ClientSecret and CertificateThumbprint are present (via CLI or AZInfo.csv), ClientSecret is used.
- Auth: Provide either ClientSecret or CertificateThumbprint (app-only auth).
- For -DryRun or -NoAuth, Intune authentication is skipped. In default package-only runs, authentication still occurs. To skip auth during package-only troubleshooting, add -NoAuth.
- Example AZInfo.csv (place alongside this script):
  TenantId,ClientId,ClientSecret,CertificateThumbprint
  00000000-0000-0000-0000-000000000000,11111111-1111-1111-1111-111111111111,"<client-secret>",
- Or certificate-based (ClientSecret empty, thumbprint provided):
  TenantId,ClientId,ClientSecret,CertificateThumbprint
  00000000-0000-0000-0000-000000000000,11111111-1111-1111-1111-111111111111,,ABCDEF1234567890ABCDEF1234567890ABCDEF12

Defaults and run modes:
- Default (no -FullRun and no -PackageOnly): Package-only and will prompt you to select a single recipe from the default Recipes folder when -PathRecipes is not provided.
- -FullRun: Full Intune run. If -PathRecipes is not provided, prompts you to select a single recipe. Use -AllRecipes to process all recipes in the default Recipes folder. If -PathRecipes points to a file, runs that file only; if it points to a folder, runs all .json files there.
- -AllRecipes: With -FullRun and no -PathRecipes, process all recipes in the default Recipes folder.
- -PackageOnly: Explicit package-only; also the default if neither -FullRun nor -PackageOnly is specified.
- -DryRun: Version comparison only. Overrides other run modes.

Examples (new defaults):
# Default (package-only) with interactive recipe selection
& '.\Intune\ChatGPT\AutoPackager V3\AutoPackager.ps1'

# Full run for all recipes in the default folder
& '.\Intune\ChatGPT\AutoPackager V3\AutoPackager.ps1' -FullRun -AllRecipes

# Full run for one recipe file
& '.\Intune\ChatGPT\AutoPackager V3\AutoPackager.ps1' -FullRun -PathRecipes '.\Intune\ChatGPT\AutoPackager V3\Recipes\MyApp.json'

# Default (package-only) for a specific recipe file
& '.\Intune\ChatGPT\AutoPackager V3\AutoPackager.ps1' -PathRecipes '.\Intune\ChatGPT\AutoPackager V3\Recipes\MyApp.json'

Examples using AZInfo.csv (no explicit auth flags):
# Dry run (no download/upload; compares versions only)
& '.\Intune\ChatGPT\AutoPackager V3\AutoPackager.ps1' -DryRun

# Full run (download, wrap, upload) – credentials taken from AZInfo.csv
& '.\Intune\ChatGPT\AutoPackager V3\AutoPackager.ps1' -FullRun

# Package-only troubleshooting (download + wrap .intunewin, no Intune upload)
& '.\Intune\ChatGPT\AutoPackager V3\AutoPackager.ps1' -PackageOnly

# Package-only without Intune auth (skip connection)
& '.\Intune\ChatGPT\AutoPackager V3\AutoPackager.ps1' -PackageOnly -NoAuth

# Target a specific recipes folder (e.g., containing a single recipe)
& '.\Intune\ChatGPT\AutoPackager V3\AutoPackager.ps1' `
-PathRecipes '.\Intune\ChatGPT\AutoPackager V3\Recipes\SingleApp'

Legacy explicit auth (when not using AZInfo.csv):
# Full run with client secret
$sec = Read-Host 'Client Secret' -AsSecureString
& '.\Intune\ChatGPT\AutoPackager V3\AutoPackager.ps1' `
  -TenantId 'TENANT_ID' `
  -ClientId 'APP_ID' `
  -ClientSecret $sec

# Full run with certificate auth (no secret)
& '.\Intune\ChatGPT\AutoPackager V3\AutoPackager.ps1' `
  -TenantId 'TENANT_ID' `
  -ClientId 'APP_ID' `
  -CertificateThumbprint 'THUMBPRINT'

Other options:
# Override architecture (default x64)
& '.\Intune\ChatGPT\AutoPackager V3\AutoPackager.ps1' -PreferArchitecture x86

# Use default scope fallback when recipe scope is blank (machine|user)
# Note: Recipe InstallerPreferences.Scope (if set) is honored first; -DefaultScope is used only when recipe scope is blank.
& '.\Intune\ChatGPT\AutoPackager V3\AutoPackager.ps1' -DefaultScope machine

# Update detection script each publish
& '.\Intune\ChatGPT\AutoPackager V3\AutoPackager.ps1' -UpdateDetection

Behavior notes:
- Always wraps installer (EXE/MSI) into .intunewin. Upload only occurs when not -DryRun and not -PackageOnly.
- DisplayVersion updated to Winget version after successful upload.
- Detection script can be updated with -UpdateDetection; checks installed >= required.
- Recipe ForceUninstall (boolean): when true, the generated install.ps1 performs a pre-uninstall of any existing version after the user popup gate and process closure, before install/upgrade. It omits SystemComponent=1 entries, prefers MSI ProductCode when available, otherwise uses the best matching registry uninstall entry, appends recipe UninstallArgs to the pre-uninstall, and treats 0, 1605, 1641, 3010 as success.
- InstallCommandLine is constructed from InstallArgs only (CustomArgs removed):
  - MSI: msiexec.exe /i "<installerName>" [InstallArgs] (no default /qn; include in InstallArgs if desired)
  - EXE: "<installerName>" [InstallArgs]
  UninstallCommandLine for MSI defaults to msiexec.exe /x {ProductCode} [UninstallArgs] (no default /qn); if ProductCode is unavailable and recipe UninstallArgs is provided, that value is used as-is.
- Scope selection applied only when present (recipe scope first, then -DefaultScope if provided).
- Winget metadata is resolved from GitHub winget-pkgs manifests; no 'winget show' parsing is used.
- Logs: devicemanagement/Intune/ChatGPT/AutoPackager V3/AutoPackager.log. Summary CSV written under Working/.
- -PathRecipes can point to a folder (multiple recipes) OR a single .json recipe file.
- Secondary requirement rule (Required Updates): replaces existing script-based requirement rules with the new presence-only rule; non-script/default requirement rules remain unchanged.
- Primary requirement rule (FullRun): generates a "NotInstalled" requirement script during packaging and applies it to the primary app only during FullRun (not during PackageOnly).
- Requirement script filenames: "<SanitizedAppName>_Requirement.ps1" (presence-only, used by Secondary) and "<SanitizedAppName>_Requirement_NotInstalled.ps1" (not-installed, used by Primary in FullRun).
- Primary deadlines: Not updated by default. To enable deadlines derived from Rings for the primary app, set Primary.AssignmentDefaults.UpdateDeadlineFromRings=true in AutoPackager.config.json.
- Graph fallback note: Uses the IntuneWin32App session (Invoke-MSGraphRequest) when available; otherwise raw REST is used and requires ClientSecret for app-only authentication. In certificate-only scenarios ensure the module-based Graph path is available (so Invoke-MSGraphRequest is used).
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()] [string]$PathRecipes,
    [Parameter()] [string]$TenantId,
    [Parameter()] [string]$ClientId,
    [Parameter()] [securestring]$ClientSecret,
    [Parameter()] [string]$CertificateThumbprint,
    [Parameter()] [switch]$DryRun,
    [Parameter()] [switch]$NoAuth,
    [Parameter()] [string]$WorkingRoot,
    [Parameter()] [string]$LogPath,
    [Parameter()] [ValidateSet("x64","x86","arm64")] [string]$PreferArchitecture = "x64",
    [Parameter()] [ValidateSet('machine','user')] [string]$DefaultScope = 'machine',
    [Parameter()] [string]$WingetSource = "winget",
    [Parameter()] [switch]$UpdateDetection, # attempt to update detection rule/script dynamically
    [Parameter()] [switch]$NoUpdateDetection, # opt-out: skip detection rule/script update
    [Parameter()] [switch]$PackageOnly, # download + wrap only; skip Intune upload/property updates
    [Parameter()] [switch]$FullRun, # full run: connect to Intune, upload, and update properties
    [Parameter()] [switch]$NoUpdateCmds, # opt-out: skip install/uninstall command updates
    [Parameter()] [string]$IntuneWinAppUtilPath,
    [Parameter()] [int]$VerifyTimeoutSeconds = 600, # default 10 minutes
    [Parameter()] [int]$VerifyIntervalSeconds = 10, # default poll every 10 seconds
    [Parameter()] [switch]$SkipVerify,
    [Parameter()] [switch]$StrictVerify,
    [Parameter()] [switch]$ForceConnect,
    [Parameter()] [switch]$NoUpdateDisplayName,
    [Parameter()] [switch]$NoUpdateAppVersion,
    [Parameter()] [string]$SecondaryAppId,
    [Parameter()] [switch]$AllRecipes,
    [Parameter()] [switch]$ReapplySecondaryAssignments,
    [Parameter()] [switch]$NoWingetRefresh

)

# ===== Resolve script root and defaults =====
$script:ScriptRootEffective = $PSScriptRoot
if (-not $script:ScriptRootEffective -or [string]::IsNullOrWhiteSpace($script:ScriptRootEffective)) {
    if ($PSCommandPath) {
        $script:ScriptRootEffective = Split-Path -Parent $PSCommandPath
    } elseif ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
        $script:ScriptRootEffective = Split-Path -Parent $MyInvocation.MyCommand.Path
    } else {
        $script:ScriptRootEffective = (Get-Location).Path
    }
}
# ===== Load optional config (AutoPackager.config.json) =====
if (-not $script:Config) {
    try {
        $cfgPath = Join-Path $script:ScriptRootEffective 'AutoPackager.config.json'
        if (Test-Path -LiteralPath $cfgPath) {
            $script:Config = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
        }
    } catch { }
}
if (-not $WorkingRoot -or [string]::IsNullOrWhiteSpace($WorkingRoot)) {
    $cfgWorking = $null
    try { if ($script:Config -and $script:Config.Paths -and $script:Config.Paths.WorkingRoot) { $cfgWorking = [string]$script:Config.Paths.WorkingRoot } } catch {}
    if ($cfgWorking -and -not [string]::IsNullOrWhiteSpace($cfgWorking)) {
        $WorkingRoot = if ([System.IO.Path]::IsPathRooted($cfgWorking)) { $cfgWorking } else { Join-Path $script:ScriptRootEffective $cfgWorking }
    } else {
        $WorkingRoot = Join-Path $script:ScriptRootEffective 'Working'
    }
}
if (-not $LogPath -or [string]::IsNullOrWhiteSpace($LogPath)) {
    $cfgLog = $null
    try { if ($script:Config -and $script:Config.Paths -and $script:Config.Paths.LogPath) { $cfgLog = [string]$script:Config.Paths.LogPath } } catch {}
    if ($cfgLog -and -not [string]::IsNullOrWhiteSpace($cfgLog)) {
        $LogPath = if ([System.IO.Path]::IsPathRooted($cfgLog)) { $cfgLog } else { Join-Path $script:ScriptRootEffective $cfgLog }
    } else {
        $LogPath = Join-Path $script:ScriptRootEffective 'AutoPackager.log'
    }
}
# ===== Email Settings (edit here) =====
# Always attempt to send a summary email at the end of the run.
# Secrets: Prefer setting SENDGRID_API_KEY environment variable; otherwise you will be prompted once per run.
$EmailTo = if ($script:Config -and $script:Config.Email -and $script:Config.Email.To) { @($script:Config.Email.To) } else { @() }
$EmailFrom = if ($script:Config -and $script:Config.Email -and $script:Config.Email.From) { [string]$script:Config.Email.From } else { $null }
$SmtpServer = if ($script:Config -and $script:Config.Email -and $script:Config.Email.Smtp -and $script:Config.Email.Smtp.Server) { [string]$script:Config.Email.Smtp.Server } else { $null }
$SmtpPort = if ($script:Config -and $script:Config.Email -and $script:Config.Email.Smtp -and $script:Config.Email.Smtp.Port) { [int]$script:Config.Email.Smtp.Port } else { 587 }
$SmtpUseSsl = if ($script:Config -and $script:Config.Email -and $script:Config.Email.Smtp -and ($null -ne $script:Config.Email.Smtp.UseSsl)) { [bool]$script:Config.Email.Smtp.UseSsl } else { $true }
$SmtpUser = if ($script:Config -and $script:Config.Email -and $script:Config.Email.Smtp -and $script:Config.Email.Smtp.User) { [string]$script:Config.Email.Smtp.User } else { $null }
# Plain-text SMTP password (SendGrid API Key). It will be converted to SecureString below.
$SmtpPasswordPlain = $null
try {
    # Prefer secret from config when present
    if ($script:Config -and $script:Config.Email -and $script:Config.Email.Smtp) {
        if ($script:Config.Email.Smtp.ApiKey) {
            $SmtpPasswordPlain = [string]$script:Config.Email.Smtp.ApiKey
        } elseif ($script:Config.Email.Smtp.Password) {
            $SmtpPasswordPlain = [string]$script:Config.Email.Smtp.Password
        }
    }
    if (-not $SmtpPasswordPlain) {
        $apiKeyEnvName = $null
        if ($script:Config -and $script:Config.Email -and $script:Config.Email.Smtp -and $script:Config.Email.Smtp.ApiKeyEnv) {
            $apiKeyEnvName = [string]$script:Config.Email.Smtp.ApiKeyEnv
        }
        if ($apiKeyEnvName -and (Get-Item -Path ("Env:" + $apiKeyEnvName) -ErrorAction SilentlyContinue)) {
            $SmtpPasswordPlain = (Get-Item -Path ("Env:" + $apiKeyEnvName)).Value
        } elseif ($env:SENDGRID_API_KEY) {
            $SmtpPasswordPlain = $env:SENDGRID_API_KEY
        }
    }
} catch { }
if ($SmtpPasswordPlain) {
    $SmtpPassword = ConvertTo-SecureString -String $SmtpPasswordPlain -AsPlainText -Force
} else {
    $SmtpPassword = $null
}
$EmailSubjectPrefix = if ($script:Config -and $script:Config.Email -and $script:Config.Email.SubjectPrefix) { [string]$script:Config.Email.SubjectPrefix } else { 'Intune AutoPackager' }
$EmailAttachCsv = if ($script:Config -and $script:Config.Email -and ($null -ne $script:Config.Email.AttachCsv)) { [bool]$script:Config.Email.AttachCsv } else { $false }
$EmailAttachLog = if ($script:Config -and $script:Config.Email -and ($null -ne $script:Config.Email.AttachLog)) { [bool]$script:Config.Email.AttachLog } else { $true }
$EmailEnabled = if ($script:Config -and $script:Config.Email -and ($null -ne $script:Config.Email.Enabled)) { [bool]$script:Config.Email.Enabled } else { $true }

# SMTP password is set from $SmtpPasswordPlain above; no environment or prompt required.

# ===== Apply config defaults to parameters =====
try {
    # Core defaults
    if (-not $PSBoundParameters.ContainsKey('PreferArchitecture')) {
        try {
            $cfg = $null
            if ($script:Config -and $script:Config.PackagingDefaults) { $cfg = $script:Config.PackagingDefaults }
            elseif ($script:Config -and $script:Config.Defaults) { $cfg = $script:Config.Defaults }
            if ($cfg -and $cfg.PreferArchitecture) { $PreferArchitecture = [string]$cfg.PreferArchitecture }
        } catch {}
    }
    if (-not $PSBoundParameters.ContainsKey('DefaultScope')) {
        try {
            $cfg = $null
            if ($script:Config -and $script:Config.PackagingDefaults) { $cfg = $script:Config.PackagingDefaults }
            elseif ($script:Config -and $script:Config.Defaults) { $cfg = $script:Config.Defaults }
            if ($cfg -and $cfg.DefaultScope) { $DefaultScope = [string]$cfg.DefaultScope }
        } catch {}
    }
    if (-not $PSBoundParameters.ContainsKey('WingetSource')) {
        try {
            $cfg = $null
            if ($script:Config -and $script:Config.PackagingDefaults) { $cfg = $script:Config.PackagingDefaults }
            elseif ($script:Config -and $script:Config.Defaults) { $cfg = $script:Config.Defaults }
            if ($cfg -and $cfg.WingetSource) { $WingetSource = [string]$cfg.WingetSource }
        } catch {}
    }
    # Run mode defaults
    if (-not $PSBoundParameters.ContainsKey('FullRun') -and -not $PSBoundParameters.ContainsKey('PackageOnly')) {
        try {
            $rm = $null
            if ($script:Config -and $script:Config.PackagingDefaults -and $script:Config.PackagingDefaults.RunMode) {
                $rm = [string]$script:Config.PackagingDefaults.RunMode
            } elseif ($script:Config -and $script:Config.Defaults -and $script:Config.Defaults.RunMode) {
                $rm = [string]$script:Config.Defaults.RunMode
            }
            if ($rm) {
                if ($rm -ieq 'FullRun') { $FullRun = $true }
                elseif ($rm -ieq 'PackageOnly') { $PackageOnly = $true }
            }
        } catch {}
    }
    if (-not $PSBoundParameters.ContainsKey('AllRecipes')) {
        try {
            $cfg = $null
            if ($script:Config -and $script:Config.PackagingDefaults) { $cfg = $script:Config.PackagingDefaults }
            elseif ($script:Config -and $script:Config.Defaults) { $cfg = $script:Config.Defaults }
            if ($cfg -and ($null -ne $cfg.AllRecipes)) { $AllRecipes = [bool]$cfg.AllRecipes }
        } catch {}
    }
    # Detection default (translate to NoUpdateDetection when false)
    if (-not $PSBoundParameters.ContainsKey('NoUpdateDetection') -and -not $PSBoundParameters.ContainsKey('UpdateDetection')) {
        try {
            $cfg = $null
            if ($script:Config -and $script:Config.PackagingDefaults) { $cfg = $script:Config.PackagingDefaults }
            elseif ($script:Config -and $script:Config.Defaults) { $cfg = $script:Config.Defaults }
            if ($cfg -and ($null -ne $cfg.UpdateDetection)) {
                if ([bool]$cfg.UpdateDetection) { $UpdateDetection = $true } else { $NoUpdateDetection = $true }
            }
        } catch {}
    }
    # Verify/polling
    if (-not $PSBoundParameters.ContainsKey('VerifyTimeoutSeconds')) {
        try {
            $ver = $null
            if ($script:Config -and $script:Config.IntuneUploadVerify) { $ver = $script:Config.IntuneUploadVerify }
            elseif ($script:Config -and $script:Config.Verify) { $ver = $script:Config.Verify }
            if ($ver -and $ver.TimeoutSeconds) { $VerifyTimeoutSeconds = [int]$ver.TimeoutSeconds }
        } catch {}
    }
    if (-not $PSBoundParameters.ContainsKey('VerifyIntervalSeconds')) {
        try {
            $ver = $null
            if ($script:Config -and $script:Config.IntuneUploadVerify) { $ver = $script:Config.IntuneUploadVerify }
            elseif ($script:Config -and $script:Config.Verify) { $ver = $script:Config.Verify }
            if ($ver -and $ver.IntervalSeconds) { $VerifyIntervalSeconds = [int]$ver.IntervalSeconds }
        } catch {}
    }
    if (-not $PSBoundParameters.ContainsKey('SkipVerify')) {
        try {
            $ver = $null
            if ($script:Config -and $script:Config.IntuneUploadVerify) { $ver = $script:Config.IntuneUploadVerify }
            elseif ($script:Config -and $script:Config.Verify) { $ver = $script:Config.Verify }
            if ($ver -and ($null -ne $ver.SkipVerify)) { $SkipVerify = [bool]$ver.SkipVerify }
        } catch {}
    }
    if (-not $PSBoundParameters.ContainsKey('StrictVerify')) {
        try {
            $ver = $null
            if ($script:Config -and $script:Config.IntuneUploadVerify) { $ver = $script:Config.IntuneUploadVerify }
            elseif ($script:Config -and $script:Config.Verify) { $ver = $script:Config.Verify }
            if ($ver -and ($null -ne $ver.StrictVerify)) { $StrictVerify = [bool]$ver.StrictVerify }
        } catch {}
    }
    # Tool path
    if (-not $PSBoundParameters.ContainsKey('IntuneWinAppUtilPath')) {
        try {
            if ($script:Config -and $script:Config.Paths -and $script:Config.Paths.IntuneWinAppUtil) {
                $cfgTool = [string]$script:Config.Paths.IntuneWinAppUtil
                if ($cfgTool -and $cfgTool.Trim()) {
                    $IntuneWinAppUtilPath = if ([System.IO.Path]::IsPathRooted($cfgTool)) { $cfgTool } else { Join-Path $script:ScriptRootEffective $cfgTool }
                }
            }
        } catch {}
    }
} catch {}

# ===== Log rotation (archive previous run; keep archives 14 days via cleanup) =====
try {
    $null = New-Item -Path (Split-Path $LogPath -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue
    if ($WorkingRoot) { $null = New-Item -Path $WorkingRoot -ItemType Directory -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $LogPath) {
        $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
        $archive = if ($WorkingRoot) { Join-Path $WorkingRoot ("AutoPackager_{0}.log" -f $ts) } else { "$LogPath.$ts.bak" }
        try {
            Move-Item -LiteralPath $LogPath -Destination $archive -Force -ErrorAction Stop
        } catch {
            try {
                Copy-Item -LiteralPath $LogPath -Destination $archive -Force -ErrorAction Stop
                Clear-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue
            } catch { }
        }
    }
} catch { }
# ========== Logging ==========
$script:LogSync = New-Object object
$script:SuppressFirstIntuneWarning = $false
function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR','DEBUG')] [string]$Level = 'INFO')
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts][$Level] $Message"
    Write-Host $line
    try{
        $null = New-Item -Path (Split-Path $LogPath -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue
        [System.Threading.Monitor]::Enter(${script:LogSync})
        $attempts = 0
        while ($true) {
            try {
                Add-Content -Path $LogPath -Value $line -ErrorAction Stop
                break
            } catch {
                if ($attempts -ge 5) { break }
                Start-Sleep -Milliseconds 150
                $attempts++
            }
        }
    } finally {
        [System.Threading.Monitor]::Exit(${script:LogSync})
    }
}
function Stop-WithError([string]$msg){ Write-Log $msg 'ERROR'; throw $msg }

# ========== Utility ==========
function ConvertTo-PlainText {
    param([securestring]$Secure)
    if (-not $Secure) { return $null }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { $null = New-Item -ItemType Directory -Path $Path -Force }
    return (Resolve-Path -LiteralPath $Path).Path
}

# Suppress warnings within a scriptblock (used to hide stale-token warnings during reconnect/first call)
function Invoke-Silently {
    param([Parameter(Mandatory=$true)][scriptblock]$Block)
    $prev = $WarningPreference
    try {
        $WarningPreference = 'SilentlyContinue'
        & $Block
    } finally {
        $WarningPreference = $prev
    }
}

function Ensure-Module {
    param([string]$Name, [string]$MinVersion = $null)
    $loaded = Get-Module -ListAvailable -Name $Name | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $loaded -or ($MinVersion -and ([version]$loaded.Version -lt [version]$MinVersion))) {
        Write-Log "Installing PowerShell module: $Name" 'INFO'
        try {
            $params = @{ Name = $Name; Scope = 'CurrentUser'; Force = $true }
            if ($MinVersion) { $params['MinimumVersion'] = $MinVersion }
            Install-Module @params -ErrorAction Stop
        } catch {
            Stop-WithError ("Failed to install module {0}: {1}" -f $Name, $_.Exception.Message)
        }
    }
    Import-Module $Name -ErrorAction Stop | Out-Null
}

# ========== Recipe JSON parsing (lenient) ==========
function Read-RecipeJson {
    param([Parameter(Mandatory=$true)][string]$Path)
    # Read file
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    } catch {
        Write-Log ("Failed to read recipe {0}: {1}" -f $Path, $_.Exception.Message) 'WARN'
        return $null
    }

    # Strict JSON first
    try {
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        $strictError = $_.Exception.Message
    }

    # Lenient cleanup: remove /* */ and // comments, BOM, and trailing commas before } or ]
    try {
        $clean = $raw
        # strip block comments
        $clean = $clean -replace '(?ms)/\*.*?\*/',''
        # strip line comments
        $clean = $clean -replace '(?m)^\s*//.*$',''
        # remove BOM if present
        if ($clean.Length -gt 0 -and [int][char]$clean[0] -eq 65279) { $clean = $clean.Substring(1) }
        # remove trailing commas
        $clean = [regex]::Replace($clean, ',\s*(?=[}\]])', '')
        # quote unquoted property names at line start (JSONC -> JSON)
        $clean = [regex]::Replace($clean, '(^\s*)([A-Za-z_][A-Za-z0-9_\-\.]*)\s*:', '$1"$2":', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        # convert single-quoted strings to double-quoted strings
        $clean = [regex]::Replace($clean, '''([^''\\]*(?:\\.[^''\\]*)*)''', '"$1"')

        $json = $clean | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $json) { throw "JSON parse returned null after cleaning" }
        Write-Log ("Lenient JSON parse used for {0}; strict parse error: {1}" -f (Split-Path -Leaf $Path), $strictError) 'WARN'
        return $json
    } catch {
        try {
            $preview = $clean
            if ($preview.Length -gt 200) { $preview = $preview.Substring(0,200) }
            Write-Log ("Invalid JSON in {0}: {1}. Cleaned preview:`n{2}" -f (Split-Path -Leaf $Path), $strictError, $preview) 'ERROR'
        } catch {
            Write-Log ("Invalid JSON in {0}: {1}" -f (Split-Path -Leaf $Path), $strictError) 'ERROR'
        }
        return $null
    }
}


# ========== GitHub manifest resolver (winget-pkgs) ==========
function Get-WingetManifestInfoFromGitHub {
   param(
     [Parameter(Mandatory=$true)][string]$WingetId,
     [Parameter()][string]$PreferArchitecture = 'x64',
     [Parameter()][ValidateSet('machine','user')][string]$PreferScope = 'machine',
     [Parameter()][string]$DesiredLocale = 'en-US',
     [Parameter()][string]$DesiredInstallerType = $null,
     [Parameter()][string]$Owner = 'microsoft',
     [Parameter()][string]$Repo = 'winget-pkgs',
     [Parameter()][string]$Branch = 'master',
     [Parameter()][string]$Token = $null
   )
   # Resolve token from config or environment if not provided
   if (-not $Token) {
     try {
       if ($script:Config -and $script:Config.GitHubToken) { $Token = [string]$script:Config.GitHubToken }
     } catch { }
     if (-not $Token) {
       if ($env:GITHUB_TOKEN) { $Token = $env:GITHUB_TOKEN }
       elseif ($env:GH_TOKEN) { $Token = $env:GH_TOKEN }
     }
   }
   $apiBase = 'https://api.github.com'
   $headers = @{
     'Accept'               = 'application/vnd.github+json'
     'User-Agent'           = 'AutoPackager-GitHubManifest/1.0'
     'X-GitHub-Api-Version' = '2022-11-28'
   }
   if ($Token) { $headers['Authorization'] = "Bearer $Token" }

   function __gh_get([string]$url){
     try { return Invoke-RestMethod -Method GET -Uri $url -Headers $headers -TimeoutSec 180 } catch { throw $_ }
   }
   function __join([string[]]$segs){ return ($segs | ForEach-Object { [System.Uri]::EscapeDataString($_) }) -join '/' }
   function __resolve_branch([string]$owner,[string]$repo,[string]$branch){
     try { [void](__gh_get "$apiBase/repos/$owner/$repo/branches/$branch"); return $branch }
     catch {
       $msg = "$($_.Exception.Message)"
       if ($branch -eq 'master' -and ($msg -match '404' -or $msg -match 'Not Found')) { return 'main' }
       return $branch
     }
   }
   function __list([string]$owner,[string]$repo,[string]$branch,[string]$path){
     $base = if ($path) { "$apiBase/repos/$owner/$repo/contents/$(__join ($path -split '/'))" } else { "$apiBase/repos/$owner/$repo/contents" }
     $ub = [System.UriBuilder]$base
     $ub.Query = "ref=$branch"
     return __gh_get $ub.Uri.AbsoluteUri
   }
   function __file([string]$owner,[string]$repo,[string]$branch,[string]$path){
     $base = "$apiBase/repos/$owner/$repo/contents/$(__join ($path -split '/'))"
     $ub = [System.UriBuilder]$base; $ub.Query = "ref=$branch"
     $obj = __gh_get $ub.Uri.AbsoluteUri
     if ($obj -and $obj.type -eq 'file' -and $obj.encoding -eq 'base64' -and $obj.content) {
       $b64 = ($obj.content -replace "`n",'')
       $bytes = [Convert]::FromBase64String($b64)
       return [Text.Encoding]::UTF8.GetString($bytes)
     }
     return $null
   }
   function __id_to_segments([string]$id){
     $parts = $id.Split('.')
     if ($parts.Count -lt 2) { throw "Invalid WingetId '$id' (expected Publisher.Product...)" }
     $bucket = ($parts[0].Substring(0,1)).ToLowerInvariant()
     return @('manifests', $bucket) + $parts
   }
   function __resolve_case([string]$owner,[string]$repo,[string]$branch,[string[]]$segments){
     $resolved=@()
     for($i=0;$i -lt $segments.Count;$i++){
       $seg=$segments[$i]
       if ($i -eq 0) { $resolved+= $seg; continue }
       $parent=($resolved -join '/')
       $items = __list $owner $repo $branch $parent
       $match = $null
       foreach($it in $items){ if ($it.type -eq 'dir' -and $it.name -ieq $seg){ $match=$it.name; break } }
       if (-not $match) { $match = $seg }
       $resolved+= $match
     }
     return ($resolved -join '/')
   }
   function __largest([string[]]$list){
     $num = $list | Where-Object { $_ -match '^\d+(\.\d+)*$' }
     if (-not $num -or $num.Count -eq 0){ return $null }
     $parsed = foreach($d in $num){ try { [pscustomobject]@{ Raw=$d; Ver=[version]$d } } catch {} }
     if (-not $parsed){ return $null }
     return ($parsed | Sort-Object Ver -Descending | Select-Object -First 1).Raw
   }
   function __yaml_scalar([string]$text,[string]$key){
     try {
       $escaped = [regex]::Escape($key)
       $pattern = "(?m)^\s*{0}\s*:\s*(.+)$" -f $escaped
       $m = [regex]::Match($text, $pattern)
       if ($m.Success) { return ($m.Groups[1].Value -replace '^(["'']?)|(["'']?)$','').Trim() }
     } catch { }
     return $null
   }

   $branchEff = __resolve_branch $Owner $Repo $Branch
   $segs = __id_to_segments $WingetId
   $path = __resolve_case $Owner $Repo $branchEff $segs

   $items = __list $Owner $Repo $branchEff $path
   $dirs = @($items | Where-Object { $_.type -eq 'dir' } | ForEach-Object { $_.name })
   $latest = __largest $dirs
   if (-not $latest) { Stop-WithError ("No numeric versions found for {0} at {1}" -f $WingetId, $path) }

   $vPath = "$path/$latest"
   $files = __list $Owner $Repo $branchEff $vPath | Where-Object { $_.type -eq 'file' }
   $installerFiles = @($files | Where-Object { $_.name -match '\.installer\.ya?ml$' } | ForEach-Object { $_.name })
   $localeFiles    = @($files | Where-Object { $_.name -match '\.locale\.[^\.]+\.(ya?ml)$' } | ForEach-Object { $_.name })

   # Fetch YAML contents
   $installerYaml = $null
   if ($installerFiles.Count -gt 0) {
     $selInstaller = ($installerFiles | Sort-Object | Select-Object -First 1)
     $installerYaml = __file $Owner $Repo $branchEff "$vPath/$selInstaller"
   }
   $localeYaml = $null
   if ($localeFiles.Count -gt 0) {
     $pattern = '\.locale\.' + [regex]::Escape($DesiredLocale) + '\.ya?ml$'
     $selLocale = ($localeFiles | Where-Object { $_ -match $pattern } | Select-Object -First 1)
     if (-not $selLocale) { $selLocale = ($localeFiles | Where-Object { $_ -match '\.locale\.en-US\.ya?ml$' } | Select-Object -First 1) }
     if (-not $selLocale) { $selLocale = ($localeFiles | Sort-Object | Select-Object -First 1) }
     if ($selLocale) { $localeYaml = __file $Owner $Repo $branchEff "$vPath/$selLocale" }
   }

   # Parse installer YAML for selection (prefer MSI-like, arch/scope preferences)
   $selUrl = $null; $selType = $null; $selArch = $null; $selScope = $null
   if ($installerYaml) {
     $yamlOk = $false
     try {
       if (-not (Get-Module -ListAvailable -Name 'powershell-yaml')) {
         try { $repoPS = Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue; if ($repoPS -and $repoPS.InstallationPolicy -ne 'Trusted') { Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue | Out-Null } } catch {}
         Install-Module -Name 'powershell-yaml' -Scope CurrentUser -Force -AllowClobber -ErrorAction SilentlyContinue | Out-Null
       }
       Import-Module 'powershell-yaml' -ErrorAction SilentlyContinue | Out-Null
       $instObj = ConvertFrom-Yaml $installerYaml
       $all = @($instObj.Installers)
       if ($all.Count -gt 0) {
         $cands = $all | Where-Object { $_.InstallerUrl }
         # Apply architecture preference strictly when possible
         if ($PreferArchitecture) {
           $archMatches = $cands | Where-Object { $_.Architecture -ieq $PreferArchitecture }
           if ($archMatches.Count -gt 0) { $cands = $archMatches }
         }
         # Apply scope preference when possible
         if ($PreferScope) {
           $scopeMatches = $cands | Where-Object { $_.Scope -ieq $PreferScope }
           if ($scopeMatches.Count -gt 0) { $cands = $scopeMatches }
         }
         # Apply installer type preference from caller (align with GUI behavior)
         if ($DesiredInstallerType) {
           try {
             $pref = $DesiredInstallerType.ToString().ToLower()
             $c3 = $null
             if ($pref -eq 'msi') {
               # Prefer MSI-like types; fallback to URL extension
               $c3 = $cands | Where-Object { $_.InstallerType -and (($_.InstallerType.ToString().ToLower() -eq 'msi') -or ($_.InstallerType.ToString().ToLower() -eq 'wix')) }
               if (-not $c3 -or $c3.Count -eq 0) { $c3 = $cands | Where-Object { $_.InstallerUrl -match '\.msi(\?|$)' } }
             } else {
               # Prefer non-MSI (exe-like) types e.g., exe/nullsoft/inno/burn; fallback to URL .exe
               $c3 = $cands | Where-Object { $_.InstallerType -and (@('msi','wix') -notcontains ($_.InstallerType.ToString().ToLower())) }
               if (-not $c3 -or $c3.Count -eq 0) { $c3 = $cands | Where-Object { $_.InstallerUrl -match '\.exe(\?|$)' } }
             }
             if ($c3 -and $c3.Count -gt 0) { $cands = $c3 }
           } catch { }
         }

         # Sort by arch/scope preferences (type already filtered above when requested)
         $sorted = $cands | Sort-Object `
           @{ Expression = {
                 if ($PreferArchitecture) {
                   if ($_.Architecture -ieq $PreferArchitecture) { 0 } else { 1 }
                 } else { 0 }
               } }, `
           @{ Expression = {
                 if ($PreferScope) {
                   if ($_.Scope -ieq $PreferScope) { 0 } else { 1 }
                 } else { 0 }
               } }

         $sel = $sorted | Select-Object -First 1
         if ($sel) {
           $selUrl  = $sel.InstallerUrl
           # If type missing, infer from URL extension
           $selType = if ($sel.InstallerType) { $sel.InstallerType } elseif ($sel.InstallerUrl -match '\.msi(\?|$)') { 'msi' } elseif ($sel.InstallerUrl -match '\.exe(\?|$)') { 'exe' } else { $null }
           $selArch = $sel.Architecture
           $selScope= $sel.Scope
           $yamlOk = $true
         }
       }
     } catch { }
     if (-not $yamlOk) {
       # Fallback regex to first InstallerUrl
       $m = [regex]::Match($installerYaml, '(?m)^\s*InstallerUrl:\s*(.+)$')
       if ($m.Success) { $selUrl = ($m.Groups[1].Value -replace '^(["''])|(["''])$','').Trim() }
     }
   }

   # Parse locale YAML for metadata
   $locName = $null; $locPublisher = $null; $locAuthor = $null; $locDesc = $null; $locInfoUrl = $null; $locPrivacy = $null
   if ($localeYaml) {
     try {
       if (Get-Module -ListAvailable -Name 'powershell-yaml') {
         $locObj = ConvertFrom-Yaml $localeYaml
         $locName = $locObj.PackageName
         $locPublisher = $locObj.Publisher
         $locAuthor = $locObj.Author
         $locDesc = $locObj.ShortDescription
         $locInfoUrl = $locObj.PublisherUrl
         $locPrivacy = $locObj.PrivacyUrl
       } else {
         $locName = __yaml_scalar $localeYaml 'PackageName'
         $locPublisher = __yaml_scalar $localeYaml 'Publisher'
         $locAuthor = __yaml_scalar $localeYaml 'Author'
         $locDesc = __yaml_scalar $localeYaml 'ShortDescription'
         $locInfoUrl = __yaml_scalar $localeYaml 'PublisherUrl'
         $locPrivacy = __yaml_scalar $localeYaml 'PrivacyUrl'
       }
     } catch { }
   }

   return [pscustomobject]@{
     Id            = $WingetId
     Name          = $locName
     Version       = $latest
     InstallerUrl  = $selUrl
     InstallerType = $selType
     Architecture  = $selArch
     Scope         = $selScope
     ProductCode   = $null
     Sha256        = $null
     Publisher     = $locPublisher
     Author        = $locAuthor
     Homepage      = $locInfoUrl
     PrivacyUrl    = $locPrivacy
     Description   = $locDesc
     Tags          = @()
   }
}

function Get-WingetInfo {
    param(
        [Parameter(Mandatory=$true)] [string]$WingetId,
        [Parameter()] [string]$PreferArchitecture = 'x64',
        [Parameter()] [string]$WingetSource = 'winget',
        [Parameter()] [ValidateSet('machine','user')] [string]$PreferScope = 'machine'
    )
    Write-Log ("Querying GitHub manifests for {0} ..." -f $WingetId) 'INFO'
    $result = Get-WingetManifestInfoFromGitHub -WingetId $WingetId -PreferArchitecture $PreferArchitecture -PreferScope $PreferScope -DesiredLocale 'en-US'
    if (-not $result) {
        Stop-WithError ("Failed to resolve winget metadata from GitHub for {0}" -f $WingetId)
    }
    return $result
}

# ========== Download and Wrap ==========
# Helper: quick validation that a file is a Windows PE executable (MZ header) and larger than a minimal size
function Test-ExeValid {
    param([string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $false }
        $fi = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($fi.Length -lt 40000) { return $false } # ~40 KB guard to avoid HTML downloads
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -lt 2) { return $false }
        return ($bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A)
    } catch { return $false }
}

function Ensure-IntuneWinAppUtil {
    $toolPath = Join-Path $script:ScriptRootEffective 'IntuneWinAppUtil.exe'
    Write-Log "toolPath variable to look up IntuneWinAppUtil = $toolPath" 'INFO'
    # 1) Explicit override path
    if ($IntuneWinAppUtilPath -and (Test-Path -LiteralPath $IntuneWinAppUtilPath)) {
        if (Test-ExeValid $IntuneWinAppUtilPath) {
            Write-Log ("Found IntuneWinAppUtil.exe via -IntuneWinAppUtilPath: {0}" -f (Resolve-Path -LiteralPath $IntuneWinAppUtilPath)) 'INFO'
            return (Resolve-Path -LiteralPath $IntuneWinAppUtilPath).Path
        } else {
            Stop-WithError ("Provided -IntuneWinAppUtilPath is not a valid IntuneWinAppUtil.exe: {0}" -f $IntuneWinAppUtilPath)
        }
    }

    # 2) Next to script
    if (Test-Path -LiteralPath $toolPath) {
        if (Test-ExeValid $toolPath) {
            Write-Log ("Found existing IntuneWinAppUtil.exe at {0}; skipping download" -f (Resolve-Path -LiteralPath $toolPath)) 'INFO'
            return (Resolve-Path -LiteralPath $toolPath).Path
        } else {
            Stop-WithError ("Invalid IntuneWinAppUtil.exe at {0}. Replace this file or pass -IntuneWinAppUtilPath." -f $toolPath)
        }
    }

    # 3) On PATH
    $onPath = Get-Command 'IntuneWinAppUtil.exe' -ErrorAction SilentlyContinue
    if ($onPath -and (Test-Path -LiteralPath $onPath.Path) -and (Test-ExeValid $onPath.Path)) {
        Write-Log ("Using IntuneWinAppUtil.exe from PATH: {0}" -f $onPath.Path) 'INFO'
        return $onPath.Path
    }

    Stop-WithError "IntuneWinAppUtil.exe not found. Place it next to the script, add it to PATH, or provide -IntuneWinAppUtilPath."
}

function Download-File {
    param(
        [string]$Url,
        [string]$Destination,
        [string]$WingetId
    )
    Write-Log "Downloading $Url -> $Destination" 'INFO'

    # Ensure destination directory exists
    $destDir = Split-Path -Parent $Destination
    if ($destDir) { Ensure-Dir $destDir | Out-Null }

    # Prefer TLS 1.2
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
    $headers = @{
        'User-Agent' = $ua
        'Accept'     = '*/*'
    }
    # SourceForge often serves a timer HTML page to browser UAs; prefer a CLI UA to trigger direct 3xx to a mirror
    try {
        if ($Url -match '(?i)sourceforge\.net') {
            $headers['User-Agent'] = 'Wget/1.21.4'
            Write-Log ("SourceForge detected; overriding User-Agent -> {0}" -f $headers['User-Agent']) 'DEBUG'
        }
    } catch {}
    # IWR defaults
    $maxRedirectionsIwr = 10
    $timeoutIwr = 120

    function Try-Invoke([string]$u,[string]$dest){
        $prev = $ProgressPreference
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $u -OutFile $dest -Headers $headers -MaximumRedirection $maxRedirectionsIwr -TimeoutSec $timeoutIwr -UseBasicParsing -ErrorAction Stop
            return $true
        } catch {
            $status = $null
            try { $status = $_.Exception.Response.StatusCode.Value__ } catch {}
            if ($null -eq $status) { $statusText = 'no status' } else { $statusText = $status }
            Write-Log ("Invoke-WebRequest failed ({0}) for {1}: {2}" -f $statusText, $u, $_.Exception.Message) 'WARN'
            return $false
        } finally {
            $ProgressPreference = $prev
        }
    }

    $ok = $false
    $attempted = @()
    $baseUrl = $null
    if ($Url -match '\?') { $baseUrl = $Url.Split('?')[0] }

    # Attempt 1: original URL
    Write-Log "Attempt 1 via Invoke-WebRequest..." 'DEBUG'
    $ok = Try-Invoke $Url $Destination
    $attempted += $Url

    # Attempt 2: if failed and query present, try without query string
    if (-not $ok -and $baseUrl -and -not ($attempted -contains $baseUrl)) {
        Write-Log ("Retry without query string: {0}" -f $baseUrl) 'INFO'
        $ok = Try-Invoke $baseUrl $Destination
        $attempted += $baseUrl
    }

    # Attempt 3: BITS on original URL
    if (-not $ok) {
        try {
            Write-Log "Falling back to BITS transfer (original URL)..." 'INFO'
            Start-BitsTransfer -Source $Url -Destination $Destination -ErrorAction Stop
            $ok = $true
        } catch {
            Write-Log ("BITS failed for {0}: {1}" -f $Url, $_.Exception.Message) 'WARN'
        }
    }

    # Attempt 4: BITS without query
    if (-not $ok -and $baseUrl) {
        try {
            Write-Log ("BITS retry without query: {0}" -f $baseUrl) 'INFO'
            Start-BitsTransfer -Source $baseUrl -Destination $Destination -ErrorAction Stop
            $ok = $true
        } catch {
            Write-Log ("BITS failed for {0}: {1}" -f $baseUrl, $_.Exception.Message) 'WARN'
        }
    }


    if (-not $ok) {
        Stop-WithError ("Failed to download {0}: {1}" -f $Url, "All attempts failed")
    }
    if (-not (Test-Path -LiteralPath $Destination)) {
        Stop-WithError ("Failed to download {0}: {1}" -f $Url, "File not found after transfer")
    }

    # Validate we actually received a binary installer (EXE/MSI) and not an HTML timer/landing page
    function Is-ValidInstaller([string]$p) {
        try {
            if (Test-ExeValid $p) { return $true }
            $pc = Get-MsiProductCodeFromFile -MsiPath $p
            if ($pc) { return $true }
        } catch {}
        return $false
    }

    if (-not (Is-ValidInstaller -p $Destination)) {
        Write-Log ("Downloaded content does not appear to be a valid EXE/MSI (may be a landing/timer page). Attempting SourceForge mirror resolution...") 'WARN'

        # Attempt to resolve the final mirror URL from SourceForge via HEAD Location or HTML meta refresh
        function Resolve-SourceForgeDirect([string]$u) {
            if (-not ($u -match '(?i)sourceforge\.net')) { return $u }
            $uaSf = 'Wget/1.21.4'
            $h2 = @{ 'User-Agent' = $uaSf; 'Accept'='*/*' }
            # Try HEAD first to capture Location without following redirects
            try {
                $resp = $null
                try {
                    $resp = Invoke-WebRequest -Uri $u -Headers $h2 -Method Head -MaximumRedirection 0 -ErrorAction Stop
                } catch {
                    try { $resp = $_.Exception.Response } catch {}
                }
                $loc = $null
                try { if ($resp -and $resp.Headers -and $resp.Headers['Location']) { $loc = [string]$resp.Headers['Location'] } } catch {}
                if ($loc -and $loc.Trim()) {
                    Write-Log ("SourceForge HEAD resolved Location -> {0}" -f $loc) 'INFO'
                    return $loc
                }
            } catch {}
            # Fetch HTML and try to parse a meta refresh or direct exe link
            try {
                $html = Invoke-WebRequest -Uri $u -Headers $h2 -UseBasicParsing -ErrorAction Stop
                $raw = $null
                try { $raw = $html.RawContent } catch { try { $raw = $html.Content } catch {} }
                if ($raw) {
                    # meta refresh e.g., <meta http-equiv="refresh" content="5; url=...">
                    $loc2 = $null
                    try {
                        if ($raw -match "url=([^\`"'\s>]+)") {
                            $loc2 = $matches[1]
                        }
                    } catch {}
                    if ($loc2) {
                        Write-Log ("SourceForge meta-refresh resolved -> {0}" -f $loc2) 'INFO'
                        return $loc2
                    }
                    # Fallback: find a likely direct file link on SF mirrors
                    $loc3 = $null
                    if ($raw -match "(https?://(?:.*\.)?dl\.sourceforge\.net/[^\s\`"'\<\>\r\n]+(?:\.exe|\.msi))") {
                        $loc3 = $matches[1]
                    }
                    if ($loc3) {
                        Write-Log ("SourceForge HTML link resolved -> {0}" -f $loc3) 'INFO'
                        return $loc3
                    }
                }
            } catch {}
            return $u
        }

        $resolvedUrl = Resolve-SourceForgeDirect -u $Url
        if ($resolvedUrl -and ($resolvedUrl -ne $Url)) {
            Write-Log ("Re-downloading from resolved mirror: {0}" -f $resolvedUrl) 'INFO'
            # Overwrite destination with mirror content
            Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue | Out-Null
            $ok2 = Try-Invoke $resolvedUrl $Destination
            if (-not $ok2) {
                # Try again without querystring
                $baseResolved = $null; if ($resolvedUrl -match '\?') { $baseResolved = $resolvedUrl.Split('?')[0] }
                if ($baseResolved) {
                    Write-Log ("Retry mirror without query: {0}" -f $baseResolved) 'INFO'
                    $ok2 = Try-Invoke $baseResolved $Destination
                }
            }
        }

        # Final validation after mirror attempt(s)
        if (-not (Is-ValidInstaller -p $Destination)) {
            Stop-WithError ("Resolved SourceForge URL still produced a non-installer payload. Manual URL may be required. Path: {0}" -f $Destination)
        } else {
            Write-Log "Validated installer payload after mirror resolution." 'INFO'
        }
    }
}

function Get-MsiProductCodeFromFile {
    param([Parameter(Mandatory=$true)][string]$MsiPath)
    try {
        if (-not (Test-Path -LiteralPath $MsiPath)) { return $null }
        $installer = New-Object -ComObject WindowsInstaller.Installer
        # OpenDatabase mode 0 = read-only
        $db = $installer.GetType().InvokeMember('OpenDatabase','InvokeMethod',$null,$installer,@($MsiPath,0))
        $view = $db.OpenView("SELECT `Value` FROM `Property` WHERE `Property`='ProductCode'")
        $view.Execute($null)
        $rec = $view.Fetch()
        if ($rec) {
            $code = $rec.StringData(1)
            if ($code -and $code.Trim()) { return $code.Trim() }
        }
    } catch { }
    return $null
}

function Wrap-IntuneWin {
    param([string]$SourceDir, [string]$SetupFileName, [string]$OutputDir)
    $tool = Ensure-IntuneWinAppUtil

    # Effective output directory (use provided OutputDir if set; else default under script root)
    $effectiveOut = if ($OutputDir -and $OutputDir.Trim()) { Ensure-Dir $OutputDir } else { Ensure-Dir (Join-Path $script:ScriptRootEffective 'output') }

    Write-Log "Wrapping into .intunewin: $SetupFileName" 'INFO'
    Write-Log ("Wrap-IntuneWin params: SourceDir='{0}', SetupFileName='{1}', OutputDir param='{2}'" -f $SourceDir, $SetupFileName, $OutputDir) 'DEBUG'
    Write-Log ("Environment: PSScriptRoot='{0}', CurrentDirectory='{1}', Temp='{2}', PSVersion='{3}'" -f $PSScriptRoot, (Get-Location).Path, $env:TEMP, $PSVersionTable.PSVersion) 'DEBUG'
    try {
        $toolResolved = (Resolve-Path -LiteralPath $tool -ErrorAction Stop).Path
        $toolItem = Get-Item -LiteralPath $toolResolved -ErrorAction Stop
        $toolVer = $null; try { $toolVer = $toolItem.VersionInfo.FileVersion } catch {}
        Write-Log ("IntuneWinAppUtil: Path='{0}', Size={1}, FileVersion='{2}'" -f $toolResolved, $toolItem.Length, $toolVer) 'DEBUG'
    } catch {
        Write-Log ("IntuneWinAppUtil resolution failed: {0}" -f $_.Exception.Message) 'WARN'
    }
    Write-Log ("Output directory (effective): '{0}'" -f $effectiveOut) 'DEBUG'
    # Validate tool before execution; no download attempts
    if (-not (Test-ExeValid $tool)) {
        Stop-WithError ("IntuneWinAppUtil.exe is not a valid executable: {0}" -f $tool)
    }

    # Preflight: ensure the setup file can be opened (avoid transient locks after download)
    $setupPath = Join-Path $SourceDir $SetupFileName
    Write-Log ("Setup path computed: '{0}' (exists={1})" -f $setupPath, (Test-Path -LiteralPath $setupPath)) 'DEBUG'
    $waited = 0
    while ($true) {
        try {
            if (-not (Test-Path -LiteralPath $setupPath)) { throw "Missing" }
            $fs = [System.IO.File]::Open($setupPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            $fs.Close()
            break
        } catch {
            if ($waited -ge 5000) {
                Stop-WithError ("Setup file not readable: {0}. {1}" -f $setupPath, $_.Exception.Message)
            }
            Start-Sleep -Milliseconds 500
            $waited += 500
        }
    }

    try {
        $fi = Get-Item -LiteralPath $setupPath -ErrorAction Stop
        Write-Log ("Setup file details: Size={0}, LastWriteTime={1}, Attributes={2}" -f $fi.Length, $fi.LastWriteTime, $fi.Attributes) 'DEBUG'
    } catch {
        Write-Log ("Could not get setup file details: {0}" -f $_.Exception.Message) 'WARN'
    }

    $quotedSource = '"' + $SourceDir + '"'
    $quotedSetup  = '"' + $SetupFileName + '"'
    $quotedOut    = '"' + $effectiveOut + '"'
    $argString    = "-c $quotedSource -s $quotedSetup -o $quotedOut -q"
    Write-Log ("Invoking IntuneWinAppUtil with arguments: {0}" -f $argString) 'DEBUG'

    try {
        $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
        $logsDir = Ensure-Dir (Join-Path (Split-Path $effectiveOut -Parent) 'Logs')
        $stdoutPath = Join-Path $logsDir ("IntuneWinAppUtil_stdout_{0}.log" -f $ts)
        $stderrPath = Join-Path $logsDir ("IntuneWinAppUtil_stderr_{0}.log" -f $ts)
        Write-Log ("Proc will be: Start-Process -FilePath `"{0}`" -ArgumentList `"{1}`" -RedirectStandardOutput `"{2}`" -RedirectStandardError `"{3}`" -PassThru -Wait -WindowStyle Hidden" -f $tool, $argString, $stdoutPath, $stderrPath) 'INFO'
        $proc = Start-Process -FilePath $tool -ArgumentList $argString -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru -Wait -WindowStyle Hidden
        
    } catch {
        Stop-WithError ("Failed to launch IntuneWinAppUtil.exe: {0}" -f $_.Exception.Message)
    }
    if (-not $proc) {
        Write-Log "IntuneWinAppUtil did not return a process handle." 'WARN'
    }

    # If exit code is non-zero, still attempt to find output, but log the code.
    if ($proc -and $proc.ExitCode -ne 0) {
        Write-Log ("IntuneWinAppUtil exit code: {0}" -f $proc.ExitCode) 'WARN'
    }

    # Determine expected output name first (prefer base name without original extension)
    $expectedOut = Join-Path $effectiveOut ("{0}.intunewin" -f [IO.Path]::GetFileNameWithoutExtension($SetupFileName))
    $altExpected = Join-Path $effectiveOut ("{0}.intunewin" -f [IO.Path]::GetFileName($SetupFileName))
    Write-Log ("Expected output path (no ext): '{0}' (exists={1}); alt (with ext): '{2}' (exists={3})" -f $expectedOut, (Test-Path -LiteralPath $expectedOut), $altExpected, (Test-Path -LiteralPath $altExpected)) 'DEBUG'
    if (Test-Path -LiteralPath $expectedOut) {
        return (Resolve-Path -LiteralPath $expectedOut).Path
    }
    if (Test-Path -LiteralPath $altExpected) {
        return (Resolve-Path -LiteralPath $altExpected).Path
    }

    # Robust search in likely locations
    $candidates = @()
    try {
        $c1 = Get-ChildItem -LiteralPath $effectiveOut -Filter *.intunewin -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if ($c1) { $candidates += $c1 }
    } catch {}
    try {
        $c2 = Get-ChildItem -LiteralPath $effectiveOut -Filter *.intunewin -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if ($c2) { $candidates += $c2 }
    } catch {}
    try {
        $c3 = Get-ChildItem -LiteralPath $SourceDir -Filter *.intunewin -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if ($c3) { $candidates += $c3 }
    } catch {}

    if ($candidates -and $candidates.Count -gt 0) {
        $pick = $candidates | Select-Object -Unique | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($pick) { return $pick.FullName }
    }

    # Last resort: scan under script root for recent intunewin artifacts
    try {
        $since = (Get-Date).AddMinutes(-10)
        $c4 = Get-ChildItem -LiteralPath $script:ScriptRootEffective -Filter *.intunewin -File -Recurse -ErrorAction SilentlyContinue |
              Where-Object { $_.LastWriteTime -ge $since } |
              Sort-Object LastWriteTime -Descending |
              Select-Object -First 1
        if ($c4) { return $c4.FullName }
    } catch {}

    # Diagnostics before failing
    try {
        if (Test-Path -LiteralPath $stdoutPath) {
            $tailOut = (Get-Content -LiteralPath $stdoutPath -Tail 50 -ErrorAction SilentlyContinue) -join "`n"
            if ($tailOut) { Write-Log ("IntuneWinAppUtil stdout (tail):`n{0}" -f $tailOut) 'DEBUG' }
        }
        if (Test-Path -LiteralPath $stderrPath) {
            $tailErr = (Get-Content -LiteralPath $stderrPath -Tail 50 -ErrorAction SilentlyContinue) -join "`n"
            if ($tailErr) { Write-Log ("IntuneWinAppUtil stderr (tail):`n{0}" -f $tailErr) 'DEBUG' }
        }
    } catch {}

    try {
        $listing = (Get-ChildItem -LiteralPath $effectiveOut -Force -ErrorAction SilentlyContinue | Select-Object Name,Length,LastWriteTime | Out-String)
        if ($listing) { Write-Log ("Output directory contents:`n{0}" -f $listing.TrimEnd()) 'DEBUG' }
        $srcList = (Get-ChildItem -LiteralPath $SourceDir -Force -ErrorAction SilentlyContinue | Select-Object Name,Length,LastWriteTime | Out-String)
        if ($srcList) { Write-Log ("Source directory contents:`n{0}" -f $srcList.TrimEnd()) 'DEBUG' }
    } catch {}

    Stop-WithError "IntuneWinAppUtil completed but no .intunewin was found."
}

# ========== Intune (via community module) ==========
function Connect-Intune {
    # Requires community module IntuneWin32App
    Ensure-Module -Name 'IntuneWin32App'
    if ($ClientSecret) {
        $plain = ConvertTo-PlainText $ClientSecret
        Write-Log "Connecting to Intune (app-only auth) using client secret ..." 'INFO'
        Invoke-Silently { Connect-MSIntuneGraph -TenantID $TenantId -ClientID $ClientId -ClientSecret $plain -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null }
        $script:SuppressFirstIntuneWarning = $true
        Write-Log "Connected to Intune (token refreshed)." 'INFO'
    } elseif ($CertificateThumbprint) {
        Write-Log "Connecting to Intune (app-only auth) using certificate thumbprint ..." 'INFO'
        Invoke-Silently { Connect-MSIntuneGraph -TenantID $TenantId -ClientID $ClientId -CertificateThumbprint $CertificateThumbprint -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null }
        $script:SuppressFirstIntuneWarning = $true
        Write-Log "Connected to Intune (token refreshed)." 'INFO'
    } else {
        Stop-WithError "Either -ClientSecret or -CertificateThumbprint must be provided for app-only authentication."
    }
}

function Ensure-IntuneToken {
    # Ensure IntuneWin32App module is present
    try { Ensure-Module -Name 'IntuneWin32App' } catch {}

    # Force reconnect when requested
    if ($ForceConnect) {
        $disc = Get-Command -Name Disconnect-MSIntuneGraph -ErrorAction SilentlyContinue
        if ($disc) { try { Disconnect-MSIntuneGraph -ErrorAction SilentlyContinue | Out-Null } catch {} }
        Write-Log "ForceConnect set; reconnecting to Intune..." 'WARN'
        Connect-Intune
        return
    }

    # Prefer Test-AccessToken if available
    $test = Get-Command -Name Test-AccessToken -ErrorAction SilentlyContinue
    if ($test) {
        try {
            if (-not (Test-AccessToken)) {
                Write-Log "Access token missing/expired. Reconnecting to Intune..." 'WARN'
                $disc = Get-Command -Name Disconnect-MSIntuneGraph -ErrorAction SilentlyContinue
                if ($disc) { try { Disconnect-MSIntuneGraph -ErrorAction SilentlyContinue | Out-Null } catch {} }
                Connect-Intune
            } else {
                Write-Log "Access token valid." 'DEBUG'
            }
        } catch {
            Write-Log ("Test-AccessToken threw: {0}. Reconnecting..." -f $_.Exception.Message) 'WARN'
            $disc = Get-Command -Name Disconnect-MSIntuneGraph -ErrorAction SilentlyContinue
            if ($disc) { try { Disconnect-MSIntuneGraph -ErrorAction SilentlyContinue | Out-Null } catch {} }
            Connect-Intune
        }
    } else {
        # No token tester available; avoid probing with Intune cmdlets (which can emit stale-token warnings). Reconnect directly.
        $disc = Get-Command -Name Disconnect-MSIntuneGraph -ErrorAction SilentlyContinue
        if ($disc) { try { Disconnect-MSIntuneGraph -ErrorAction SilentlyContinue | Out-Null } catch {} }
        Connect-Intune
    }
}

# ========== Graph helpers for content verification ==========
function Get-GraphAccessToken {
    # Client credentials (app-only) flow using provided TenantId/ClientId/ClientSecret
    if (-not $ClientSecret) {
        Stop-WithError "Graph fallback requires -ClientSecret. Either install a module exposing Invoke-MSGraphRequest or provide -ClientSecret."
    }
    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $ClientId
        client_secret = (ConvertTo-PlainText $ClientSecret)
        scope         = 'https://graph.microsoft.com/.default'
        grant_type    = 'client_credentials'
    }
    try {
        $resp = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
        if (-not $resp.access_token) { throw "No access_token in response." }
        return $resp.access_token
    } catch {
        Stop-WithError ("Failed to obtain Graph access token: {0}" -f $_.Exception.Message)
    }
}

function Invoke-GraphJson {
    param(
        [Parameter()][ValidateSet('GET','POST','PATCH','DELETE')][string]$Method = 'GET',
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter()][hashtable]$Query,
        [Parameter()][object]$Body
    )
    $base = 'https://graph.microsoft.com/v1.0'
    $url = if ($Path -match '^https?://') { $Path } else { "$base$Path" }
    if ($Query -and $Query.Count -gt 0) {
        $pairs = @()
        foreach ($k in $Query.Keys) {
            $v = [System.Uri]::EscapeDataString([string]$Query[$k])
            $pairs += ("{0}={1}" -f $k, $v)
        }
        $qs = ($pairs -join '&')
        if ($url -match '\?') { $url = "$url&$qs" } else { $url = "$url`?$qs" }
    }

    # Preferred: Invoke-MSGraphRequest (uses current module session)
    $cmd = Get-Command -Name Invoke-MSGraphRequest -ErrorAction SilentlyContinue
    if ($cmd) {
        try {
            if ($cmd.Parameters.Keys -contains 'HttpMethod') {
                return Invoke-MSGraphRequest -Url $url -HttpMethod $Method -OutputType Json -Body $Body -ErrorAction Stop
            } else {
                return Invoke-MSGraphRequest -Url $url -Method $Method -OutputType Json -Body $Body -ErrorAction Stop
            }
        } catch {
            Stop-WithError ("Graph call failed via module: {0} {1} -> {2}" -f $Method, $url, $_.Exception.Message)
        }
    }

    # Fallback: raw REST using app-only token
    $token = Get-GraphAccessToken
    $headers = @{
        Authorization = "Bearer $token"
        Accept        = "application/json"
        'Content-Type'= "application/json"
    }
    try {
        if ($Method -in @('POST','PATCH')) {
            $jsonBody = $null
            if ($Body) { $jsonBody = ($Body | ConvertTo-Json -Depth 10) }
            return Invoke-RestMethod -Method $Method -Uri $url -Headers $headers -Body $jsonBody -ErrorAction Stop
        } else {
            return Invoke-RestMethod -Method $Method -Uri $url -Headers $headers -ErrorAction Stop
        }
    } catch {
        try {
            $respText = $null
            if ($_.Exception.Response) {
                $stream = $_.Exception.Response.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $respText = $reader.ReadToEnd()
                }
            }
            if ($respText) { Write-Log ("Graph error body: {0}" -f $respText) 'ERROR' }
        } catch { }
        Stop-WithError ("Graph call failed (REST): {0} {1} -> {2}" -f $Method, $url, $_.Exception.Message)
    }
}



# ========== AllowAvailableUninstall (Recipe-driven, module-only) ==========
function Apply-RecipeAllowAvailableUninstall {
    param(
        [Parameter(Mandatory=$true)][string]$AppId,
        [Parameter(Mandatory=$true)][bool]$Desired
    )
    Write-Log ("AAU (recipe): desired={0} appId={1}" -f $Desired, $AppId) 'INFO'
    $errorText = $null
    try {
        $cmd = Get-Command -Name Set-IntuneWin32App -ErrorAction SilentlyContinue
        if (-not $cmd) { throw "Set-IntuneWin32App cmdlet not found." }
        if ($cmd.Parameters.Keys -contains 'AllowAvailableUninstall') {
            $boolToken = if ($Desired) { '$true' } else { '$false' }
            $logCmd = ("Set-IntuneWin32App -Id {0} -AllowAvailableUninstall {1} -ErrorAction Stop" -f $AppId, $boolToken)
            Write-Log ("AAU command: {0}" -f $logCmd) 'INFO'
            Set-IntuneWin32App -Id $AppId -AllowAvailableUninstall $Desired -ErrorAction Stop | Out-Null
        } else {
            throw "Module does not expose -AllowAvailableUninstall parameter."
        }
    } catch {
        $errorText = $_.Exception.Message
        Write-Log ("AAU set failed for app {0}: {1}" -f $AppId, $errorText) 'WARN'
    }

    $after = $null
    try {
        $verify = Get-IntuneWin32App -Id $AppId -ErrorAction Stop
        $names = $verify.PSObject.Properties.Name
        if ($names -contains 'allowAvailableUninstall') { try { $after = [bool]$verify.allowAvailableUninstall } catch {} }
        elseif ($names -contains 'AllowAvailableUninstall') { try { $after = [bool]$verify.AllowAvailableUninstall } catch {} }
    } catch {
        if (-not $errorText) { $errorText = $_.Exception.Message }
        Write-Log ("AAU read-back failed for app {0}: {1}" -f $AppId, $_.Exception.Message) 'WARN'
    }

    $ok = ($after -eq $Desired)
    if ($ok) {
        Write-Log ("AAU validated: {0}" -f $after) 'INFO'
    } else {
        Write-Log ("AAU validation mismatch: after={0} desired={1}" -f $after, $Desired) 'WARN'
    }

    return [pscustomobject]@{
        Succeeded = $ok
        After     = $after
        Error     = $errorText
    }
}


# ========== RAW GRAPH FALLBACK HELPERS (Win32 .intunewin upload) ==========
function Get-IntuneWinDetectionInfo {
    param([Parameter(Mandatory=$true)][string]$IntuneWinPath)
    Write-Log ("GraphFallback: reading detection.xml from intunewin '{0}'" -f $IntuneWinPath) 'INFO'
    if (-not (Test-Path -LiteralPath $IntuneWinPath)) {
        Stop-WithError ("GraphFallback: intunewin not found: {0}" -f $IntuneWinPath)
    }
    $zip = $null
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    } catch {}
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($IntuneWinPath)
        $entry = $zip.Entries | Where-Object { $_.Name -and ($_.Name.ToString() -ieq 'detection.xml') -or ($_.FullName -match '(?i)detection\.xml$') } | Select-Object -First 1
        if (-not $entry) { throw "detection.xml entry not found in package" }
        $sr = New-Object System.IO.StreamReader ($entry.Open())
        $xmlText = $sr.ReadToEnd()
        $sr.Close()
        $xml = [xml]$xmlText
        $appInfo = $xml.ApplicationInfo
        if (-not $appInfo) { throw "ApplicationInfo node missing in detection.xml" }
        $fileName = [string]$appInfo.FileName
        $unencryptedSize = [int64]$appInfo.UnencryptedContentSize
        $enc = $appInfo.EncryptionInfo
        if (-not $enc) { throw "EncryptionInfo missing in detection.xml" }

        return [pscustomobject]@{
            FileName                = $fileName
            UnencryptedContentSize  = $unencryptedSize
            Encryption              = [pscustomobject]@{
                encryptionKey        = [string]$enc.EncryptionKey
                macKey               = [string]$enc.MacKey
                initializationVector = [string]$enc.InitializationVector
                mac                  = [string]$enc.Mac
                profileIdentifier    = [string]$enc.ProfileIdentifier
                fileDigest           = [string]$enc.FileDigest
                fileDigestAlgorithm  = [string]$enc.FileDigestAlgorithm
            }
        }
    } catch {
        Stop-WithError ("GraphFallback: failed to parse detection.xml: {0}" -f $_.Exception.Message)
    } finally {
        try { if ($zip) { $zip.Dispose() } } catch {}
    }
}

function New-Win32ContentVersion {
    param([Parameter(Mandatory=$true)][string]$AppId)
    Write-Log ("GraphFallback: creating content version for app {0}" -f $AppId) 'INFO'
    $res = Invoke-GraphJson -Method 'POST' -Path ("https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/{0}/microsoft.graph.win32LobApp/contentVersions" -f $AppId) -Body @{}
    $vid = $null
    try { $vid = [string]$res.id } catch {}
    if (-not $vid) { Stop-WithError "GraphFallback: content version id not returned." }
    Write-Log ("GraphFallback: contentVersion='{0}'" -f $vid) 'DEBUG'
    return $vid
}

function New-Win32FilePlaceholder {
    param(
        [Parameter(Mandatory=$true)][string]$AppId,
        [Parameter(Mandatory=$true)][string]$VersionId,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][int64]$Size,
        [Parameter(Mandatory=$true)][int64]$SizeEncrypted
    )
    Write-Log ("GraphFallback: creating file placeholder name='{0}', size={1}, sizeEncrypted={2}" -f $Name, $Size, $SizeEncrypted) 'INFO'
    $body = @{
        "@odata.type"   = "#microsoft.graph.mobileAppContentFile"
        name            = $Name
        size            = $Size
        sizeEncrypted   = $SizeEncrypted
        manifest        = $null
        isDependency    = $false
    }
    $res = Invoke-GraphJson -Method 'POST' -Path ("https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/{0}/microsoft.graph.win32LobApp/contentVersions/{1}/files" -f $AppId, $VersionId) -Body $body
    $fid = $null
    try { $fid = [string]$res.id } catch {}
    if (-not $fid) { Stop-WithError "GraphFallback: file placeholder id not returned." }
    return $fid
}

function Get-Win32FileStatus {
    param(
        [Parameter(Mandatory=$true)][string]$AppId,
        [Parameter(Mandatory=$true)][string]$VersionId,
        [Parameter(Mandatory=$true)][string]$FileId
    )
    return (Invoke-GraphJson -Method 'GET' -Path ("https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/{0}/microsoft.graph.win32LobApp/contentVersions/{1}/files/{2}" -f $AppId, $VersionId, $FileId))
}

function Wait-Win32FileStorageUri {
    param(
        [Parameter(Mandatory=$true)][string]$AppId,
        [Parameter(Mandatory=$true)][string]$VersionId,
        [Parameter(Mandatory=$true)][string]$FileId,
        [Parameter()][int]$TimeoutSeconds = 600,
        [Parameter()][int]$IntervalSeconds = 5
    )
    Write-Log ("GraphFallback: waiting for azureStorageUri (timeout={0}s, interval={1}s)..." -f $TimeoutSeconds, $IntervalSeconds) 'INFO'
    $start = Get-Date
    while ((Get-Date) - $start -lt [TimeSpan]::FromSeconds($TimeoutSeconds)) {
        try {
            $st = Get-Win32FileStatus -AppId $AppId -VersionId $VersionId -FileId $FileId
            $uri = $null; try { $uri = [string]$st.azureStorageUri } catch {}
            if ($uri -and $uri.Trim()) { return $uri }
        } catch {
            Write-Log ("GraphFallback: polling storage uri failed: {0}" -f $_.Exception.Message) 'WARN'
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
    Stop-WithError "GraphFallback: timed out waiting for azureStorageUri."
}

function Upload-BlobInBlocks {
    param(
        [Parameter(Mandatory=$true)][string]$AzureStorageSasUrl,
        [Parameter(Mandatory=$true)][string]$IntuneWinPath,
        [Parameter()][int]$ChunkSizeBytes = (6MB)
    )
    Write-Log ("GraphFallback: uploading blocks to blob (chunk={0} bytes)" -f $ChunkSizeBytes) 'INFO'
    if (-not (Test-Path -LiteralPath $IntuneWinPath)) {
        Stop-WithError ("GraphFallback: intunewin not found at {0}" -f $IntuneWinPath)
    }
    $fileInfo = Get-Item -LiteralPath $IntuneWinPath -ErrorAction Stop
    $fileLen = [int64]$fileInfo.Length
    $sep = if ($AzureStorageSasUrl -match '\?') { '&' } else { '?' }
    $stream = $null
    $reader = $null
    $blockIds = New-Object System.Collections.Generic.List[string]
    try {
        $stream = [System.IO.File]::Open($IntuneWinPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $reader = New-Object System.IO.BinaryReader($stream)
        $chunks = [int][Math]::Ceiling($fileLen / $ChunkSizeBytes)
        for ($i = 0; $i -lt $chunks; $i++) {
            $start = [int64]$i * [int64]$ChunkSizeBytes
            $len = [int][Math]::Min($ChunkSizeBytes, $fileLen - $start)
            $bytes = $reader.ReadBytes($len)
            $idRaw = $i.ToString("0000")
            $idB64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($idRaw))
            $blockIds.Add($idB64) | Out-Null
            $u = "{0}{1}comp=block&blockid={2}" -f $AzureStorageSasUrl, $sep, [System.Uri]::EscapeDataString($idB64)
            try {
                Invoke-RestMethod -Uri $u -Method Put -Body $bytes -ContentType 'application/octet-stream' -ErrorAction Stop | Out-Null
            } catch {
                Stop-WithError ("GraphFallback: PUT block {0} failed: {1}" -f $idRaw, $_.Exception.Message)
            }
            if ( ($i+1) % 50 -eq 0 -or ($i+1) -eq $chunks) {
                Write-Log ("GraphFallback: uploaded {0}/{1} blocks" -f ($i+1), $chunks) 'DEBUG'
            }
        }
    } finally {
        try { if ($reader) { $reader.Close() } } catch {}
        try { if ($stream) { $stream.Close() } } catch {}
    }
    # Commit block list
    $xml = New-Object System.Text.StringBuilder
    [void]$xml.Append('<?xml version="1.0" encoding="utf-8"?><BlockList>')
    foreach ($bid in $blockIds) { [void]$xml.Append("<Latest>$bid</Latest>") }
    [void]$xml.Append('</BlockList>')
    $commitBlocksUrl = "{0}{1}comp=blocklist" -f $AzureStorageSasUrl, $sep
    try {
        Invoke-RestMethod -Uri $commitBlocksUrl -Method Put -Body ($xml.ToString()) -ContentType 'application/xml' -ErrorAction Stop | Out-Null
    } catch {
        Stop-WithError ("GraphFallback: committing block list failed: {0}" -f $_.Exception.Message)
    }
}

function Commit-Win32FileUpload {
    param(
        [Parameter(Mandatory=$true)][string]$AppId,
        [Parameter(Mandatory=$true)][string]$VersionId,
        [Parameter(Mandatory=$true)][string]$FileId,
        [Parameter(Mandatory=$true)][hashtable]$EncryptionInfo
    )
    Write-Log "GraphFallback: committing Win32 content (encryption info)" 'INFO'
    $body = @{ fileEncryptionInfo = $EncryptionInfo }
    Invoke-GraphJson -Method 'POST' -Path ("https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/{0}/microsoft.graph.win32LobApp/contentVersions/{1}/files/{2}/commit" -f $AppId, $VersionId, $FileId) -Body $body | Out-Null
}

function Wait-Win32CommitComplete {
    param(
        [Parameter(Mandatory=$true)][string]$AppId,
        [Parameter(Mandatory=$true)][string]$VersionId,
        [Parameter(Mandatory=$true)][string]$FileId,
        [Parameter()][int]$TimeoutSeconds = 600,
        [Parameter()][int]$IntervalSeconds = 5
    )
    Write-Log ("GraphFallback: waiting for commit complete (timeout={0}s, interval={1}s)..." -f $TimeoutSeconds, $IntervalSeconds) 'INFO'
    $start = Get-Date
    while ((Get-Date) - $start -lt [TimeSpan]::FromSeconds($TimeoutSeconds)) {
        try {
            $st = Get-Win32FileStatus -AppId $AppId -VersionId $VersionId -FileId $FileId
            $us = $null; try { $us = [string]$st.uploadState } catch {}
            if ($us -and ($us -ieq 'commitFileCompleted' -or $us -ieq 'commitFileSuccess' -or $us -ieq 'success')) {
                Write-Log ("GraphFallback: commit state='{0}'" -f $us) 'INFO'
                return $true
            }
            $detail = $null; try { $detail = [string]$st.uploadStateDetail } catch {}
            Write-Log ("GraphFallback: commit state='{0}' detail='{1}' (waiting...)" -f $us, $detail) 'DEBUG'
        } catch {
            Write-Log ("GraphFallback: polling commit failed: {0}" -f $_.Exception.Message) 'WARN'
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
    Write-Log "GraphFallback: commit wait timed out; proceeding with caution." 'WARN'
    return $false
}

function Set-Win32CommittedContentVersion {
    param(
        [Parameter(Mandatory=$true)][string]$AppId,
        [Parameter(Mandatory=$true)][string]$VersionId
    )
    Write-Log ("GraphFallback: setting committedContentVersion -> {0}" -f $VersionId) 'INFO'
    $body = @{
        "@odata.type"             = "#microsoft.graph.win32LobApp"
        "committedContentVersion" = $VersionId
    }
    Invoke-GraphJson -Method 'PATCH' -Path ("https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/{0}" -f $AppId) -Body $body | Out-Null
}

function Upload-IntuneWinViaGraph {
    param(
        [Parameter(Mandatory=$true)][string]$AppId,
        [Parameter(Mandatory=$true)][string]$IntuneWinPath,
        [Parameter()][int]$TimeoutSeconds = 600,
        [Parameter()][int]$IntervalSeconds = 5
    )
    Write-Log ("GraphFallback: starting raw Graph upload for app {0}" -f $AppId) 'INFO'
    $det = Get-IntuneWinDetectionInfo -IntuneWinPath $IntuneWinPath
    $verId = New-Win32ContentVersion -AppId $AppId
    $lenEnc = ([int64](Get-Item -LiteralPath $IntuneWinPath -ErrorAction Stop).Length)
    $fileId = New-Win32FilePlaceholder -AppId $AppId -VersionId $verId -Name $det.FileName -Size $det.UnencryptedContentSize -SizeEncrypted $lenEnc
    $sas = Wait-Win32FileStorageUri -AppId $AppId -VersionId $verId -FileId $fileId -TimeoutSeconds $TimeoutSeconds -IntervalSeconds $IntervalSeconds
    # For safety, avoid logging full SAS
    try { Write-Log ("GraphFallback: received SAS uri (length={0})" -f $sas.Length) 'DEBUG' } catch {}

    Upload-BlobInBlocks -AzureStorageSasUrl $sas -IntuneWinPath $IntuneWinPath
    $enc = @{
        encryptionKey        = $det.Encryption.encryptionKey
        macKey               = $det.Encryption.macKey
        initializationVector = $det.Encryption.initializationVector
        mac                  = $det.Encryption.mac
        profileIdentifier    = $det.Encryption.profileIdentifier
        fileDigest           = $det.Encryption.fileDigest
        fileDigestAlgorithm  = $det.Encryption.fileDigestAlgorithm
    }
    Commit-Win32FileUpload -AppId $AppId -VersionId $verId -FileId $fileId -EncryptionInfo $enc | Out-Null
    $ok = Wait-Win32CommitComplete -AppId $AppId -VersionId $verId -FileId $fileId -TimeoutSeconds $TimeoutSeconds -IntervalSeconds $IntervalSeconds
    if ($ok) { Set-Win32CommittedContentVersion -AppId $AppId -VersionId $verId }
    Write-Log ("GraphFallback: upload+commit complete (commitObserved={0})" -f $ok) 'INFO'
    return $ok
}

function Get-IntuneAppById {
    param([string]$Id)
    try {
        if ($script:SuppressFirstIntuneWarning) {
            $res = $null
            Invoke-Silently { $res = Get-IntuneWin32App -Id $Id -ErrorAction Stop }
            $script:SuppressFirstIntuneWarning = $false
            return $res
        } else {
            return Get-IntuneWin32App -Id $Id -ErrorAction Stop
        }
    } catch {
        Stop-WithError ("Failed to get Intune Win32 app {0}: {1}" -f $Id, $_.Exception.Message)
    }
}

function Get-IntuneAppByIdSafe {
    param([string]$Id)
    if ([string]::IsNullOrWhiteSpace($Id)) {
        Write-Log "Get-IntuneAppByIdModule: IntuneAppId is blank; cannot resolve app." 'WARN'
        return $null
    }
    try {
        $res = $null
        $res = Get-IntuneWin32App -Id $Id -ErrorAction Stop
        return $res
     } catch {
        Write-Log ("Get-IntuneAppByIdModule failed: {0}" -f $_.Exception.Message) 'WARN'
        return $null
    }
}

function Get-DisplayVersion {
    param($App)
    if (-not $App) { return $null }
    try {
        $names = $App.PSObject.Properties.Name
        foreach ($n in @('displayVersion','DisplayVersion','appVersion','AppVersion','version','Version')) {
            if ($names -contains $n) {
                $val = [string]$App.$n
                if ($val) { return $val }
            }
        }
        Write-Log ("DisplayVersion not found on app object. Properties: {0}" -f ($names -join ', ')) 'DEBUG'
    } catch {
        Write-Log ("Get-DisplayVersion inspection failed: {0}" -f $_.Exception.Message) 'WARN'
    }
    return $null
}

# Extract size from module app object (tries several property names)
function Get-AppModuleSize {
    param([Parameter(Mandatory=$true)]$AppObject)
    if (-not $AppObject) { return $null }
    $names = $AppObject.PSObject.Properties.Name
    $candidates = @('size','Size','totalSize','TotalSize','totalContentSize','TotalContentSize','packageSize','PackageSize')
    foreach ($n in $candidates) {
        if ($names -contains $n) {
            try { return [int64]($AppObject.$n) } catch { }
        }
    }
    return $null
}

# Verify by module: committedContentVersion increase and size tolerance vs local .intunewin

function Update-IntuneAppContent {
    param([string]$AppId, [string]$IntuneWinPath, [string]$InstallCommandLine, [string]$UninstallCommandLine)
    # Update content version for existing Win32 app
    Write-Log "Uploading .intunewin and updating content for app $AppId ..." 'INFO'

    # Try common upload cmdlets in order, with graceful fallbacks and clear logging
    $cmdUpdate = Get-Command -Name Update-IntuneWin32App -ErrorAction SilentlyContinue
    if ($cmdUpdate) {
        try {
            Write-Log "Attempting upload via Update-IntuneWin32App ..." 'INFO'
            Update-IntuneWin32App -Id $AppId -FilePath $IntuneWinPath -Force -ErrorAction Stop | Out-Null
            if ($InstallCommandLine -or $UninstallCommandLine) {
                try {
                    $body = @{ '@odata.type' = '#microsoft.graph.win32LobApp' }
                    if ($InstallCommandLine)   { $body['installCommandLine']   = $InstallCommandLine }
                    if ($UninstallCommandLine) { $body['uninstallCommandLine'] = $UninstallCommandLine }
                    if ($body.Count -gt 1) {
                        Write-Log "Updating app command lines via Graph PATCH in Update-IntuneAppContent." 'INFO'
                        Invoke-GraphJson -Method 'PATCH' -Path "/deviceAppManagement/mobileApps/$AppId" -Body $body | Out-Null
                    } else {
                        Write-Log "No command line values provided; skipping PATCH." 'DEBUG'
                    }
                } catch {
                    Write-Log ("Failed to update app command lines in Update-IntuneAppContent: {0}" -f $_.Exception.Message) 'WARN'
                }
            }
            return
        } catch {
            Write-Log ("Update-IntuneWin32App failed: {0}" -f $_.Exception.Message) 'WARN'
        }
    }

    $cmdUpload = Get-Command -Name Invoke-IntuneWin32AppUpload -ErrorAction SilentlyContinue
    if ($cmdUpload) {
        try {
            Write-Log "Attempting upload via Invoke-IntuneWin32AppUpload ..." 'INFO'
            Invoke-IntuneWin32AppUpload -Id $AppId -FilePath $IntuneWinPath -ErrorAction Stop | Out-Null
            if ($InstallCommandLine -or $UninstallCommandLine) {
                try {
                    $body = @{ '@odata.type' = '#microsoft.graph.win32LobApp' }
                    if ($InstallCommandLine)   { $body['installCommandLine']   = $InstallCommandLine }
                    if ($UninstallCommandLine) { $body['uninstallCommandLine'] = $UninstallCommandLine }
                    if ($body.Count -gt 1) {
                        Write-Log "Updating app command lines via Graph PATCH in Update-IntuneAppContent." 'INFO'
                        Invoke-GraphJson -Method 'PATCH' -Path "/deviceAppManagement/mobileApps/$AppId" -Body $body | Out-Null
                    } else {
                        Write-Log "No command line values provided; skipping PATCH." 'DEBUG'
                    }
                } catch {
                    Write-Log ("Failed to update app command lines in Update-IntuneAppContent: {0}" -f $_.Exception.Message) 'WARN'
                }
            }
            return
        } catch {
            Write-Log ("Invoke-IntuneWin32AppUpload failed: {0}" -f $_.Exception.Message) 'WARN'
        }
    }

    # Some module versions expose Set-IntuneWin32App with a -FilePath parameter
    $cmdSet = Get-Command -Name Set-IntuneWin32App -ErrorAction SilentlyContinue
    if ($cmdSet -and ($cmdSet.Parameters.Keys -contains 'FilePath')) {
        try {
            Write-Log "Attempting upload via Set-IntuneWin32App -FilePath ..." 'INFO'
            Set-IntuneWin32App -Id $AppId -FilePath $IntuneWinPath -Force -ErrorAction Stop | Out-Null
            if ($InstallCommandLine -or $UninstallCommandLine) {
                try {
                    $body = @{ '@odata.type' = '#microsoft.graph.win32LobApp' }
                    if ($InstallCommandLine)   { $body['installCommandLine']   = $InstallCommandLine }
                    if ($UninstallCommandLine) { $body['uninstallCommandLine'] = $UninstallCommandLine }
                    if ($body.Count -gt 1) {
                        Write-Log "Updating app command lines via Graph PATCH in Update-IntuneAppContent." 'INFO'
                        Invoke-GraphJson -Method 'PATCH' -Path "/deviceAppManagement/mobileApps/$AppId" -Body $body | Out-Null
                    } else {
                        Write-Log "No command line values provided; skipping PATCH." 'DEBUG'
                    }
                } catch {
                    Write-Log ("Failed to update app command lines in Update-IntuneAppContent: {0}" -f $_.Exception.Message) 'WARN'
                }
            }
            return
        } catch {
            Write-Log ("Set-IntuneWin32App -FilePath failed: {0}" -f $_.Exception.Message) 'WARN'
        }
    }

    # Some module versions expose Add-IntuneWin32AppFile for content upload
    $cmdAddFile = Get-Command -Name Add-IntuneWin32AppFile -ErrorAction SilentlyContinue
    if ($cmdAddFile) {
        try {
            Write-Log "Attempting upload via Add-IntuneWin32AppFile ..." 'INFO'
            Add-IntuneWin32AppFile -Id $AppId -FilePath $IntuneWinPath -ErrorAction Stop | Out-Null
            if ($InstallCommandLine -or $UninstallCommandLine) {
                try {
                    $body = @{ '@odata.type' = '#microsoft.graph.win32LobApp' }
                    if ($InstallCommandLine)   { $body['installCommandLine']   = $InstallCommandLine }
                    if ($UninstallCommandLine) { $body['uninstallCommandLine'] = $UninstallCommandLine }
                    if ($body.Count -gt 1) {
                        Write-Log "Updating app command lines via Graph PATCH in Update-IntuneAppContent." 'INFO'
                        Invoke-GraphJson -Method 'PATCH' -Path "/deviceAppManagement/mobileApps/$AppId" -Body $body | Out-Null
                    } else {
                        Write-Log "No command line values provided; skipping PATCH." 'DEBUG'
                    }
                } catch {
                    Write-Log ("Failed to update app command lines in Update-IntuneAppContent: {0}" -f $_.Exception.Message) 'WARN'
                }
            }
            return
        } catch {
            Write-Log ("Add-IntuneWin32AppFile failed: {0}" -f $_.Exception.Message) 'WARN'
        }
    }

    # Some module versions expose Update-IntuneWin32AppPackageFile for content update
    $cmdUpdatePkg = Get-Command -Name Update-IntuneWin32AppPackageFile -ErrorAction SilentlyContinue
    if ($cmdUpdatePkg) {
        try {
            Write-Log "Attempting upload via Update-IntuneWin32AppPackageFile ..." 'INFO'
            Update-IntuneWin32AppPackageFile -Id $AppId -FilePath $IntuneWinPath -ErrorAction Stop | Out-Null
            if ($InstallCommandLine -or $UninstallCommandLine) {
                try {
                    $body = @{ '@odata.type' = '#microsoft.graph.win32LobApp' }
                    if ($InstallCommandLine)   { $body['installCommandLine']   = $InstallCommandLine }
                    if ($UninstallCommandLine) { $body['uninstallCommandLine'] = $UninstallCommandLine }
                    if ($body.Count -gt 1) {
                        Write-Log "Updating app command lines via Graph PATCH in Update-IntuneAppContent." 'INFO'
                        Invoke-GraphJson -Method 'PATCH' -Path "/deviceAppManagement/mobileApps/$AppId" -Body $body | Out-Null
                    } else {
                        Write-Log "No command line values provided; skipping PATCH." 'DEBUG'
                    }
                } catch {
                    Write-Log ("Failed to update app command lines in Update-IntuneAppContent: {0}" -f $_.Exception.Message) 'WARN'
                }
            }
            return
        } catch {
            Write-Log ("Update-IntuneWin32AppPackageFile failed: {0}" -f $_.Exception.Message) 'WARN'
        }
    }

    # As a last diagnostic step, enumerate available commands from the module to aid troubleshooting
    try {
        $available = (Get-Command -Module IntuneWin32App -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Sort-Object) -join ', '
        if ($available) {
            Write-Log ("Available IntuneWin32App commands: {0}" -f $available) 'DEBUG'
        } else {
            Write-Log "No commands discovered from IntuneWin32App module (module may not be loaded correctly)." 'DEBUG'
        }
    } catch {}

    # Raw Graph fallback: attempt direct upload if module attempts failed/unavailable
    try {
        Write-Log "Module-based upload attempts failed or unavailable; attempting raw Graph upload fallback..." 'WARN'
        # Use verification settings as timeouts for SAS provisioning/commit
        $to = if ($VerifyTimeoutSeconds) { [int]$VerifyTimeoutSeconds } else { 600 }
        $iv = if ($VerifyIntervalSeconds) { [int]$VerifyIntervalSeconds } else { 10 }
        $okFallback = Upload-IntuneWinViaGraph -AppId $AppId -IntuneWinPath $IntuneWinPath -TimeoutSeconds $to -IntervalSeconds $iv
        if ($okFallback) {
            Write-Log "Graph fallback upload succeeded." 'INFO'
            if ($InstallCommandLine -or $UninstallCommandLine) {
                try {
                    $body = @{ '@odata.type' = '#microsoft.graph.win32LobApp' }
                    if ($InstallCommandLine)   { $body['installCommandLine']   = $InstallCommandLine }
                    if ($UninstallCommandLine) { $body['uninstallCommandLine'] = $UninstallCommandLine }
                    if ($body.Count -gt 1) {
                        Write-Log "Graph fallback: updating app command lines via Graph PATCH." 'INFO'
                        Invoke-GraphJson -Method 'PATCH' -Path "/deviceAppManagement/mobileApps/$AppId" -Body $body | Out-Null
                    }
                } catch {
                    Write-Log ("Graph fallback: command line PATCH failed: {0}" -f $_.Exception.Message) 'WARN'
                }
            }
            return
        } else {
            Write-Log "Graph fallback upload returned false (unexpected); will throw." 'ERROR'
        }
    } catch {
        Write-Log ("Graph fallback upload failed: {0}" -f $_.Exception.Message) 'ERROR'
    }

    Stop-WithError "Upload failed: module-based upload attempts failed and Graph fallback was not successful."
}

function Set-IntuneAppDisplayVersion {
    param([string]$AppId, [string]$DisplayVersion)
    $cmdSet = Get-Command -Name Set-IntuneWin32App -ErrorAction SilentlyContinue
    if ($cmdSet) {
        if (-not ($cmdSet.Parameters.Keys -contains 'DisplayVersion')) {
            Write-Log "Set-IntuneWin32App in this module version does not support -DisplayVersion; skipping displayVersion update." 'WARN'
            return
        }
        try {
            Set-IntuneWin32App -Id $AppId -DisplayVersion $DisplayVersion -ErrorAction Stop | Out-Null
            Write-Log "Updated app displayVersion -> $DisplayVersion" 'INFO'
            return
        } catch {
            Write-Log "Failed to set displayVersion via Set-IntuneWin32App: $($_.Exception.Message)" 'WARN'
        }
    } else {
        Write-Log "Set-IntuneWin32App cmdlet not found. Skipping displayVersion update." 'WARN'
    }
}

# Snapshot current app metadata (displayName, displayVersion, contentVersion if available)
function Get-IntuneAppSnapshot {
    param([string]$AppId)
    try {
        $app = Get-IntuneWin32App -Id $AppId -ErrorAction Stop
    } catch {
        Stop-WithError ("Get-IntuneAppSnapshot failed to get app {0}: {1}" -f $AppId, $_.Exception.Message)
    }

    $displayName = $app.displayName
    $displayVersion = $app.displayVersion
    $contentVersion = $null

    # Derive content version directly from the app object to avoid interactive Get-IntuneWin32AppMetaData prompts
    try {
        $names = $app.PSObject.Properties.Name
        if ($names -contains 'committedContentVersion') {
            $contentVersion = $app.committedContentVersion
        } elseif ($names -contains 'CommittedContentVersion') {
            $contentVersion = $app.CommittedContentVersion
        } elseif ($names -contains 'contentVersion') {
            $contentVersion = $app.contentVersion
        } elseif ($names -contains 'ContentVersion') {
            $contentVersion = $app.ContentVersion
        }
    } catch {
        Write-Log ("Get-IntuneAppSnapshot: failed to read content version from app object: {0}" -f $_.Exception.Message) 'WARN'
    }

    return [PSCustomObject]@{
        DisplayName    = $displayName
        DisplayVersion = $displayVersion
        ContentVersion = $contentVersion
    }
}

# Poll Intune until the new version is observable (displayVersion or contentVersion advancement)
function Verify-IntuneUpload {
    param(
        [Parameter(Mandatory=$true)][string]$AppId,
        [Parameter()][string]$TargetDisplayVersion,
        [Parameter()][object]$PreSnapshot,
        [Parameter()][int]$TimeoutSeconds = 600,
        [Parameter()][int]$IntervalSeconds = 10,
        [Parameter()][switch]$Strict
    )
    $start = Get-Date
    while ((Get-Date) - $start -lt [TimeSpan]::FromSeconds($TimeoutSeconds)) {
        try {
            $snap = Get-IntuneAppSnapshot -AppId $AppId
            Write-Log ("Verify: displayName='{0}', displayVersion='{1}', contentVersion='{2}'" -f $snap.DisplayName, $snap.DisplayVersion, $snap.ContentVersion) 'DEBUG'

            if ($TargetDisplayVersion -and $snap.DisplayVersion -and ($snap.DisplayVersion -eq $TargetDisplayVersion)) {
                Write-Log ("Verify: displayVersion converged to target '{0}'." -f $TargetDisplayVersion) 'INFO'
                return $true
            }

            if ($PreSnapshot -and $PreSnapshot.ContentVersion -and $snap.ContentVersion -and ($snap.ContentVersion -ne $PreSnapshot.ContentVersion)) {
                Write-Log ("Verify: contentVersion advanced {0} -> {1}" -f $PreSnapshot.ContentVersion, $snap.ContentVersion) 'INFO'
                return $true
            }
        } catch {
            Write-Log ("Verify: snapshot failed: {0}" -f $_.Exception.Message) 'WARN'
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
    Write-Log "Verify: Timeout waiting for Intune to reflect updated app." 'WARN'
    if ($Strict) {
        return $false
    } else {
        Write-Log "Non-strict verification: proceeding despite lack of observable displayVersion/contentVersion change." 'WARN'
        return $true
    }
}

# Attempt to update a PowerShell detection rule script content dynamically if supported by module.
# ========== Detection Script File Generation ==========
function Generate-DetectionScriptFile {
    param(
        [string]$AppName,
        [string]$RequiredVersion,
        [string]$ProductCode, # may be $null
        [string]$VersionRootPath
    )
    try {
        $sanName = ($AppName -replace '[\\/:*?"<>|]','_')
        $sanVer  = ($RequiredVersion -replace '[\\/:*?"<>|]','_')
        $verBase = if ($VersionRootPath -and $VersionRootPath.Trim()) { Ensure-Dir $VersionRootPath } else { Ensure-Dir (Join-Path (Ensure-Dir (Join-Path $WorkingRoot $sanName)) $sanVer) }
        $work = Ensure-Dir (Join-Path $verBase 'Scripts')
        $detectPath = Join-Path $work "$($sanName)_Detect.ps1"
        $content = @"
# Auto-generated by AutoPackager.ps1 (multi-source detection)
param()
`$AppIdentifier = '$AppName'
`$ProductCode   = '$ProductCode'
`$Required      = '$RequiredVersion'

function TryParse-Version([string]`$s){
  try { return [version]`$s } catch {
    if (-not `$s){ return `$null }
    `$parts = (`$s -split '[^0-9]+' | Where-Object { `$_ -match '^\d+$' })
    if (`$parts.Count -eq 0){ return `$null }
    `$nums = `$parts | ForEach-Object { [int]`$_ }
    while(`$nums.Count -lt 4){ `$nums += 0 }
    try { return [version]("{0}.{1}.{2}.{3}" -f `$nums[0],`$nums[1],`$nums[2],`$nums[3]) } catch { return `$null }
  }
}

function Get-FromRegistry([string]`$name,[string]`$productCode){
  `$search = (`$name -replace '\s*\([^)]*\)', '').Trim()
  `$hives = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
  )
  if (`$productCode -and `$productCode -match '^\{[0-9A-Fa-f-]+\}$'){
    foreach(`$h in `$hives){
      `$p = Join-Path `$h `$productCode
      `$props = Get-ItemProperty -Path `$p -EA SilentlyContinue
      if (`$props){
        return [pscustomobject]@{ Name=`$props.DisplayName; Version=`$props.DisplayVersion }
      }
    }
  }
  `$best = `$null
  foreach(`$h in `$hives){
    foreach(`$k in (Get-ChildItem `$h -EA SilentlyContinue)){
      `$props = Get-ItemProperty `$k.PSPath -EA SilentlyContinue
      if (`$props.DisplayName -and (`$props.DisplayName -like "*`$search*")){
        `$cand = [pscustomobject]@{ Name=`$props.DisplayName; Version=`$props.DisplayVersion }
        if (-not `$best){
          `$best = `$cand
        } else {
          `$bv = TryParse-Version `$best.Version
          `$cv = TryParse-Version `$cand.Version
          if (`$cv -and `$bv -and `$cv -gt `$bv){ `$best = `$cand }
        }
      }
    }
  }
  return `$best
}

function Get-FromPackage([string]`$name){
  `$search = (`$name -replace '\s*\([^)]*\)', '').Trim()
  `$best = `$null
  `$pkgs = Get-Package -EA SilentlyContinue | Where-Object { `$_.Name -like "*`$search*" }
  foreach(`$p in `$pkgs){
    `$cand = [pscustomobject]@{ Name=`$p.Name; Version=([string]`$p.Version) }
    if (-not `$best){
      `$best = `$cand
    } else {
      `$bv = TryParse-Version `$best.Version
      `$cv = TryParse-Version `$cand.Version
      if (`$cv -and `$bv -and `$cv -gt `$bv){ `$best = `$cand }
    }
  }
  return `$best
}

function Get-FromUwp([string]`$name){
  `$search = (`$name -replace '\s*\([^)]*\)', '').Trim()
  `$best = `$null
  `$apps = Get-AppxPackage -AllUsers -EA SilentlyContinue | Where-Object { `$_.Name -like "*`$search*" }
  foreach(`$a in `$apps){
    `$cand = [pscustomobject]@{ Name=`$a.Name; Version=([string]`$a.Version) }
    if (-not `$best){
      `$best = `$cand
    } else {
      `$bv = TryParse-Version `$best.Version
      `$cv = TryParse-Version `$cand.Version
      if (`$cv -and `$bv -and `$cv -gt `$bv){ `$best = `$cand }
    }
  }
  return `$best
}

`$candidates = @()
`$reg = Get-FromRegistry `$AppIdentifier `$ProductCode; if (`$reg) { `$candidates += `$reg }
`$pkg = Get-FromPackage `$AppIdentifier; if (`$pkg) { `$candidates += `$pkg }
`$uwp = Get-FromUwp `$AppIdentifier; if (`$uwp) { `$candidates += `$uwp }

if (-not `$candidates -or `$candidates.Count -eq 0){ exit 1 }

`$best = `$candidates | Sort-Object { TryParse-Version `$_.Version } -Descending | Select-Object -First 1
`$installed = TryParse-Version `$best.Version
`$required  = TryParse-Version `$Required
if (-not `$installed -or -not `$required){ exit 1 }
if (`$installed -ge `$required){ Write-Output "installed"; exit 0 } else { exit 1 }
"@
        Set-Content -LiteralPath $detectPath -Value $content -Encoding UTF8
        return $detectPath
    } catch {
        Write-Log ("Generate-DetectionScriptFile error: {0}" -f $_.Exception.Message) 'WARN'
        return $null
    }
}

function Update-DetectionScriptIfPossible {
    param(
        [string]$AppId,
        [string]$AppName,
        [string]$RequiredVersion,
        [string]$ProductCode, # may be $null
        [string]$VersionRootPath
    )
    # Caller controls gating; proceeding to update detection script.
    # Create a stamped detection script file in working folder
    # Place detection script under Working\<AppName>\<Version>\Scripts
    $sanName = ($AppName -replace '[\\/:*?"<>|]','_')
    $sanVer  = ($RequiredVersion -replace '[\\/:*?"<>|]','_')
    $verBase = if ($VersionRootPath -and $VersionRootPath.Trim()) { Ensure-Dir $VersionRootPath } else { Ensure-Dir (Join-Path (Ensure-Dir (Join-Path $WorkingRoot $sanName)) $sanVer) }
    $work = Ensure-Dir (Join-Path $verBase 'Scripts')
    $detectPath = Join-Path $work "$($sanName)_Detect.ps1"
    $content = @"
# Auto-generated by AutoPackager.ps1 (multi-source detection)
param()
`$AppIdentifier = '$AppName'
`$ProductCode   = '$ProductCode'
`$Required      = '$RequiredVersion'

function TryParse-Version([string]`$s){
  try { return [version]`$s } catch {
    if (-not `$s){ return `$null }
    `$parts = (`$s -split '[^0-9]+' | Where-Object { `$_ -match '^\d+$' })
    if (`$parts.Count -eq 0){ return `$null }
    `$nums = `$parts | ForEach-Object { [int]`$_ }
    while(`$nums.Count -lt 4){ `$nums += 0 }
    try { return [version]("{0}.{1}.{2}.{3}" -f `$nums[0],`$nums[1],`$nums[2],`$nums[3]) } catch { return `$null }
  }
}

function Get-FromRegistry([string]`$name,[string]`$productCode){
  `$search = (`$name -replace '\s*\([^)]*\)', '').Trim()
  `$hives = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
  )
  if (`$productCode -and `$productCode -match '^\{[0-9A-Fa-f-]+\}$'){
    foreach(`$h in `$hives){
      `$p = Join-Path `$h `$productCode
      `$props = Get-ItemProperty -Path `$p -EA SilentlyContinue
      if (`$props){
        return [pscustomobject]@{ Name=`$props.DisplayName; Version=`$props.DisplayVersion }
      }
    }
  }
  `$best = `$null
  foreach(`$h in `$hives){
    foreach(`$k in (Get-ChildItem `$h -EA SilentlyContinue)){
      `$props = Get-ItemProperty `$k.PSPath -EA SilentlyContinue
      if (`$props.DisplayName -and (`$props.DisplayName -like "*`$search*")){
        `$cand = [pscustomobject]@{ Name=`$props.DisplayName; Version=`$props.DisplayVersion }
        if (-not `$best){
          `$best = `$cand
        } else {
          `$bv = TryParse-Version `$best.Version
          `$cv = TryParse-Version `$cand.Version
          if (`$cv -and `$bv -and `$cv -gt `$bv){ `$best = `$cand }
        }
      }
    }
  }
  return `$best
}

function Get-FromPackage([string]`$name){
  `$search = (`$name -replace '\s*\([^)]*\)', '').Trim()
  `$best = `$null
  `$pkgs = Get-Package -EA SilentlyContinue | Where-Object { `$_.Name -like "*`$search*" }
  foreach(`$p in `$pkgs){
    `$cand = [pscustomobject]@{ Name=`$p.Name; Version=([string]`$p.Version) }
    if (-not `$best){
      `$best = `$cand
    } else {
      `$bv = TryParse-Version `$best.Version
      `$cv = TryParse-Version `$cand.Version
      if (`$cv -and `$bv -and `$cv -gt `$bv){ `$best = `$cand }
    }
  }
  return `$best
}

function Get-FromUwp([string]`$name){
  `$search = (`$name -replace '\s*\([^)]*\)', '').Trim()
  `$best = `$null
  `$apps = Get-AppxPackage -AllUsers -EA SilentlyContinue | Where-Object { `$_.Name -like "*`$search*" }
  foreach(`$a in `$apps){
    `$cand = [pscustomobject]@{ Name=`$a.Name; Version=([string]`$a.Version) }
    if (-not `$best){
      `$best = `$cand
    } else {
      `$bv = TryParse-Version `$best.Version
      `$cv = TryParse-Version `$cand.Version
      if (`$cv -and `$bv -and `$cv -gt `$bv){ `$best = `$cand }
    }
  }
  return `$best
}

`$candidates = @()
`$reg = Get-FromRegistry `$AppIdentifier `$ProductCode; if (`$reg) { `$candidates += `$reg }
`$pkg = Get-FromPackage `$AppIdentifier; if (`$pkg) { `$candidates += `$pkg }
`$uwp = Get-FromUwp `$AppIdentifier; if (`$uwp) { `$candidates += `$uwp }

if (-not `$candidates -or `$candidates.Count -eq 0){ exit 1 }

`$best = `$candidates | Sort-Object { TryParse-Version `$_.Version } -Descending | Select-Object -First 1
`$installed = TryParse-Version `$best.Version
`$required  = TryParse-Version `$Required
if (-not `$installed -or -not `$required){ exit 1 }
if (`$installed -ge `$required){ Write-Output "installed"; exit 0 } else { exit 1 }
"@
    Set-Content -LiteralPath $detectPath -Value $content -Encoding UTF8

    $cmdSetRule = Get-Command -Name Set-IntuneWin32AppDetectionRule -ErrorAction SilentlyContinue
    $cmdAddRule = Get-Command -Name Add-IntuneWin32AppDetectionRule -ErrorAction SilentlyContinue
    if ($cmdSetRule) {
        try {
            Write-Log "Attempting to update detection script via Set-IntuneWin32AppDetectionRule ..." 'INFO'
            Set-IntuneWin32AppDetectionRule -Id $AppId -PowerShellScriptPath $detectPath -RunAs32Bit:$false -RunAsAccount system -ErrorAction Stop | Out-Null
            Write-Log "Detection script updated." 'INFO'
            return
        } catch {
            Write-Log "Set-IntuneWin32AppDetectionRule failed: $($_.Exception.Message)" 'WARN'
        }
    } elseif ($cmdAddRule) {
        try {
            Write-Log "Attempting to replace detection rule via Add-IntuneWin32AppDetectionRule ..." 'INFO'
            # Some module versions require specify -Replace to overwrite existing rule(s)
            Add-IntuneWin32AppDetectionRule -Id $AppId -PowerShellScriptPath $detectPath -RunAs32Bit:$false -RunAsAccount system -Replace -ErrorAction Stop | Out-Null
            Write-Log "Detection script updated." 'INFO'
            return
        } catch {
            Write-Log "Add-IntuneWin32AppDetectionRule failed: $($_.Exception.Message)" 'WARN'
        }
    } else {
        try {
            Write-Log "Attempting to update detection script via Graph PATCH (beta base) ..." 'INFO'
            $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))
            $rule = @{
                "@odata.type" = "#microsoft.graph.win32LobAppPowerShellScriptRule"
                comparisonValue = $null
                displayName = $null
                enforceSignatureCheck = $false
                operationType = "notConfigured"
                operator = "notConfigured"
                ruleType = "detection"
                runAs32Bit = $false
                runAsAccount = $null
                scriptContent = $encoded
            }
            $body = @{
                "@odata.type" = "#microsoft.graph.win32LobApp"
                rules = @($rule)
            }
            # Use absolute beta URL to bypass the v1.0 base in Invoke-GraphJson
            Invoke-GraphJson -Method 'PATCH' -Path "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$AppId" -Body $body | Out-Null
            Write-Log ("Detection script PATCH (beta) sent. Script length={0} bytes" -f $content.Length) 'INFO'

            # Read-back verification on beta
            try {
                $verify = Invoke-GraphJson -Method 'GET' -Path "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$AppId"
                $hasRule = $false
                try {
                    if ($verify.rules -and $verify.rules.Count -gt 0 -and $verify.rules[0].scriptContent) { $hasRule = $true }
                } catch {}
                if ($hasRule) {
                    Write-Log "Detection script present after PATCH (beta)." 'INFO'
                } else {
                    Write-Log "Detection script not present after PATCH; rules array may not have been accepted." 'WARN'
                }
            } catch {
                Write-Log ("Detection read-back failed: {0}" -f $_.Exception.Message) 'WARN'
            }
        } catch {
            Write-Log ("Graph PATCH for detection rule failed: {0}" -f $_.Exception.Message) 'WARN'
        }
    }
}

# ========== Requirement Rule (NotInstalled generator) ==========
function Generate-RequirementNotInstalledScript {
    param(
        [Parameter(Mandatory=$true)][string]$AppName,
        [Parameter()][string]$VersionRootPath
    )
    try {
        $sanName = ($AppName -replace '[\\/:*?"<>|]','_')
        $verBase = if ($VersionRootPath -and $VersionRootPath.Trim()) { Ensure-Dir $VersionRootPath } else { Ensure-Dir (Join-Path (Ensure-Dir $WorkingRoot) $sanName) }
        $work = Ensure-Dir (Join-Path $verBase 'Scripts')
        $reqPath = Join-Path $work "$($sanName)_Requirement_NotInstalled.ps1"
        $content = @"
# Auto-generated by AutoPackager.ps1 (requirement: NOT installed)
param()
`$AppIdentifier = '$AppName'

function Get-FromRegistry([string]`$name){
  `$search = (`$name -replace '\s*\([^)]*\)', '').Trim()
  `$hives = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
  )
  foreach(`$h in `$hives){
    foreach(`$k in (Get-ChildItem `$h -EA SilentlyContinue)){
      `$props = Get-ItemProperty `$k.PSPath -EA SilentlyContinue
      if (`$props.DisplayName -and (`$props.DisplayName -like "*`$search*")) { return `$true }
    }
  }
  return `$false
}
function Get-FromPackage([string]`$name){
  `$search = (`$name -replace '\s*\([^)]*\)', '').Trim()
  try {
    `$pkgs = Get-Package -EA SilentlyContinue | Where-Object { `$_.Name -like "*`$search*" }
    if (`$pkgs -and `$pkgs.Count -gt 0) { return `$true }
  } catch {}
  return `$false
}
function Get-FromUwp([string]`$name){
  `$search = (`$name -replace '\s*\([^)]*\)', '').Trim()
  try {
    `$apps = Get-AppxPackage -AllUsers -EA SilentlyContinue | Where-Object { `$_.Name -like "*`$search*" }
    if (`$apps -and `$apps.Count -gt 0) { return `$true }
  } catch {}
  return `$false
}

`$present = (Get-FromRegistry `$AppIdentifier) -or (Get-FromPackage `$AppIdentifier) -or (Get-FromUwp `$AppIdentifier)
Write-Output (-not `$present)
exit 0
"@
        Set-Content -LiteralPath $reqPath -Value $content -Encoding UTF8
        Write-Log ("Requirement (NotInstalled) script generated at: {0}" -f $reqPath) 'INFO'
        return $reqPath
    } catch {
        Write-Log ("Generate-RequirementNotInstalledScript error: {0}" -f $_.Exception.Message) 'WARN'
        return $null
    }
}

# ========== Requirement Rule (presence-only) ==========
function Update-RequirementRuleIfPossible {
    param(
        [string]$AppId,
        [string]$AppName,
        [string]$VersionRootPath
    )
    # Generate a presence-only requirement script (no version checks). Returns $true/$false, always exit 0.
    try {
        $sanName = ($AppName -replace '[\\/:*?"<>|]','_')
        $verBase = if ($VersionRootPath -and $VersionRootPath.Trim()) { Ensure-Dir $VersionRootPath } else { Ensure-Dir (Join-Path (Ensure-Dir $WorkingRoot) $sanName) }
        $work = Ensure-Dir (Join-Path $verBase 'Scripts')
        $reqPath = Join-Path $work "$($sanName)_Requirement.ps1"

        $content = @"
# Auto-generated by AutoPackager.ps1 (presence-only requirement)
param()
`$AppIdentifier = '$AppName'

function Get-FromRegistry([string]`$name){
  `$search = (`$name -replace '\s*\([^)]*\)', '').Trim()
  `$hives = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
  )
  foreach(`$h in `$hives){
    foreach(`$k in (Get-ChildItem `$h -EA SilentlyContinue)){
      `$props = Get-ItemProperty `$k.PSPath -EA SilentlyContinue
      if (`$props.DisplayName -and (`$props.DisplayName -like "*`$search*")) { return `$true }
    }
  }
  return `$false
}
function Get-FromPackage([string]`$name){
  `$search = (`$name -replace '\s*\([^)]*\)', '').Trim()
  try {
    `$pkgs = Get-Package -EA SilentlyContinue | Where-Object { `$_.Name -like "*`$search*" }
    if (`$pkgs -and `$pkgs.Count -gt 0) { return `$true }
  } catch {}
  return `$false
}
function Get-FromUwp([string]`$name){
  `$search = (`$name -replace '\s*\([^)]*\)', '').Trim()
  try {
    `$apps = Get-AppxPackage -AllUsers -EA SilentlyContinue | Where-Object { `$_.Name -like "*`$search*" }
    if (`$apps -and `$apps.Count -gt 0) { return `$true }
  } catch {}
  return `$false
}

`$present = (Get-FromRegistry `$AppIdentifier) -or (Get-FromPackage `$AppIdentifier) -or (Get-FromUwp `$AppIdentifier)
Write-Output (`$present -eq `$true)
exit 0
"@
        Set-Content -LiteralPath $reqPath -Value $content -Encoding UTF8
        Write-Log ("Requirement script generated at: {0}" -f $reqPath) 'INFO'
        return $reqPath
    } catch {
        Write-Log ("Update-RequirementRuleIfPossible error: {0}" -f $_.Exception.Message) 'WARN'
    }
}

function Update-RequirementRuleForApp {
    param(
        [Parameter(Mandatory=$true)][string]$AppId,
        [Parameter(Mandatory=$true)][string]$RequirementScriptPath
    )
    if ([string]::IsNullOrWhiteSpace($AppId)) {
        Write-Log "Update-RequirementRuleForApp: AppId is blank." 'WARN'
        return $false
    }
    if (-not (Test-Path -LiteralPath $RequirementScriptPath)) {
        Write-Log ("Update-RequirementRuleForApp: Requirement script not found: {0}" -f $RequirementScriptPath) 'WARN'
        return $false
    }

    # Try module-first
    $usedModule = $false
    try {
        Ensure-Module -Name 'IntuneWin32App'
        $cmdNew = Get-Command -Name New-IntuneWin32AppRequirementRuleScript -ErrorAction SilentlyContinue
        if ($cmdNew) {
            Write-Log "Building requirement rule from script via module..." 'INFO'
            $rule = New-IntuneWin32AppRequirementRuleScript `
                -ScriptFile $RequirementScriptPath `
                -BooleanComparisonOperator equal `
                -BooleanOutputDataType boolean `
                -BooleanValue $true `
                -ScriptContext system

            $cmdSetReq = Get-Command -Name Set-IntuneWin32AppRequirementRule -ErrorAction SilentlyContinue
            $cmdAddReq = Get-Command -Name Add-IntuneWin32AppRequirementRule -ErrorAction SilentlyContinue

            if ($cmdSetReq -and ($cmdSetReq.Parameters.Keys -contains 'Replace')) {
                Write-Log "Setting requirement rule via Set-IntuneWin32AppRequirementRule -Replace ..." 'INFO'
                Set-IntuneWin32AppRequirementRule -Id $AppId -Rule $rule -Replace -ErrorAction Stop | Out-Null
                $usedModule = $true
            } elseif ($cmdSetReq) {
                Write-Log "Setting requirement rule via Set-IntuneWin32AppRequirementRule ..." 'INFO'
                Set-IntuneWin32AppRequirementRule -Id $AppId -Rule $rule -ErrorAction Stop | Out-Null
                $usedModule = $true
            } elseif ($cmdAddReq -and ($cmdAddReq.Parameters.Keys -contains 'Replace')) {
                Write-Log "Adding requirement rule via Add-IntuneWin32AppRequirementRule -Replace ..." 'INFO'
                Add-IntuneWin32AppRequirementRule -Id $AppId -Rule $rule -Replace -ErrorAction Stop | Out-Null
                $usedModule = $true
            } elseif ($cmdAddReq) {
                Write-Log "Adding requirement rule via Add-IntuneWin32AppRequirementRule ..." 'INFO'
                Add-IntuneWin32AppRequirementRule -Id $AppId -Rule $rule -ErrorAction Stop | Out-Null
                $usedModule = $true
            }
        } else {
            Write-Log "New-IntuneWin32AppRequirementRuleScript not available; will use Graph fallback." 'WARN'
        }
    } catch {
        Write-Log ("Module requirement rule update failed: {0}" -f $_.Exception.Message) 'WARN'
    }

    if ($usedModule) {
        Write-Log "Requirement rule updated via module." 'INFO'
        return $true
    }

    # Graph fallback
    try {
        Write-Log "Requirement rule: Graph fallback (beta) to replace script-based requirement rules, preserving non-script/default rules." 'INFO'
        $content = Get-Content -LiteralPath $RequirementScriptPath -Raw -ErrorAction Stop
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))

        $app = Invoke-GraphJson -Method 'GET' -Path ("https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/{0}" -f $AppId)
        $existing = @()
        try { $existing = @($app.rules) } catch {}

        $kept = @()
        foreach ($r in $existing) {
            $odata = $null; $rtype = $null
            try { $odata = [string]$r.'@odata.type' } catch {}
            try { $rtype = [string]$r.ruleType } catch {}
            if ($rtype -and $rtype -ieq 'requirement' -and $odata -and $odata -ieq '#microsoft.graph.win32LobAppPowerShellScriptRule') {
                # drop any previous script-based requirement rules
                Write-Log "Graph fallback: removing existing script-based requirement rule." 'DEBUG'
            } else {
                $kept += $r
            }
        }

        # Compute display name for requirement rule (Graph requires non-empty displayName).
        # Primary (NotInstalled rule): "Presence - <AppName> - Not Installed"
        # Secondary/presence rule:     "Presence - <AppName> - Installed"
        $displayNameForRule = "Presence Requirement"
        $appNameForDisplay = $null
        try { $appNameForDisplay = [string]$app.displayName } catch {}
        $statusSuffix = "Installed"
        try {
            $leafReq = $null
            try { $leafReq = Split-Path -Leaf $RequirementScriptPath } catch {}
            if ($leafReq -and ($leafReq -match '_Requirement_NotInstalled\.ps1$')) {
                $statusSuffix = "Not Installed"
            } else {
                $statusSuffix = "Installed"
            }
        } catch {}
        if ($appNameForDisplay -and $appNameForDisplay.Trim()) {
            $displayNameForRule = "Presence - $appNameForDisplay - $statusSuffix"
        } else {
            $displayNameForRule = "Presence - $statusSuffix"
        }

        $newRule = @{
            "@odata.type" = "#microsoft.graph.win32LobAppPowerShellScriptRule"
            ruleType = "requirement"
            enforceSignatureCheck = $false
            runAs32Bit = $false
            runAsAccount = "system"
            operationType = "boolean"
            operator = "equal"
            comparisonValue = "true"
            displayName = $displayNameForRule
            scriptContent = $encoded
        }

        $merged = @($kept + @($newRule))
        $body = @{
            "@odata.type" = "#microsoft.graph.win32LobApp"
            rules = $merged
        }

        Invoke-GraphJson -Method 'PATCH' -Path ("https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/{0}" -f $AppId) -Body $body | Out-Null
        # Read-back verification (beta) for requirement rule fields
        try {
            $verifyReq = Invoke-GraphJson -Method 'GET' -Path ("https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/{0}" -f $AppId)
            $reqRules = @()
            try { $reqRules = @($verifyReq.rules | Where-Object { $_.ruleType -eq 'requirement' -and $_.'@odata.type' -eq '#microsoft.graph.win32LobAppPowerShellScriptRule' }) } catch {}
            if ($reqRules -and $reqRules.Count -gt 0) {
                $r = $reqRules | Select-Object -First 1
                Write-Log ("Requirement rule verification: operationType='{0}', operator='{1}', comparisonValue='{2}'" -f $r.operationType, $r.operator, $r.comparisonValue) 'INFO'
            } else {
                Write-Log "Requirement rule verification: no script-based requirement rule found after PATCH." 'WARN'
            }
        } catch {
            Write-Log ("Requirement rule read-back failed: {0}" -f $_.Exception.Message) 'WARN'
        }
        Write-Log "Requirement rule updated via Graph (script-based requirement rules replaced)." 'INFO'
        return $true
    } catch {
        Write-Log ("Graph requirement rule update failed: {0}" -f $_.Exception.Message) 'ERROR'
        return $false
    }
}

# ========== Dynamic Install Script Generation ==========
function Generate-InstallScript {
    param(
        [Parameter(Mandatory=$true)][string]$VersionRoot,
        [Parameter(Mandatory=$true)][string]$DownloadDir,
        [Parameter(Mandatory=$true)][string]$InstallerName,
        [Parameter()][string]$InstallArgs,
        [Parameter()][object]$ForceTaskCloseSpec,
        [Parameter()][string]$AppNameForLogs,
        [Parameter()][string]$AppVersionForLogs,
        [Parameter()][bool]$NotificationPopupFlag,
        [Parameter()][string]$ProductCode,
        [Parameter()][bool]$ForceUninstallFlag,
        [Parameter()][string]$UninstallArgsPre,
        [Parameter()][int]$NotificationTimeoutSeconds = 120,
        [Parameter()][int]$DeferralHoursAllowed = 0,
        [Parameter()][bool]$DeferralAllowed = $true
    )
    try {
        $scriptsDir = Ensure-Dir (Join-Path $VersionRoot 'Scripts')
        # Normalize ForceTaskClose into clean .exe list
        $forceList = @()
        if ($ForceTaskCloseSpec) {
            if ($ForceTaskCloseSpec -is [System.Collections.IEnumerable] -and -not ($ForceTaskCloseSpec -is [string])) {
                foreach ($x in $ForceTaskCloseSpec) { if ($null -ne $x) { $forceList += $x.ToString() } }
            } else {
                $s = $ForceTaskCloseSpec.ToString()
                $parts = $s -split "(`r`n|`n|,|;)"
                foreach ($p in $parts) { if ($null -ne $p) { $forceList += $p } }
            }
            $forceList = $forceList | ForEach-Object { $_.ToString().Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
            $forceList = $forceList | ForEach-Object {
                $leaf = [IO.Path]::GetFileName($_)
                if ($leaf -match '\.exe$') { $leaf } else { "$leaf.exe" }
            } | Select-Object -Unique
        }

        $installerNameSafe = [IO.Path]::GetFileName($InstallerName)
        $installArgsSafe = ''
        if ($InstallArgs) { $installArgsSafe = $InstallArgs }
        $uninstallArgsPreSafe = ''
        if ($UninstallArgsPre) { $uninstallArgsPreSafe = $UninstallArgsPre }
        $productCodeSafe = if ($ProductCode) { $ProductCode } else { '' }

        $forceArrayLiteral = if ($forceList -and $forceList.Count -gt 0) {
            $q = $forceList | ForEach-Object { '"' + ($_ -replace '"','`"') + '"' }
            "@(" + ($q -join ",") + ")"
        } else { "@()" }

        # Precompute brand title to bake into generated script (avoid runtime dependency on $script:Config)
        $brandTitleGen = 'Your Company'
        try {
            if ($script:Config -and $script:Config.Branding -and $script:Config.Branding.NotificationBrandTitle) {
                $brandTitleGen = [string]$script:Config.Branding.NotificationBrandTitle
            }
        } catch {}
        # Escape any embedded quotes for safe insertion into here-string
        $brandTitleLiteral = ($brandTitleGen -replace '"','`"')

$content = @"
# Generated by AutoPackager at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
param()
`$GeneratedAt = [datetime]::ParseExact('$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")','yyyy-MM-dd HH:mm:ss',`$null)
`$ErrorActionPreference = 'Stop'
`$VerbosePreference = 'Continue'
# Log file initialization for Intune IME Logs
`$AppNameRaw = "$($AppNameForLogs -replace '"','`"')"
`$AppVersionRaw = "$($AppVersionForLogs -replace '"','`"')"
function Sanitize-ForPath([string]`$s){
  if (-not `$s) { return 'UnknownApp' }
  `$invalid = [IO.Path]::GetInvalidFileNameChars() + [IO.Path]::GetInvalidPathChars()
  -join (`$s.ToCharArray() | ForEach-Object { if (`$invalid -contains `$_) { '_' } else { `$_ } })
}
`$AppName  = Sanitize-ForPath `$AppNameRaw
`$AppVer   = Sanitize-ForPath `$AppVersionRaw
`$LogRoot  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
`$AppLogDir = Join-Path `$LogRoot `$AppName
try { `$null = New-Item -ItemType Directory -Path `$AppLogDir -Force -ErrorAction Stop } catch { `$AppLogDir = Join-Path `$env:TEMP `$AppName; `$null = New-Item -ItemType Directory -Path `$AppLogDir -Force -ErrorAction SilentlyContinue }
`$Stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
`$LogPath = Join-Path `$AppLogDir ("Install_{0}_{1}_{2}.log" -f `$AppName, `$AppVer, `$Stamp)
function Write-Log {
  param([string]`$Message,[ValidateSet('INFO','WARN','ERROR','DEBUG')][string]`$Level='INFO')
  `$ts=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); `$line="[`$ts][`$Level] `$Message"
  Write-Host `$line
  try { Add-Content -Path `$LogPath -Value `$line -Encoding UTF8 } catch {}
}
function Stop-WithError([string]`$m){ Write-Log `$m 'ERROR'; exit 1 }
function Close-Processes([string[]]`$ImageNames,[int]`$TimeoutSeconds=15){
  if(-not `$ImageNames -or `$ImageNames.Count -eq 0){ return }
  foreach(`$img in `$ImageNames){
    `$base=[IO.Path]::GetFileNameWithoutExtension(`$img); if([string]::IsNullOrWhiteSpace(`$base)){ continue }
    `$procs=Get-Process -Name `$base -ErrorAction SilentlyContinue
    if(-not `$procs){ continue }
    foreach(`$p in `$procs){
      `$procId=`$p.Id; `$didGrace=`$false
      try{
        if(`$p.MainWindowHandle -and `$p.MainWindowHandle -ne 0){
          try{ if(`$p.CloseMainWindow()){ `$didGrace=`$true; Write-Log ("Sent CloseMainWindow to PID {0} ({1})" -f `$procId, `$p.ProcessName) 'DEBUG' } } catch {}
        }
      } catch {}
      `$deadline=(Get-Date).AddSeconds(15)
      while((Get-Date) -lt `$deadline){
        if(-not (Get-Process -Id `$procId -ErrorAction SilentlyContinue)){ break }
        Start-Sleep -Milliseconds 400
      }
      if(Get-Process -Id `$procId -ErrorAction SilentlyContinue){
        try{ Stop-Process -Id `$procId -Force -ErrorAction Stop; Write-Log ("Force-terminated PID {0}" -f `$procId) 'WARN' }
        catch{
          try{
            `$tkArgs="/PID `$procId /F /T"; Write-Log ("Fallback: taskkill {0}" -f `$tkArgs) 'WARN'
`$null = Start-Process -FilePath taskkill.exe -ArgumentList `$tkArgs -WindowStyle Hidden -Wait -PassThru
          } catch { Write-Log ("taskkill failed for PID {0}: {1}" -f `$procId, `$_.Exception.Message) 'ERROR' }
        }
      }
    }
  }
}
`$ForceTaskClose = $forceArrayLiteral
`$NotificationPopupEnabled = [bool]::Parse("$( $NotificationPopupFlag )")
`$ForceUninstallEnabled = [bool]::Parse("$( $ForceUninstallFlag )")
`$KnownProductCode = "$productCodeSafe"
`$UninstallArgsPre = "$($uninstallArgsPreSafe -replace '"','`"')"
`$NotificationTimerSeconds = [int]::Parse("$( $NotificationTimeoutSeconds )")
`$DeferralHoursAllowed = [int]::Parse("$( $DeferralHoursAllowed )")
`$DeferralAllowed = [bool]::Parse("$( $DeferralAllowed )")

# Helpers for pre-uninstall (match behavior of uninstall script)
function Normalize-ProductCode([string]`$pc){
  if(-not `$pc){ return `$null }
  `$pc = (`$pc | Out-String).Trim()
  if(`$pc -match '^[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}$'){ return "{`$pc}" }
  if(`$pc -match '^\{[0-9A-Fa-f-]+\}$'){ return `$pc }
  return `$pc
}
function TryParse-Version([string]`$s){
  try { return [version]`$s } catch {
    if (-not `$s){ return `$null }
    `$parts = (`$s -split '[^0-9]+' | Where-Object { `$_ -match '^\d+$' })
    if (`$parts.Count -eq 0){ return `$null }
    `$nums = `$parts | ForEach-Object { [int]`$_ }
    while(`$nums.Count -lt 4){ `$nums += 0 }
    try { return [version]("{0}.{1}.{2}.{3}" -f `$nums[0],`$nums[1],`$nums[2],`$nums[3]) } catch { return `$null }
  }
}
function Get-UninstallEntries {
  `$paths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
  )
  `$list = @()
  foreach(`$p in `$paths){
    foreach(`$k in (Get-ChildItem `$p -EA SilentlyContinue)){
      try{
        `$props = Get-ItemProperty `$k.PSPath -EA SilentlyContinue
        if(-not `$props){ continue }
        # Omit system components
        `$sc = `$null; try { `$sc = [int]`$props.SystemComponent } catch {}
        if (`$sc -eq 1) { Write-Log ("Skipping uninstall key due to SystemComponent=1: {0}" -f `$k.PSPath) 'DEBUG'; continue }
        `$dn = [string]`$props.DisplayName
        `$uv = [string]`$props.DisplayVersion
        `$us = [string]`$props.UninstallString
        if([string]::IsNullOrWhiteSpace(`$dn) -or [string]::IsNullOrWhiteSpace(`$us)){ continue }
        `$list += [pscustomobject]@{
          DisplayName = `$dn
          DisplayVersion = `$uv
          UninstallString = `$us
          KeyPath = `$k.PSPath
        }
      } catch {}
    }
  }
  return `$list
}
function Normalize-SearchName([string]`$s){
  if(-not `$s){ return `$s }
  return ((`$s -replace '\s*\([^)]*\)', '').Trim())
}
function Select-BestMatch([string]`$name,`$entries){
  if(-not `$entries){ return `$null }
  `$cand = `$entries | Where-Object { `$_ -and `$_.DisplayName -and (`$_.DisplayName -like "*`$name*") -and `$_.UninstallString }
  if(-not `$cand -or `$cand.Count -eq 0){ return `$null }
  `$cand = `$cand | Sort-Object @{Expression={ TryParse-Version `$_.DisplayVersion }; Descending=`$true}
  return `$cand | Select-Object -First 1
}
function Parse-UninstallString([string]`$Text){
  if([string]::IsNullOrWhiteSpace(`$Text)){ return `$null }
  # Normalize: strip NULs and normalize smart quotes
  `$in = (`$Text -replace "`u0000","")
  `$in = `$in -replace '[\u201C\u201D]', '"'
  `$in = `$in -replace '[\u2018\u2019]', "'"
  `$in = `$in.Trim()

  `$file = `$null; `$args = ""; `$isMsi = `$false; `$pc = `$null

  # 1) Quoted path with optional args
  if(`$in -match '^\s*"([^"]+)"\s*(.*)$'){
    `$file = `$matches[1]; `$args = `$matches[2]
  } elseif(`$in -match '^(.*?\.(?:exe|msi))(?:\s+(.*))?$'){
    # 2) Unquoted path ending with .exe/.msi, capture remainder as args
    `$file = `$matches[1]
    if (`$matches.Count -ge 3) { `$args = `$matches[2] } else { `$args = "" }
  } else {
    # 3) Fallback: treat entire string as file, trim quotes
    `$file = `$in.Trim('"')
    `$args = ""
  }

  if([string]::IsNullOrWhiteSpace(`$file)){ return `$null }

  `$isMsi = (`$file -match '(?i)\\?msiexec(\.exe)?$') -or (`$file -match '^(?i)msiexec(\.exe)?$')
  if(`$isMsi){
    if(`$args -match '(?i)\{[0-9A-Fa-f\-]{36}\}'){
      `$pc = Normalize-ProductCode `$matches[0]
    } elseif(`$in -match '(?i)\{[0-9A-Fa-f\-]{36}\}'){
      `$pc = Normalize-ProductCode `$matches[0]
    }
  }
  return [pscustomobject]@{ File=`$file; Args=`$args; IsMsi=`$isMsi; ProductCode=`$pc }
}
function Invoke-UninstallCommand([string]`$File,[string]`$Arguments){
  if((![string]::Equals(`$File,'msiexec.exe',[System.StringComparison]::OrdinalIgnoreCase)) -and (-not (Test-Path -LiteralPath `$File))){
    Stop-WithError ("Uninstall executable not found: {0}" -f `$File)
  }
  # Always append recipe UninstallArgsPre if provided (idempotent)
  try {
    `$ua = `$UninstallArgsPre
    if (`$ua) { `$ua = `$ua.Trim() }
    if (`$ua -and `$ua.Length -gt 0) {
      if ([string]::IsNullOrWhiteSpace(`$Arguments)) {
        `$Arguments = `$ua
      } elseif (-not (`$Arguments -match [regex]::Escape(`$ua))) {
        `$Arguments = ("{0} {1}" -f `$Arguments, `$ua)
      }
    }
  } catch { }
  Write-Log ("[PRE-UNINSTALL] Executing: {0} {1}" -f `$File, `$Arguments) 'INFO'
  if ([string]::IsNullOrWhiteSpace(`$Arguments)) {
    `$proc = Start-Process -FilePath `$File -PassThru -Wait -WindowStyle Hidden
  } else {
    `$proc = Start-Process -FilePath `$File -ArgumentList `$Arguments -PassThru -Wait -WindowStyle Hidden
  }
  `$code = if(`$proc){ `$proc.ExitCode } else { `$LASTEXITCODE }
  if(`$null -eq `$code){ `$code = 0 }
  Write-Log ("[PRE-UNINSTALL] Exit code: {0}" -f `$code) 'INFO'
  return `$code
}

# Helper to enumerate currently running targets from ForceTaskClose
function Get-RunningProcessList([string[]]`$ImageNames){
  `$out = @()
  if(-not `$ImageNames -or `$ImageNames.Count -eq 0){ return `$out }
  foreach(`$img in `$ImageNames){
    `$base=[IO.Path]::GetFileName(`$img)
    if([string]::IsNullOrWhiteSpace(`$base)){ continue }
    try{
      `$core = [IO.Path]::GetFileNameWithoutExtension(`$base)
      if([string]::IsNullOrWhiteSpace(`$core)){ continue }
      `$p = Get-Process -Name `$core -ErrorAction SilentlyContinue
      if(`$p){
        if(-not `$base.EndsWith('.exe',[System.StringComparison]::OrdinalIgnoreCase)){ `$base = "`$base.exe" }
        `$out += `$base
      }
    } catch {}
  }
  return (`$out | Where-Object { `$_ } | Select-Object -Unique)
}

# Helper: Active session + WTSSendMessage popup to warn user before forced closes
function Invoke-UserNotification {
  param(
    [string]`$AppName,
    [string]`$AppVersion,
    [string[]]`$ProcessList,
    [int]`$TimeoutSeconds = 120,
    [bool]`$AllowDeferral = `$true,
    [int]`$RemainingDeferralHours = 0,
    [bool]`$DeferralExpired = `$false
  )
  `$BrandTitle = "$brandTitleLiteral"
  if (-not ([System.Management.Automation.PSTypeName]'WTSMessage').Type) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class WTSMessage {
  [DllImport("wtsapi32.dll", SetLastError = true)]
  public static extern bool WTSSendMessage(
    IntPtr hServer,
    int SessionId,
    string pTitle,
    int TitleLength,
    string pMessage,
    int MessageLength,
    uint Style,
    int Timeout,
    out int pResponse,
    bool bWait
  );
}
'@
  }
  function Get-ActiveSessionId {
    try {
      `$raw = (quser) -replace '\s{2,}', ',' | ConvertFrom-Csv
      foreach (`$s in `$raw) {
        if ((`$s.sessionname -notlike "console") -and (`$s.sessionname -notlike "rdp-tcp*")) {
          if (`$s.ID -eq "Active") { return `$s.SESSIONNAME }
        } else {
          if (`$s.STATE -eq "Active") { return [int]`$s.ID }
        }
      }
    } catch {}
    return 1
  }
  `$procListText = (`$ProcessList | ForEach-Object { [IO.Path]::GetFileName(`$_) } | Where-Object { `$_ } | Select-Object -Unique) -join ', '
  if (-not `$procListText -or [string]::IsNullOrWhiteSpace(`$procListText)) { `$procListText = 'the application' }
  `$title = ("{0} - {1} {2} Notification" -f `$BrandTitle, `$AppName, `$AppVersion)
  `$TimeoutMinutes = [int][Math]::Ceiling([double]`$TimeoutSeconds / 60.0)
  `$remainingText = if (`$RemainingDeferralHours -ge 48) { ("{0} days" -f ([int][Math]::Ceiling(`$RemainingDeferralHours / 24.0))) } else { ("{0} hours" -f `$RemainingDeferralHours) }
  if (`$AllowDeferral -and (-not `$DeferralExpired)) {
    `$message = ("{0} needs to install or update {1}. The following apps will be closed: {2}. You have {3} remaining to defer. Click OK to proceed, or Cancel to defer. This will auto-continue after {4} minutes." -f `$BrandTitle, `$AppName, `$procListText, `$remainingText, `$TimeoutMinutes)
    `$style = 0x00001031
  } elseif (`$DeferralExpired) {
    `$message = ("{0} needs to install or update {1}. The following apps will be closed: {2}. The deferral window has expired and the install/update must occur. Click OK to proceed. This will auto-continue after {3} minutes." -f `$BrandTitle, `$AppName, `$procListText, `$TimeoutMinutes)
    `$style = 0x00001030
  } else {
    `$message = ("{0} needs to install or update {1}. The following apps will be closed: {2}. Click OK to proceed. This will auto-continue after {3} minutes." -f `$BrandTitle, `$AppName, `$procListText, `$TimeoutMinutes)
    `$style = 0x00001030
  }
  `$sid = Get-ActiveSessionId
  try {
    `$resp = 0
    [void][WTSMessage]::WTSSendMessage([IntPtr]::Zero, `$sid, `$title, `$title.Length, `$message, `$message.Length, [uint32]`$style, `$TimeoutSeconds, [ref]`$resp, `$true)
    if (`$resp -eq 2) { return 'Cancel' }
    return 'OK'
  } catch {
    return 'OK'
  }
}

`$InstallerName = "$installerNameSafe"
`$InstallArgs   = "$($installArgsSafe -replace '"','`"')"
Write-Log "===== BEGIN Install for '`$AppNameRaw' version '`$AppVersionRaw' ====="
try{
  `$runningList = Get-RunningProcessList -ImageNames `$ForceTaskClose
  if(`$NotificationPopupEnabled -and `$ForceTaskClose -and `$ForceTaskClose.Count -gt 0 -and `$runningList -and `$runningList.Count -gt 0){
    try{
      # Deferral calculation from generation timestamp
      `$deferralConfigured = `$DeferralAllowed -and (`$DeferralHoursAllowed -gt 0)
      `$now = Get-Date
      `$ExpiresAt = if (`$deferralConfigured) { `$GeneratedAt.AddHours(`$DeferralHoursAllowed) } else { `$GeneratedAt }
      `$remainingHours = [int][Math]::Ceiling(([TimeSpan](`$ExpiresAt - `$now)).TotalHours)
      if (`$remainingHours -lt 0) { `$remainingHours = 0 }
      `$deferralExpired = `$deferralConfigured -and (`$now -ge `$ExpiresAt)
      `$effectiveAllowDeferral = `$deferralConfigured -and (-not `$deferralExpired)
      Write-Log ("Deferral window: GeneratedAt={0}, ExpiresAt={1}, Now={2}, RemainingHours={3}, AllowDeferralEffective={4}" -f `$GeneratedAt, `$ExpiresAt, `$now, `$remainingHours, `$effectiveAllowDeferral) 'INFO'
      `$notifResult = Invoke-UserNotification -AppName `$AppNameRaw -AppVersion `$AppVersionRaw -ProcessList `$runningList -TimeoutSeconds `$NotificationTimerSeconds -AllowDeferral `$effectiveAllowDeferral -RemainingDeferralHours `$remainingHours -DeferralExpired `$deferralExpired
      if(`$notifResult -eq 'Cancel'){ Write-Log "User cancelled; deferring (exit 1618)." 'WARN'; exit 1618 }
    } catch { Write-Log ("Popup error: {0}" -f `$_.Exception.Message) 'WARN' }
  }
  if(`$ForceTaskClose -and `$ForceTaskClose.Count -gt 0){ Write-Log ("ForceTaskClose targets: {0}" -f (`$ForceTaskClose -join ', ')) 'INFO'; Close-Processes -ImageNames `$ForceTaskClose -TimeoutSeconds 15 }
  # Resolve path relative to this script's directory (robust across hosts)
  `$scriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
  `$full = Join-Path `$scriptDir `$InstallerName
  if(-not (Test-Path -LiteralPath `$full)){ Stop-WithError ("Installer not found at expected path: {0}" -f `$full) }

  # Optional pre-uninstall flow (after popup gate and process closure)
  if(`$ForceUninstallEnabled){
    Write-Log "ForceUninstall enabled; attempting pre-uninstall..." 'INFO'
    try{
      if(-not [string]::IsNullOrWhiteSpace(`$KnownProductCode)){
        `$pc = Normalize-ProductCode `$KnownProductCode
        `$argsPre = ""
        if (`$UninstallArgsPre -and `$UninstallArgsPre.Trim()) { `$argsPre = `$UninstallArgsPre.Trim() }
        `$codeUn = Invoke-UninstallCommand -File 'msiexec.exe' -Arguments (('/x {0} {1}' -f `$pc, `$argsPre).Trim())
        if(@(0,1605,1641,3010) -notcontains `$codeUn){
          Stop-WithError ("Pre-uninstall via ProductCode failed with exit code {0}" -f `$codeUn)
        }
      } else {
        `$entries = Get-UninstallEntries
        `$searchName = Normalize-SearchName `$AppNameRaw
        `$match = Select-BestMatch -name `$searchName -entries `$entries
        if(-not `$match){
          Write-Log ("Pre-uninstall: no uninstall entry found for name like '*{0}*'; skipping." -f `$AppNameRaw) 'INFO'
        } else {
          `$raw = (`$match.UninstallString -replace "`u0000","") -replace '[\u201C\u201D]', '"' -replace '[\u2018\u2019]', "'"
          `$parsed = Parse-UninstallString -Text `$raw
          if (-not `$parsed -or [string]::IsNullOrWhiteSpace(`$parsed.File)) {
            Write-Log "Pre-uninstall: could not parse uninstall string; skipping." 'WARN'
          } else {
            if(`$parsed.IsMsi -and `$parsed.ProductCode){
              `$codeUn = Invoke-UninstallCommand -File 'msiexec.exe' -Arguments ('/x {0}' -f `$parsed.ProductCode)
            } else {
              `$codeUn = Invoke-UninstallCommand -File `$parsed.File -Arguments `$parsed.Args
            }
            if(@(0,1605,1641,3010) -notcontains `$codeUn){
              Stop-WithError ("Pre-uninstall failed with exit code {0}" -f `$codeUn)
            }
          }
        }
      }
    } catch {
      Write-Log ("Pre-uninstall encountered an error: {0}" -f `$_.Exception.Message) 'ERROR'
      throw
    }
  }

  `$ext = [IO.Path]::GetExtension(`$full).ToLower()
  if ([string]::Equals(`$ext, '.msi', [System.StringComparison]::OrdinalIgnoreCase)) {
    `$file='msiexec.exe'
    `$procArgs = ('/i "{0}"' -f `$full)
    if(`$InstallArgs -and `$InstallArgs.Trim()){ `$procArgs = "`$procArgs `$InstallArgs" }
  } else {
    `$file=`$full
    if (`$InstallArgs -and `$InstallArgs.Trim()) {
      `$procArgs = `$InstallArgs.Trim()
    } else {
      `$procArgs = ""
    }
  }
  Write-Log ("Executing: {0} {1}" -f `$file, `$procArgs) 'INFO'
  `$proc = Start-Process -FilePath `$file -ArgumentList `$procArgs -PassThru -Wait -WindowStyle Hidden
  `$code = if(`$proc){ `$proc.ExitCode } else { `$LASTEXITCODE }
if(`$null -eq `$code){ `$code = 0 }
  Write-Log ("Installer exit code: {0}" -f `$code) 'INFO'
  Write-Log "===== END Install ====="
  exit `$code
} catch {
  Write-Log ("install.ps1 error: {0}" -f `$_.Exception.Message) 'ERROR'
  exit 1
}
"@

        $installScriptPath = Join-Path $scriptsDir 'install.ps1'
        Set-Content -LiteralPath $installScriptPath -Value $content -Encoding UTF8
        # Copy to Download so packaging includes installer + install.ps1 together
        try {
            Copy-Item -LiteralPath $installScriptPath -Destination (Join-Path $DownloadDir 'install.ps1') -Force
        } catch {
            Write-Log ("Failed to copy install.ps1 to Download: {0}" -f $_.Exception.Message) 'WARN'
        }
        Write-Log ("install.ps1 generated at: {0} and copied into Download." -f $installScriptPath) 'INFO'
    } catch {
        Write-Log ("Generate-InstallScript error: {0}" -f $_.Exception.Message) 'ERROR'
        throw
    }
}
# ========== Dynamic Uninstall Script Generation ==========
function Generate-UninstallScript {
    param(
        [Parameter(Mandatory=$true)][string]$VersionRoot,
        [Parameter(Mandatory=$true)][string]$DownloadDir,
        [Parameter(Mandatory=$true)][string]$InstallerName,
        [Parameter()][string]$UninstallArgs,
        [Parameter()][object]$ForceTaskCloseSpec,
        [Parameter()][string]$ProductCode,
        [Parameter()][string]$AppNameForLogs,
        [Parameter()][string]$AppVersionForLogs
    )
    try {
        $scriptsDir = Ensure-Dir (Join-Path $VersionRoot 'Scripts')

        # Normalize ForceTaskClose into clean .exe list
        $forceList = @()
        if ($ForceTaskCloseSpec) {
            if ($ForceTaskCloseSpec -is [System.Collections.IEnumerable] -and -not ($ForceTaskCloseSpec -is [string])) {
                foreach ($x in $ForceTaskCloseSpec) { if ($null -ne $x) { $forceList += $x.ToString() } }
            } else {
                $s = $ForceTaskCloseSpec.ToString()
                $parts = $s -split "(`r`n|`n|,|;)"
                foreach ($p in $parts) { if ($null -ne $p) { $forceList += $p } }
            }
            $forceList = $forceList | ForEach-Object { $_.ToString().Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
            $forceList = $forceList | ForEach-Object {
                $leaf = [IO.Path]::GetFileName($_)
                if ($leaf -match '\.exe$') { $leaf } else { "$leaf.exe" }
            } | Select-Object -Unique
        }

        $installerNameSafe = [IO.Path]::GetFileName($InstallerName)
        $uninstallArgsSafe = ''
        if ($UninstallArgs) { $uninstallArgsSafe = $UninstallArgs }
        $productCodeSafe = if ($ProductCode) { $ProductCode } else { '' }

        $forceArrayLiteral = if ($forceList -and $forceList.Count -gt 0) {
            $q = $forceList | ForEach-Object { '"' + ($_ -replace '"','`"') + '"' }
            "@(" + ($q -join ",") + ")"
        } else { "@()" }

        $content = @"
# Generated by AutoPackager at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
param()
`$ErrorActionPreference = 'Stop'
`$VerbosePreference = 'Continue'
# Log file initialization for Intune IME Logs
`$AppNameRaw = "$($AppNameForLogs -replace '"','`"')"
`$AppVersionRaw = "$($AppVersionForLogs -replace '"','`"')"
function Sanitize-ForPath([string]`$s){
  if (-not `$s) { return 'UnknownApp' }
  `$invalid = [IO.Path]::GetInvalidFileNameChars() + [IO.Path]::GetInvalidPathChars()
  -join (`$s.ToCharArray() | ForEach-Object { if (`$invalid -contains `$_) { '_' } else { `$_ } })
}
`$AppName  = Sanitize-ForPath `$AppNameRaw
`$AppVer   = Sanitize-ForPath `$AppVersionRaw
`$LogRoot  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
`$AppLogDir = Join-Path `$LogRoot `$AppName
try { `$null = New-Item -ItemType Directory -Path `$AppLogDir -Force -ErrorAction Stop } catch { `$AppLogDir = Join-Path `$env:TEMP `$AppName; `$null = New-Item -ItemType Directory -Path `$AppLogDir -Force -ErrorAction SilentlyContinue }
`$Stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
`$LogPath = Join-Path `$AppLogDir ("Uninstall_{0}_{1}_{2}.log" -f `$AppName, `$AppVer, `$Stamp)
function Write-Log {
  param([string]`$Message,[ValidateSet('INFO','WARN','ERROR','DEBUG')][string]`$Level='INFO')
  `$ts=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); `$line="[`$ts][`$Level] `$Message"
  Write-Host `$line
  try { Add-Content -Path `$LogPath -Value `$line -Encoding UTF8 } catch {}
}
function Stop-WithError([string]`$m){ Write-Log `$m 'ERROR'; exit 1 }
function Close-Processes([string[]]`$ImageNames,[int]`$TimeoutSeconds=15){
  if(-not `$ImageNames -or `$ImageNames.Count -eq 0){ return }
  foreach(`$img in `$ImageNames){
    `$base=[IO.Path]::GetFileNameWithoutExtension(`$img); if([string]::IsNullOrWhiteSpace(`$base)){ continue }
    `$procs=Get-Process -Name `$base -ErrorAction SilentlyContinue
    if(-not `$procs){ continue }
    foreach(`$p in `$procs){
      `$procId=`$p.Id; `$didGrace=`$false
      try{
        if(`$p.MainWindowHandle -and `$p.MainWindowHandle -ne 0){
          try{ if(`$p.CloseMainWindow()){ `$didGrace=`$true; Write-Log ("Sent CloseMainWindow to PID {0} ({1})" -f `$procId, `$p.ProcessName) 'DEBUG' } } catch {}
        }
      } catch {}
      `$deadline=(Get-Date).AddSeconds(15)
      while((Get-Date) -lt `$deadline){
        if(-not (Get-Process -Id `$procId -ErrorAction SilentlyContinue)){ break }
        Start-Sleep -Milliseconds 400
      }
      if(Get-Process -Id `$procId -ErrorAction SilentlyContinue){
        try{ Stop-Process -Id `$procId -Force -ErrorAction Stop; Write-Log ("Force-terminated PID {0}" -f `$procId) 'WARN' }
        catch{
          try{
            `$tkArgs="/PID `$procId /F /T"; Write-Log ("Fallback: taskkill {0}" -f `$tkArgs) 'WARN'
`$null = Start-Process -FilePath taskkill.exe -ArgumentList `$tkArgs -WindowStyle Hidden -Wait -PassThru
          } catch { Write-Log ("taskkill failed for PID {0}: {1}" -f `$procId, `$_.Exception.Message) 'ERROR' }
        }
      }
    }
  }
}
function Get-MsiProductCodeFromFile([string]`$MsiPath){
  try {
    if (-not (Test-Path -LiteralPath `$MsiPath)) { return `$null }
    try { `$installer = New-Object -ComObject WindowsInstaller.Installer } catch { return `$null }
    `$db = `$installer.GetType().InvokeMember('OpenDatabase','InvokeMethod',`$null,`$installer,@(`$MsiPath,0))
    `$view = `$db.OpenView("SELECT ``Value`` FROM ``Property`` WHERE ``Property``='ProductCode'")
    `$view.Execute(`$null)
    `$rec = `$view.Fetch()
    if (`$rec) {
      `$code = `$rec.StringData(1)
      if (`$code -and `$code.Trim()) { return `$code.Trim() }
    }
  } catch { }
  return `$null
}
`$ForceTaskClose = $forceArrayLiteral
`$InstallerName = "$installerNameSafe"
`$UninstallArgs = "$($uninstallArgsSafe -replace '"','`"')"
`$KnownProductCode = "$productCodeSafe"

Write-Log "===== BEGIN Uninstall for '`$AppNameRaw' version '`$AppVersionRaw' ====="
try{
  if(`$ForceTaskClose -and `$ForceTaskClose.Count -gt 0){ Write-Log ("ForceTaskClose targets: {0}" -f (`$ForceTaskClose -join ', ')) 'INFO'; Close-Processes -ImageNames `$ForceTaskClose -TimeoutSeconds 15 }

  # Resolve path relative to this script's directory
  `$scriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
  `$installerFull = Join-Path `$scriptDir `$InstallerName
  `$ext = [IO.Path]::GetExtension(`$installerFull).ToLower()
  Write-Log ("Context: ext='{0}', KnownProductCode='{1}'" -f `$ext, `$KnownProductCode) 'DEBUG'

  function Normalize-ProductCode([string]`$pc){
    if(-not `$pc){ return `$null }
    `$pc = (`$pc | Out-String).Trim()
    if(`$pc -match '^[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}$'){ return "{`$pc}" }
    if(`$pc -match '^\{[0-9A-Fa-f-]+\}$'){ return `$pc }
    return `$pc
  }

  function Get-UninstallEntries {
    `$paths = @(
      'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    `$list = @()
    foreach(`$p in `$paths){
      foreach(`$k in (Get-ChildItem `$p -EA SilentlyContinue)){
        try{
          `$props = Get-ItemProperty `$k.PSPath -EA SilentlyContinue
          if(-not `$props){ continue }
          # Omit system components
          `$sc = `$null; try { `$sc = [int]`$props.SystemComponent } catch {}
          if (`$sc -eq 1) { Write-Log ("Skipping uninstall key due to SystemComponent=1: {0}" -f `$k.PSPath) 'DEBUG'; continue }
          `$dn = [string]`$props.DisplayName
          `$uv = [string]`$props.DisplayVersion
          `$us = [string]`$props.UninstallString
          if([string]::IsNullOrWhiteSpace(`$dn) -or [string]::IsNullOrWhiteSpace(`$us)){ continue }
          `$list += [pscustomobject]@{
            DisplayName = `$dn
            DisplayVersion = `$uv
            UninstallString = `$us
            KeyPath = `$k.PSPath
          }
        } catch {}
      }
    }
    return `$list
  }

  function TryParse-Version([string]`$s){
    try { return [version]`$s } catch {
      if (-not `$s){ return `$null }
      `$parts = (`$s -split '[^0-9]+' | Where-Object { `$_ -match '^\d+$' })
      if (`$parts.Count -eq 0){ return `$null }
      `$nums = `$parts | ForEach-Object { [int]`$_ }
      while(`$nums.Count -lt 4){ `$nums += 0 }
      try { return [version]("{0}.{1}.{2}.{3}" -f `$nums[0],`$nums[1],`$nums[2],`$nums[3]) } catch { return `$null }
    }
  }

  function Select-BestMatch([string]`$name,`$entries){
    if(-not `$entries){ return `$null }
    `$cand = `$entries | Where-Object { `$_ -and `$_.DisplayName -and (`$_.DisplayName -like "*`$name*") -and `$_.UninstallString }
    if(-not `$cand -or `$cand.Count -eq 0){ return `$null }
    `$cand = `$cand | Sort-Object @{Expression={ TryParse-Version `$_.DisplayVersion }; Descending=`$true}
    return `$cand | Select-Object -First 1
  }

  function Parse-UninstallString([string]`$Text){
    if([string]::IsNullOrWhiteSpace(`$Text)){ return `$null }
    # Normalize: strip NULs and normalize smart quotes
    `$in = (`$Text -replace "`u0000","")
    `$in = `$in -replace '[\u201C\u201D]', '"'
    `$in = `$in -replace '[\u2018\u2019]', "'"
    `$in = `$in.Trim()

    `$file = `$null; `$args = ""; `$isMsi = `$false; `$pc = `$null

    # 1) Quoted path with optional args
    if(`$in -match '^\s*"([^"]+)"\s*(.*)$'){
      `$file = `$matches[1]; `$args = `$matches[2]
    } elseif(`$in -match '^(.*?\.(?:exe|msi))(?:\s+(.*))?$'){
      # 2) Unquoted path ending with .exe/.msi, capture remainder as args
      `$file = `$matches[1]
      if (`$matches.Count -ge 3) { `$args = `$matches[2] } else { `$args = "" }
    } else {
      # 3) Fallback: treat entire string as file, trim quotes
      `$file = `$in.Trim('"')
      `$args = ""
    }

    if([string]::IsNullOrWhiteSpace(`$file)){ return `$null }

    `$isMsi = (`$file -match '(?i)\\?msiexec(\.exe)?$') -or (`$file -match '^(?i)msiexec(\.exe)?$')
    if(`$isMsi){
      if(`$args -match '(?i)\{[0-9A-Fa-f\-]{36}\}'){
        `$pc = Normalize-ProductCode `$matches[0]
      } elseif(`$in -match '(?i)\{[0-9A-Fa-f\-]{36}\}'){
        `$pc = Normalize-ProductCode `$matches[0]
      }
    }
    return [pscustomobject]@{ File=`$file; Args=`$args; IsMsi=`$isMsi; ProductCode=`$pc }
  }

  function Invoke-UninstallCommand([string]`$File,[string]`$Arguments){
    if((![string]::Equals(`$File,'msiexec.exe',[System.StringComparison]::OrdinalIgnoreCase)) -and (-not (Test-Path -LiteralPath `$File))){
      Stop-WithError ("Uninstall executable not found: {0}" -f `$File)
    }
    # Always append recipe UninstallArgs if provided (idempotent)
    try {
      `$ua = `$UninstallArgs
      if (`$ua) { `$ua = `$ua.Trim() }
      if (`$ua -and `$ua.Length -gt 0) {
        if ([string]::IsNullOrWhiteSpace(`$Arguments)) {
          `$Arguments = `$ua
        } elseif (-not (`$Arguments -match [regex]::Escape(`$ua))) {
          `$Arguments = ("{0} {1}" -f `$Arguments, `$ua)
        }
      }
    } catch { }
    Write-Log ("[POST-APPEND] Args='{0}'" -f `$Arguments) 'DEBUG'
    Write-Log ("Executing: {0} {1}" -f `$File, `$Arguments) 'INFO'
    if ([string]::IsNullOrWhiteSpace(`$Arguments)) {
      `$proc = Start-Process -FilePath `$File -PassThru -Wait -WindowStyle Hidden
    } else {
      `$proc = Start-Process -FilePath `$File -ArgumentList `$Arguments -PassThru -Wait -WindowStyle Hidden
    }
    `$code = if(`$proc){ `$proc.ExitCode } else { `$LASTEXITCODE }
    if(`$null -eq `$code){ `$code = 0 }
    Write-Log ("Uninstaller exit code: {0}" -f `$code) 'INFO'
    return `$code
  }

  # Priority 1: Known ProductCode
  `$kc = Normalize-ProductCode `$KnownProductCode
  if(`$kc){
    `$file='msiexec.exe'
    `$procArgs = ('/x {0}' -f `$kc)
    if(`$UninstallArgs -and `$UninstallArgs.Trim()){ `$procArgs = "`$procArgs `$UninstallArgs" }
    Write-Log ("[PRIO1] KnownProductCode -> {0}" -f `$kc) 'INFO'
    Write-Log ("[PRE-INVOKE] File='{0}' Args='{1}'" -f `$file, `$procArgs) 'DEBUG'
    `$exit = Invoke-UninstallCommand -File `$file -Arguments `$procArgs
    Write-Log "===== END Uninstall ====="
    exit `$exit
  }

  # Priority 2: MSI file product code
  if ([string]::Equals(`$ext, '.msi', [System.StringComparison]::OrdinalIgnoreCase)) {
    `$pc = Get-MsiProductCodeFromFile -MsiPath `$installerFull
    if(-not `$pc){ Stop-WithError ("MSI uninstall requested but ProductCode not available and could not be derived from '{0}'." -f `$installerFull) }
    `$pc = Normalize-ProductCode `$pc
    `$file='msiexec.exe'
    `$procArgs = ('/x {0}' -f `$pc)
    if(`$UninstallArgs -and `$UninstallArgs.Trim()){ `$procArgs = "`$procArgs `$UninstallArgs" }
    Write-Log ("[PRIO2] MSI file ProductCode -> {0}" -f `$pc) 'INFO'
    Write-Log ("[PRE-INVOKE] File='{0}' Args='{1}'" -f `$file, `$procArgs) 'DEBUG'
    `$exit = Invoke-UninstallCommand -File `$file -Arguments `$procArgs
    Write-Log "===== END Uninstall ====="
    exit `$exit
  }

  # Priority 3: Registry search by DisplayName pattern
  `$entries = Get-UninstallEntries
  `$match = Select-BestMatch -name `$AppNameRaw -entries `$entries
  if(-not `$match){
    Stop-WithError ("No uninstall entry found matching DisplayName like '{0}' in HKLM uninstall hives." -f `$AppNameRaw)
  }
  `$raw = `$match.UninstallString
  if([string]::IsNullOrWhiteSpace(`$raw)){
    Stop-WithError ("Uninstall entry selected but uninstall string is empty (key: {0})." -f `$match.KeyPath)
  }
  Write-Log ("Selected uninstall entry: Name='{0}', Version='{1}', Key='{2}'" -f `$match.DisplayName, `$match.DisplayVersion, `$match.KeyPath) 'INFO'
  Write-Log ("UninstallString raw: {0}" -f `$raw) 'DEBUG'

  # MSI via GUID from registry key (when UninstallString lacks ProductCode)
  try { `$leafGuid = Split-Path -Leaf `$match.KeyPath } catch { `$leafGuid = `$null }
  if (`$leafGuid -and (`$leafGuid -match '^\{[0-9A-Fa-f\-]{36}\}$')) {
    `$pc = Normalize-ProductCode `$leafGuid
    if (`$pc) {
      `$file = 'msiexec.exe'
      `$procArgs = ('/x {0}' -f `$pc)
      if(`$UninstallArgs -and `$UninstallArgs.Trim()){ `$procArgs = "`$procArgs `$UninstallArgs" }
      Write-Log ("[PRIO3-MSI-GUID] Key leaf='{0}' -> ProductCode={1}" -f `$leafGuid, `$pc) 'INFO'
      Write-Log ("[PRE-INVOKE] File='{0}' Args='{1}'" -f `$file, `$procArgs) 'DEBUG'
      `$exit = Invoke-UninstallCommand -File `$file -Arguments `$procArgs
      Write-Log "===== END Uninstall ====="
      exit `$exit
    }
  }

  # Fast-path: UninstallString is only an EXE path with no arguments
  `$norm = (`$raw -replace "`u0000","")
  `$norm = `$norm -replace '[\u201C\u201D]', '"'
  `$norm = `$norm -replace '[\u2018\u2019]', "'"
  `$norm = `$norm.Trim()

  `$file = `$null
  `$procArgs = ""
  if (`$norm -match '^\s*"([^"]+\.exe)"\s*$') {
    `$file = `$matches[1]
  } elseif (`$norm -match '^\s*([^\s]+\.exe)\s*$') {
    `$file = `$matches[1]
  }

  if (`$file) {
    if(`$UninstallArgs -and `$UninstallArgs.Trim()){ `$procArgs = `$UninstallArgs.Trim() }
    try { `$leafCheck = [IO.Path]::GetFileName(`$file) } catch { `$leafCheck = `$null }
    Write-Log ("[PRIO3-EXE-FAST] File='{0}' Args='{1}'" -f `$file, `$procArgs) 'INFO'
    Write-Log ("[PRE-INVOKE] File='{0}' Args='{1}'" -f `$file, `$procArgs) 'DEBUG'
    `$exit = Invoke-UninstallCommand -File `$file -Arguments `$procArgs
    Write-Log "===== END Uninstall ====="
    exit `$exit
  }

  # Fallback to parser path
  `$parsed = Parse-UninstallString -Text `$raw
  if (-not `$parsed -or [string]::IsNullOrWhiteSpace(`$parsed.File)) {
    Stop-WithError ("Could not parse an executable from uninstall string. Raw='{0}'" -f `$raw)
  }
  Write-Log ("Parsed uninstall: File='{0}', Args='{1}', IsMsi={2}, ProductCode='{3}'" -f `$parsed.File, `$parsed.Args, `$parsed.IsMsi, `$parsed.ProductCode) 'DEBUG'
  if(`$parsed -and `$parsed.IsMsi -and `$parsed.ProductCode){
    `$file='msiexec.exe'
    `$procArgs = ('/x {0}' -f `$parsed.ProductCode)
    if(`$UninstallArgs -and `$UninstallArgs.Trim()){ `$procArgs = "`$procArgs `$UninstallArgs" }
  } elseif (`$parsed -and `$parsed.IsMsi) {
    # Parsed MSI but no ProductCode; try GUID from registry key leaf
    try { `$leafGuid = Split-Path -Leaf `$match.KeyPath } catch { `$leafGuid = `$null }
    if (`$leafGuid -and (`$leafGuid -match '^\{[0-9A-Fa-f\-]{36}\}$')) {
      `$pc = Normalize-ProductCode `$leafGuid
      `$file='msiexec.exe'
      `$procArgs = ('/x {0}' -f `$pc)
      Write-Log ("[PARSE-MSI-NO-PC] Using GUID leaf='{0}' -> ProductCode={1}" -f `$leafGuid, `$pc) 'INFO'
      if(`$UninstallArgs -and `$UninstallArgs.Trim()){ `$procArgs = "`$procArgs `$UninstallArgs" }
    } else {
      # Fall back to parsed file/args (may not uninstall if ProductCode is missing)
      `$file = `$parsed.File
      if (-not `$file -or [string]::IsNullOrWhiteSpace(`$file)) {
        Stop-WithError ("Parsed uninstall file is null/empty. Raw='{0}'" -f `$raw)
      }
      `$procArgs = `$parsed.Args
      if(`$UninstallArgs -and `$UninstallArgs.Trim()){ `$procArgs = "`$procArgs `$UninstallArgs" }
    }
  } else {
    `$file = `$parsed.File
    if (-not `$file -or [string]::IsNullOrWhiteSpace(`$file)) {
      Stop-WithError ("Parsed uninstall file is null/empty. Raw='{0}'" -f `$raw)
    }
    `$procArgs = `$parsed.Args
    if(`$UninstallArgs -and `$UninstallArgs.Trim()){ `$procArgs = "`$procArgs `$UninstallArgs" }
  }

  Write-Log ("[PRE-INVOKE] File='{0}' Args='{1}'" -f `$file, `$procArgs) 'DEBUG'
  `$exit = Invoke-UninstallCommand -File `$file -Arguments `$procArgs
  Write-Log "===== END Uninstall ====="
  exit `$exit
} catch {
  Write-Log ("uninstall.ps1 error: {0}" -f `$_.Exception.Message) 'ERROR'
  exit 1
}
"@

        $uninstallScriptPath = Join-Path $scriptsDir 'uninstall.ps1'
        Set-Content -LiteralPath $uninstallScriptPath -Value $content -Encoding UTF8
        # Copy to Download so packaging includes uninstall.ps1 next to installer
        try {
            Copy-Item -LiteralPath $uninstallScriptPath -Destination (Join-Path $DownloadDir 'uninstall.ps1') -Force
        } catch {
            Write-Log ("Failed to copy uninstall.ps1 to Download: {0}" -f $_.Exception.Message) 'WARN'
        }
        Write-Log ("uninstall.ps1 generated at: {0} and copied into Download." -f $uninstallScriptPath) 'INFO'
    } catch {
        Write-Log ("Generate-UninstallScript error: {0}" -f $_.Exception.Message) 'ERROR'
        throw
    }
}
# ========== Version Comparison ==========
function Compare-VersionStrings {
    param([string]$A,[string]$B)
    try {
        $va = [version]$A
        $vb = [version]$B
        if ($va -gt $vb) { return 1 }
        if ($va -lt $vb) { return -1 }
        return 0
    } catch {
        # Numeric-segment fallback
        $as = $A -split '[^0-9]+' | Where-Object { $_ -ne '' }
        $bs = $B -split '[^0-9]+' | Where-Object { $_ -ne '' }
        for ($i=0; $i -lt [Math]::Max($as.Count,$bs.Count); $i++){
            $ai = 0; if ($i -lt $as.Count -and $as[$i] -match '^\d+$') { $ai = [int]$as[$i] }
            $bi = 0; if ($i -lt $bs.Count -and $bs[$i] -match '^\d+$') { $bi = [int]$bs[$i] }
            if ($ai -gt $bi) { return 1 }
            if ($ai -lt $bi) { return -1 }
        }
        return 0
    }
}

# ===== Startup cleanup (purge output .intunewin and Working subfolders) =====
try {
    # Purge .intunewin artifacts in output/
    # Output folder moved under Working; no separate script-level output cleanup needed.

    # Purge all subfolders under Working/ (leave root so CSV/log archives can be written)
    $purge = $true
    try {
        if ($script:Config -and $script:Config.Cleanup -and ($null -ne $script:Config.Cleanup.PurgeWorkingOnStart)) {
            $purge = [bool]$script:Config.Cleanup.PurgeWorkingOnStart
        }
    } catch {}
    if ($purge) {
        if ($WorkingRoot) {
            $wrk = Ensure-Dir $WorkingRoot
            Get-ChildItem -LiteralPath $wrk -Directory -Force -ErrorAction SilentlyContinue |
                ForEach-Object {
                    try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop } catch {
                        Write-Log ("Cleanup (working) could not remove folder '{0}': {1}" -f $_.FullName, $_.Exception.Message) 'WARN'
                    }
                }
        }
    } else {
        Write-Log "Startup purge skipped by config." 'INFO'
    }
} catch {
    Write-Log ("Startup cleanup failed: {0}" -f $_.Exception.Message) 'WARN'
}

# ===== Testing cleanup (mirror Working purge policy) =====
try {
    # Default to same policy as Working purge; allow override via Cleanup.PurgeTestingOnStart
    $purgeTesting = $purge
    try {
        if ($script:Config -and $script:Config.Cleanup -and ($null -ne $script:Config.Cleanup.PurgeTestingOnStart)) {
            $purgeTesting = [bool]$script:Config.Cleanup.PurgeTestingOnStart
        }
    } catch {}
    if ($purgeTesting) {
        # Resolve Testing root from config or default under script root
        $testingRoot = $null
        try {
            if ($script:Config -and $script:Config.Paths -and $script:Config.Paths.TestingRoot) {
                $testingRoot = [string]$script:Config.Paths.TestingRoot
            }
        } catch {}
        if ($testingRoot -and $testingRoot.Trim()) {
            if (-not [System.IO.Path]::IsPathRooted($testingRoot)) {
                $testingRoot = Join-Path $script:ScriptRootEffective $testingRoot
            }
        } else {
            $testingRoot = Join-Path $script:ScriptRootEffective 'Testing'
        }

        if (Test-Path -LiteralPath $testingRoot) {
            Get-ChildItem -LiteralPath $testingRoot -Directory -Force -ErrorAction SilentlyContinue |
                ForEach-Object {
                    try {
                        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                    } catch {
                        Write-Log ("Cleanup (testing) could not remove folder '{0}': {1}" -f $_.FullName, $_.Exception.Message) 'WARN'
                    }
                }
        } else {
            Write-Log ("Testing folder not found; skipping Testing cleanup. Path='{0}'" -f $testingRoot) 'DEBUG'
        }
    } else {
        Write-Log "Testing purge skipped by config." 'INFO'
    }
} catch {
    Write-Log ("Testing cleanup failed: {0}" -f $_.Exception.Message) 'WARN'
}

# ========== Secondary Ring Assignments Helpers ==========
# Cache for resolved group IDs to avoid repeated Graph calls
$script:GroupIdCache = @{}
# Cache for resolved assignment filter IDs
$script:AssignmentFilterCache = @{}

function Parse-RingsFromRecipe {
    param([Parameter(Mandatory=$true)][object]$RecipeJson)
    $rings = @()
    try {
        $ringsObj = $RecipeJson.Rings
        if (-not $ringsObj) {
            Write-Log "Rings schema not present in recipe; no assignment changes will be made for secondary." 'INFO'
            return @()
        }
        foreach ($rk in @('Ring1','Ring2','Ring3')) {
            if (-not ($ringsObj.PSObject.Properties.Name -contains $rk)) { continue }
            $r = $ringsObj.$rk
            if (-not $r) { continue }
            $groupName = $null
            $delayDays = $null
            try { $groupName = [string]$r.Group } catch {}
            try { $delayDays = [int]$r.DeadlineDelayDays } catch {}
            if ([string]::IsNullOrWhiteSpace($groupName)) {
                Write-Log ("Rings.{0} missing Group; skipping this ring." -f $rk) 'WARN'
                continue
            }
            if ($delayDays -lt 0 -or $null -eq $delayDays) {
                # Fallback to config defaults when recipe omits/invalids the delay days
                $fallback = $null
                try {
                    if ($script:Config -and $script:Config.RequiredUpdateDefaultGroups) {
                        switch ($rk) {
                            'Ring1' { $fallback = $script:Config.RequiredUpdateDefaultGroups.PilotDelayDays }
                            'Ring2' { $fallback = $script:Config.RequiredUpdateDefaultGroups.UATDelayDays }
                            'Ring3' { $fallback = $script:Config.RequiredUpdateDefaultGroups.GADelayDays }
                        }
                    }
                } catch {}
                if ($fallback -ne $null) {
                    try {
                        $delayDays = [int]$fallback
                        if ($delayDays -lt 0) { $delayDays = 0 }
                        if ($delayDays -gt 365) { $delayDays = 365 }
                        Write-Log ("Rings.{0} DelayDays missing/invalid in recipe; using config default={1}" -f $rk, $delayDays) 'INFO'
                    } catch {
                        Write-Log ("Rings.{0} invalid DeadlineDelayDays and config default unusable; skipping this ring." -f $rk) 'WARN'
                        continue
                    }
                } else {
                    Write-Log ("Rings.{0} invalid DeadlineDelayDays='{1}' and no config default; skipping this ring." -f $rk, $r.DeadlineDelayDays) 'WARN'
                    continue
                }
            }
            $ringNum = [int]($rk -replace '[^\d]','')
            $rings += [PSCustomObject]@{
                Ring       = $ringNum
                GroupName  = $groupName
                DelayDays  = $delayDays
                FilterId   = $(if ($r.PSObject.Properties.Name -contains 'FilterId' -and $r.FilterId) { [string]$r.FilterId } else { $null })
                FilterName = $(if ($r.PSObject.Properties.Name -contains 'FilterName' -and $r.FilterName) { [string]$r.FilterName } else { $null })
                FilterType = $( if ($r.PSObject.Properties.Name -contains 'FilterType' -and $r.FilterType -and ([string]$r.FilterType).Trim().ToLower() -eq 'exclude') { 'exclude' } else { 'include' } )
            }
        }
        if ($rings.Count -gt 0) {
            $desc = ($rings | ForEach-Object { "Ring$($_.Ring)='$($_.GroupName)' Delay=$($_.DelayDays)d" }) -join '; '
            Write-Log ("Parsed Rings from recipe: {0}" -f $desc) 'INFO'
        } else {
            Write-Log "Rings schema present but no valid rings after validation; skipping assignment changes." 'WARN'
        }
    } catch {
        Write-Log ("Parse-RingsFromRecipe failed: {0}" -f $_.Exception.Message) 'WARN'
    }
    return $rings
}

function Resolve-GroupIdByName {
    param([Parameter(Mandatory=$true)][string]$DisplayName)
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { return $null }
    $key = $DisplayName.ToLowerInvariant()
    if ($script:GroupIdCache.ContainsKey($key)) { return $script:GroupIdCache[$key] }

    $filterName = $DisplayName.Replace("'","''")
    Write-Log ("Resolving Entra group by name: '{0}'" -f $DisplayName) 'INFO'
    try {
        $resp = Invoke-GraphJson -Method 'GET' -Path '/groups' -Query @{ '$filter' = "displayName eq '$filterName'"; '$select' = 'id,displayName'; '$top'='5' }
        $vals = @(); try { $vals = @($resp.value) } catch {}
        if (-not $vals -or $vals.Count -eq 0) {
            Write-Log ("Group not found: '{0}'" -f $DisplayName) 'WARN'
            $script:GroupIdCache[$key] = $null
            return $null
        }
        $chosen = $vals | Where-Object { $_.displayName -and ($_.displayName.ToString().Trim().ToLower() -eq $DisplayName.Trim().ToLower()) } | Select-Object -First 1
        if (-not $chosen) { $chosen = $vals[0] }
        if ($vals.Count -gt 1) {
            try {
                $cand = ($vals | ForEach-Object { ("{0}({1})" -f $_.displayName, $_.id) }) -join '; '
                Write-Log ("Multiple groups matched name '{0}'; choosing '{1}' ({2}). Candidates: {3}" -f $DisplayName, $chosen.displayName, $chosen.id, $cand) 'WARN'
            } catch {
                Write-Log ("Multiple groups matched name '{0}'; choosing first result ({1})." -f $DisplayName, $chosen.id) 'WARN'
            }
        } else {
            Write-Log ("Resolved '{0}' -> {1}" -f $DisplayName, $chosen.id) 'INFO'
        }
        $gid = [string]$chosen.id
        $script:GroupIdCache[$key] = $gid
        return $gid
    } catch {
        Write-Log ("Resolve-GroupIdByName Graph error for '{0}': {1}" -f $DisplayName, $_.Exception.Message) 'ERROR'
        $script:GroupIdCache[$key] = $null
        return $null
    }
}

# Resolve assignment filter id from displayName with simple caching
function Resolve-AssignmentFilterIdByName {
    param([Parameter(Mandatory=$true)][string]$DisplayName)
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { return $null }
    $key = $DisplayName.ToLowerInvariant()
    if ($script:AssignmentFilterCache.ContainsKey($key)) { return $script:AssignmentFilterCache[$key] }
    $filterName = $DisplayName.Replace("'","''")
    Write-Log ("Resolving assignment filter by name: '{0}'" -f $DisplayName) 'INFO'
    try {
        $vals = @()
        # Enumerate v1.0 without $filter (service may not support filtering on displayName)
        try {
            $nextUrl = "/deviceManagement/assignmentFilters?`$select=id,displayName&`$top=50"
            do {
                $resp = Invoke-GraphJson -Method 'GET' -Path $nextUrl
                $page = @(); try { $page = @($resp.value) } catch {}
                if ($page -and $page.Count -gt 0) { $vals += $page }
                $nextUrl = $null
                try { if ($resp.'@odata.nextLink') { $nextUrl = [string]$resp.'@odata.nextLink' } } catch {}
            } while ($nextUrl)
        } catch {
            Write-Log ("assignmentFilters v1.0 enumerate failed; retrying beta for '{0}'" -f $DisplayName) 'WARN'
        }
        # Fallback to beta enumerate if no results
        if (-not $vals -or $vals.Count -eq 0) {
            try {
                $nextUrl = "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters?`$select=id,displayName&`$top=50"
                do {
                    $resp = Invoke-GraphJson -Method 'GET' -Path $nextUrl
                    $page = @(); try { $page = @($resp.value) } catch {}
                    if ($page -and $page.Count -gt 0) { $vals += $page }
                    $nextUrl = $null
                    try { if ($resp.'@odata.nextLink') { $nextUrl = [string]$resp.'@odata.nextLink' } } catch {}
                } while ($nextUrl)
            } catch {
                Write-Log ("assignmentFilters beta enumerate failed for '{0}': {1}" -f $DisplayName, $_.Exception.Message) 'ERROR'
            }
        }
        if (-not $vals -or $vals.Count -eq 0) {
            Write-Log ("Assignment filter not found: '{0}'" -f $DisplayName) 'WARN'
            $script:AssignmentFilterCache[$key] = $null
            return $null
        }
        $chosen = $vals | Where-Object { $_.displayName -and ($_.displayName.ToString().Trim().ToLower() -eq $DisplayName.Trim().ToLower()) } | Select-Object -First 1
        if (-not $chosen) { $chosen = $vals[0] }
        if ($vals.Count -gt 1) {
            try {
                $cand = ($vals | ForEach-Object { ("{0}({1})" -f $_.displayName, $_.id) }) -join '; '
                Write-Log ("Multiple assignment filters enumerated; choosing '{0}' ({1}). Candidates: {2}" -f $chosen.displayName, $chosen.id, $cand) 'WARN'
            } catch {
                Write-Log ("Multiple assignment filters enumerated; choosing first result ({0})." -f $chosen.id) 'WARN'
            }
        } else {
            Write-Log ("Resolved assignment filter '{0}' -> {1}" -f $DisplayName, $chosen.id) 'INFO'
        }
        $fid = [string]$chosen.id
        $script:AssignmentFilterCache[$key] = $fid
        return $fid
    } catch {
        Write-Log ("Resolve-AssignmentFilterIdByName Graph error for '{0}': {1}" -f $DisplayName, $_.Exception.Message) 'ERROR'
        $script:AssignmentFilterCache[$key] = $null
        return $null
    }
}

function Get-AppAssignmentsGraph {
    param([Parameter(Mandatory=$true)][string]$AppId)
    try {
        $res = Invoke-GraphJson -Method 'GET' -Path "/deviceAppManagement/mobileApps/$AppId/assignments"
        $vals = @(); try { $vals = @($res.value) } catch {}
        return $vals
    } catch {
        Write-Log ("Get-AppAssignmentsGraph failed for app {0}: {1}" -f $AppId, $_.Exception.Message) 'WARN'
        return @()
    }
}

function Clear-AppAssignmentsGraph {
    param([Parameter(Mandatory=$true)][string]$AppId)
    $existing = Get-AppAssignmentsGraph -AppId $AppId
    $count = if ($existing) { $existing.Count } else { 0 }
    Write-Log ("Secondary assignments: clearing existing assignments (found {0})..." -f $count) 'INFO'
    foreach ($a in $existing) {
        try {
            if ($a.id) {
                Invoke-GraphJson -Method 'DELETE' -Path "/deviceAppManagement/mobileApps/$AppId/assignments/$($a.id)" | Out-Null
            }
        } catch {
            Write-Log ("Delete assignment '{0}' failed: {1}" -f $a.id, $_.Exception.Message) 'WARN'
        }
    }
}

# Map well-known built-in names to Intune built-in assignment targets
function Get-BuiltInAssignmentTarget {
    param([Parameter(Mandatory=$true)][string]$GroupName)
    if ([string]::IsNullOrWhiteSpace($GroupName)) { return $null }
    try {
        $name = $GroupName.Trim().ToLower()
        # Normalize common separators/variants
        $name = ($name -replace '[-_]+',' ')
        $name = ($name -replace '\s{2,}',' ')
        switch ($name) {
            { $_ -match '^(all\s*device|all\s*devices)$' } {
                return @{ "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget" }
            }
            { $_ -match '^(all\s*user|all\s*users|all\s*licensed\s*user|all\s*licensed\s*users)$' } {
                return @{ "@odata.type" = "#microsoft.graph.allLicensedUsersAssignmentTarget" }
            }
            default { return $null }
        }
    } catch { return $null }
}

function Assign-AppToRingsGraph {
    param(
        [Parameter(Mandatory=$true)][string]$AppId,
        [Parameter(Mandatory=$true)][object[]]$Rings
    )
    $items = @()
    $made = 0
    foreach ($r in $Rings | Sort-Object Ring) {
        $name = $r.GroupName
        $target = $null
        $targetDesc = $null
        $builtIn = Get-BuiltInAssignmentTarget -GroupName $name
        if ($builtIn) {
            $target = $builtIn
            $targetDesc = if ($builtIn.'@odata.type' -eq '#microsoft.graph.allDevicesAssignmentTarget') { 'built-in: allDevices' } else { 'built-in: allLicensedUsers' }
        } else {
            $gid = Resolve-GroupIdByName -DisplayName $name
            if (-not $gid) {
                Write-Log ("Ring{0}: group '{1}' unresolved; skipping assignment for this ring." -f $r.Ring, $name) 'WARN'
                continue
            }
            $target = @{
                "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                groupId       = $gid
            }
            $targetDesc = "groupId=$gid"
        }
        # Apply optional assignment filter if specified
        try {
            $fid = $null
            if ($r.PSObject.Properties.Name -contains 'FilterId' -and $r.FilterId) { $fid = [string]$r.FilterId }
            elseif ($r.PSObject.Properties.Name -contains 'FilterName' -and $r.FilterName) { $fid = Resolve-AssignmentFilterIdByName -DisplayName ([string]$r.FilterName) }
            if ($fid -and $fid.Trim()) {
                $ftype = 'include'
                try {
                    if ($r.PSObject.Properties.Name -contains 'FilterType' -and $r.FilterType) {
                        $ft = [string]$r.FilterType
                        if ($ft -and $ft.Trim().ToLower() -eq 'exclude') { $ftype = 'exclude' }
                    }
                } catch {}
                $target['deviceAndAppManagementAssignmentFilterId'] = $fid
                $target['deviceAndAppManagementAssignmentFilterType'] = $ftype
                Write-Log ("Ring{0}: applying assignment filter {1} ({2})" -f $r.Ring, $fid, $ftype) 'INFO'
            }
        } catch {}
        $dlHour = 23; $dlMin = 59
        try {
            if ($script:Config -and $script:Config.SecondaryRequiredApp -and $script:Config.SecondaryRequiredApp.AssignmentDefaults -and $script:Config.SecondaryRequiredApp.AssignmentDefaults.Deadline) {
                if ($null -ne $script:Config.SecondaryRequiredApp.AssignmentDefaults.Deadline.HourOfDay) { $dlHour = [int]$script:Config.SecondaryRequiredApp.AssignmentDefaults.Deadline.HourOfDay }
                if ($null -ne $script:Config.SecondaryRequiredApp.AssignmentDefaults.Deadline.MinuteOfHour) { $dlMin = [int]$script:Config.SecondaryRequiredApp.AssignmentDefaults.Deadline.MinuteOfHour }
            } elseif ($script:Config -and $script:Config.Secondary -and $script:Config.Secondary.AssignmentDefaults -and $script:Config.Secondary.AssignmentDefaults.Deadline) {
                if ($null -ne $script:Config.Secondary.AssignmentDefaults.Deadline.HourOfDay) { $dlHour = [int]$script:Config.Secondary.AssignmentDefaults.Deadline.HourOfDay }
                if ($null -ne $script:Config.Secondary.AssignmentDefaults.Deadline.MinuteOfHour) { $dlMin = [int]$script:Config.Secondary.AssignmentDefaults.Deadline.MinuteOfHour }
            }
        } catch {}
        $deadline = (Get-Date).AddDays([int]$r.DelayDays).Date.AddHours($dlHour).AddMinutes($dlMin)
        Write-Log ("Ring{0} -> Target '{1}' ({2}); deadline local: {3}" -f $r.Ring, $name, $targetDesc, $deadline.ToString("yyyy-MM-dd HH:mm")) 'INFO'
        # Assignment policy from config with safe defaults
        $intentConf = "required"
        $notifConf = "showAll"
        $doPrioConf = "notConfigured"
        try {
            if ($script:Config -and $script:Config.SecondaryRequiredApp -and $script:Config.SecondaryRequiredApp.AssignmentDefaults) {
                if ($script:Config.SecondaryRequiredApp.AssignmentDefaults.Intent) { $intentConf = [string]$script:Config.SecondaryRequiredApp.AssignmentDefaults.Intent }
                if ($script:Config.SecondaryRequiredApp.AssignmentDefaults.Notifications) { $notifConf = [string]$script:Config.SecondaryRequiredApp.AssignmentDefaults.Notifications }
                if ($script:Config.SecondaryRequiredApp.AssignmentDefaults.DeliveryOptimizationPriority) { $doPrioConf = [string]$script:Config.SecondaryRequiredApp.AssignmentDefaults.DeliveryOptimizationPriority }
            } elseif ($script:Config -and $script:Config.Secondary -and $script:Config.Secondary.AssignmentDefaults) {
                if ($script:Config.Secondary.AssignmentDefaults.Intent) { $intentConf = [string]$script:Config.Secondary.AssignmentDefaults.Intent }
                if ($script:Config.Secondary.AssignmentDefaults.Notifications) { $notifConf = [string]$script:Config.Secondary.AssignmentDefaults.Notifications }
                if ($script:Config.Secondary.AssignmentDefaults.DeliveryOptimizationPriority) { $doPrioConf = [string]$script:Config.Secondary.AssignmentDefaults.DeliveryOptimizationPriority }
            }
        } catch {}
        $item = @{
            "@odata.type" = "#microsoft.graph.mobileAppAssignment"
            intent        = $intentConf
            target        = $target
            settings      = @{
                "@odata.type"                    = "#microsoft.graph.win32LobAppAssignmentSettings"
                notifications                    = $notifConf
                deliveryOptimizationPriority     = $doPrioConf
                installTimeSettings              = @{
                    "@odata.type"    = "#microsoft.graph.mobileAppInstallTimeSettings"
                    useLocalTime     = $true
                    startDateTime    = $null
                    deadlineDateTime = $deadline.ToString("o")
                }
            }
        }
        $items += $item
        $made++
    }
    if ($items.Count -eq 0) {
        Write-Log "No valid ring assignments to create; nothing posted." 'WARN'
        return 0
    }
    try {
        Invoke-GraphJson -Method 'POST' -Path "/deviceAppManagement/mobileApps/$AppId/assign" -Body @{ mobileAppAssignments = $items } | Out-Null
        Write-Log ("Posted {0} assignment(s) to secondary app {1}" -f $items.Count, $AppId) 'INFO'
        return $items.Count
    } catch {
        Write-Log ("POST assign failed for app {0}: {1}" -f $AppId, $_.Exception.Message) 'ERROR'
        return 0
    }
}
# Helper: build human-readable ring summary with local deadlines
function Build-RingSummary {
    param([Parameter(Mandatory=$true)][object[]]$Rings)
    if (-not $Rings -or $Rings.Count -eq 0) { return "" }
    $parts = @()
    foreach ($r in ($Rings | Sort-Object Ring)) {
        try {
            $name = if ($r.GroupName) { $r.GroupName } else { "Ring$($r.Ring)" }
            $dlHour = 23; $dlMin = 59
            try {
                if ($script:Config -and $script:Config.Secondary -and $script:Config.Secondary.AssignmentDefaults -and $script:Config.Secondary.AssignmentDefaults.Deadline) {
                    if ($null -ne $script:Config.Secondary.AssignmentDefaults.Deadline.HourOfDay) { $dlHour = [int]$script:Config.Secondary.AssignmentDefaults.Deadline.HourOfDay }
                    if ($null -ne $script:Config.Secondary.AssignmentDefaults.Deadline.MinuteOfHour) { $dlMin = [int]$script:Config.Secondary.AssignmentDefaults.Deadline.MinuteOfHour }
                }
            } catch {}
            $dl = (Get-Date).AddDays([int]$r.DelayDays).Date.AddHours($dlHour).AddMinutes($dlMin)
            $filText = ''
            try {
                $ftype = 'include'
                if ($r.PSObject.Properties.Name -contains 'FilterType' -and $r.FilterType -and ([string]$r.FilterType).Trim().ToLower() -eq 'exclude') { $ftype = 'exclude' }
                $fname = $null
                if ($r.PSObject.Properties.Name -contains 'FilterName' -and $r.FilterName) { $fname = [string]$r.FilterName }
                elseif ($r.PSObject.Properties.Name -contains 'FilterId' -and $r.FilterId) { $fname = [string]$r.FilterId }
                if ($fname) { $filText = (" [filter: {0} {1}]" -f $fname, $ftype) }
            } catch {}
            $parts += ("Ring{0}: {1} {2} (local){3}" -f $r.Ring, $name, $dl.ToString("yyyy-MM-dd HH:mm"), $filText)
        } catch {
            try {
                $ringName = if ($r.GroupName) { $r.GroupName } else { "Ring$($r.Ring)" }
                $parts += ("Ring{0}: {1} +{2}d" -f $r.Ring, $ringName, [int]$r.DelayDays)
            } catch {}
        }
    }
    return ($parts -join "; ")
}

# ========== Simplified Uninstall Script Generator (overrides previous definition) ==========
function Generate-UninstallScript {
    param(
        [Parameter(Mandatory=$true)][string]$VersionRoot,
        [Parameter(Mandatory=$true)][string]$DownloadDir,
        [Parameter(Mandatory=$true)][string]$InstallerName,
        [Parameter()][string]$UninstallArgs,
        [Parameter()][object]$ForceTaskCloseSpec,
        [Parameter()][string]$ProductCode,
        [Parameter()][string]$AppNameForLogs,
        [Parameter()][string]$AppVersionForLogs
    )
    try {
        $scriptsDir = Ensure-Dir (Join-Path $VersionRoot 'Scripts')

        # Normalize ForceTaskClose into clean .exe list (same pattern as Generate-InstallScript)
        $forceList = @()
        if ($ForceTaskCloseSpec) {
            if ($ForceTaskCloseSpec -is [System.Collections.IEnumerable] -and -not ($ForceTaskCloseSpec -is [string])) {
                foreach ($x in $ForceTaskCloseSpec) { if ($null -ne $x) { $forceList += $x.ToString() } }
            } else {
                $s = $ForceTaskCloseSpec.ToString()
                $parts = $s -split "(`r`n|`n|,|;)"
                foreach ($p in $parts) { if ($null -ne $p) { $forceList += $p } }
            }
            $forceList = $forceList | ForEach-Object { $_.ToString().Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
            $forceList = $forceList | ForEach-Object {
                $leaf = [IO.Path]::GetFileName($_)
                if ($leaf -match '\.exe$') { $leaf } else { "$leaf.exe" }
            } | Select-Object -Unique
        }

        $uninstallArgsSafe = ''
        if ($UninstallArgs) { $uninstallArgsSafe = $UninstallArgs }

        $forceArrayLiteral = if ($forceList -and $forceList.Count -gt 0) {
            $q = $forceList | ForEach-Object { '"' + ($_ -replace '"','`"') + '"' }
            "@(" + ($q -join ",") + ")"
        } else { "@()" }

        $content = @"
# Generated by AutoPackager at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
param()
`$ErrorActionPreference = 'Stop'
`$VerbosePreference = 'Continue'

# Log file initialization for Intune IME Logs
`$AppNameRaw = "$($AppNameForLogs -replace '"','`"')"
`$AppVersionRaw = "$($AppVersionForLogs -replace '"','`"')"
function Sanitize-ForPath([string]`$s){
  if (-not `$s) { return 'UnknownApp' }
  `$invalid = [IO.Path]::GetInvalidFileNameChars() + [IO.Path]::GetInvalidPathChars()
  -join (`$s.ToCharArray() | ForEach-Object { if (`$invalid -contains `$_) { '_' } else { `$_ } })
}
`$AppName  = Sanitize-ForPath `$AppNameRaw
`$AppVer   = Sanitize-ForPath `$AppVersionRaw
`$LogRoot  = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
`$AppLogDir = Join-Path `$LogRoot `$AppName
try { `$null = New-Item -ItemType Directory -Path `$AppLogDir -Force -ErrorAction Stop } catch { `$AppLogDir = Join-Path `$env:TEMP `$AppName; `$null = New-Item -ItemType Directory -Path `$AppLogDir -Force -ErrorAction SilentlyContinue }
`$Stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
`$LogPath = Join-Path `$AppLogDir ("Uninstall_{0}_{1}_{2}.log" -f `$AppName, `$AppVer, `$Stamp)
function Write-Log {
  param([string]`$Message,[ValidateSet('INFO','WARN','ERROR','DEBUG')][string]`$Level='INFO')
  `$ts=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); `$line="[`$ts][`$Level] `$Message"
  Write-Host `$line
  try { Add-Content -Path `$LogPath -Value `$line -Encoding UTF8 } catch {}
}
function Stop-WithError([string]`$m){ Write-Log `$m 'ERROR'; exit 1 }

# Optional: close interfering processes
function Close-Processes([string[]]`$ImageNames,[int]`$TimeoutSeconds=15){
  if(-not `$ImageNames -or `$ImageNames.Count -eq 0){ return }
  foreach(`$img in `$ImageNames){
    `$base=[IO.Path]::GetFileNameWithoutExtension(`$img); if([string]::IsNullOrWhiteSpace(`$base)){ continue }
    `$procs=Get-Process -Name `$base -ErrorAction SilentlyContinue
    if(-not `$procs){ continue }
    foreach(`$p in `$procs){
      `$procId=`$p.Id
      try{
        if(`$p.MainWindowHandle -and `$p.MainWindowHandle -ne 0){
          try{ [void]`$p.CloseMainWindow(); Write-Log ("Sent CloseMainWindow to PID {0} ({1})" -f `$procId, `$p.ProcessName) 'DEBUG' } catch {}
        }
      } catch {}
      `$deadline=(Get-Date).AddSeconds(`$TimeoutSeconds)
      while((Get-Date) -lt `$deadline){
        if(-not (Get-Process -Id `$procId -ErrorAction SilentlyContinue)){ break }
        Start-Sleep -Milliseconds 400
      }
      if(Get-Process -Id `$procId -ErrorAction SilentlyContinue){
        try{ Stop-Process -Id `$procId -Force -ErrorAction Stop; Write-Log ("Force-terminated PID {0}" -f `$procId) 'WARN' }
        catch{
          try{ `$null = Start-Process -FilePath taskkill.exe -ArgumentList ("/PID {0} /F /T" -f `$procId) -WindowStyle Hidden -Wait -PassThru }
          catch { Write-Log ("taskkill failed for PID {0}: {1}" -f `$procId, `$_.Exception.Message) 'ERROR' }
        }
      }
    }
  }
}

# Inputs from generator
`$ForceTaskClose = $forceArrayLiteral
`$UninstallArgs  = "$($uninstallArgsSafe -replace '"','`"')"

# Registry helpers
function TryParse-Version([string]`$s){
  try { return [version]`$s } catch {
    if (-not `$s){ return `$null }
    `$parts = (`$s -split '[^0-9]+' | Where-Object { `$_ -match '^\d+$' })
    if (`$parts.Count -eq 0){ return `$null }
    `$nums = `$parts | ForEach-Object { [int]`$_ }
    while(`$nums.Count -lt 4){ `$nums += 0 }
    try { return [version]("{0}.{1}.{2}.{3}" -f `$nums[0],`$nums[1],`$nums[2],`$nums[3]) } catch { return `$null }
  }
}
function Normalize-SearchName([string]`$s){
  if(-not `$s){ return `$s }
  return ((`$s -replace '\s*\([^)]*\)', '').Trim())
}
function Get-UninstallEntry([string]`$name){
  `$rows = @()
  `$cleanName = `$name
  foreach(`$view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)){
    try{
      `$base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, `$view)
      `$rootPath = "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
      `$key  = `$base.OpenSubKey(`$rootPath)
      if(-not `$key){ continue }
      `$subNames = `$key.GetSubKeyNames()
      foreach(`$sub in `$subNames){
        try{
          `$sk = `$key.OpenSubKey(`$sub)
          if(-not `$sk){ continue }
          `$dnObj = `$sk.GetValue("DisplayName")
          if(-not `$dnObj){ continue }
          `$dn = [string]`$dnObj
          `$sc = `$sk.GetValue("SystemComponent", `$null)
          `$scInt = `$null; try { `$scInt = [int]`$sc } catch {}
          if(`$scInt -eq 1){ Write-Log ("Skip (SystemComponent=1, View={0}): HKLM:\{1}\{2}" -f `$view, `$rootPath, `$sub) 'DEBUG'; continue }
          if(`$dn -notlike ("*{0}*" -f `$cleanName)){ continue }
          `$us = [string]`$sk.GetValue("UninstallString")
          if([string]::IsNullOrWhiteSpace(`$us)){ continue }
          `$dv = [string]`$sk.GetValue("DisplayVersion")
          `$rows += [pscustomobject]@{
            DisplayName     = `$dn
            DisplayVersion  = `$dv
            UninstallString = `$us
            KeyPath         = ("HKLM:\{0}\{1} [View={2}]" -f `$rootPath, `$sub, `$view)
          }
        } catch {}
      }
    } catch {}
  }
  if(-not `$rows -or `$rows.Count -eq 0){ return `$null }
  return (`$rows | Sort-Object @{Expression={ TryParse-Version `$_.DisplayVersion }; Descending=`$true} | Select-Object -First 1)
}

function Is-MsiexecStart([string]`$s){
  if([string]::IsNullOrWhiteSpace(`$s)){ return `$false }
  return (`$s -match '^(?is)\s*("?[^"]*\\)?msiexec(\.exe)?"?\s+/(i|x)\b')
}
function Build-MsiexecArgs([string]`$raw){
  # Remove the leading msiexec token and normalize a leading /i to /x
  `$args = (`$raw -replace '^(?is)\s*("?[^"]*\\)?msiexec(\.exe)?"?\s*','')
  `$args = (`$args -replace '^(?i)\s*/i\b','/x')
  return `$args.Trim()
}

Write-Log "===== BEGIN Uninstall for '`$AppNameRaw' version '`$AppVersionRaw' ====="
try{
  if(`$ForceTaskClose -and `$ForceTaskClose.Count -gt 0){ Write-Log ("ForceTaskClose targets: {0}" -f (`$ForceTaskClose -join ', ')) 'INFO'; Close-Processes -ImageNames `$ForceTaskClose -TimeoutSeconds 15 }

  `$searchName = Normalize-SearchName `$AppNameRaw
  `$entry = Get-UninstallEntry -name `$searchName
  if(-not `$entry){ Stop-WithError ("No uninstall entry found for name like '*{0}*'." -f `$AppNameRaw) }

  `$raw = (`$entry.UninstallString -replace "`u0000","") -replace '[\u201C\u201D]', '"' -replace '[\u2018\u2019]', "'"
  `$raw = `$raw.Trim()
  Write-Log ("Registry UninstallString: {0}" -f `$raw) 'INFO'

  if(Is-MsiexecStart `$raw){
    `$argsOnly = Build-MsiexecArgs `$raw
    if(`$UninstallArgs -and `$UninstallArgs.Trim()){ `$argsOnly = ("{0} {1}" -f `$argsOnly, `$UninstallArgs).Trim() }
    Write-Log ("Executing: msiexec.exe {0}" -f `$argsOnly) 'INFO'
    `$proc = Start-Process -FilePath msiexec.exe -ArgumentList `$argsOnly -PassThru -Wait -WindowStyle Hidden
  } else {
    # Try to execute EXE uninstall directly with proper quoting and working directory
    `$exePath = `$null
    `$exeArgs = ""
    `$m = [regex]::Match(`$raw, '^\s*"([^"]+\.exe)"\s*(.*)$')
    if (`$m.Success) {
      `$exePath = `$m.Groups[1].Value
      `$exeArgs = `$m.Groups[2].Value.Trim()
    } else {
      `$m2 = [regex]::Match(`$raw, '^\s*([^\s]+\.exe)\s*(.*)$')
      if (`$m2.Success) {
        `$exePath = `$m2.Groups[1].Value
        `$exeArgs = `$m2.Groups[2].Value.Trim()
      }
    }
    if ([string]::IsNullOrWhiteSpace(`$exePath) -and (Test-Path -LiteralPath `$raw)) {
      `$exePath = `$raw
      `$exeArgs = ""
    }
    # Append recipe UninstallArgs if provided
    if (`$UninstallArgs -and `$UninstallArgs.Trim()) {
      if ([string]::IsNullOrWhiteSpace(`$exeArgs)) {
        `$exeArgs = `$UninstallArgs.Trim()
      } else {
        `$exeArgs = ("{0} {1}" -f `$exeArgs, `$UninstallArgs.Trim()).Trim()
      }
    }
    if (`$exePath -and (Test-Path -LiteralPath `$exePath)) {
      `$wd = `$null
      try { `$wd = Split-Path -Parent `$exePath } catch {}
      Write-Log ("Executing (direct): {0} {1}" -f `$exePath, `$exeArgs) 'INFO'
      if ([string]::IsNullOrWhiteSpace(`$exeArgs)) {
        `$proc = Start-Process -FilePath `$exePath -WorkingDirectory `$wd -PassThru -Wait -WindowStyle Hidden
      } else {
        `$proc = Start-Process -FilePath `$exePath -ArgumentList `$exeArgs -WorkingDirectory `$wd -PassThru -Wait -WindowStyle Hidden
      }
    } else {
      # Fallback to cmd.exe with quoting to preserve spaces
      `$cmdAll = `$raw
      if (`$UninstallArgs -and `$UninstallArgs.Trim()) { `$cmdAll = ("{0} {1}" -f `$cmdAll, `$UninstallArgs).Trim() }
      Write-Log ("Executing via cmd.exe /c: {0}" -f `$cmdAll) 'INFO'
      `$proc = Start-Process -FilePath cmd.exe -ArgumentList @('/c', '"' + `$cmdAll + '"') -PassThru -Wait -WindowStyle Hidden
    }
  }

  `$code = if(`$proc){ `$proc.ExitCode } else { `$LASTEXITCODE }
  if(`$null -eq `$code){ `$code = 0 }
  Write-Log ("Uninstaller exit code: {0}" -f `$code) 'INFO'
  Write-Log "===== END Uninstall ====="
  exit `$code
} catch {
  Write-Log ("uninstall.ps1 error: {0}" -f `$_.Exception.Message) 'ERROR'
  exit 1
}
"@

        $uninstallScriptPath = Join-Path $scriptsDir 'uninstall.ps1'
        Set-Content -LiteralPath $uninstallScriptPath -Value $content -Encoding UTF8
        # Copy to Download so packaging includes uninstall.ps1 next to installer
        try {
            Copy-Item -LiteralPath $uninstallScriptPath -Destination (Join-Path $DownloadDir 'uninstall.ps1') -Force
        } catch {
            Write-Log ("Failed to copy uninstall.ps1 to Download: {0}" -f $_.Exception.Message) 'WARN'
        }
        Write-Log ("uninstall.ps1 generated at: {0} and copied into Download." -f $uninstallScriptPath) 'INFO'
    } catch {
        Write-Log ("Generate-UninstallScript (simplified) error: {0}" -f $_.Exception.Message) 'ERROR'
        throw
    }
}

# ========== Primary Assignment Deadline Update Helper ==========
function Update-PrimaryRequiredAssignmentDeadlineFromRecipe {
    param(
        [Parameter(Mandatory=$true)][string]$AppId,
        [Parameter(Mandatory=$true)][object]$RecipeJson
    )
    $attempted = 0
    $updated = 0
    $hadError = $false
    try {
        # Parse rings to compute max delay in days
        $rings = Parse-RingsFromRecipe -RecipeJson $RecipeJson
        if (-not $rings -or $rings.Count -eq 0) {
            Write-Log "Primary deadline update: no Rings in recipe; skipping deadline adjustment." 'INFO'
            return [PSCustomObject]@{ Attempted = 0; Updated = 0; HadError = $false }
        }
        $maxDelayDays = 0
        try {
            $maxDelayDays = ($rings | ForEach-Object { try { [int]$_.DelayDays } catch { 0 } } | Measure-Object -Maximum).Maximum
            if ($null -eq $maxDelayDays) { $maxDelayDays = 0 }
        } catch { $maxDelayDays = 0 }

        # Resolve hour/minute for deadline (primary overrides > secondary-required > secondary > default 23:59)
        $dlHour = 23; $dlMin = 59
        try {
            if ($script:Config -and $script:Config.Primary -and $script:Config.Primary.AssignmentDefaults -and $script:Config.Primary.AssignmentDefaults.Deadline) {
                if ($null -ne $script:Config.Primary.AssignmentDefaults.Deadline.HourOfDay) { $dlHour = [int]$script:Config.Primary.AssignmentDefaults.Deadline.HourOfDay }
                if ($null -ne $script:Config.Primary.AssignmentDefaults.Deadline.MinuteOfHour) { $dlMin = [int]$script:Config.Primary.AssignmentDefaults.Deadline.MinuteOfHour }
            } elseif ($script:Config -and $script:Config.SecondaryRequiredApp -and $script:Config.SecondaryRequiredApp.AssignmentDefaults -and $script:Config.SecondaryRequiredApp.AssignmentDefaults.Deadline) {
                if ($null -ne $script:Config.SecondaryRequiredApp.AssignmentDefaults.Deadline.HourOfDay) { $dlHour = [int]$script:Config.SecondaryRequiredApp.AssignmentDefaults.Deadline.HourOfDay }
                if ($null -ne $script:Config.SecondaryRequiredApp.AssignmentDefaults.Deadline.MinuteOfHour) { $dlMin = [int]$script:Config.SecondaryRequiredApp.AssignmentDefaults.Deadline.MinuteOfHour }
            } elseif ($script:Config -and $script:Config.Secondary -and $script:Config.Secondary.AssignmentDefaults -and $script:Config.Secondary.AssignmentDefaults.Deadline) {
                if ($null -ne $script:Config.Secondary.AssignmentDefaults.Deadline.HourOfDay) { $dlHour = [int]$script:Config.Secondary.AssignmentDefaults.Deadline.HourOfDay }
                if ($null -ne $script:Config.Secondary.AssignmentDefaults.Deadline.MinuteOfHour) { $dlMin = [int]$script:Config.Secondary.AssignmentDefaults.Deadline.MinuteOfHour }
            }
        } catch {}

        $deadlineLocal = (Get-Date).AddDays([int]$maxDelayDays).Date.AddHours($dlHour).AddMinutes($dlMin)
        Write-Log ("Primary deadline update: max DelayDays={0}, computed local deadline={1}" -f $maxDelayDays, $deadlineLocal.ToString("yyyy-MM-dd HH:mm")) 'INFO'

        # Fetch assignments and filter required
        $assignments = Get-AppAssignmentsGraph -AppId $AppId
        if (-not $assignments -or $assignments.Count -eq 0) {
            Write-Log "Primary deadline update: app has no assignments; skipping." 'INFO'
            return [PSCustomObject]@{ Attempted = 0; Updated = 0; HadError = $false }
        }
        $req = @($assignments | Where-Object { $_.intent -and ($_.intent.ToString().Trim().ToLower() -eq 'required') })
        $attempted = if ($req) { $req.Count } else { 0 }
        if (-not $req -or $req.Count -eq 0) {
            Write-Log "Primary deadline update: no required assignments found; skipping." 'INFO'
            return [PSCustomObject]@{ Attempted = $attempted; Updated = 0; HadError = $false }
        }
        # Trace discovered required assignments for target mapping and existing deadlines
        try {
            foreach ($x in $req) {
                $t = $x.target
                $tType = $null
                $gid = $null
                try { $tType = [string]$t.'@odata.type' } catch {}
                try { if ($tType -eq '#microsoft.graph.groupAssignmentTarget') { $gid = [string]$t.groupId } } catch {}
                $ed = $null
                try { if ($x.settings -and $x.settings.installTimeSettings -and $x.settings.installTimeSettings.deadlineDateTime) { $ed = [string]$x.settings.installTimeSettings.deadlineDateTime } } catch {}
                Write-Log ("Primary deadline update: discovered required assignment id='{0}', targetType='{1}', groupId='{2}', existingDeadline='{3}'" -f $x.id, $tType, $gid, $ed) 'DEBUG'
            }
        } catch {}

        $updated = 0
        foreach ($a in $req) {
            # Capture target signature for retry mapping
            $aTarget = $a.target
            $aTargetType = $null
            $aGroupId = $null
            try { $aTargetType = [string]$aTarget.'@odata.type' } catch {}
            try { if ($aTargetType -eq '#microsoft.graph.groupAssignmentTarget') { $aGroupId = [string]$aTarget.groupId } } catch {}
            try {
                $settingsExisting = $a.settings
                $notif = 'showAll'
                $doPrio = 'notConfigured'
                $startDt = $null
                $existingDeadline = $null
                if ($settingsExisting) {
                    try { if ($settingsExisting.notifications) { $notif = [string]$settingsExisting.notifications } } catch {}
                    try { if ($settingsExisting.deliveryOptimizationPriority) { $doPrio = [string]$settingsExisting.deliveryOptimizationPriority } } catch {}
                    try { if ($settingsExisting.installTimeSettings -and $settingsExisting.installTimeSettings.startDateTime) { $startDt = $settingsExisting.installTimeSettings.startDateTime } } catch {}
                    try { if ($settingsExisting.installTimeSettings -and $settingsExisting.installTimeSettings.deadlineDateTime) { $existingDeadline = [datetime]$settingsExisting.installTimeSettings.deadlineDateTime } } catch {}
                }

                # Idempotency: skip if existing deadline already equals computed (rounded to minute)
                $deadlineRound = $deadlineLocal.AddSeconds(-$deadlineLocal.Second).AddMilliseconds(-$deadlineLocal.Millisecond)
                $existingRound = $null
                if ($existingDeadline) { $existingRound = $existingDeadline.AddSeconds(-$existingDeadline.Second).AddMilliseconds(-$existingDeadline.Millisecond) }
                if ($existingRound -and ($existingRound -eq $deadlineRound)) {
                    Write-Log ("Primary deadline update: no change for assignment '{0}' (targetType='{1}', groupId='{2}') - existing deadline already {3}" -f $a.id, $aTargetType, $aGroupId, $existingRound.ToString("o")) 'DEBUG'
                    continue
                }

                $body = @{
                    settings = @{
                        "@odata.type" = "#microsoft.graph.win32LobAppAssignmentSettings"
                        notifications = $notif
                        deliveryOptimizationPriority = $doPrio
                        installTimeSettings = @{
                            "@odata.type"    = "#microsoft.graph.mobileAppInstallTimeSettings"
                            useLocalTime     = $true
                            startDateTime    = $startDt
                            deadlineDateTime = $deadlineLocal.ToString("o")
                        }
                    }
                }

                # Attempt PATCH on the current assignment id
                Invoke-GraphJson -Method 'PATCH' -Path ("/deviceAppManagement/mobileApps/{0}/assignments/{1}" -f $AppId, $a.id) -Body $body | Out-Null
                $updated++
                    } catch {
                        $errText = $_.Exception.Message
                        $didFallback = $false
                        # Retry once on 404 by refreshing assignments and matching by target signature (v1.0)
                        if ($errText -match '404' -or $errText -match '(?i)not\s*found') {
                            try {
                                $assignmentsRef = Get-AppAssignmentsGraph -AppId $AppId
                                $equiv = $null
                                foreach ($cand in $assignmentsRef) {
                                    $ct = $null; $cgid = $null
                                    try { $ct = [string]$cand.target.'@odata.type' } catch {}
                                    try { if ($ct -eq '#microsoft.graph.groupAssignmentTarget') { $cgid = [string]$cand.target.groupId } } catch {}
                                    if ($ct -eq $aTargetType -and ($cgid -eq $aGroupId)) { $equiv = $cand; break }
                                }
                                if ($equiv -and $equiv.id) {
                                    Write-Log ("Primary deadline update: 404 on id '{0}', retrying with refreshed id '{1}' (targetType='{2}', groupId='{3}')." -f $a.id, $equiv.id, $aTargetType, $aGroupId) 'WARN'
                                    Invoke-GraphJson -Method 'PATCH' -Path ("/deviceAppManagement/mobileApps/{0}/assignments/{1}" -f $AppId, $equiv.id) -Body $body | Out-Null
                                    $updated++
                                    $didFallback = $true
                                } else {
                                    Write-Log ("Primary deadline update: retry not possible; no equivalent assignment found for targetType='{0}', groupId='{1}'." -f $aTargetType, $aGroupId) 'WARN'
                                }
                            } catch {
                                Write-Log ("Primary deadline update: retry after 404 failed for original id '{0}': {1}" -f $a.id, $_.Exception.Message) 'WARN'
                            }
                            # Beta endpoint fallback if v1.0 PATCH continues to 404
                            if (-not $didFallback) {
                                try {
                                    Invoke-GraphJson -Method 'PATCH' -Path ("https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/{0}/assignments/{1}" -f $AppId, $a.id) -Body $body | Out-Null
                                    Write-Log ("Primary deadline update (beta): PATCH succeeded for assignment '{0}'" -f $a.id) 'INFO'
                                    $updated++
                                    $didFallback = $true
                                } catch {
                                    Write-Log ("Primary deadline update (beta): PATCH failed for assignment '{0}': {1}" -f $a.id, $_.Exception.Message) 'WARN'
                                }
                            }
                            if (-not $didFallback) {
                                # Beta: re-resolve equivalent assignment by target signature then PATCH
                                try {
                                    $assignmentsRefBeta = Invoke-GraphJson -Method 'GET' -Path ("https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/{0}/assignments" -f $AppId)
                                    $equivBeta = $null
                                    foreach ($cand in @($assignmentsRefBeta.value)) {
                                        $ct = $null; $cgid = $null
                                        try { $ct = [string]$cand.target.'@odata.type' } catch {}
                                        try { if ($ct -eq '#microsoft.graph.groupAssignmentTarget') { $cgid = [string]$cand.target.groupId } } catch {}
                                        if ($ct -eq $aTargetType -and ($cgid -eq $aGroupId)) { $equivBeta = $cand; break }
                                    }
                                    if ($equivBeta -and $equivBeta.id) {
                                        Write-Log ("Primary deadline update (beta): retrying with refreshed id '{0}'" -f $equivBeta.id) 'WARN'
                                        Invoke-GraphJson -Method 'PATCH' -Path ("https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/{0}/assignments/{1}" -f $AppId, $equivBeta.id) -Body $body | Out-Null
                                        $updated++
                                        $didFallback = $true
                                    }
                                } catch {
                                    Write-Log ("Primary deadline update (beta): re-resolve failed: {0}" -f $_.Exception.Message) 'WARN'
                                }
                            }
                            if (-not $didFallback) {
                                # Final fallback: POST /assign upsert for same target signature
                                try {
                                    $targetObj = $aTarget
                                    if (-not $targetObj) {
                                        if ($aTargetType -eq '#microsoft.graph.allDevicesAssignmentTarget') {
                                            $targetObj = @{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' }
                                        } elseif ($aTargetType -eq '#microsoft.graph.allLicensedUsersAssignmentTarget') {
                                            $targetObj = @{ '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget' }
                                        } elseif ($aTargetType -eq '#microsoft.graph.groupAssignmentTarget' -and $aGroupId) {
                                            $targetObj = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $aGroupId }
                                        }
                                    }
                                    if ($targetObj) {
                                        $item = @{
                                            '@odata.type' = '#microsoft.graph.mobileAppAssignment'
                                            intent        = 'required'
                                            target        = $targetObj
                                            settings      = $body.settings
                                        }
                                        Invoke-GraphJson -Method 'POST' -Path ("/deviceAppManagement/mobileApps/{0}/assign" -f $AppId) -Body @{ mobileAppAssignments = @($item) } | Out-Null
                                        Write-Log ("Primary deadline update: applied via POST /assign for targetType='{0}', groupId='{1}'" -f $aTargetType, $aGroupId) 'INFO'
                                        $updated++
                                        $didFallback = $true
                                    } else {
                                        Write-Log ("Primary deadline update: unable to construct target object for upsert; skipping.") 'WARN'
                                    }
                                } catch {
                                    Write-Log ("Primary deadline update: POST /assign fallback failed: {0}" -f $_.Exception.Message) 'ERROR'
                                }
                            }
                        } else {
                            Write-Log ("Primary deadline update: PATCH failed for assignment '{0}': {1}" -f $a.id, $errText) 'WARN'
                        }
                    }
        }
        Write-Log ("Primary deadline update: updated {0} required assignment(s) to deadline {1} (local)" -f $updated, $deadlineLocal.ToString("yyyy-MM-dd HH:mm")) 'INFO'
    } catch {
        $hadError = $true
        Write-Log ("Primary deadline update encountered an error: {0}" -f $_.Exception.Message) 'ERROR'
    }
    return [PSCustomObject]@{
        Attempted = $attempted
        Updated   = $updated
        HadError  = $hadError
    }
}

# ========== Main ==========
$summary = New-Object System.Collections.Generic.List[object]
$updates = New-Object System.Collections.Generic.List[object]
$failures = New-Object System.Collections.Generic.List[object]

try {
    if (-not $PSBoundParameters.ContainsKey('PathRecipes') -or [string]::IsNullOrWhiteSpace($PathRecipes)) {
        $cfgRecipes = $null
        try { if ($script:Config -and $script:Config.Paths -and $script:Config.Paths.RecipesRoot) { $cfgRecipes = [string]$script:Config.Paths.RecipesRoot } } catch {}
        if ($cfgRecipes -and -not [string]::IsNullOrWhiteSpace($cfgRecipes)) {
            $defaultRecipes = if ([System.IO.Path]::IsPathRooted($cfgRecipes)) { $cfgRecipes } else { Join-Path $script:ScriptRootEffective $cfgRecipes }
        } else {
            $defaultRecipes = Join-Path $script:ScriptRootEffective 'Recipes'
        }
        if ($FullRun) {
            if ($AllRecipes) {
                # Full run without explicit recipe and -AllRecipes: process all in default folder
                $PathRecipes = $defaultRecipes
            } else {
                # Full run without explicit recipe: prompt to select a single recipe (same as default/package-only)
                if (-not (Test-Path -LiteralPath $defaultRecipes -PathType Container)) {
                    Stop-WithError "Recipes folder not found: $defaultRecipes"
                }
                $candidates = Get-ChildItem -LiteralPath $defaultRecipes -Filter *.json -File -ErrorAction SilentlyContinue
                if (-not $candidates -or $candidates.Count -eq 0) {
                    Stop-WithError "No recipe JSON files found at $defaultRecipes"
                } elseif ($candidates.Count -eq 1) {
                    $PathRecipes = $candidates[0].FullName
                    Write-Log ("Selected single recipe: {0}" -f $PathRecipes) 'INFO'
                } else {
                    Write-Host "Available Recipes:"
                    for ($i=0; $i -lt $candidates.Count; $i++) {
                        Write-Host ("[{0}] {1}" -f ($i+1), $candidates[$i].Name)
                    }
                    while ($true) {
                        $input = Read-Host "Enter number or recipe name (without .json)"
                        if ([string]::IsNullOrWhiteSpace($input)) { continue }
                        $sel = $null
                        if ($input -match '^\d+$') {
                            $idx = [int]$input - 1
                            if ($idx -ge 0 -and $idx -lt $candidates.Count) { $sel = $candidates[$idx] }
                        } else {
                            $name = $input.Trim()
                            $sel = $candidates | Where-Object { $_.BaseName -ieq $name } | Select-Object -First 1
                            if (-not $sel) {
                                $sel = $candidates | Where-Object { $_.Name -ieq $name -or $_.Name -ieq ($name + '.json') } | Select-Object -First 1
                            }
                        }
                        if ($sel) { $PathRecipes = $sel.FullName; break }
                        Write-Host "Invalid selection. Try again."
                    }
                }
            }
        } else {
            # Default behavior: package-only and prompt user to pick a single recipe
            if (-not (Test-Path -LiteralPath $defaultRecipes -PathType Container)) {
                Stop-WithError "Recipes folder not found: $defaultRecipes"
            }
            $candidates = Get-ChildItem -LiteralPath $defaultRecipes -Filter *.json -File -ErrorAction SilentlyContinue
            if (-not $candidates -or $candidates.Count -eq 0) {
                Stop-WithError "No recipe JSON files found at $defaultRecipes"
            } elseif ($candidates.Count -eq 1) {
                $PathRecipes = $candidates[0].FullName
                Write-Log ("Selected single recipe: {0}" -f $PathRecipes) 'INFO'
            } else {
                Write-Host "Available Recipes:"
                for ($i=0; $i -lt $candidates.Count; $i++) {
                    Write-Host ("[{0}] {1}" -f ($i+1), $candidates[$i].Name)
                }
                while ($true) {
                    $input = Read-Host "Enter number or recipe name (without .json)"
                    if ([string]::IsNullOrWhiteSpace($input)) { continue }
                    $sel = $null
                    if ($input -match '^\d+$') {
                        $idx = [int]$input - 1
                        if ($idx -ge 0 -and $idx -lt $candidates.Count) { $sel = $candidates[$idx] }
                    } else {
                        $name = $input.Trim()
                        $sel = $candidates | Where-Object { $_.BaseName -ieq $name } | Select-Object -First 1
                        if (-not $sel) {
                            $sel = $candidates | Where-Object { $_.Name -ieq $name -or $_.Name -ieq ($name + '.json') } | Select-Object -First 1
                        }
                    }
                    if ($sel) { $PathRecipes = $sel.FullName; break }
                    Write-Host "Invalid selection. Try again."
                }
            }
        }
    }
    $PathRecipes = (Resolve-Path -LiteralPath $PathRecipes).Path
} catch {
    Stop-WithError "Recipes path not found: $PathRecipes"
}

# Support -PathRecipes pointing to either a folder of recipes or a single .json recipe file
if (Test-Path -LiteralPath $PathRecipes -PathType Leaf) {
    if ($PathRecipes -match '\.json$') {
        $recipes = @((Get-Item -LiteralPath $PathRecipes -ErrorAction Stop))
    } else {
        Stop-WithError "PathRecipes points to a file that is not .json: $PathRecipes"
    }
} else {
    $recipes = Get-ChildItem -LiteralPath $PathRecipes -Filter *.json -File -ErrorAction SilentlyContinue
}
if (-not $recipes -or $recipes.Count -eq 0) { Stop-WithError "No recipe JSON files found at $PathRecipes" }

if ($DryRun -and $PackageOnly) {
    Write-Log "Both -DryRun and -PackageOnly were provided. -DryRun takes precedence; no download/wrap/upload will occur." 'WARN'
}
Write-Log "Found $($recipes.Count) recipe(s) at $PathRecipes" 'INFO'
Ensure-Dir $WorkingRoot | Out-Null

# ===== AzureAuth from config (optional; precedence: CLI > Config.AzureAuth > AZInfo.csv) =====
try {
    $__hasCliTenant = ($PSBoundParameters.ContainsKey('TenantId') -and $TenantId -and (-not [string]::IsNullOrWhiteSpace($TenantId)))
    $__hasCliClient = ($PSBoundParameters.ContainsKey('ClientId') -and $ClientId -and (-not [string]::IsNullOrWhiteSpace($ClientId)))
    $__hasCliSecret = ($PSBoundParameters.ContainsKey('ClientSecret') -and $ClientSecret)
    $__hasCliThumb  = ($PSBoundParameters.ContainsKey('CertificateThumbprint') -and $CertificateThumbprint -and (-not [string]::IsNullOrWhiteSpace($CertificateThumbprint)))

    $sourcedCfgTenant = $false; $sourcedCfgClient = $false; $sourcedCfgSecret = $false; $sourcedCfgThumb = $false
    if ($script:Config -and $script:Config.AzureAuth) {
        if (-not $__hasCliTenant -and $script:Config.AzureAuth.TenantId) {
            $TenantId = [string]$script:Config.AzureAuth.TenantId
            $sourcedCfgTenant = $true
        }
        if (-not $__hasCliClient -and $script:Config.AzureAuth.ClientId) {
            $ClientId = [string]$script:Config.AzureAuth.ClientId
            $sourcedCfgClient = $true
        }
        if (-not $__hasCliSecret -and $script:Config.AzureAuth.ClientSecret) {
            try {
                $ClientSecret = ConvertTo-SecureString -String ([string]$script:Config.AzureAuth.ClientSecret) -AsPlainText -Force
                $sourcedCfgSecret = $true
            } catch { }
        }
        if (-not $__hasCliThumb -and $script:Config.AzureAuth.CertificateThumbprint) {
            $CertificateThumbprint = [string]$script:Config.AzureAuth.CertificateThumbprint
            $sourcedCfgThumb = $true
        }
        try {
            $appliedAuth = @()
            if ($sourcedCfgTenant) { $appliedAuth += 'TenantId' }
            if ($sourcedCfgClient) { $appliedAuth += 'ClientId' }
            if ($sourcedCfgSecret) { $appliedAuth += 'ClientSecret' }
            if ($sourcedCfgThumb)  { $appliedAuth += 'CertificateThumbprint' }
            if ($appliedAuth.Count -gt 0) { Write-Log ("AzureAuth (config) applied: {0}" -f ($appliedAuth -join ', ')) 'INFO' }
        } catch { }
    }
} catch { }
# ===== AZInfo.csv (optional credentials override) =====
try {
    $csvPath = Join-Path $script:ScriptRootEffective 'AZInfo.csv'
    if (Test-Path -LiteralPath $csvPath) {
        $rows = Import-Csv -LiteralPath $csvPath -ErrorAction Stop
        $row = $null
        if ($rows -is [System.Collections.IEnumerable]) { $row = ($rows | Select-Object -First 1) } else { $row = $rows }
        if ($row) {
            function __GetCsvVal([object]$o, [string]$name) {
                try {
                    $val = $null
                    if ($o.PSObject.Properties.Name -contains $name) { $val = [string]$o.$name }
                    else {
                        $prop = $o.PSObject.Properties | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
                        if ($prop) { $val = [string]$prop.Value }
                    }
                    if ($val) { $val = $val.Trim() }
                    if ($val -and -not [string]::IsNullOrWhiteSpace($val)) { return $val } else { return $null }
                } catch { return $null }
            }
            $csvTenant = __GetCsvVal $row 'TenantId'
            $csvClient = __GetCsvVal $row 'ClientId'
            $csvSecret = __GetCsvVal $row 'ClientSecret'
            $csvThumb  = __GetCsvVal $row 'CertificateThumbprint'

            $applied = @()
            if ($csvTenant -and -not $__hasCliTenant -and -not $sourcedCfgTenant) { $TenantId = $csvTenant; $applied += 'TenantId' }
            if ($csvClient -and -not $__hasCliClient -and -not $sourcedCfgClient) { $ClientId = $csvClient; $applied += 'ClientId' }
            if ($csvSecret -and -not $__hasCliSecret -and -not $sourcedCfgSecret) {
                try {
                    $ClientSecret = ConvertTo-SecureString -String $csvSecret -AsPlainText -Force
                    $applied += 'ClientSecret'
                } catch {
                    Write-Log ("AZInfo.csv: failed to convert ClientSecret to SecureString: {0}" -f $_.Exception.Message) 'WARN'
                }
            }
            if ($csvThumb -and -not $__hasCliThumb -and -not $sourcedCfgThumb) { $CertificateThumbprint = $csvThumb; $applied += 'CertificateThumbprint' }

            $hasSecret = [bool]$csvSecret
            $hasThumb  = [bool]$csvThumb
            if ($applied.Count -gt 0) {
                Write-Log ("AZInfo.csv applied: {0}; ClientSecret present={1}; CertificateThumbprint present={2}" -f ($applied -join ', '), $hasSecret, $hasThumb) 'INFO'
            } else {
                Write-Log "AZInfo.csv present but contained no non-empty values; using CLI parameters." 'WARN'
            }
        } else {
            Write-Log "AZInfo.csv contained no rows; using CLI parameters." 'WARN'
        }
    }
} catch {
    Write-Log ("AZInfo.csv load error: {0}" -f $_.Exception.Message) 'WARN'
}

# Compute effective run mode (default is PackageOnly unless -FullRun provided)
$script:EffectivePackageOnly = $true
if ($PSBoundParameters.ContainsKey('FullRun')) { $script:EffectivePackageOnly = $false }
if ($PSBoundParameters.ContainsKey('PackageOnly')) { $script:EffectivePackageOnly = $true }
if ($DryRun) { $script:EffectivePackageOnly = $true }

# Connect to Intune for this run (authenticate by default; opt-out with -NoAuth or -DryRun)
$disc = Get-Command -Name Disconnect-MSIntuneGraph -ErrorAction SilentlyContinue
if ($disc) { try { Disconnect-MSIntuneGraph -ErrorAction SilentlyContinue | Out-Null } catch {} }
if (-not $DryRun -and -not $NoAuth) {
    Ensure-Module -Name 'IntuneWin32App'
    if ($ClientSecret) {
        $plain = ConvertTo-PlainText $ClientSecret
        Write-Log "Connecting to Intune (app-only auth) using client secret ..." 'INFO'
        Invoke-Silently { Connect-MSIntuneGraph -TenantID $TenantId -ClientID $ClientId -ClientSecret $plain -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null }
        $script:SuppressFirstIntuneWarning = $true
        Write-Log "Connected to Intune (fresh session)." 'INFO'
    } elseif ($CertificateThumbprint) {
        Write-Log "Connecting to Intune (app-only auth) using certificate thumbprint ..." 'INFO'
        Invoke-Silently { Connect-MSIntuneGraph -TenantID $TenantId -ClientID $ClientId -CertificateThumbprint $CertificateThumbprint -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null }
        $script:SuppressFirstIntuneWarning = $true
        Write-Log "Connected to Intune (fresh session)." 'INFO'
    } else {
        Stop-WithError "Either -ClientSecret or -CertificateThumbprint must be provided for app-only authentication."
    }
} else {
    Write-Log "Skipping Intune connection due to -DryRun or -NoAuth." 'INFO'
}

foreach ($file in $recipes) {
    Write-Log ("Processing recipe: {0}" -f $file.FullName) 'INFO'
    try {

    $recipeJson = Read-RecipeJson -Path $file.FullName
    if (-not $recipeJson) { continue }
    Write-Log ("Recipe parsed: {0} WingetId='{1}' IntuneAppId='{2}'" -f $file.Name, $recipeJson.WingetId, $recipeJson.IntuneAppId) 'DEBUG'

    $wingetId     = $recipeJson.WingetId
    $appName      = $recipeJson.AppName
    $intuneAppId  = $recipeJson.IntuneAppId
    $archPref     = $recipeJson.InstallerPreferences.Architecture
    $scopePref    = $recipeJson.InstallerPreferences.Scope
    $customArgs   = $recipeJson.CustomArgs
    $updateProps  = $recipeJson.UpdateAppProperties
    $installArgsFromRecipe   = $recipeJson.InstallArgs
    $uninstallArgsFromRecipe = $recipeJson.UninstallArgs
$forceTaskCloseSpec      = $recipeJson.ForceTaskClose
$secondaryAppIdRecipe    = $recipeJson.SecondaryAppId

# Recipe flag: AllowAvailableUninstall (apply only if present)
$allowAvailableUninstall = $null
try {
    if ($recipeJson.PSObject.Properties.Name -contains 'AllowAvailableUninstall' -and $null -ne $recipeJson.AllowAvailableUninstall) {
        $allowAvailableUninstall = [bool]$recipeJson.AllowAvailableUninstall
        Write-Log ("Recipe specifies AllowAvailableUninstall={0}" -f $allowAvailableUninstall) 'INFO'
    }
} catch {}
# Recipe-only AAU: no config fallback (removed)
    # Support nested schema: Secondary.{IntuneAppId|AppId|Id}
    $secondaryNested = $null
    try {
        if ($recipeJson.Secondary) {
            $secondaryNested = @(
                $recipeJson.Secondary.IntuneAppId,
                $recipeJson.Secondary.AppId,
                $recipeJson.Secondary.Id
            ) | Where-Object { $_ -and $_.ToString().Trim() } | Select-Object -First 1
        }
    } catch { }
    $secondaryAppIdCandidate = $null
    # Always use per-recipe SecondaryAppId (or nested Secondary.*). Ignore any CLI -SecondaryAppId.
    if ($secondaryAppIdRecipe -and $secondaryAppIdRecipe.Trim()) {
        $secondaryAppIdCandidate = $secondaryAppIdRecipe
    } elseif ($secondaryNested) {
        $secondaryAppIdCandidate = $secondaryNested
    }
    if ($PSBoundParameters.ContainsKey('SecondaryAppId') -and $SecondaryAppId -and $SecondaryAppId.Trim()) {
        Write-Log "Ignoring -SecondaryAppId CLI parameter; using recipe SecondaryAppId only." 'WARN'
    }
    $secondaryAppId = if ($secondaryAppIdCandidate) { $secondaryAppIdCandidate.Trim() } else { $null }
    if ($secondaryAppId) {
        Write-Log ("Secondary target detected: {0}" -f $secondaryAppId) 'INFO'
    } else {
        Write-Log "Secondary target not specified in recipe; skipping secondary." 'INFO'
    }
    if ([string]::IsNullOrWhiteSpace($wingetId)) {
        Write-Log "Recipe $($file.Name) missing required WingetId. Skipping." 'WARN'
        continue
    }
    if ((-not $DryRun) -and (-not $script:EffectivePackageOnly) -and [string]::IsNullOrWhiteSpace($intuneAppId)) {
        Write-Log "FullRun requires IntuneAppId; recipe $($file.Name) missing it. Skipping." 'WARN'
        continue
    }
    if (-not $appName) { $appName = $wingetId }

    # Winget lookup via GitHub manifest (replaces 'winget show' text parsing)
    $wg = Get-WingetManifestInfoFromGitHub `
        -WingetId $wingetId `
        -PreferArchitecture ($(if ($archPref) { $archPref } else { $PreferArchitecture })) `
        -PreferScope ($(if ($scopePref) { $scopePref } else { $DefaultScope })) `
        -DesiredLocale ($(if ($recipeJson.InstallerPreferences.Locale) { $recipeJson.InstallerPreferences.Locale } else { 'en-US' })) `
        -DesiredInstallerType ($(if ($recipeJson.InstallerPreferences.InstallerType) { $recipeJson.InstallerPreferences.InstallerType } else { $null }))
    if (-not $wg) { Stop-WithError ("Failed to resolve winget manifest for {0} via GitHub" -f $wingetId) }
    $wingetVersion = $wg.Version
    $installerUrl  = $wg.InstallerUrl
    $installerType = $wg.InstallerType
    if (-not $appName -and $wg.Name) { $appName = $wg.Name }
    if ($wg.Publisher)   { $publisher  = $wg.Publisher }
    if ($wg.Author)      { $author     = $wg.Author }
    if ($wg.Homepage)    { $homepage   = $wg.Homepage }
    if ($wg.PrivacyUrl)  { $privacyUrl = $wg.PrivacyUrl }
    if ($wg.Description) { $description= $wg.Description }

    # Stale manifest detection disabled: using GitHub winget-pkgs repository as source of truth for latest version
    try {
        if ($wingetVersion) {
            Write-Log ("Using GitHub manifest latest='{0}' for {1}" -f $wingetVersion, $wingetId) 'INFO'
        } else {
            Stop-WithError ("GitHub manifest did not yield a version for {0}" -f $wingetId)
        }
    } catch {
        Write-Log ("Manifest check failed: {0}" -f $_.Exception.Message) 'WARN'
    }

    # Winget metadata resolved via GitHub manifests (winget-pkgs). No winget show parsing.
    Write-Log "Winget metadata sourced from GitHub winget-pkgs manifests." 'INFO'
    if (-not $appName -and $wg.Name) {
        $appName = $wg.Name
        Write-Log ("Resolved appName from winget: '{0}'" -f $appName) 'DEBUG'
    }
    $resolvedName = if ($wg -and $wg.Name) { $wg.Name } elseif ($appName) { $appName } else { $wingetId }
    Write-Log ("Using Winget app name for logs/summary: '{0}'" -f $resolvedName) 'DEBUG'

    # Persist additional winget metadata for later use
    $publisher   = $wg.Publisher
    $author      = $wg.Author
    $homepage    = $wg.Homepage
    $privacyUrl  = $wg.PrivacyUrl
    $description = $wg.Description
    $descPreview = $description
    if ($descPreview -and $descPreview.Length -gt 120) { $descPreview = $descPreview.Substring(0,120) + '...' }
    Write-Log ("Winget meta: Publisher='{0}', Author='{1}', Homepage='{2}', PrivacyUrl='{3}', Description='{4}'" -f $publisher, $author, $homepage, $privacyUrl, $descPreview) 'DEBUG'

    # Surface and log tags (from text parsing)
    $tags = $null
    try {
        if ($wg -and ($wg.PSObject.Properties.Name -contains 'Tags') -and $wg.Tags) { $tags = @($wg.Tags) }
    } catch {}
    if ($tags) {
        try { Write-Log ("Winget tags: {0}" -f (($tags | ForEach-Object { $_.ToString() }) -join ', ')) 'DEBUG' } catch {}
    }


    if (-not $DryRun -and -not $script:EffectivePackageOnly) {
        $appModule = Get-IntuneAppByIdSafe -Id $intuneAppId
        $app = $appModule
        $currentVersion = Get-DisplayVersion -App $appModule

        $secAppModule = if ($secondaryAppId) { Get-IntuneAppByIdSafe -Id $secondaryAppId } else { $null }
        $secApp = $secAppModule
        $secCurrentVersion = Get-DisplayVersion -App $secAppModule
    } else {
        $appModule = $null
        $app = $null
        $currentVersion = $null

        $secAppModule = $null
        $secApp = $null
        $secCurrentVersion = $null
    }

Write-Log "$resolvedName | Intune version: '$currentVersion' | Winget: '$wingetVersion'" 'INFO'
if (-not $DryRun -and -not $script:EffectivePackageOnly) {
    if ([string]::IsNullOrWhiteSpace($currentVersion)) {
        $errText = "No Intune version found for primary app (displayVersion is null or blank)."
        Write-Log ("{0} | {1}" -f $resolvedName, $errText) 'ERROR'
        $failures.Add([pscustomobject]@{
            App          = $resolvedName
            WingetId     = $wingetId
            Stage        = 'Precheck'
            ErrorMessage = $errText
        }) | Out-Null
        $summary.Add([PSCustomObject]@{
            App    = $resolvedName
            Intune = $currentVersion
            Winget = $wingetVersion
            Action = 'Failed'
            Notes  = $errText
        }) | Out-Null
        continue
    }
}
$cmp = if ($currentVersion) { Compare-VersionStrings -A $wingetVersion -B $currentVersion } else { 1 }
if ($cmp -le 0) {
    if ($secondaryAppId -and $ReapplySecondaryAssignments) {
            Write-Log ("Primary is up-to-date; reapplying secondary ring assignments due to -ReapplySecondaryAssignments for '{0}'." -f $secondaryAppId) 'INFO'
            try {
                $ringsParsed = Parse-RingsFromRecipe -RecipeJson $recipeJson
                if ($ringsParsed -and $ringsParsed.Count -gt 0) {
                    $doClear = $true
                    try {
                        if ($script:Config -and $script:Config.Secondary -and $script:Config.Secondary.AssignmentDefaults -and ($null -ne $script:Config.Secondary.AssignmentDefaults.ClearExistingBeforeAssign)) {
                            $doClear = [bool]$script:Config.Secondary.AssignmentDefaults.ClearExistingBeforeAssign
                        }
                    } catch {}
                    if ($doClear) {
                        Clear-AppAssignmentsGraph -AppId $secondaryAppId
                    } else {
                        Write-Log "Secondary assignments: skipping clear step by config." 'INFO'
                    }
                    $countAssigned = Assign-AppToRingsGraph -AppId $secondaryAppId -Rings $ringsParsed
                    $summary.Add([PSCustomObject]@{
                        App    = ("{0} (Required Updates)" -f $resolvedName)
                        Intune = $secCurrentVersion
                        Winget = $wingetVersion
                        Action = 'AssignmentsUpdatedSecondary'
                        Notes  = ("Ring assignments re-applied: {0}" -f $countAssigned)
                    }) | Out-Null
                } else {
                    Write-Log "No ring assignments specified in recipe; nothing to reapply." 'INFO'
                }
            } catch {
                Write-Log ("Reapply secondary assignments failed: {0}" -f $_.Exception.Message) 'ERROR'
            }
            $primaryActionNoUpdate = 'Skipped'
            $primaryNotesNoUpdate = 'Up-to-date'
            Write-Log "Up-to-date. No content upload required." 'INFO'
            $summary.Add([PSCustomObject]@{ App=$resolvedName; Intune=$currentVersion; Winget=$wingetVersion; Action=$primaryActionNoUpdate ; Notes=$primaryNotesNoUpdate }) | Out-Null
            continue
        } else {
            if ($secondaryAppId) {
                Write-Log ("Primary is up-to-date; secondary updates are tied to primary in this workflow. Skipping secondary '{0}'." -f $secondaryAppId) 'INFO'
            }
            $primaryActionNoUpdate = 'Skipped'
            $primaryNotesNoUpdate = 'Up-to-date'
            Write-Log "Up-to-date. No action required." 'INFO'
            $summary.Add([PSCustomObject]@{ App=$resolvedName; Intune=$currentVersion; Winget=$wingetVersion; Action=$primaryActionNoUpdate ; Notes=$primaryNotesNoUpdate }) | Out-Null
            continue
        }
    }

    if ($DryRun) {
        Write-Log "Dry-Run: Would update $resolvedName from $currentVersion to $wingetVersion" 'INFO'
        $summary.Add([PSCustomObject]@{ App=$resolvedName; Intune=$currentVersion; Winget=$wingetVersion; Action='WouldUpdate' ; Notes=$installerType }) | Out-Null
        continue
    }

    # Prepare working dirs (structured): Working\<Publisher>\<AppName>\<Version>\Download
    # Sanitize components
    $pubSafe = $publisher
    if (-not $pubSafe -or -not $pubSafe.Trim()) { $pubSafe = 'UnknownPublisher' }
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $pubSafe = -join ($pubSafe.ToCharArray() | ForEach-Object { if ($invalid -contains $_) { '_' } else { $_ } })
    $appSafe = -join ($resolvedName.ToCharArray() | ForEach-Object { if ($invalid -contains $_) { '_' } else { $_ } })
    $verSafe = -join ($wingetVersion.ToCharArray() | ForEach-Object { if ($invalid -contains $_) { '_' } else { $_ } })
    # Normalize trailing dots/spaces to avoid Windows path normalization issues (e.g., 'Inc.' -> 'Inc')
    $pubSafe = $pubSafe.Trim().TrimEnd('.').TrimEnd(' ')
    $appSafe = $appSafe.Trim().TrimEnd('.').TrimEnd(' ')
    $verSafe = $verSafe.Trim().TrimEnd('.').TrimEnd(' ')

    $pubRoot    = Ensure-Dir (Join-Path $WorkingRoot $pubSafe)
    $appWork    = Ensure-Dir (Join-Path $pubRoot $appSafe)
    $verRoot    = Ensure-Dir (Join-Path $appWork $verSafe)
    $downloadDir = Ensure-Dir (Join-Path $verRoot 'Download')
    # Normalize SourceForge URL to direct mirror so filename isn't just 'download'
    try {
        if ($installerUrl -match '^(?i)https?://sourceforge\.net/projects?/([^/]+)/files/(.+?)/download/?$') {
            $proj = $matches[1]; $pathSegs = $matches[2]
            $sfDirect = "https://downloads.sourceforge.net/project/$proj/$pathSegs"
            Write-Log ("SourceForge link detected; normalized to direct: {0}" -f $sfDirect) 'INFO'
            $installerUrl = $sfDirect
        }
    } catch {}

    # Derive a safe filename from URL (ignore query)
    try { $installerUri = [Uri]$installerUrl } catch { $installerUri = $null }
    if ($installerUri) {
        $installerName = [IO.Path]::GetFileName($installerUri.LocalPath)
    } else {
        $installerName = Split-Path -Leaf ($installerUrl -split '\?')[0]
    }
    # Fallback: handle cases where filename still resolves to 'download'
    if ([string]::IsNullOrWhiteSpace($installerName) -or $installerName -ieq 'download') {
        try {
            $parts = ($installerUrl -split '\?')[0].TrimEnd('/') -split '/'
            if ($parts.Count -ge 1) { $installerName = $parts[-1] }
        } catch {}
    }
    # Sanitize invalid filename chars
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $installerName = -join ($installerName.ToCharArray() | ForEach-Object { if ($invalid -contains $_) { '_' } else { $_ } })
    Write-Log ("Using installer file name: {0}" -f $installerName) 'DEBUG'
    $installerPath = Join-Path $downloadDir $installerName

    Download-File -Url $installerUrl -Destination $installerPath -WingetId $wingetId

    # Ensure/normalize MSI ProductCode prior to script generation so uninstall.ps1 bakes in msiexec /x {ProductCode}
    try {
        function __NormalizePc([Parameter(ValueFromPipeline=$true)]$pcIn) {
            if ($null -eq $pcIn) { return $null }
            if ($pcIn -is [System.Collections.IEnumerable] -and -not ($pcIn -is [string])) {
                foreach ($x in $pcIn) {
                    $s = [string]$x
                    if (-not [string]::IsNullOrWhiteSpace($s)) { $pcIn = $s; break }
                }
            }
            $s = [string]$pcIn
            if ([string]::IsNullOrWhiteSpace($s)) { return $null }
            $s = $s.Trim()
            if ($s -match '^\{[0-9A-Fa-f-]+\}$') { return $s }
            if ($s -match '^[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}$') { return "{${s}}" }
            return $s
        }

        # Initialize productCode to null; enforce MSI-only policy (never from winget)
        $productCode = $null
        if ($installerName -match '\.msi$') {
            $pcRaw = Get-MsiProductCodeFromFile $installerPath
            $productCode = __NormalizePc $pcRaw
            if ($productCode) {
                Write-Log ("Resolved MSI ProductCode from file (pre-gen): {0}" -f $productCode) 'INFO'
            } else {
                Write-Log ("MSI ProductCode could not be derived from file at '{0}'" -f $installerPath) 'WARN'
            }
        }
    } catch {
        Write-Log ("Pre-generation ProductCode normalization failed: {0}" -f $_.Exception.Message) 'WARN'
    }

    # Generate dynamic install.ps1 based on recipe ForceTaskClose + InstallArgs, then wrap Download with install.ps1 as setup
    # Compute NotificationPopup (minutes-only) and deferral settings (under NotificationPopup)
    $notifEnabled = $false
    try { if ($script:Config -and $script:Config.Notification -and $script:Config.Notification.Defaults -and ($null -ne $script:Config.Notification.Defaults.Enabled)) { $notifEnabled = [bool]$script:Config.Notification.Defaults.Enabled } } catch {}
    $notifTimeout = 120
    try { if ($script:Config -and $script:Config.Notification -and $script:Config.Notification.Defaults -and $script:Config.Notification.Defaults.TimerMinutes) { $notifTimeout = [int]$script:Config.Notification.Defaults.TimerMinutes * 60 } } catch {}
    try {
        $np = $recipeJson.NotificationPopup
        if ($np) {
            try { if ($np.PSObject.Properties.Name -contains 'Enabled') { $notifEnabled = [bool]$np.Enabled } } catch {}
            try {
                if ($np.PSObject.Properties.Name -contains 'NotificationTimerInMinutes') {
                    $mins = [int]$np.NotificationTimerInMinutes
                    if ($mins -le 0) { $mins = 2 }
                    $notifTimeout = $mins * 60
                } else {
                    $notifTimeout = 2 * 60
                }
            } catch {}
        }
    } catch {}
    $deferralEnabled = $true
    $deferralHours = 24
    try {
        if ($script:Config -and $script:Config.Notification -and $script:Config.Notification.Defaults) {
            try { if ($script:Config.Notification.Defaults.PSObject.Properties.Name -contains 'DeferralEnabled') { $deferralEnabled = [bool]$script:Config.Notification.Defaults.DeferralEnabled } } catch {}
            try { if ($script:Config.Notification.Defaults.PSObject.Properties.Name -contains 'DeferralHoursAllowed' -and $script:Config.Notification.Defaults.DeferralHoursAllowed -ne $null) { $deferralHours = [int]$script:Config.Notification.Defaults.DeferralHoursAllowed } } catch {}
        }
    } catch {}
    try {
        if ($np) {
            try {
                if ($np.PSObject.Properties.Name -contains 'DeferralEnabled') {
                    $deferralEnabled = [bool]$np.DeferralEnabled
                }
            } catch {}
            try {
                if ($np.PSObject.Properties.Name -contains 'DeferralHoursAllowed' -and $np.DeferralHoursAllowed -ne $null) {
                    $deferralHours = [int]$np.DeferralHoursAllowed
                }
            } catch {}
        }
    } catch {}

    # Compute total deferral horizon from the longest ring deadline in days + configured hours
    $maxDelayDays = 0
    try {
        $ringsForDef = Parse-RingsFromRecipe -RecipeJson $recipeJson
        if ($ringsForDef -and $ringsForDef.Count -gt 0) {
            $maxDelayDays = ($ringsForDef | ForEach-Object { try { [int]$_.DelayDays } catch { 0 } } | Measure-Object -Maximum).Maximum
            if ($null -eq $maxDelayDays) { $maxDelayDays = 0 }
        }
    } catch { $maxDelayDays = 0 }
    $deferralHoursTotal = ([int]$deferralHours) + ([int]$maxDelayDays * 24)

    Generate-InstallScript -VersionRoot $verRoot -DownloadDir $downloadDir -InstallerName $installerName -InstallArgs $installArgsFromRecipe -ForceTaskCloseSpec $forceTaskCloseSpec -AppNameForLogs $resolvedName -AppVersionForLogs $wingetVersion -NotificationPopupFlag $notifEnabled -ProductCode $productCode -ForceUninstallFlag ([bool]$recipeJson.ForceUninstall) -UninstallArgsPre $uninstallArgsFromRecipe -NotificationTimeoutSeconds $notifTimeout -DeferralHoursAllowed $deferralHoursTotal -DeferralAllowed $deferralEnabled
    Generate-UninstallScript -VersionRoot $verRoot -DownloadDir $downloadDir -InstallerName $installerName -UninstallArgs $uninstallArgsFromRecipe -ForceTaskCloseSpec $forceTaskCloseSpec -ProductCode $productCode -AppNameForLogs $resolvedName -AppVersionForLogs $wingetVersion

    # Generate detection script file for both PackageOnly and full runs
    $null = Generate-DetectionScriptFile -AppName $resolvedName -RequiredVersion $wingetVersion -ProductCode $productCode -VersionRootPath $verRoot
# Generate requirement script file for both PackageOnly and full runs
$null = Update-RequirementRuleIfPossible -AppId $null -AppName $resolvedName -VersionRootPath $verRoot
# Generate NOT-installed requirement script for primary (used only in FullRun application)
$reqNotInstalledPath = Generate-RequirementNotInstalledScript -AppName $resolvedName -VersionRootPath $verRoot

    $outDir  = Ensure-Dir (Join-Path $verRoot 'Output')
    $outDirPkg = Ensure-Dir (Join-Path $outDir 'Package')
    $intunewin = Wrap-IntuneWin -SourceDir $downloadDir -SetupFileName 'install.ps1' -OutputDir $outDirPkg

    if ($script:EffectivePackageOnly) {
        Write-Log ("PackageOnly: Skipping upload. Wrapped file at: {0}" -f $intunewin) 'INFO'
        $summary.Add([PSCustomObject]@{ App=$resolvedName; Intune=$currentVersion; Winget=$wingetVersion; Action='PackagedOnly' ; Notes=$installerType }) | Out-Null
        continue
    }

    # Upload and update content (capture pre-upload snapshot for verification)
    $preSnap = $null
    try {
        $preSnap = Get-IntuneAppSnapshot -AppId $intuneAppId
        Write-Log ("Pre-upload snapshot: displayVersion='{0}', contentVersion='{1}'" -f $preSnap.DisplayVersion, $preSnap.ContentVersion) 'DEBUG'
    } catch {
        Write-Log ("Pre-upload snapshot failed: {0}" -f $_.Exception.Message) 'WARN'
    }

    $preCommitted = $null
    $preModuleSize = $null
    try {
        $preCommitted = $preSnap.ContentVersion
        $preModuleSize = Get-AppModuleSize -AppObject $app
        $localSizePre = ([int64](Get-Item -LiteralPath $intunewin -ErrorAction SilentlyContinue).Length)
        Write-Log ("Pre-upload Module Snapshot: committedContentVersion='{0}', moduleSizeBytes='{1}', localIntuneWinBytes='{2}'" -f $preCommitted, $preModuleSize, $localSizePre) 'DEBUG'
    } catch {
        Write-Log ("Pre-upload module snapshot failed: {0}" -f $_.Exception.Message) 'WARN'
    }

# Build install/uninstall commands for in-function update (merge2 alignment)
# MSI: only CustomArgs; EXE: InstallArgs + CustomArgs
$installCmd = $null
$uninstallCmd = $null

# Build effective install args from InstallArgs only (CustomArgs removed)
$argsEffective = $null
if ($installArgsFromRecipe -and $installArgsFromRecipe.Trim()) { $argsEffective = $installArgsFromRecipe.Trim() }

if (($installerType -eq 'msi') -or ($installerName -match '\.msi$')) {
    # MSI install: no default /qn; include any needed flags in InstallArgs
    $installCmd = "msiexec.exe /i `"$installerName`""
    if ($argsEffective) { $installCmd += " $argsEffective" }

    # Ensure ProductCode (derive from MSI file if missing from winget)
    if (-not $productCode -or [string]::IsNullOrWhiteSpace($productCode)) {
        $pc = Get-MsiProductCodeFromFile $installerPath
        if ($pc) {
            $productCode = $pc
            Write-Log ("Resolved MSI ProductCode from file: {0}" -f $productCode) 'INFO'
        }
    }

    # MSI uninstall: no default /qn; append UninstallArgs if provided
    if ($productCode) {
        $uninstallCmd = "msiexec.exe /x $productCode"
        if ($uninstallArgsFromRecipe -and $uninstallArgsFromRecipe.Trim()) { $uninstallCmd += " $uninstallArgsFromRecipe" }
    } elseif ($uninstallArgsFromRecipe -and $uninstallArgsFromRecipe.Trim()) {
        $uninstallCmd = $uninstallArgsFromRecipe
    } else {
        Write-Log "MSI ProductCode unavailable and no UninstallArgs provided; leaving uninstall unchanged." 'WARN'
    }
} else {
    # EXE install: InstallArgs only
    $installCmd = "`"$installerName`""
    if ($argsEffective) { $installCmd += " $argsEffective" }
    if ($uninstallArgsFromRecipe -and $uninstallArgsFromRecipe.Trim()) {
        $uninstallCmd = $uninstallArgsFromRecipe
    }
}

# Honor UseScriptCommandLines from config
$useScriptCmds = $true
try { if ($script:Config -and $script:Config.PackagingDefaults -and ($null -ne $script:Config.PackagingDefaults.UseScriptCommandLines)) { $useScriptCmds = [bool]$script:Config.PackagingDefaults.UseScriptCommandLines } } catch {}
if ($useScriptCmds) {
    $installCmd = 'powershell.exe -ExecutionPolicy Bypass -File "install.ps1"'
    $uninstallCmd = 'powershell.exe -ExecutionPolicy Bypass -File "uninstall.ps1"'
    Write-Log ("Install command overridden to: {0}" -f $installCmd) 'INFO'
    Write-Log ("Uninstall command set to: {0}" -f $uninstallCmd) 'INFO'
} else {
    Write-Log "Using vendor command lines (no script override)." 'INFO'
}
$didCommandsAtUpload = $true
$priUploadSucceeded = $true
$priUploadError = $null
try {
    Update-IntuneAppContent -AppId $intuneAppId -IntunewinPath $intunewin -InstallCommandLine $installCmd -UninstallCommandLine $uninstallCmd
} catch {
    $priUploadSucceeded = $false
    $priUploadError = $_.Exception.Message
    Write-Log ("Primary Update-IntuneAppContent failed: {0}" -f $priUploadError) 'ERROR'
}
# Immediate read-back to confirm command lines post-upload (since we updated inside Update-IntuneAppContent)
try {
    $verifyCmds = Get-IntuneWin32App -Id $intuneAppId -ErrorAction Stop
    $names = $verifyCmds.PSObject.Properties.Name
    $ic = $null; $uc = $null
    if ($names -contains 'installCommandLine')   { $ic = $verifyCmds.installCommandLine }
    elseif ($names -contains 'InstallCommandLine'){ $ic = $verifyCmds.InstallCommandLine }
    if ($names -contains 'uninstallCommandLine')   { $uc = $verifyCmds.uninstallCommandLine }
    elseif ($names -contains 'UninstallCommandLine'){ $uc = $verifyCmds.UninstallCommandLine }
    $icPrev = if ($ic) { ($ic.Substring(0, [Math]::Min(140, $ic.Length))) } else { '' }
    $ucPrev = if ($uc) { ($uc.Substring(0, [Math]::Min(140, $uc.Length))) } else { '' }
    Write-Log ("InstallCommandLine (post-upload verification): {0}" -f $icPrev) 'INFO'
    if ($uc) { Write-Log ("UninstallCommandLine (post-upload verification): {0}" -f $ucPrev) 'INFO' }
} catch {
    Write-Log ("Failed to re-read app for command line verification after upload: {0}" -f $_.Exception.Message) 'WARN'
}
    $didMetaUpdate = $false

    # Optionally update app install/uninstall command lines (uses InstallArgs + CustomArgs)
    # Update when either UpdateAppProperties is true OR CustomArgs is provided.
    if ($false) {
        # Build effective install args: InstallArgs then CustomArgs
        $effectiveArgsParts = @()
        if ($installArgsFromRecipe -and $installArgsFromRecipe.Trim()) { $effectiveArgsParts += $installArgsFromRecipe.Trim() }
        if ($customArgs -and $customArgs.Trim()) { $effectiveArgsParts += $customArgs.Trim() }
        $effectiveArgs = ($effectiveArgsParts -join ' ').Trim()

        $installCmd = $null
        $uninstallCmd = $null

        if (($installerType -eq 'msi') -or ($installerName -match '\.msi$')) {
            $installCmd = "msiexec.exe /i `"$installerName`" /qn"
            if ($effectiveArgs) { $installCmd += " $effectiveArgs" }

            if ([string]::IsNullOrWhiteSpace($uninstallArgsFromRecipe)) {
                if ($productCode) {
                    $uninstallCmd = "msiexec.exe /x $productCode /qn"
                }
            } else {
                $uninstallCmd = $uninstallArgsFromRecipe
            }
        } else {
            $installCmd = "`"$installerName`""
            if ($effectiveArgs) { $installCmd += " $effectiveArgs" }
            if ($uninstallArgsFromRecipe -and $uninstallArgsFromRecipe.Trim()) {
                $uninstallCmd = $uninstallArgsFromRecipe
            }
        }

        if ($installCmd) {
            Write-Log ("Applying InstallCommandLine: {0}" -f $installCmd) 'INFO'
        }
        if ($uninstallCmd) {
            Write-Log ("Applying UninstallCommandLine: {0}" -f $uninstallCmd) 'INFO'
        }

        $cmdSet = Get-Command -Name Set-IntuneWin32App -ErrorAction SilentlyContinue
        if ($cmdSet) {
            try {
                if ($uninstallCmd) {
                    Set-IntuneWin32App -Id $intuneAppId -InstallCommandLine $installCmd -UninstallCommandLine $uninstallCmd -ErrorAction Stop | Out-Null
                } else {
                    Set-IntuneWin32App -Id $intuneAppId -InstallCommandLine $installCmd -ErrorAction Stop | Out-Null
                }
                Write-Log "Updated app command line properties." 'INFO'
            } catch {
                Write-Log ("Failed to update app command lines: {0}" -f $_.Exception.Message) 'WARN'
            }
        } else {
            Write-Log "Set-IntuneWin32App cmdlet not found; skipping command line property update." 'WARN'
        }
    }


    # Verify upload via contentVersion/displayVersion, and ensure module-reported size changed (no local .intunewin size check)
    if ($SkipVerify) {
        Write-Log "SkipVerify set; skipping post-upload verification." 'WARN'
    } else {
        $ok = $false
        try {
            $ok = Verify-IntuneUpload -AppId $intuneAppId `
                 -TargetDisplayVersion $wingetVersion `
                 -PreSnapshot $preSnap `
                 -TimeoutSeconds $VerifyTimeoutSeconds `
                 -IntervalSeconds $VerifyIntervalSeconds `
                 -Strict:$StrictVerify
        } catch {
            Write-Log ("Verify-IntuneUpload threw: {0}" -f $_.Exception.Message) 'WARN'
        }

        # Additional check: ensure module-reported content size changed vs pre-check (ignore local .intunewin size)
        if ($ok -and ($preModuleSize -ne $null)) {
            try {
                $postAppForSize = Get-IntuneWin32App -Id $intuneAppId -ErrorAction Stop
                $postSize = Get-AppModuleSize -AppObject $postAppForSize
                Write-Log ("Size compare: pre={0} post={1}" -f $preModuleSize, $postSize) 'DEBUG'
                if ($postSize -ne $null -and $postSize -eq $preModuleSize) {
                    Write-Log "Verification: committed/content updated but size is unchanged; treating as failure per policy." 'WARN'
                    $ok = $false
                }
            } catch {
                Write-Log ("Size compare check failed: {0}" -f $_.Exception.Message) 'WARN'
            }
        }

        if (-not $ok) {
            if ($StrictVerify) {
                Stop-WithError ("Module upload verification failed for app {0}. Content version did not advance or size did not change." -f $intuneAppId)
            } else {
                Write-Log "Module verification did not pass; continuing due to non-strict mode." 'WARN'
            }
        }

        # Primary success gating: treat upload/verify failure as hard failure (no metadata/assignments)
        $priSucceeded = $true
        if ($null -eq $priUploadSucceeded) { $priUploadSucceeded = $true }
        $priSucceeded = $priUploadSucceeded -and ($SkipVerify -or $ok)
        if (-not $priSucceeded) {
            $stage = if ($priUploadSucceeded) { 'PrimaryVerify' } else { 'PrimaryUpload' }
            $errText = if ($priUploadSucceeded) { "Primary verification failed (content version did not advance or size did not change)." } else { $priUploadError }
            $failures.Add([pscustomobject]@{ App=$resolvedName; WingetId=$wingetId; Stage=$stage; ErrorMessage=$errText }) | Out-Null
            $summary.Add([PSCustomObject]@{ App=$resolvedName; Intune=$currentVersion; Winget=$wingetVersion; Action='Failed' ; Notes=$errText }) | Out-Null
            continue
        }

        # Auto-update metadata from winget unless explicitly disabled (AppVersion/DisplayName)
        $cmdSet = Get-Command -Name Set-IntuneWin32App -ErrorAction SilentlyContinue
        if ($cmdSet) {
            try {
                $params = @{ Id = $intuneAppId }
                # Apply AllowAvailableUninstall via module in metadata step removed (handled separately)

                # AppVersion
                if ($wingetVersion -and ($cmdSet.Parameters.Keys -contains 'AppVersion')) {
                    $params['AppVersion'] = $wingetVersion
                }

                # DisplayName "<winget name> <winget version>" (prefer parsed winget Name)
                $resolvedName = if ($wg -and $wg.Name) { $wg.Name } elseif ($appName) { $appName } else { $wingetId }
                $displayNameValue = "$resolvedName $wingetVersion"
                if ($cmdSet.Parameters.Keys -contains 'DisplayName') {
                    $params['DisplayName'] = $displayNameValue
                }

                # Description (trim + conservative length cap)
                if ($description -and ($cmdSet.Parameters.Keys -contains 'Description')) {
                    $descToSet = $description.Trim()
                    if ($descToSet.Length -gt 2000) { $descToSet = $descToSet.Substring(0,2000) }
                    if ($descToSet) { $params['Description'] = $descToSet }
                }

                # Developer (winget Author)
                if ($author -and ($cmdSet.Parameters.Keys -contains 'Developer')) {
                    $params['Developer'] = $author.Trim()
                }

                # InformationUrl (prefer 'InformationUrl', fallback 'InformationURL')
                $infoKey = @('InformationUrl','InformationURL') | Where-Object { $cmdSet.Parameters.Keys -contains $_ } | Select-Object -First 1
                if ($infoKey -and $homepage) {
                    $params[$infoKey] = $homepage.Trim()
                }

# Notes "Winget Updated - YYYY-MM-DD" plus Tags (if available)
if ($cmdSet.Parameters.Keys -contains 'Notes') {
    $notesText = ("Winget Updated - {0}" -f (Get-Date -Format 'yyyy-MM-dd'))
    if ($tags -and $tags.Count -gt 0) {
        try {
            $tagsJoined = ($tags | ForEach-Object { $_.ToString() } | Where-Object { $_ } | Select-Object -Unique) -join ', '
            if ($tagsJoined) { $notesText = ("{0} | Tags: {1}" -f $notesText, $tagsJoined) }
        } catch {}
    }
    $params['Notes'] = $notesText
}

                # Privacy URL (prefer 'PrivacyInformationUrl', fallback 'PrivacyUrl')
                $privKey = @('PrivacyInformationUrl','PrivacyUrl') | Where-Object { $cmdSet.Parameters.Keys -contains $_ } | Select-Object -First 1
                if ($privKey -and $privacyUrl) {
                    $params[$privKey] = $privacyUrl.Trim()
                }

                # Publisher
                if ($publisher -and ($cmdSet.Parameters.Keys -contains 'Publisher')) {
                    $params['Publisher'] = $publisher.Trim()
                }

                if ($params.Keys.Count -gt 1) {
                    Set-IntuneWin32App @params -ErrorAction Stop | Out-Null
                    $didMetaUpdate = $true
                    Write-Log "Auto-updated app metadata: $($params.Keys -join ', ')." 'INFO'

                    # Verify DisplayName if we updated it
                    if ($params.ContainsKey('DisplayName')) {
                        try {
                            $verify = Get-IntuneWin32App -Id $intuneAppId -ErrorAction Stop
                            if ($verify.displayName -eq $params['DisplayName']) {
                                Write-Log "DisplayName verification passed." 'INFO'
                            } else {
                                Write-Log ("DisplayName verification failed. Expected='{0}' Actual='{1}'" -f $params['DisplayName'], $verify.displayName) 'WARN'
                            }
                        } catch {
                            Write-Log ("Failed to re-read app after metadata update: {0}" -f $_.Exception.Message) 'WARN'
                        }
                    }
                } else {
                    Write-Log "No metadata updates applied (disabled via switches, empty values, or module lacks parameters)." 'DEBUG'
                }

# AAU Graph fallback removed (handled by module-only Apply-RecipeAllowAvailableUninstall)
            } catch {
                Write-Log ("Failed to update app metadata: {0}" -f $_.Exception.Message) 'WARN'
            }
        } else {
            Write-Log "Set-IntuneWin32App cmdlet not found; skipping metadata updates." 'WARN'
        }

        # Apply AllowAvailableUninstall per recipe and validate (primary)
        $aauResult = $null
        try {
            if ($null -ne $allowAvailableUninstall) {
                $aauResult = Apply-RecipeAllowAvailableUninstall -AppId $intuneAppId -Desired $allowAvailableUninstall
            }
        } catch {
            Write-Log ("AAU (primary) apply/validate failed: {0}" -f $_.Exception.Message) 'WARN'
        }

        # Log final module snapshot for audit
        try {
            $postApp = Get-IntuneWin32App -Id $intuneAppId -ErrorAction Stop
            $postCommitted = $null
            $names = $postApp.PSObject.Properties.Name
            if ($names -contains 'committedContentVersion') { $postCommitted = $postApp.committedContentVersion }
            elseif ($names -contains 'CommittedContentVersion') { $postCommitted = $postApp.CommittedContentVersion }
            elseif ($names -contains 'contentVersion') { $postCommitted = $postApp.contentVersion }
            elseif ($names -contains 'ContentVersion') { $postCommitted = $postApp.ContentVersion }
            $postSize = Get-AppModuleSize -AppObject $postApp
            $localSize = ([int64](Get-Item -LiteralPath $intunewin -ErrorAction Stop).Length)
            Write-Log ("Post-upload Module Snapshot: committedContentVersion='{0}', moduleSizeBytes='{1}', localIntuneWinBytes='{2}'" -f $postCommitted, $postSize, $localSize) 'INFO'
        } catch {
            Write-Log ("Post-verify module snapshot failed: {0}" -f $_.Exception.Message) 'WARN'
        }
    }

# Primary NotInstalled requirement rule is applied after detection update to avoid overwrite.

# Secondary target processing (mirror of primary, simple)
    if ($secondaryAppId) {
        Write-Log ("Secondary target detected: {0}" -f $secondaryAppId) 'INFO'
        # Pre-upload snapshot
        $preSnapSec = $null
        try {
            $preSnapSec = Get-IntuneAppSnapshot -AppId $secondaryAppId
            Write-Log ("Pre-upload snapshot (secondary): displayVersion='{0}', contentVersion='{1}'" -f $preSnapSec.DisplayVersion, $preSnapSec.ContentVersion) 'DEBUG'
        } catch {
            Write-Log ("Pre-upload snapshot (secondary) failed: {0}" -f $_.Exception.Message) 'WARN'
        }

        $preCommittedSec = $null
        $preModuleSizeSec = $null
        try {
            $preCommittedSec = $preSnapSec.ContentVersion
            $preModuleSizeSec = if ($secApp) { Get-AppModuleSize -AppObject $secApp } else { $null }
            $localSizePreSec = ([int64](Get-Item -LiteralPath $intunewin -ErrorAction SilentlyContinue).Length)
            Write-Log ("Pre-upload Module Snapshot (secondary): committedContentVersion='{0}', moduleSizeBytes='{1}', localIntuneWinBytes='{2}'" -f $preCommittedSec, $preModuleSizeSec, $localSizePreSec) 'DEBUG'
        } catch {
            Write-Log ("Pre-upload module snapshot (secondary) failed: {0}" -f $_.Exception.Message) 'WARN'
        }

        # Upload content + set commands for secondary (mirror manual usage)
        Ensure-IntuneToken
        Start-Sleep -Seconds 5
        $secUploadSucceeded = $true
        $secUploadError = $null
        try {
            $cmdUpdatePkgSec = Get-Command -Name Update-IntuneWin32AppPackageFile -ErrorAction SilentlyContinue
            if ($cmdUpdatePkgSec) {
                Write-Log "Secondary: Attempting upload via Update-IntuneWin32AppPackageFile (direct) ..." 'INFO'
                Update-IntuneWin32AppPackageFile -Id $secondaryAppId -FilePath $intunewin -ErrorAction Stop | Out-Null
                if ($installCmd -or $uninstallCmd) {
                    try {
                        $bodySec = @{ '@odata.type' = '#microsoft.graph.win32LobApp' }
                        if ($installCmd)   { $bodySec['installCommandLine']   = $installCmd }
                        if ($uninstallCmd) { $bodySec['uninstallCommandLine'] = $uninstallCmd }
                        if ($bodySec.Count -gt 1) {
                            Write-Log "Secondary: updating app command lines via Graph PATCH after direct upload." 'INFO'
                            Invoke-GraphJson -Method 'PATCH' -Path "/deviceAppManagement/mobileApps/$secondaryAppId" -Body $bodySec | Out-Null
                        }
                    } catch {
                        Write-Log ("Secondary: command line PATCH failed: {0}" -f $_.Exception.Message) 'WARN'
                    }
                }
            } else {
                Write-Log "Secondary: Update-IntuneWin32AppPackageFile not available; using Update-IntuneAppContent." 'INFO'
                Update-IntuneAppContent -AppId $secondaryAppId -IntunewinPath $intunewin -InstallCommandLine $installCmd -UninstallCommandLine $uninstallCmd
            }
        } catch {
            # Fallback once to Update-IntuneAppContent if direct call failed
            try {
                if ($cmdUpdatePkgSec) {
                    Write-Log ("Secondary direct upload failed: {0} - falling back to Update-IntuneAppContent." -f $_.Exception.Message) 'WARN'
                    Update-IntuneAppContent -AppId $secondaryAppId -IntunewinPath $intunewin -InstallCommandLine $installCmd -UninstallCommandLine $uninstallCmd
                } else {
                    throw
                }
            } catch {
                $secUploadError = $_.Exception.Message
                $secUploadSucceeded = $false
                Write-Log ("Secondary upload failed: {0}" -f $secUploadError) 'ERROR'
            }
        }

        # Verify secondary
        $okSec = $false
        if ($secUploadSucceeded) {
            try {
                $okSec = Verify-IntuneUpload -AppId $secondaryAppId `
                         -TargetDisplayVersion $wingetVersion `
                         -PreSnapshot $preSnapSec `
                         -TimeoutSeconds $VerifyTimeoutSeconds `
                         -IntervalSeconds $VerifyIntervalSeconds `
                         -Strict:$StrictVerify
            } catch {
                Write-Log ("Verify-IntuneUpload (secondary) threw: {0}" -f $_.Exception.Message) 'WARN'
            }
        } else {
            Write-Log "Secondary upload did not start or failed; skipping verify to avoid long polling." 'WARN'
        }

        # Additional check (secondary): ensure module-reported content size changed vs pre-check
        if ($okSec -and ($preModuleSizeSec -ne $null)) {
            try {
                $postAppForSizeSec = Get-IntuneWin32App -Id $secondaryAppId -ErrorAction Stop
                $postSizeSec = Get-AppModuleSize -AppObject $postAppForSizeSec
                Write-Log ("Size compare (secondary): pre={0} post={1}" -f $preModuleSizeSec, $postSizeSec) 'DEBUG'
                if ($postSizeSec -ne $null -and $postSizeSec -eq $preModuleSizeSec) {
                    Write-Log "Secondary verification: committed/content updated but size is unchanged; treating as failure per policy." 'WARN'
                    $okSec = $false
                }
            } catch {
                Write-Log ("Size compare check (secondary) failed: {0}" -f $_.Exception.Message) 'WARN'
            }
        }
        if (-not $okSec) {
            $stage = if ($secUploadSucceeded) { 'SecondaryVerify' } else { 'SecondaryUpload' }
            $errText = if ($secUploadSucceeded) { "Secondary verification failed (content version did not advance or size did not change)." } else { $secUploadError }
            $failures.Add([pscustomobject]@{ App=("$resolvedName (Required Updates)"); WingetId=$wingetId; Stage=$stage; ErrorMessage=$errText }) | Out-Null
            $summary.Add([PSCustomObject]@{ App=("$resolvedName (Required Updates)"); Intune=$secCurrentVersion; Winget=$wingetVersion; Action='Failed' ; Notes=$errText }) | Out-Null
        }

        if ($okSec) {
            # Always update metadata on secondary; DisplayName with " - Required Update"
        $cmdSetSec = Get-Command -Name Set-IntuneWin32App -ErrorAction SilentlyContinue
        if ($cmdSetSec) {
            try {
                $paramsSec = @{ Id = $secondaryAppId }
                # Apply AllowAvailableUninstall via module in metadata step (secondary) removed (handled separately)

                if ($wingetVersion -and ($cmdSetSec.Parameters.Keys -contains 'AppVersion')) {
                    $paramsSec['AppVersion'] = $wingetVersion
                }

                $resolvedNameForDisplay = if ($wg -and $wg.Name) { $wg.Name } elseif ($appName) { $appName } else { $wingetId }
                $secSuffix = " - Required Update"
                try {
                    if ($script:Config -and $script:Config.SecondaryRequiredApp -and $script:Config.SecondaryRequiredApp.DisplayNameSuffix) {
                        $secSuffix = [string]$script:Config.SecondaryRequiredApp.DisplayNameSuffix
                    } elseif ($script:Config -and $script:Config.Secondary -and $script:Config.Secondary.DisplayNameSuffix) {
                        $secSuffix = [string]$script:Config.Secondary.DisplayNameSuffix
                    }
                } catch {}
                $displayNameSec = "$resolvedNameForDisplay $wingetVersion$secSuffix"
                if ($cmdSetSec.Parameters.Keys -contains 'DisplayName') {
                    $paramsSec['DisplayName'] = $displayNameSec
                }

                if ($description -and ($cmdSetSec.Parameters.Keys -contains 'Description')) {
                    $descToSetSec = $description.Trim()
                    if ($descToSetSec.Length -gt 2000) { $descToSetSec = $descToSetSec.Substring(0,2000) }
                    if ($descToSetSec) { $paramsSec['Description'] = $descToSetSec }
                }
                if ($author -and ($cmdSetSec.Parameters.Keys -contains 'Developer')) {
                    $paramsSec['Developer'] = $author.Trim()
                }
                $infoKeySec = @('InformationUrl','InformationURL') | Where-Object { $cmdSetSec.Parameters.Keys -contains $_ } | Select-Object -First 1
                if ($infoKeySec -and $homepage) { $paramsSec[$infoKeySec] = $homepage.Trim() }
                $privKeySec = @('PrivacyInformationUrl','PrivacyUrl') | Where-Object { $cmdSetSec.Parameters.Keys -contains $_ } | Select-Object -First 1
                if ($privKeySec -and $privacyUrl) { $paramsSec[$privKeySec] = $privacyUrl.Trim() }
                if ($publisher -and ($cmdSetSec.Parameters.Keys -contains 'Publisher')) { $paramsSec['Publisher'] = $publisher.Trim() }
                if ($cmdSetSec.Parameters.Keys -contains 'Notes') {
                    $notesTextSec = ("Winget Updated - {0}" -f (Get-Date -Format 'yyyy-MM-dd'))
                    if ($tags -and $tags.Count -gt 0) {
                        try {
                            $tagsJoinedSec = ($tags | ForEach-Object { $_.ToString() } | Where-Object { $_ } | Select-Object -Unique) -join ', '
                            if ($tagsJoinedSec) { $notesTextSec = ("{0} | Tags: {1}" -f $notesTextSec, $tagsJoinedSec) }
                        } catch {}
                    }
                    $paramsSec['Notes'] = $notesTextSec
                }

                if ($paramsSec.Keys.Count -gt 1) {
                    Set-IntuneWin32App @paramsSec -ErrorAction Stop | Out-Null
                    Write-Log "Secondary: auto-updated app metadata." 'INFO'
                } else {
                    Write-Log "Secondary: no metadata fields available to update (module parameter support missing)." 'WARN'
                }
            } catch {
                Write-Log ("Secondary: failed to update app metadata: {0}" -f $_.Exception.Message) 'WARN'
            }
        } else {
            Write-Log "Secondary: Set-IntuneWin32App cmdlet not found; skipping metadata updates." 'WARN'
        }

# AAU Graph fallback (secondary) removed (handled by module-only Apply-RecipeAllowAvailableUninstall)

        # Apply AllowAvailableUninstall per recipe and validate (secondary)
        $aauResultSec = $null
        try {
            if ($null -ne $allowAvailableUninstall) {
                $aauResultSec = Apply-RecipeAllowAvailableUninstall -AppId $secondaryAppId -Desired $allowAvailableUninstall
            }
        } catch {
            Write-Log ("AAU (secondary) apply/validate failed: {0}" -f $_.Exception.Message) 'WARN'
        }

        # Post snapshot (secondary) for audit
        try {
            $postAppSec = Get-IntuneWin32App -Id $secondaryAppId -ErrorAction Stop
            $postCommittedSec = $null
            $namesSec = $postAppSec.PSObject.Properties.Name
            if ($namesSec -contains 'committedContentVersion') { $postCommittedSec = $postAppSec.committedContentVersion }
            elseif ($namesSec -contains 'CommittedContentVersion') { $postCommittedSec = $postAppSec.CommittedContentVersion }
            elseif ($namesSec -contains 'contentVersion') { $postCommittedSec = $postAppSec.contentVersion }
            elseif ($namesSec -contains 'ContentVersion') { $postCommittedSec = $postAppSec.ContentVersion }
            $postSizeSec = Get-AppModuleSize -AppObject $postAppSec
            $localSizeSec = ([int64](Get-Item -LiteralPath $intunewin -ErrorAction Stop).Length)
            Write-Log ("Post-upload Module Snapshot (secondary): committedContentVersion='{0}', moduleSizeBytes='{1}', localIntuneWinBytes='{2}'" -f $postCommittedSec, $postSizeSec, $localSizeSec) 'INFO'
        } catch {
            Write-Log ("Secondary: post-verify module snapshot failed: {0}" -f $_.Exception.Message) 'WARN'
        }

$secAction = if (($null -ne $allowAvailableUninstall) -and $aauResultSec -and (-not $aauResultSec.Succeeded)) { 'UpdatedWithErrors' } else { 'UpdatedSecondary' }
$secNotes = $installerType
if (($null -ne $allowAvailableUninstall) -and $aauResultSec -and (-not $aauResultSec.Succeeded)) {
    $secNotes = ("{0} | AAU validation failed (desired={1}, after={2})" -f $secNotes, $allowAvailableUninstall, $aauResultSec.After)
}
$summary.Add([PSCustomObject]@{ App=("$resolvedName (Required Updates)"); Intune=$secCurrentVersion; Winget=$wingetVersion; Action=$secAction ; Notes=$secNotes }) | Out-Null

        # Secondary ring assignments (nested Rings schema)
        try {
            $ringsParsed = Parse-RingsFromRecipe -RecipeJson $recipeJson
            if ($ringsParsed -and $ringsParsed.Count -gt 0) {
                if ($DryRun -or $script:EffectivePackageOnly) {
                    Write-Log "DryRun/PackageOnly: Rings parsed but assignment changes are skipped in this mode." 'INFO'
                } else {
                    # Remove existing assignments then create new ones per Rings
                    $doClear = $true
                    try {
                        if ($script:Config -and $script:Config.Secondary -and $script:Config.Secondary.AssignmentDefaults -and ($null -ne $script:Config.Secondary.AssignmentDefaults.ClearExistingBeforeAssign)) {
                            $doClear = [bool]$script:Config.Secondary.AssignmentDefaults.ClearExistingBeforeAssign
                        }
                    } catch {}
                    if ($doClear) {
                        Clear-AppAssignmentsGraph -AppId $secondaryAppId
                    } else {
                        Write-Log "Secondary assignments: skipping clear step by config." 'INFO'
                    }
                    $countAssigned = Assign-AppToRingsGraph -AppId $secondaryAppId -Rings $ringsParsed
            $noteText = ("Ring assignments created: {0}" -f $countAssigned)
$summary.Add([PSCustomObject]@{ App=("$resolvedName (Required Updates)"); Intune=$secCurrentVersion; Winget=$wingetVersion; Action='AssignmentsUpdatedSecondary' ; Notes=$noteText }) | Out-Null

            # Append ring summary to the UpdatedSecondary row's Notes for email visibility
            try {
                $ringSummary = Build-RingSummary -Rings $ringsParsed
                if ($ringSummary -and $ringSummary.Trim()) {
                    $updatedRow = $summary | Where-Object { $_.App -eq "$resolvedName (Required Updates)" -and $_.Action -eq 'UpdatedSecondary' } | Select-Object -Last 1
                    if ($updatedRow) {
                        $prev = $updatedRow.Notes
                        if ($prev -and $prev.Trim()) {
                            $updatedRow.Notes = ("{0} | Rings: {1}" -f $prev, $ringSummary)
                        } else {
                            $updatedRow.Notes = ("Rings: {0}" -f $ringSummary)
                        }
                    }
                }
            } catch {
                Write-Log ("Failed to append ring summary to email notes: {0}" -f $_.Exception.Message) 'WARN'
            }
                }
            } else {
                Write-Log "No ring assignments specified for secondary; leaving assignments unchanged." 'INFO'
            }
        } catch {
            Write-Log ("Secondary ring assignment flow failed: {0}" -f $_.Exception.Message) 'ERROR'
        }

        # Secondary detection + requirement rule updates (parity with primary; requirement = presence-only)
        if (-not $NoUpdateDetection) {
            try {
                Update-DetectionScriptIfPossible -AppId $secondaryAppId -AppName $resolvedName -RequiredVersion $wingetVersion -ProductCode $productCode -VersionRootPath $verRoot
            } catch {
                Write-Log ("Secondary: detection update failed: {0}" -f $_.Exception.Message) 'WARN'
            }
            try {
                Write-Log "Secondary: requirement script generation started ..." 'INFO'
                $reqPath = Update-RequirementRuleIfPossible -AppId $secondaryAppId -AppName $resolvedName -VersionRootPath $verRoot
                if ($reqPath) {
                    try {
                        Update-RequirementRuleForApp -AppId $secondaryAppId -RequirementScriptPath $reqPath
                    } catch {
                        Write-Log ("Secondary: requirement rule update failed (module+Graph attempts): {0}" -f $_.Exception.Message) 'WARN'
                    }
                } else {
                    Write-Log "Secondary: requirement script path not returned; skipping requirement rule update." 'WARN'
                }
            } catch {
                Write-Log ("Secondary: requirement script generation failed: {0}" -f $_.Exception.Message) 'WARN'
            }
        } else {
            Write-Log "Secondary: NoUpdateDetection set; skipping detection and requirement updates." 'DEBUG'
        }
    } # end if ($okSec)
    }

    # Post-success default updates (Install/Uninstall commands + Detection), only after verify success AND metadata updated
    if ((($ok) -or $SkipVerify) -and $didMetaUpdate) {
        # Install/Uninstall command lines by default (unless -NoUpdateCmds)
        if (-not $NoUpdateCmds -and -not $didCommandsAtUpload) {
            # MSI: only CustomArgs; EXE: InstallArgs + CustomArgs
            $installCmd = $null
            $uninstallCmd = $null

            # Build effective install args from InstallArgs only (CustomArgs removed)
            $argsEffective = $null
            if ($installArgsFromRecipe -and $installArgsFromRecipe.Trim()) { $argsEffective = $installArgsFromRecipe.Trim() }

            if (($installerType -eq 'msi') -or ($installerName -match '\.msi$')) {
                # MSI install: no default /qn; include any needed flags in InstallArgs
                $installCmd = "msiexec.exe /i `"$installerName`""
                if ($argsEffective) { $installCmd += " $argsEffective" }

                # Ensure ProductCode (derive from MSI file if missing from winget)
                if (-not $productCode -or [string]::IsNullOrWhiteSpace($productCode)) {
                    $pc = Get-MsiProductCodeFromFile $installerPath
                    if ($pc) {
                        $productCode = $pc
                        Write-Log ("Resolved MSI ProductCode from file: {0}" -f $productCode) 'INFO'
                    }
                }

                # MSI uninstall: no default /qn; append UninstallArgs if provided
                if ($productCode) {
                    $uninstallCmd = "msiexec.exe /x $productCode"
                    if ($uninstallArgsFromRecipe -and $uninstallArgsFromRecipe.Trim()) { $uninstallCmd += " $uninstallArgsFromRecipe" }
                } elseif ($uninstallArgsFromRecipe -and $uninstallArgsFromRecipe.Trim()) {
                    $uninstallCmd = $uninstallArgsFromRecipe
                } else {
                    Write-Log "MSI ProductCode unavailable and no UninstallArgs provided; leaving uninstall unchanged." 'WARN'
                }
            } else {
                # EXE install: InstallArgs only
                $installCmd = "`"$installerName`""
                if ($argsEffective) { $installCmd += " $argsEffective" }
                if ($uninstallArgsFromRecipe -and $uninstallArgsFromRecipe.Trim()) {
                    $uninstallCmd = $uninstallArgsFromRecipe
                }
            }

            $usedModule = $false
            $cmdSet = Get-Command -Name Set-IntuneWin32App -ErrorAction SilentlyContinue
            if ($cmdSet) {
                $hasInstall = ($cmdSet.Parameters.Keys -contains 'InstallCommandLine')
                $hasUninst  = ($cmdSet.Parameters.Keys -contains 'UninstallCommandLine')
                if ($hasInstall -and (($uninstallCmd -and $hasUninst) -or (-not $uninstallCmd))) {
                    try {
                        if ($uninstallCmd -and $hasUninst) {
                            Set-IntuneWin32App -Id $intuneAppId -InstallCommandLine $installCmd -UninstallCommandLine $uninstallCmd -ErrorAction Stop | Out-Null
                        } else {
                            Set-IntuneWin32App -Id $intuneAppId -InstallCommandLine $installCmd -ErrorAction Stop | Out-Null
                        }
                        Write-Log "Updated app command line properties via Set-IntuneWin32App (post-success)." 'INFO'
                        $usedModule = $true
                    } catch {
                        Write-Log ("Set-IntuneWin32App command line update failed: {0}" -f $_.Exception.Message) 'WARN'
                    }
                } else {
                    Write-Log "Set-IntuneWin32App lacks Install/UninstallCommandLine parameters; falling back to Graph PATCH." 'WARN'
                }
            } else {
                Write-Log "Set-IntuneWin32App cmdlet not found; attempting Graph PATCH for command lines." 'WARN'
            }

            if (-not $usedModule) {
                try {
                    $body = @{ '@odata.type' = '#microsoft.graph.win32LobApp' }
                    if ($installCmd)   { $body['installCommandLine']   = $installCmd }
                    if ($uninstallCmd) { $body['uninstallCommandLine'] = $uninstallCmd }
                    if ($body.Count -gt 1) {
                        Invoke-GraphJson -Method 'PATCH' -Path "/deviceAppManagement/mobileApps/$intuneAppId" -Body $body | Out-Null
                        Write-Log "Updated app command line properties via Graph PATCH (post-success)." 'INFO'
                    } else {
                        Write-Log "No command line values to set; Graph PATCH skipped." 'DEBUG'
                    }
                } catch {
                    Write-Log ("Graph PATCH for command lines failed: {0}" -f $_.Exception.Message) 'ERROR'
                }
            }

            # Read-back verification (log preview of command lines)
            try {
                $verifyCmds = Get-IntuneWin32App -Id $intuneAppId -ErrorAction Stop
                $names = $verifyCmds.PSObject.Properties.Name
                $ic = $null; $uc = $null
                if ($names -contains 'installCommandLine')   { $ic = $verifyCmds.installCommandLine }
                elseif ($names -contains 'InstallCommandLine'){ $ic = $verifyCmds.InstallCommandLine }
                if ($names -contains 'uninstallCommandLine')   { $uc = $verifyCmds.uninstallCommandLine }
                elseif ($names -contains 'UninstallCommandLine'){ $uc = $verifyCmds.UninstallCommandLine }
                $icPrev = if ($ic) { ($ic.Substring(0, [Math]::Min(140, $ic.Length))) } else { '' }
                $ucPrev = if ($uc) { ($uc.Substring(0, [Math]::Min(140, $uc.Length))) } else { '' }
                Write-Log ("InstallCommandLine (preview): {0}" -f $icPrev) 'INFO'
                if ($uc) { Write-Log ("UninstallCommandLine (preview): {0}" -f $ucPrev) 'INFO' }
            } catch {
                Write-Log ("Failed to re-read app for command line verification: {0}" -f $_.Exception.Message) 'WARN'
            }
        }

        # Detection update by default (unless -NoUpdateDetection)
        if (-not $NoUpdateDetection) {
            Update-DetectionScriptIfPossible -AppId $intuneAppId -AppName $resolvedName -RequiredVersion $wingetVersion -ProductCode $productCode -VersionRootPath $verRoot
        } else {
            Write-Log "NoUpdateDetection set; skipping detection update." 'DEBUG'
        }
    } else {
        Write-Log "Post-success updates skipped (verify/meta not confirmed); leaving commands/detection unchanged this run." 'DEBUG'
    }

# Apply primary NOT-installed requirement rule in FullRun (after detection update so it isn't overwritten)
try {
    if (-not $script:EffectivePackageOnly) {
        if ($reqNotInstalledPath -and (Test-Path -LiteralPath $reqNotInstalledPath)) {
            Update-RequirementRuleForApp -AppId $intuneAppId -RequirementScriptPath $reqNotInstalledPath
            Write-Log "Primary: requirement rule (NotInstalled) applied." 'INFO'
        } else {
            Write-Log "Primary: requirement script (NotInstalled) not found; skipping requirement application." 'WARN'
        }
    } else {
        Write-Log "Primary: PackageOnly; requirement application skipped." 'DEBUG'
    }
} catch {
    Write-Log ("Primary: requirement rule (NotInstalled) apply failed: {0}" -f $_.Exception.Message) 'WARN'
}

    # Final AAU enforcement to guarantee final state (after any metadata/command/detection updates)
    try {
        if ($null -ne $allowAvailableUninstall -and -not $DryRun -and -not $script:EffectivePackageOnly) {
            if ($intuneAppId) {
                try {
                    $null = Apply-RecipeAllowAvailableUninstall -AppId $intuneAppId -Desired $allowAvailableUninstall
                } catch {
                    Write-Log ("AAU final (primary) apply failed: {0}" -f $_.Exception.Message) 'WARN'
                }
                try {
                    $verifyFinal = Get-IntuneWin32App -Id $intuneAppId -ErrorAction Stop
                    $finalVal = $null
                    $props = $verifyFinal.PSObject.Properties.Name
                    if ($props -contains 'allowAvailableUninstall') { $finalVal = [bool]$verifyFinal.allowAvailableUninstall }
                    elseif ($props -contains 'AllowAvailableUninstall') { $finalVal = [bool]$verifyFinal.AllowAvailableUninstall }
                    Write-Log ("AAU final (primary): {0}" -f $finalVal) 'INFO'
                } catch {
                    Write-Log ("AAU final (primary) read-back failed: {0}" -f $_.Exception.Message) 'WARN'
                }
            }
            if ($secondaryAppId -and $okSec) {
                try {
                    $null = Apply-RecipeAllowAvailableUninstall -AppId $secondaryAppId -Desired $allowAvailableUninstall
                } catch {
                    Write-Log ("AAU final (secondary) apply failed: {0}" -f $_.Exception.Message) 'WARN'
                }
                try {
                    $verifyFinalSec = Get-IntuneWin32App -Id $secondaryAppId -ErrorAction Stop
                    $finalValSec = $null
                    $propsSec = $verifyFinalSec.PSObject.Properties.Name
                    if ($propsSec -contains 'allowAvailableUninstall') { $finalValSec = [bool]$verifyFinalSec.allowAvailableUninstall }
                    elseif ($propsSec -contains 'AllowAvailableUninstall') { $finalValSec = [bool]$verifyFinalSec.AllowAvailableUninstall }
                    Write-Log ("AAU final (secondary): {0}" -f $finalValSec) 'INFO'
                } catch {
                    Write-Log ("AAU final (secondary) read-back failed: {0}" -f $_.Exception.Message) 'WARN'
                }
            }
        }
    } catch {
        Write-Log ("AAU finalization block error: {0}" -f $_.Exception.Message) 'WARN'
    }

# Update primary required assignments' deadline based on Rings max delay from recipe (config-gated)
$deadlineResult = $null
$doPrimaryDeadlineUpdate = $false
try {
    if ($script:Config -and $script:Config.Primary -and $script:Config.Primary.AssignmentDefaults -and ($null -ne $script:Config.Primary.AssignmentDefaults.UpdateDeadlineFromRings)) {
        $doPrimaryDeadlineUpdate = [bool]$script:Config.Primary.AssignmentDefaults.UpdateDeadlineFromRings
    }
} catch {}
if ($doPrimaryDeadlineUpdate) {
    try {
        $deadlineResult = Update-PrimaryRequiredAssignmentDeadlineFromRecipe -AppId $intuneAppId -RecipeJson $recipeJson
    } catch {
        Write-Log ("Primary deadline update step failed: {0}" -f $_.Exception.Message) 'WARN'
    }
} else {
    Write-Log "Primary deadline update: skipped by policy (UpdateDeadlineFromRings=false)." 'INFO'
}
$action = 'Updated'
$notes  = $installerType
if ($deadlineResult -and $deadlineResult.Attempted -gt 0) {
    if (($deadlineResult.Updated -lt $deadlineResult.Attempted) -or $deadlineResult.HadError) {
        $action = 'UpdatedWithErrors'
        $notes = ("{0} | Status: Updated with errors | DeadlineUpdate: updated {1}/{2}" -f $notes, $deadlineResult.Updated, $deadlineResult.Attempted)
    }
}
if (($null -ne $allowAvailableUninstall) -and $aauResult -and (-not $aauResult.Succeeded)) {
    $action = 'UpdatedWithErrors'
    $notes = ("{0} | AAU validation failed (desired={1}, after={2})" -f $notes, $allowAvailableUninstall, $aauResult.After)
}
$summary.Add([PSCustomObject]@{ App=$resolvedName; Intune=$currentVersion; Winget=$wingetVersion; Action=$action ; Notes=$notes }) | Out-Null
    Write-Log "Completed update for $resolvedName to $wingetVersion" 'INFO'
    }
    catch {
        $aname = if ($resolvedName) { $resolvedName } else { $file.BaseName }
        $wid = $wingetId
        $err = $_.Exception.Message
        $failures.Add([pscustomobject]@{ App=$aname; WingetId=$wid; Stage='Processing'; ErrorMessage=$err }) | Out-Null
        Write-Log ("Recipe failed: {0}" -f $err) 'ERROR'
        try {
            $summary.Add([pscustomobject]@{ App=$aname; Intune=$currentVersion; Winget=$wingetVersion; Action='Failed'; Notes=$err }) | Out-Null
        } catch {}
    }
}

# ========== Summary ==========
Write-Log "Run summary:" 'INFO'
$summary | ForEach-Object {
    Write-Log (" - {0}: {1} -> {2} [{3}]" -f $_.App, $_.Intune, $_.Winget, $_.Action) 'INFO'
}

# Optionally export CSV in working root
try {
    $csv = Join-Path $WorkingRoot ("Summary_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date))
    $summary | Export-Csv -LiteralPath $csv -NoTypeInformation -Force
    Write-Log "Summary CSV: $csv" 'INFO'
} catch {
    Write-Log "Failed to export summary CSV: $($_.Exception.Message)" 'WARN'
}

# ===== Email Summary =====
try {
    # Build updates list from summary (include secondary updates; exclude WouldUpdate/PackagedOnly/Skipped)
    $updates = @($summary | Where-Object { $_.Action -in @('Updated','UpdatedSecondary') })
    $updatesWithErrors = @($summary | Where-Object { $_.Action -eq 'UpdatedWithErrors' })
 
    # Send policy (always | updatesOrFailures | failuresOnly | never)
    $policy = 'updatesOrFailures'
    try { if ($script:Config -and $script:Config.Email -and $script:Config.Email.SendPolicy) { $policy = [string]$script:Config.Email.SendPolicy } } catch {}
    switch ($policy.ToLower()) {
        'always' { $shouldSend = $true }
        'never' { $shouldSend = $false }
        'failuresonly' { $shouldSend = ($failures.Count -gt 0) }
        default { $shouldSend = (($updates.Count -gt 0) -or ($failures.Count -gt 0)) }
    }

    if ($EmailEnabled -and $EmailTo -and $EmailFrom -and $SmtpServer -and $shouldSend) {
        # Build HTML rows
        $htmlRowsUpdates = ($updates | ForEach-Object {
            "<tr><td>$($_.App)</td><td>$($_.Intune)</td><td>$($_.Winget)</td><td>$($_.Notes)</td></tr>"
        }) -join "`n"
        if (-not $htmlRowsUpdates) { $htmlRowsUpdates = "<tr><td colspan='4'>None</td></tr>" }

        $htmlRowsUpdatedWithErrors = ($updatesWithErrors | ForEach-Object {
            "<tr><td>$($_.App)</td><td>$($_.Intune)</td><td>$($_.Winget)</td><td>$($_.Notes)</td></tr>"
        }) -join "`n"
        if (-not $htmlRowsUpdatedWithErrors) { $htmlRowsUpdatedWithErrors = "<tr><td colspan='4'>None</td></tr>" }

        $htmlRowsFailures = ($failures | ForEach-Object {
            "<tr><td>$($_.App)</td><td>$($_.WingetId)</td><td>$($_.Stage)</td><td>$($_.ErrorMessage)</td></tr>"
        }) -join "`n"
        if (-not $htmlRowsFailures) { $htmlRowsFailures = "<tr><td colspan='4'>None</td></tr>" }

        $date = Get-Date -Format 'yyyy-MM-dd'
        $subject = ("{0} - Updates: {1}, Failures: {2} ({3})" -f $EmailSubjectPrefix, ($updates.Count), ($failures.Count), $date)

        $body = @"
<html>
<body style='font-family:Segoe UI,Arial,sans-serif;font-size:12px'>
  <h2>Intune AutoPackager Summary</h2>
  <p>Ran on $(Get-Date)</p>

  <h3>Updated Apps ($($updates.Count))</h3>
  <table border='1' cellpadding='4' cellspacing='0'>
    <tr><th>App</th><th>Intune</th><th>Winget</th><th>Notes</th></tr>
    $htmlRowsUpdates
  </table>

  <h3>Updated with Errors ($($updatesWithErrors.Count))</h3>
  <table border='1' cellpadding='4' cellspacing='0'>
    <tr><th>App</th><th>Intune</th><th>Winget</th><th>Notes</th></tr>
    $htmlRowsUpdatedWithErrors
  </table>

  <h3>Failures ($($failures.Count))</h3>
  <table border='1' cellpadding='4' cellspacing='0'>
    <tr><th>App</th><th>WingetId</th><th>Stage</th><th>Error</th></tr>
    $htmlRowsFailures
  </table>
</body>
</html>
"@

        $mail = New-Object System.Net.Mail.MailMessage
        $mail.From = $EmailFrom
        foreach($to in $EmailTo){ if ($to) { [void]$mail.To.Add($to) } }
        $mail.Subject = $subject
        $mail.Body = $body
        $mail.IsBodyHtml = $true
        # Optional CSV attachment per config
        try {
            if ($EmailAttachCsv -and $csv -and (Test-Path -LiteralPath $csv)) {
                [void]$mail.Attachments.Add([System.Net.Mail.Attachment]::new($csv))
            }
        } catch {
            Write-Log ("Unable to attach CSV: {0}" -f $_.Exception.Message) 'WARN'
        }

        # Attach log only on failures; attach a copy to avoid file lock conflicts
        if ($EmailAttachLog -and ($failures.Count -gt 0) -and $LogPath -and (Test-Path -LiteralPath $LogPath)) {
            try {
                $logCopy = Join-Path $WorkingRoot ("AutoPackager_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
                Copy-Item -LiteralPath $LogPath -Destination $logCopy -Force
                [void]$mail.Attachments.Add([System.Net.Mail.Attachment]::new($logCopy))
            } catch {
                Write-Log ("Unable to attach log: {0}" -f $_.Exception.Message) 'WARN'
            }
        }

        $smtp = New-Object System.Net.Mail.SmtpClient($SmtpServer, $SmtpPort)
        $smtp.EnableSsl = [bool]$SmtpUseSsl
        if ($SmtpUser) {
            $smtp.Credentials = New-Object System.Net.NetworkCredential($SmtpUser, (ConvertTo-PlainText $SmtpPassword))
        } else {
            $smtp.UseDefaultCredentials = $true
        }

        $smtp.Send($mail)
        Write-Log ("Summary email sent to: {0}" -f ($EmailTo -join ', ')) 'INFO'
        try { $mail.Dispose(); $smtp.Dispose() } catch {}
    } else {
        Write-Log "Email not sent (disabled by conditions or missing parameters)." 'DEBUG'
    }
} catch {
    Write-Log ("Failed to send summary email: {0}" -f $_.Exception.Message) 'WARN'
}

# ===== Cleanup (keep last 14 days of generated summaries and logs) =====
try {
    $retentionDays = 14
    try { if ($script:Config -and $script:Config.Archive -and $script:Config.Archive.RetentionDays) { $retentionDays = [int]$script:Config.Archive.RetentionDays } } catch {}
    $cutoff = (Get-Date).AddDays(-$retentionDays)

    # Archive Working subfolders to network location (config-driven)
    try {
        $archiveEnabled = $true
        try { if ($script:Config -and $script:Config.Archive -and ($null -ne $script:Config.Archive.Enabled)) { $archiveEnabled = [bool]$script:Config.Archive.Enabled } } catch { }
        if (-not $archiveEnabled) {
            Write-Log "Archive step disabled by config." 'INFO'
            return
        }

        $networkArchiveRoot = $null
        try { if ($script:Config -and $script:Config.Archive -and $script:Config.Archive.NetworkArchiveRoot) { $networkArchiveRoot = [string]$script:Config.Archive.NetworkArchiveRoot } } catch { }
        if (-not $networkArchiveRoot -or [string]::IsNullOrWhiteSpace($networkArchiveRoot)) {
            Write-Log "Archive enabled but Archive.NetworkArchiveRoot is not set in config; skipping archive." 'WARN'
            return
        }

        try { $null = New-Item -ItemType Directory -Path $networkArchiveRoot -Force -ErrorAction Stop } catch { }

        if ($WorkingRoot -and (Test-Path -LiteralPath $WorkingRoot)) {
            $subdirs = Get-ChildItem -LiteralPath $WorkingRoot -Directory -Force -ErrorAction SilentlyContinue
            if ($subdirs) {
                foreach ($dir in $subdirs) {
                    try {
                        Write-Log ("Archiving Working subfolder '{0}' to '{1}'" -f $dir.FullName, $networkArchiveRoot) 'INFO'
                        Copy-Item -LiteralPath $dir.FullName -Destination $networkArchiveRoot -Recurse -Force -ErrorAction Stop
                    } catch {
                        Write-Log ("Archive copy failed for '{0}' -> '{1}': {2}" -f $dir.FullName, $networkArchiveRoot, $_.Exception.Message) 'WARN'
                    }
                }

                # Retain only the N newest version folders per app (from config; default 3)
                try {
                    $keep = 3
                    try { if ($script:Config -and $script:Config.Archive -and $script:Config.Archive.KeepVersionsPerApp) { $keep = [int]$script:Config.Archive.KeepVersionsPerApp } } catch { }
                    Write-Log ("Archive retention: keeping {0} newest version folders per app (only apps touched this run)" -f $keep) 'INFO'

                    $pubsWorked = Get-ChildItem -LiteralPath $WorkingRoot -Directory -ErrorAction SilentlyContinue
                    foreach ($pub in ($pubsWorked | Where-Object { $_ })) {
                        $appsWorked = Get-ChildItem -LiteralPath $pub.FullName -Directory -ErrorAction SilentlyContinue
                        foreach ($app in ($appsWorked | Where-Object { $_ })) {
                            $appArchive = Join-Path $networkArchiveRoot (Join-Path $pub.Name $app.Name)
                            if (-not (Test-Path -LiteralPath $appArchive)) {
                                Write-Log ("Archive retention: path not found, skipping '{0}'" -f $appArchive) 'DEBUG'
                                continue
                            }

                            $verDirs = Get-ChildItem -LiteralPath $appArchive -Directory -ErrorAction SilentlyContinue
                            if (-not $verDirs -or $verDirs.Count -le $keep) { continue }

                            $verObjs = @()
                            foreach ($vd in $verDirs) {
                                $parsed = $null
                                $isVersion = $false
                                try {
                                    $parsed = [version]$vd.Name
                                    $isVersion = $true
                                } catch {
                                    if ($vd.Name -match '^\d+(?:\.\d+){1,3}') {
                                        $prefix = $matches[0]
                                        try { $parsed = [version]$prefix; $isVersion = $true } catch { }
                                    }
                                }
                                if ($isVersion) {
                                    $verObjs += [pscustomobject]@{
                                        Dir           = $vd
                                        Version       = $parsed
                                        LastWriteTime = $vd.LastWriteTime
                                    }
                                }
                            }

                            if (-not $verObjs -or $verObjs.Count -le $keep) { continue }

                            $sorted = $verObjs | Sort-Object `
                                @{ Expression = { if ($_.Version) { $_.Version } else { [version]'0.0.0.0' } }; Descending = $true }, `
                                @{ Expression = { $_.LastWriteTime }; Descending = $true }

                            $toDelete = $sorted | Select-Object -Skip $keep
                            foreach ($d in $toDelete) {
                                try {
                                    Remove-Item -LiteralPath $d.Dir.FullName -Recurse -Force -ErrorAction Stop
                                    Write-Log ("Archive retention: removed old version '{0}\{1}\{2}'" -f $pub.Name, $app.Name, $d.Dir.Name) 'INFO'
                                } catch {
                                    Write-Log ("Archive retention: failed to remove '{0}': {1}" -f $d.Dir.FullName, $_.Exception.Message) 'WARN'
                                }
                            }
                        }
                    }
                } catch {
                    Write-Log ("Archive retention step failed: {0}" -f $_.Exception.Message) 'WARN'
                }
            } else {
                Write-Log "No Working subfolders found to archive to network path." 'DEBUG'
            }
        }
    } catch {
        Write-Log ("Network archive copy encountered error: {0}" -f $_.Exception.Message) 'WARN'
    }

    # Working folder: Summary_*.csv and AutoPackager_*.log (email attachment copies)
    if ($WorkingRoot -and (Test-Path -LiteralPath $WorkingRoot)) {
        $deleted = @()

        foreach ($pattern in @('Summary_*.csv','AutoPackager_*.log')) {
            $files = Get-ChildItem -LiteralPath $WorkingRoot -File -Filter $pattern -ErrorAction SilentlyContinue |
                     Where-Object { $_.LastWriteTime -lt $cutoff }
            foreach ($f in $files) {
                try {
                    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                    $deleted += $f.FullName
                } catch {
                    Write-Log ("Cleanup skip '{0}': {1}" -f $f.FullName, $_.Exception.Message) 'WARN'
                }
            }
        }

        if ($deleted.Count -gt 0) {
            Write-Log ("Cleanup removed {0} old file(s) from Working: {1}" -f $deleted.Count, ($deleted -join '; ')) 'INFO'
        } else {
            Write-Log "Cleanup found no old files in Working." 'DEBUG'
        }
    }

    # Working Output logs: IntuneWinAppUtil stdout/stderr logs
    if ($WorkingRoot -and (Test-Path -LiteralPath $WorkingRoot)) {
        $deletedOut = @()
        foreach ($pattern in @('IntuneWinAppUtil_stdout_*.log','IntuneWinAppUtil_stderr_*.log')) {
            $files = Get-ChildItem -LiteralPath $WorkingRoot -File -Filter $pattern -Recurse -ErrorAction SilentlyContinue |
                     Where-Object { $_.LastWriteTime -lt $cutoff }
            foreach ($f in $files) {
                try {
                    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                    $deletedOut += $f.FullName
                } catch {
                    Write-Log ("Cleanup skip '{0}' (working output logs): {1}" -f $f.FullName, $_.Exception.Message) 'WARN'
                }
            }
        }
        if ($deletedOut.Count -gt 0) {
            Write-Log ("Cleanup removed {0} old working output log(s)." -f $deletedOut.Count) 'INFO'
        } else {
            Write-Log "Cleanup found no old working output logs." 'DEBUG'
        }
    }

    # Note: The primary log file ($LogPath) is rotated per run into Working/AutoPackager_yyyyMMdd_HHmmss.log; archives are purged after 14 days.
} catch {
    Write-Log ("Cleanup failed: {0}" -f $_.Exception.Message) 'WARN'
}
