<# 
New-RecipeFromWinget.ps1
Purpose:
  Generate a starter Recipe JSON for the AutoPackager from a given WingetId.
  The output JSON lives under .\Recipes by default (or a provided -OutputDir).

Quick Examples:

1) Basic (writes .\Recipes\ShareX.ShareX.json)
  PowerShell:
    & '.\devicemanagement\Intune\ChatGPT\AutoPackager V3\New-RecipeFromWinget.ps1' `
      -WingetId 'ShareX.ShareX'

2) Include IntuneAppId (so the autopackager can upload/overwrite the right Win32 app)
  PowerShell:
    & '.\devicemanagement\Intune\ChatGPT\AutoPackager V3\New-RecipeFromWinget.ps1' `
      -WingetId 'Zoom.Zoom' `
      -IntuneAppId '00000000-0000-0000-0000-000000000000'

3) Specify architecture + add ForceTaskClose image names
  PowerShell:
    & '.\devicemanagement\Intune\ChatGPT\AutoPackager V3\New-RecipeFromWinget.ps1' `
      -WingetId 'Zoom.Zoom' `
      -Architecture x64 `
      -ForceTaskClose 'zoom.exe','outlook.exe','teams.exe'

4) Override AppName and output file name/location
  PowerShell:
    & '.\devicemanagement\Intune\ChatGPT\AutoPackager V3\New-RecipeFromWinget.ps1' `
      -WingetId 'ShareX.ShareX' `
      -AppName 'ShareX' `
      -OutputDir '.\devicemanagement\Intune\ChatGPT\AutoPackager V3\Recipes' `
      -OutputFile 'sharex.sharex.json'

5) Override locale (if you prefer metadata from a specific locale)
  PowerShell:
    & '.\devicemanagement\Intune\ChatGPT\AutoPackager V3\New-RecipeFromWinget.ps1' `
      -WingetId 'Mozilla.Firefox' `
      -Locale 'en-GB'

Notes:
- ForceTaskClose is optional; provide process image names (with or without .exe).
- IntuneAppId should be set to your existing Win32 app’s GUID in Intune if you plan to upload/overwrite via the autopackager.
- After generating a recipe, open the JSON to review/update properties (e.g., InstallArgs/UninstallArgs/scope).
- Default output folder is .\Recipes next to this script unless -OutputDir is specified.
- New in output JSON: ForceUninstall (default false), NotificationPopup.Enabled (default false), NotificationPopup.NotificationTimerInMinutes (default 2), NotificationPopup.DeferralEnabled (default true), and NotificationPopup.DeferralHoursAllowed (default 24). Toggle these per recipe as needed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$WingetId,

    [Parameter()]
    [string]$IntuneAppId = "",

    [Parameter()]
    [ValidateSet("x64","x86","arm64")]
    [string]$Architecture = "x64",

    [Parameter()]
    [string]$Locale = "en-US",
 
    [Parameter()]
    [string[]]$ForceTaskClose,
 
    [Parameter()]
    [string]$AppName,

    [Parameter()]
    [string]$OutputDir,

    [Parameter()]
    [string]$OutputFile # optional explicit filename (e.g. MyApp.json)
)
if ($WingetId -ne ""){
}
Else{
    $WingetId = Read-Host 'Input Winget ID (ex. zoom.zoom)'
    }

if (-not $PSBoundParameters.ContainsKey('OutputDir') -or [string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $PSScriptRoot 'Recipes'
}

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')] [string]$Level = 'INFO')
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts][$Level] $Message"
    Write-Host $line
}

function Stop-WithError([string]$msg){ Write-Log $msg 'ERROR'; throw $msg }

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { $null = New-Item -ItemType Directory -Path $Path -Force }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Parse-WingetShowText {
    param([Parameter(Mandatory=$true)][string]$Text)
    $pkgName = $null; $publisher = $null; $version = $null

    $lines = $Text -split '\r?\n'
    foreach ($line in $lines) {
        if (-not $pkgName) {
            $mName = [regex]::Match($line, '^\s*(Name|Package\s*Name):\s*(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($mName.Success) { $pkgName = $mName.Groups[2].Value.Trim() }
        }
        if (-not $publisher) {
            $mPub = [regex]::Match($line, '^\s*Publisher:\s*(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($mPub.Success) { $publisher = $mPub.Groups[1].Value.Trim() }
        }
        if (-not $version) {
            $mVer = [regex]::Match($line, '^\s*Version:\s*(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($mVer.Success) { $version = $mVer.Groups[1].Value.Trim() }
        }
        if ($pkgName -and $publisher -and $version) { break }
    }

    if (-not $pkgName) {
        # try to derive from any "Found ..." line or fall back to last segment of Id
        $mFound = [regex]::Match($Text, 'Found\s+(.+?)\s+\[', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($mFound.Success) { $pkgName = $mFound.Groups[1].Value.Trim() }
    }

    [PSCustomObject]@{
        PackageName = $pkgName
        Publisher   = $publisher
        Version     = $version
    }
}

function Get-WingetMetadata {
    param(
        [Parameter(Mandatory=$true)][string]$WingetId,
        [Parameter()][string]$WingetSource = 'winget'
    )
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) { Stop-WithError "winget.exe not found. Install 'App Installer' from Microsoft Store." }

    $args = @('show','--id', $WingetId, '--exact','--source', $WingetSource,'--accept-source-agreements','--accept-package-agreements','--output','json')
    $raw = & $winget.Path @args 2>&1 | Out-String
    if (-not $raw) { Stop-WithError ("winget returned no data for {0}" -f $WingetId) }

    # Sanitize and robustly extract the JSON block from winget output
    $text = $raw.Trim()

    # Fast path: already starts with JSON
    if (-not ($text.StartsWith('{') -or $text.StartsWith('['))) {
        # Try regex singleline extraction of the first JSON object/array
        if ($text -match '(?s)({.*}|\[.*\])') {
            $text = $matches[1]
        } else {
            Write-Log ('winget produced non-JSON output for {0}; attempting plaintext parse' -f $WingetId) 'WARN'
            $parsed = Parse-WingetShowText -Text $raw
            $pkg = if ($parsed.PackageName) { $parsed.PackageName } else { (($WingetId -split '\.')[-1]) }
            $pub = $parsed.Publisher
            $ver = $parsed.Version
            return [PSCustomObject]@{
                DefaultLocale = [PSCustomObject]@{
                    PackageName = $pkg
                    Publisher   = $pub
                }
                Versions = @( if ($ver) { [PSCustomObject]@{ Version = $ver } } )
            }
        }
    }

    try {
        $obj = $text | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Log ("Raw winget output (first 400 chars): {0}" -f ($raw.Substring(0, [Math]::Min(400, $raw.Length)))) 'WARN'
        Write-Log ("Failed to parse winget JSON for {0}: {1} - attempting plaintext parse" -f $WingetId, $_.Exception.Message) 'WARN'
        $parsed = Parse-WingetShowText -Text $raw
        $pkg = if ($parsed.PackageName) { $parsed.PackageName } else { (($WingetId -split '\.')[-1]) }
        $pub = $parsed.Publisher
        $ver = $parsed.Version
        return [PSCustomObject]@{
            DefaultLocale = [PSCustomObject]@{
                PackageName = $pkg
                Publisher   = $pub
            }
            Versions = @( if ($ver) { [PSCustomObject]@{ Version = $ver } } )
        }
    }
    return $obj
}

function Select-LatestVersion {
    param($Obj)
    $versions = @()
    if ($Obj.PSObject.Properties.Name -contains 'Versions') {
        $versions = @($Obj.Versions)
    } elseif ($Obj.PSObject.Properties.Name -contains 'Version' -or $Obj.PSObject.Properties.Name -contains 'Installers') {
        $versions = @($Obj)
    } elseif ($Obj.Data) {
        $versions = @($Obj.Data)
    }
    if (-not $versions -or $versions.Count -eq 0) { return $null }

    function Convert-Version([string]$v){ try { [version]$v } catch { $null } }
    $sorted = $versions | Sort-Object -Property @{Expression={ Convert-Version $_.Version }; Ascending=$true}, Version
    return $sorted[-1]
}

function Sanitize-Name([string]$name) {
    if (-not $name) { return $name }
    return ($name -replace '[\\/:*?"<>|]','_')
}

# GitHub manifest resolver (winget-pkgs)
function Get-WingetManifestInfoFromGitHub {
  param(
    [Parameter(Mandatory=$true)][string]$WingetId,
    [Parameter()][string]$PreferArchitecture = 'x64',
    [Parameter()][ValidateSet('auto','machine','user')][string]$PreferScope = 'machine',
    [Parameter()][string]$DesiredLocale = 'en-US',
    [Parameter()][string]$Owner = 'microsoft',
    [Parameter()][string]$Repo = 'winget-pkgs',
    [Parameter()][string]$Branch = 'master',
    [Parameter()][ValidateSet('auto','msi','exe')][string]$PreferInstallerType = 'auto',
    [Parameter()][string]$Token = $null
  )
  # Optional token from env for higher rate limits
  if (-not $Token) {
    if ($env:GITHUB_TOKEN) { $Token = $env:GITHUB_TOKEN }
    elseif ($env:GH_TOKEN) { $Token = $env:GH_TOKEN }
  }
  $apiBase = 'https://api.github.com'
  $headers = @{
    'Accept'               = 'application/vnd.github+json'
    'User-Agent'           = 'AutoPackager-NewRecipe/1.0'
    'X-GitHub-Api-Version' = '2022-11-28'
  }
  if ($Token) { $headers['Authorization'] = "Bearer $Token" }

  function __gh_get([string]$url){
    return Invoke-RestMethod -Method GET -Uri $url -Headers $headers -TimeoutSec 180
  }
  function __join([string[]]$segs){ return ($segs | ForEach-Object { [System.Uri]::EscapeDataString($_) }) -join '/' }
  function __resolve_branch([string]$owner,[string]$repo,[string]$branch){
    try { [void](__gh_get "$apiBase/repos/$owner/$repo/branches/$branch"); return $branch }
    catch { if ($branch -eq 'master') { return 'main' } else { return $branch } }
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
  if (-not $latest) { return $null }

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

  # Parse installer YAML (optionally via powershell-yaml)
  $selType = $null; $selArch = $null; $selScope = $null
  if ($installerYaml) {
    $yamlOk = $false
    try {
      if (-not (Get-Module -ListAvailable -Name 'powershell-yaml')) {
        try {
          $repoPS = Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue
          if ($repoPS -and $repoPS.InstallationPolicy -ne 'Trusted') { Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue | Out-Null }
        } catch {}
        Install-Module -Name 'powershell-yaml' -Scope CurrentUser -Force -AllowClobber -ErrorAction SilentlyContinue | Out-Null
      }
      Import-Module 'powershell-yaml' -ErrorAction SilentlyContinue | Out-Null
      $instObj = ConvertFrom-Yaml $installerYaml
      $all = @($instObj.Installers)
      if ($all.Count -gt 0) {
        $cands = $all
        if ($PreferArchitecture) {
          $c1 = $all | Where-Object { $_.Architecture -ieq $PreferArchitecture }
          if ($PreferArchitecture -ne 'arm64' -and ($c1.Count -eq 0)) { $c1 = $all | Where-Object { $_.Architecture -ieq 'x86' } }
          if ($c1.Count -gt 0) { $cands = $c1 }
        } else {
          $cands = $all | Where-Object { $_.Architecture -ne 'arm64' }
          if ($cands.Count -eq 0) { $cands = $all }
        }
        if ($PreferScope -and $PreferScope -ne 'auto') {
          $c2 = $cands | Where-Object { $_.Scope -ieq $PreferScope }
          if ($c2.Count -gt 0) { $cands = $c2 }
        }
        if ($PreferInstallerType -and $PreferInstallerType -ne 'auto') {
          if ($PreferInstallerType -ieq 'msi') {
            $c3 = $cands | Where-Object { $_.InstallerType -and (($_.InstallerType -ieq 'msi') -or ($_.InstallerType -ieq 'wix')) }
            if (-not $c3 -or $c3.Count -eq 0) { $c3 = $cands | Where-Object { $_.InstallerUrl -match '\.msi(\?|$)' } }
          } else {
            $c3 = $cands | Where-Object { $_.InstallerType -and (@('msi','wix') -notcontains ($_.InstallerType.ToString().ToLower())) }
            if (-not $c3 -or $c3.Count -eq 0) { $c3 = $cands | Where-Object { $_.InstallerUrl -match '\.exe(\?|$)' } }
          }
          if ($c3 -and $c3.Count -gt 0) { $cands = $c3 }
        }
        $sel = $cands | Where-Object { $_.InstallerUrl } | Select-Object -First 1
        if (-not $sel) { $sel = $cands | Select-Object -First 1 }
        if ($sel) {
          $selType = $sel.InstallerType
          $selArch = $sel.Architecture
          $selScope= $sel.Scope
          $yamlOk = $true
        }
      }
    } catch { }
    if (-not $yamlOk) {
      # best effort fallback: none required for New-Recipe; we only need version/name/publisher
    }
  }

  # Parse locale YAML for metadata
  $locName = $null; $locPublisher = $null
  if ($localeYaml) {
    try {
      if (Get-Module -ListAvailable -Name 'powershell-yaml') {
        $locObj = ConvertFrom-Yaml $localeYaml
        $locName = $locObj.PackageName
        $locPublisher = $locObj.Publisher
      } else {
        $locName = __yaml_scalar $localeYaml 'PackageName'
        $locPublisher = __yaml_scalar $localeYaml 'Publisher'
      }
    } catch { }
  }

  return [pscustomobject]@{
    Id            = $WingetId
    Name          = $locName
    Version       = $latest
    InstallerType = $selType
    Architecture  = $selArch
    Scope         = $selScope
    Publisher     = $locPublisher
  }
}

# Main
try {
    Write-Log "Building recipe from WingetId '$WingetId' ..." 'INFO'
    $info = $null
    try {
        $info = Get-WingetManifestInfoFromGitHub -WingetId $WingetId -PreferArchitecture $Architecture -PreferScope 'machine' -PreferInstallerType 'auto' -DesiredLocale $Locale
    } catch {
        $info = $null
    }
    if (-not $info) {
        Write-Log "Failed to resolve manifests via GitHub for '$WingetId'." 'WARN'
    }
    $latest = if ($info -and $info.Version) { $info.Version } else { $null }
    if (-not $latest) {
        Write-Log "No version resolved from GitHub manifests, continuing with minimal metadata." 'WARN'
    }

    # Best-effort to derive a friendly app name from GitHub locale YAML
    $derivedName = $null
    if ($info -and $info.Name) {
        $derivedName = $info.Name
    } else {
        # fallback to last segment of WingetId
        if ($WingetId -match '\.') {
            $derivedName = ($WingetId -split '\.')[-1]
        } else {
            $derivedName = $WingetId
        }
    }

    if (-not $AppName -or [string]::IsNullOrWhiteSpace($AppName)) {
        $AppName = $derivedName
    }
 
    # Normalize ForceTaskClose into a clean string array (trim, drop empties)
    $ForceTaskCloseClean = @()
    if ($PSBoundParameters.ContainsKey('ForceTaskClose') -and $ForceTaskClose) {
        $ForceTaskCloseClean = $ForceTaskClose | ForEach-Object { if ($_ -ne $null) { $_.ToString().Trim() } } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $ForceTaskCloseClean = $ForceTaskCloseClean | Select-Object -Unique
    }
 
    # Load default ring delay days from AutoPackager.config.json
    $defR1 = 1; $defR2 = 3; $defR3 = 5
    try {
      $cfgPath = Join-Path $PSScriptRoot 'AutoPackager.config.json'
      if (Test-Path -LiteralPath $cfgPath) {
        $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
        if ($cfg -and $cfg.RequiredUpdateDefaultGroups) {
          function Clamp([int]$v){ if ($v -lt 0){return 0} elseif($v -gt 365){return 365} else {return $v} }
          try { if ($cfg.RequiredUpdateDefaultGroups.PilotDelayDays -ne $null) { $defR1 = Clamp([int]$cfg.RequiredUpdateDefaultGroups.PilotDelayDays) } } catch {}
          try { if ($cfg.RequiredUpdateDefaultGroups.UATDelayDays -ne $null) { $defR2 = Clamp([int]$cfg.RequiredUpdateDefaultGroups.UATDelayDays) } } catch {}
          try { if ($cfg.RequiredUpdateDefaultGroups.GADelayDays -ne $null) { $defR3 = Clamp([int]$cfg.RequiredUpdateDefaultGroups.GADelayDays) } } catch {}
        }
      }
    } catch {}

    $recipe = [ordered]@{
        WingetId = $WingetId
        AppName  = $AppName
        IntuneAppId = $IntuneAppId
        SecondaryAppId = ""
        InstallerPreferences = [ordered]@{
            Architecture = $Architecture
            Locale       = $Locale
            Scope        = ""
        }
        InstallArgs          = ""
        UninstallArgs        = ""
        ForceTaskClose       = $ForceTaskCloseClean
        ForceUninstall       = $false
        NotificationPopup    = [ordered]@{
            Enabled = $false
            NotificationTimerInMinutes = 2
            DeferralEnabled = $true
            DeferralHoursAllowed = 24
        }
        Rings = [ordered]@{
            Ring1 = [ordered]@{ Group = ""; DeadlineDelayDays = $defR1 }
            Ring2 = [ordered]@{ Group = ""; DeadlineDelayDays = $defR2 }
            Ring3 = [ordered]@{ Group = ""; DeadlineDelayDays = $defR3 }
        }
    }

    $outDir = Ensure-Dir $OutputDir
    $fileName = if ($OutputFile) {
        $OutputFile
    } else {
        ("{0}.json" -f ($WingetId))
    }

    $outPath = Join-Path $outDir $fileName
    $jsonOut = $recipe | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $outPath -Value $jsonOut -Encoding UTF8

    Write-Log "Recipe created: $outPath" 'INFO'
    if ($latest -and $latest.Version) {
        Write-Log "Latest winget version detected: $($latest.Version)" 'INFO'
    }
    if ($info -and $info.Publisher) {
        Write-Log "Publisher: $($info.Publisher)" 'INFO'
    }
    Write-Log "Next: Open the file and set IntuneAppId to the existing Win32 app GUID, then run the autopackager." 'INFO'
}
catch {
    Stop-WithError $_.Exception.Message
}
