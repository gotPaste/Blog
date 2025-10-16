#requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Resolve script root
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot -or [string]::IsNullOrWhiteSpace($ScriptRoot)) {
  if ($PSCommandPath) { $ScriptRoot = Split-Path -Parent $PSCommandPath }
  elseif ($MyInvocation.MyCommand.Path) { $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
  else { $ScriptRoot = (Get-Location).Path }
}

# Paths to scripts and files
$PathAutoPackager      = Join-Path $ScriptRoot 'AutoPackagerv2.ps1'
$PathNewRecipe         = Join-Path $ScriptRoot 'New-RecipeFromWinget.ps1'
$PathResetPrimary      = Join-Path $ScriptRoot 'IntuneApplicationResetAll.ps1'
$PathResetSecondary    = Join-Path $ScriptRoot 'IntuneApplicationResetAll.ps1'
$PathIntuneTools       = Join-Path $ScriptRoot 'IntuneAppTools.ps1'
$PathCreateTemplate    = Join-Path $ScriptRoot 'CreateWin32AppFromTemplate.ps1'
$PathConfig            = Join-Path $ScriptRoot 'AutoPackager.config.json'
$PathLog               = Join-Path $ScriptRoot 'AutoPackager.log'
$PathRecipesDefault    = Join-Path $ScriptRoot 'Recipes'
$PathReadme            = Join-Path $ScriptRoot 'readme.txt'
$PathWorking           = Join-Path $ScriptRoot 'Working'

$script:PreferArchitecture = 'x64'
$script:ReturnToRecipeAfterFind = $false
$script:ReturnToResetAfterFind = $false
$script:DefaultAllowAvailableUninstall = $false
$script:DefaultRingDelay1 = 1
$script:DefaultRingDelay2 = 3
$script:DefaultRingDelay3 = 5
try {
  if (Test-Path -LiteralPath $PathConfig) {
    $cfg = Get-Content -LiteralPath $PathConfig -Raw | ConvertFrom-Json
    if ($cfg -and ($cfg.PSObject.Properties.Name -contains 'AllowAvailableUninstall') -and ($null -ne $cfg.AllowAvailableUninstall)) {
      $script:DefaultAllowAvailableUninstall = [bool]$cfg.AllowAvailableUninstall
    }
  }
} catch {}

function Resolve-ExistingPath([string]$p) {
  try {
    if ([string]::IsNullOrWhiteSpace($p)) { return $null }
        if (Test-Path -LiteralPath $p) {
          $resolved = (Resolve-Path -LiteralPath $p).Path
          try { if ($resolved -match '^[^:]+::') { $resolved = $resolved -replace '^[^:]+::','' } } catch {}
          return $resolved
        }
  } catch {}
  return $null
}

function Get-DefaultIconDirectory {
  try {
    if (Test-Path -LiteralPath $PathConfig) {
      $cfg = Get-Content -LiteralPath $PathConfig -Raw | ConvertFrom-Json
      $p = $null
      if ($cfg -and $cfg.Paths -and ($cfg.Paths.PSObject.Properties.Name -contains 'DefaultIconFolder')) {
        $p = [string]$cfg.Paths.DefaultIconFolder
      } elseif ($cfg -and $cfg.GUI -and ($cfg.GUI.PSObject.Properties.Name -contains 'DefaultIconFolder')) {
        # Optional alternate location if a GUI section is introduced later
        $p = [string]$cfg.GUI.DefaultIconFolder
      }
      if ($p) {
        try { $p = [System.Environment]::ExpandEnvironmentVariables($p) } catch {}
        if (-not [System.IO.Path]::IsPathRooted($p)) {
          $p = Join-Path $ScriptRoot $p
        }
        # If a file was specified, use its parent directory
        try { if (Test-Path -LiteralPath $p -PathType Leaf) { $p = Split-Path -Parent $p } } catch {}
        $resolved = Resolve-ExistingPath $p
        if ($resolved) { return $resolved }
      }
    }
  } catch {}
  # Fallbacks
  try {
    $pics = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::MyPictures)
    if ($pics -and (Test-Path -LiteralPath $pics)) { return $pics }
  } catch {}
  try {
    $wk = Join-Path $ScriptRoot 'Working'
    if (Test-Path -LiteralPath $wk) { return $wk }
  } catch {}
  return $ScriptRoot
}

function Get-DefaultRecipeNetworkDirectory {
  try {
    if (Test-Path -LiteralPath $PathConfig) {
      $cfg = Get-Content -LiteralPath $PathConfig -Raw | ConvertFrom-Json
      $p = $null
      if ($cfg -and $cfg.Paths -and ($cfg.Paths.PSObject.Properties.Name -contains 'RecipeNetworkFolder')) {
        $p = [string]$cfg.Paths.RecipeNetworkFolder
      }
      if ($p) {
        # Normalize/clean input
        try { $p = [string]$p } catch {}
        try {
          # Trim quotes/whitespace and normalize slashes (avoid converting URLs)
          $p = ($p -replace '^[\uFEFF\s"]+','' -replace '[\s"]+$','')
          if ($p -notmatch '^[A-Za-z]+://') { $p = $p -replace '/', '\' }
        } catch {}
        # Expand env vars and resolve relative to script folder
        try { $p = [System.Environment]::ExpandEnvironmentVariables($p) } catch {}
        if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $ScriptRoot $p }
        # If a file path was provided, use its parent directory
        try {
          if ($p -match '\.json$') { $p = Split-Path -Parent $p }
        } catch {}
        try { if (Test-Path -LiteralPath $p -PathType Leaf) { $p = Split-Path -Parent $p } } catch {}
        # If the path doesn't exist, walk up to the nearest existing parent (UNC safe)
        try {
          $probe = $p
          while ($probe -and -not (Test-Path -LiteralPath $probe)) {
            $parent = Split-Path -Parent $probe
            if (-not $parent -or $parent -eq $probe) { break }
            $probe = $parent
          }
          if ($probe -and (Test-Path -LiteralPath $probe)) { $p = $probe }
        } catch {}
        if (Test-Path -LiteralPath $p) {
          $resolved = (Resolve-Path -LiteralPath $p).Path
          try { if ($resolved -match '^[^:]+::') { $resolved = $resolved -replace '^[^:]+::','' } } catch {}
          return $resolved
        }
      }
    }
  } catch {}
  try {
    $userProfilePath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
    if ($userProfilePath -and (Test-Path -LiteralPath $userProfilePath)) { return $userProfilePath }
  } catch {}
  return $ScriptRoot
}

# UI helpers
function New-Button([string]$text, [int]$x, [int]$y, [int]$w=140, [int]$h=28) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $text; $b.Left = $x; $b.Top = $y; $b.Width = $w; $b.Height = $h
  return $b
}
function New-Label([string]$text, [int]$x, [int]$y, [int]$w=160, [int]$h=20) {
  $l = New-Object System.Windows.Forms.Label
  $l.Text = $text; $l.Left = $x; $l.Top = $y; $l.Width = $w; $l.Height = $h
  return $l
}
function New-TextBox([int]$x, [int]$y, [int]$w=260, [int]$h=22, [bool]$multiline=$false, [bool]$readonly=$false) {
  $t = New-Object System.Windows.Forms.TextBox
  $t.Left = $x; $t.Top = $y; $t.Width = $w
  if ($multiline) { $t.Multiline = $true; $t.Height = $h; $t.ScrollBars = 'Vertical' } else { $t.Height = 22 }
  $t.ReadOnly = $readonly
  return $t
}
function New-Group([string]$text, [int]$x, [int]$y, [int]$w, [int]$h) {
  $g = New-Object System.Windows.Forms.GroupBox
  $g.Text = $text; $g.Left = $x; $g.Top = $y; $g.Width = $w; $g.Height = $h
  return $g
}
function Append-Output($tb, [string]$text) {
  if ($null -eq $text) { return }
  if ($text -eq '') { $tb.AppendText("`r`n"); return }

  # Normalize all line endings to CRLF so WinForms TextBox renders each line correctly
  $normalized = ($text -replace "(`r`n|`r|`n)", "`r`n")
  if (-not $normalized.EndsWith("`r`n")) { $normalized += "`r`n" }

  $tb.AppendText($normalized)
}
# Colored output helper for RichTextBox (falls back to plain Append-Output)
function Append-OutputColored($tb, [string]$text, [string]$colorName = 'Black') {
  if ($null -eq $text) { return }
  try {
    if ($tb -is [System.Windows.Forms.RichTextBox]) {
      $col = [System.Drawing.Color]::FromName($colorName)
      if (-not $col.IsKnownColor) { $col = [System.Drawing.Color]::Black }
      $tb.SelectionStart = $tb.TextLength
      $tb.SelectionLength = 0
      $tb.SelectionColor = $col
      # Normalize line endings
      $norm = ($text -replace "(`r`n|`r|`n)", "`r`n")
      $tb.AppendText($norm)
      if (-not $norm.EndsWith("`r`n")) { $tb.AppendText("`r`n") }
      $tb.SelectionColor = $tb.ForeColor
    } else {
      Append-Output $tb $text
    }
  } catch {
    Append-Output $tb $text
  }
}

# ------- Utilities (new) -------
function Sanitize-Leaf([string]$s) {
  if (-not $s) { return 'Unknown' }
  $invalid = [IO.Path]::GetInvalidFileNameChars() + [IO.Path]::GetInvalidPathChars()
  return -join ($s.ToCharArray() | ForEach-Object { if ($invalid -contains $_) { '_' } else { $_ } })
}

function Set-RingFilter([object]$ringObj,[string]$text,[string]$typeSel) {
  if (-not $ringObj) { return }
  $val = if ($text) { $text.Trim() } else { '' }
  $t = if ($typeSel) { $typeSel.Trim().ToLower() } else { 'include' }
  if ($val) {
    if ($val -match '^\{?[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}?$') {
      $idNorm = ($val -replace '^\{|\}$','')
      $ringObj | Add-Member -NotePropertyName FilterId -NotePropertyValue $idNorm -Force
      $ringObj | Add-Member -NotePropertyName FilterName -NotePropertyValue $null -Force
    } else {
      $ringObj | Add-Member -NotePropertyName FilterName -NotePropertyValue $val -Force
      $ringObj | Add-Member -NotePropertyName FilterId -NotePropertyValue $null -Force
    }
    $ringObj | Add-Member -NotePropertyName FilterType -NotePropertyValue ($(if ($t -eq 'exclude') {'exclude'} else {'include'})) -Force
  } else {
    # Clear if empty
    $ringObj | Add-Member -NotePropertyName FilterName -NotePropertyValue $null -Force
    $ringObj | Add-Member -NotePropertyName FilterId -NotePropertyValue $null -Force
    $ringObj | Add-Member -NotePropertyName FilterType -NotePropertyValue 'include' -Force
  }
}

function Get-SafeAppVersion([string]$raw) {
  if (-not $raw) { return '0.1' }
  $v = $raw.Trim()
  if (-not $v) { return '0.1' }
  if ($v -match '(\d+(?:\.\d+){0,3})') { return $matches[1] }
  return '0.1'
}

function Ensure-WingetParsed([string]$WingetId) {
  $id = $WingetId
  try {
    if (-not $id -or [string]::IsNullOrWhiteSpace($id)) {
      if ($tbId -and $tbId.Text) { $id = $tbId.Text.Trim() }
      if (-not $id -and $tbWingetApps -and $tbWingetApps.Text) { $id = $tbWingetApps.Text.Trim() }
      if (-not $id -and $tbWingetForNew -and $tbWingetForNew.Text) { $id = $tbWingetForNew.Text.Trim() }
    }
  } catch {}
  if (-not $id) { return $null }

  try {
    if ($script:LastWingetParsed -and $script:LastWingetParsed.Id -and ([string]$script:LastWingetParsed.Id -eq $id) -and $script:LastWingetParsed.Name) {
      return $script:LastWingetParsed
    }
  } catch {}

  # Preferences (no winget.exe)
  $archPref = $script:PreferArchitecture
  if (-not $archPref -or [string]::IsNullOrWhiteSpace($archPref)) { $archPref = 'x64' }
  try { if ($cbArchWinget -and $cbArchWinget.SelectedItem) { $archPref = [string]$cbArchWinget.SelectedItem } } catch {}

  $scopePref = 'machine'
  try { if ($cbScope -and $cbScope.SelectedItem -and [string]$cbScope.SelectedItem -ne 'auto') { $scopePref = [string]$cbScope.SelectedItem } } catch {}

  $installerTypePref = 'auto'
  try { if ($cbInstTypeWinget -and $cbInstTypeWinget.SelectedItem) { $installerTypePref = ([string]$cbInstTypeWinget.SelectedItem).ToLower() } } catch {}

  $localePref = 'en-US'
  try { if ($tbLocale -and $tbLocale.Text -and $tbLocale.Text.Trim()) { $localePref = $tbLocale.Text.Trim() } } catch {}

  # Resolve via GitHub API/YAML only
  $parsed = $null
  try {
    $parsed = Get-WingetManifestInfoFromGitHub -WingetId $id -PreferArchitecture $archPref -PreferScope $scopePref -PreferInstallerType $installerTypePref -DesiredLocale $localePref
  } catch {
    $parsed = $null
  }

  if ($parsed) { $script:LastWingetParsed = $parsed }
  return $parsed
}

# Winget ID sync helper (keeps Winget ID in sync across Winget, Recipe, and Intune App(s) tabs)
$script:WingetSyncing = $false
function Set-WingetIdAll([string]$val) {
  if ($script:WingetSyncing) { return }
  $script:WingetSyncing = $true
  try {
    if ($tbId -and ($tbId.Text -ne $val)) { $tbId.Text = $val }
    if ($tbWingetForNew -and ($tbWingetForNew.Text -ne $val)) { $tbWingetForNew.Text = $val }
    if ($tbWingetApps -and ($tbWingetApps.Text -ne $val)) { $tbWingetApps.Text = $val }
  } catch {}
  $script:WingetSyncing = $false
}

# Winget text normalization (mirrors backend)
function Normalize-WingetText {
  param([Parameter(Mandatory=$true)][string]$Text)
  $t = $Text
  try {
    $t = ($t -replace "`e\[[0-9;]*[A-Za-z]", '')
    $t = $t -replace '\u00A0', ' '
    $t = $t -replace '\r\n', "`n"
    $t = $t -replace '\r', "`n"
  } catch {}
  return $t
}

# Parse 'winget show' plain-text output (fallback parser from backend)
function Parse-WingetShowText {
  param(
    [Parameter(Mandatory=$true)][string]$Text,
    [Parameter(Mandatory=$true)][string]$WingetId,
    [Parameter()][string]$PreferArchitecture = 'x64',
    [Parameter()][ValidateSet('auto','machine','user')][string]$PreferScope = 'auto'
  )
  $Text = Normalize-WingetText -Text $Text
  $version = $null
  $currentArch = $null
  $currentScope = $null
  $candidates = New-Object System.Collections.Generic.List[object]

  # App Name from banner 'Found ...'
  $appName = $null
  try {
    $foundLine = ($Text -split "`n" | Where-Object { $_ -match '^\s*Found\s+' } | Select-Object -First 1)
    if ($foundLine) {
      $lineText = $foundLine
      if ($lineText -like 'Found *') {
        $namePortion = $lineText.Substring(6)
      } else {
        $namePortion = ($lineText -replace '^\s*Found\s+','')
      }
      if ($namePortion -match '^(.*?)\[') {
        $appName = $matches[1].Trim()
      } else {
        $appName = $namePortion.Trim()
      }
    }
  } catch {}

  $publisher  = $null
  $author     = $null
  $homepage   = $null
  $privacyUrl = $null
  $description= $null
  $tags       = @()

  $lines = $Text -split '\r?\n'
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]

    if (-not $version) {
      $mVer = [regex]::Match($line, '^\s*(Latest\s+)?Version\s*:\s*(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
      if ($mVer.Success) { $version = $mVer.Groups[2].Value.Trim() }
    }

    $mArch = [regex]::Match($line, '^\s*Architecture:\s*(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($mArch.Success) { $currentArch = $mArch.Groups[1].Value.Trim() }

    $mScope = [regex]::Match($line, '^\s*Scope:\s*(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($mScope.Success) { $currentScope = $mScope.Groups[1].Value.Trim() }

    if (-not $appName) {
      $mName = [regex]::Match($line, '^\s*Name\s*:\s*(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
      if ($mName.Success) { $appName = $mName.Groups[1].Value.Trim() }
    }

    if (-not $publisher) {
      $mPub = [regex]::Match($line, '^\s*Publisher\s*:\s*(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
      if ($mPub.Success) { $publisher = $mPub.Groups[1].Value.Trim() }
    }
    if (-not $author) {
      $mAuth = [regex]::Match($line, '^\s*Author\s*:\s*(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
      if ($mAuth.Success) { $author = $mAuth.Groups[1].Value.Trim() }
    }
    if (-not $homepage) {
      $mHome = [regex]::Match($line, '^\s*Homepage(\s+Url)?\s*:\s*(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
      if ($mHome.Success) { $homepage = $mHome.Groups[$mHome.Groups.Count-1].Value.Trim() }
    }
    if (-not $homepage) {
      $mPubUrl = [regex]::Match($line, '^\s*Publisher\s+Url\s*:\s*(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
      if ($mPubUrl.Success) { $homepage = $mPubUrl.Groups[1].Value.Trim() }
    }
    if (-not $homepage) {
      $mSupp = [regex]::Match($line, '^\s*Publisher\s+Support\s+Url\s*:\s*(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
      if ($mSupp.Success) { $homepage = $mSupp.Groups[1].Value.Trim() }
    }
    if (-not $privacyUrl) {
      $mPriv = [regex]::Match($line, '^\s*Privacy\s*Url\s*:\s*(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
      if ($mPriv.Success) { $privacyUrl = $mPriv.Groups[1].Value.Trim() } else {
        $mPriv2 = [regex]::Match($line, '^\s*PrivacyUrl\s*:\s*(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($mPriv2.Success) { $privacyUrl = $mPriv2.Groups[1].Value.Trim() }
      }
    }

    if (-not $tags -or $tags.Count -eq 0) {
      $mTags = [regex]::Match($line, '^\s*Tags?\s*:\s*(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
      if ($mTags.Success) {
        $tags = ($mTags.Groups[1].Value -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
      }
    }

    if (-not $description) {
      $mDesc = [regex]::Match($line, '^\s*Description\s*:\s*(.*)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
      if ($mDesc.Success) {
        $descBuffer = @()
        $first = $mDesc.Groups[1].Value
        if ($first) { $descBuffer += $first.Trim() }
        $j = $i + 1
        while ($j -lt $lines.Count) {
          $peek = $lines[$j]
          if ($peek -match '^\s*[A-Za-z][A-Za-z0-9 /-]{0,30}:\s') { break }
          $trimLine = $peek.Trim()
          if ($trimLine -and $trimLine -ne '.') { $descBuffer += $trimLine }
          $j++
        }
        if ($descBuffer.Count -gt 0) { $description = ($descBuffer -join ' ') }
        $i = $j - 1
      }
    }

    if ($line -match '^\s*Installer\s*:\s*$') {
      $j = $i + 1
      while ($j -lt $lines.Count -and [string]::IsNullOrWhiteSpace($lines[$j])) { $j++ }
      if ($j -lt $lines.Count) {
        $next = $lines[$j].Trim()
        $urlToken = ($next -split '\s+' | Where-Object { $_ -match '^https?://\S+' } | Select-Object -First 1)
        if ($urlToken) {
          $base = ($urlToken -split '\?')[0]
          $ext = [System.IO.Path]::GetExtension($base).Trim('.').ToLower()
          if ([string]::IsNullOrWhiteSpace($ext)) {
            $seg = ($base -split '/')[(-1)]
            if ($seg -match '\.([A-Za-z0-9]+)$') { $ext = $matches[1].ToLower() }
          }
          $arch = if ($currentArch) { $currentArch } else { '' }
          $cand = [PSCustomObject]@{ Url=$urlToken; Architecture=$arch; Type=$ext; Scope=$currentScope }
          $candidates.Add($cand) | Out-Null
        }
      }
    }

    $mUrl = [regex]::Match($line, '^\s*(Installer|Download)\s+Url(s)?\s*:\s*(.*)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($mUrl.Success) {
      $url = $null
      $after = $mUrl.Groups[3].Value.Trim()
      if ([string]::IsNullOrWhiteSpace($after)) {
        $j = $i + 1
        while ($j -lt $lines.Count -and [string]::IsNullOrWhiteSpace($lines[$j])) { $j++ }
        if ($j -lt $lines.Count) {
          $next = $lines[$j].Trim()
          if ($next -match '^(https?://\S+)$') {
            $url = $matches[1]; $i = $j
          } else {
            $parts = $next -split '\s+'
            $url = ($parts | Where-Object { $_ -match '^https?://\S+' } | Select-Object -First 1)
            if ($url) { $i = $j }
          }
        }
      } else {
        $parts = $after -split '\s+'
        $url = ($parts | Where-Object { $_ -match '^https?://\S+' } | Select-Object -First 1)
        if (-not $url) { $url = $after }
      }

      if ($url) {
        $base = ($url -split '\?')[0]
        $ext = [System.IO.Path]::GetExtension($base).Trim('.').ToLower()
        if ([string]::IsNullOrWhiteSpace($ext)) {
          $seg = ($base -split '/')[(-1)]
          if ($seg -match '\.([A-Za-z0-9]+)$') { $ext = $matches[1].ToLower() }
        }
        $arch = if ($currentArch) { $currentArch } else { '' }
        $cand = [PSCustomObject]@{ Url=$url; Architecture=$arch; Type=$ext; Scope=$currentScope }
        $candidates.Add($cand) | Out-Null
      }
    }
  }

  if (-not $version) {
    $derived = $null
    foreach ($cand in $candidates) {
      $u = $cand.Url
      if ($u -and ($u -match '/(\d+(?:\.\d+){1,3})/')) {
        $derived = $matches[1]; break
      }
    }
    if ($derived) { $version = $derived } else { return $null }
  }
  if ($candidates.Count -eq 0) { return $null }

  if ($PreferScope -and $PreferScope -ne 'auto') {
    $scopeFirst = $candidates | Where-Object { $_.Scope -and ($_.Scope -ieq $PreferScope) }
    if (-not $scopeFirst -or $scopeFirst.Count -eq 0) { $scopeFirst = $candidates }
  } else {
    $scopeFirst = $candidates
  }
  $preferred = $scopeFirst | Where-Object { $_.Architecture -and ($_.Architecture -ieq $PreferArchitecture) }
  if (-not $preferred -or $preferred.Count -eq 0) { $preferred = $scopeFirst }
  $chosen = $preferred | Select-Object -First 1
  if (-not $chosen) { return $null }

  return [PSCustomObject]@{
    Id            = $WingetId
    Name          = $appName
    Version       = $version
    InstallerUrl  = $chosen.Url
    InstallerType = $chosen.Type
    ProductCode   = $null
    Architecture  = $chosen.Architecture
    Sha256        = $null
    Publisher     = $publisher
    Author        = $author
    Homepage      = $homepage
    PrivacyUrl    = $privacyUrl
    Description   = $description
    Tags          = $tags
  }
}

# GitHub manifest resolver (winget-pkgs) - adapted from AutoPackagerv2.ps1
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
  # Token (optional) from environment/config if available later
  if (-not $Token) {
    try {
      if ($script:Config -and $script:Config.GitHubToken) { $Token = [string]$script:Config.GitHubToken }
    } catch {}
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

  # Parse installer YAML for selection with optional powershell-yaml
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
        # Apply InstallerType preference from caller (msi/exe), default 'auto'
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
        # Keep order stable after filtering; just pick first valid with URL
        $sorted = $cands | Sort-Object @{ Expression = { 0 } }
        $sel = $sorted | Where-Object { $_.InstallerUrl } | Select-Object -First 1
        if (-not $sel) { $sel = $sorted | Select-Object -First 1 }
        if ($sel) {
          $selUrl  = $sel.InstallerUrl
          $selType = $sel.InstallerType
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

  # Parse locale YAML for metadata fallbacks
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
    InstallerYaml = $installerYaml
    Tags          = @()
  }
}

# Run a PowerShell command and capture stdout/stderr (blocking)
function Invoke-PSCapture {
  param(
    [Parameter(Mandatory=$true)][string]$Command,
    [switch]$NoProfile
  )
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = 'powershell.exe'
  $args = @()
  if ($NoProfile) { $args += '-NoProfile' }
  $args += '-ExecutionPolicy','Bypass','-Command', $Command
  $psi.Arguments = ($args | ForEach-Object { if ($_ -match '\s') { '"{0}"' -f ($_ -replace '"','\"') } else { $_ } }) -join ' '
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  [void]$p.Start()
  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  return [PSCustomObject]@{ ExitCode = $p.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

# Launch an external console window (for scripts that prompt user)
function Launch-ExternalPS([string]$file, [string]$args) {
  if (-not (Test-Path -LiteralPath $file)) {
    [System.Windows.Forms.MessageBox]::Show("Script not found:`r`n$file","Missing",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    return
  }
  $psArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$file`"")
  if ($args) { $psArgs += $args }
  Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs -WorkingDirectory $ScriptRoot
}

function Load-ConfigDefaults {
  try {
    if (Test-Path -LiteralPath $PathConfig) {
      $cfg = Get-Content -LiteralPath $PathConfig -Raw | ConvertFrom-Json
      if ($cfg) {
        try {
          function ClampDelay([int]$v){ if ($v -lt 0){0} elseif($v -gt 365){365} else {$v} }
          if ($cfg.RequiredUpdateDefaultGroups) {
            if ($cfg.RequiredUpdateDefaultGroups.PilotDelayDays -ne $null) { $script:DefaultRingDelay1 = ClampDelay([int]$cfg.RequiredUpdateDefaultGroups.PilotDelayDays) }
            if ($cfg.RequiredUpdateDefaultGroups.UATDelayDays -ne $null)    { $script:DefaultRingDelay2 = ClampDelay([int]$cfg.RequiredUpdateDefaultGroups.UATDelayDays) }
            if ($cfg.RequiredUpdateDefaultGroups.GADelayDays -ne $null)     { $script:DefaultRingDelay3 = ClampDelay([int]$cfg.RequiredUpdateDefaultGroups.GADelayDays) }
          }
        } catch {}
        try {
          if ($numRing1D) { $numRing1D.Value = [decimal][int]$script:DefaultRingDelay1 }
          if ($numRing2D) { $numRing2D.Value = [decimal][int]$script:DefaultRingDelay2 }
          if ($numRing3D) { $numRing3D.Value = [decimal][int]$script:DefaultRingDelay3 }
        } catch {}
        # Run mode
        try {
          $rm = $null
          if ($cfg.PackagingDefaults -and $cfg.PackagingDefaults.RunMode) { $rm = [string]$cfg.PackagingDefaults.RunMode }
          if ($rm) {
            if ($rm -ieq 'FullRun') { $rbFull.Checked = $true }
            elseif ($rm -ieq 'PackageOnly') { $rbPkg.Checked = $true }
            elseif ($rm -ieq 'DryRun') { $rbDry.Checked = $true }
          }
        } catch {}

        # Verify flags
        try {
          if ($cfg.IntuneUploadVerify) {
            if ($null -ne $cfg.IntuneUploadVerify.SkipVerify)   { $chkSkipVerify.Checked   = [bool]$cfg.IntuneUploadVerify.SkipVerify }
            if ($null -ne $cfg.IntuneUploadVerify.StrictVerify) { $chkStrictVerify.Checked = [bool]$cfg.IntuneUploadVerify.StrictVerify }
          }
        } catch {}

        # Winget tab defaults
        try {
          if ($cfg.PackagingDefaults) {
            if ($cfg.PackagingDefaults.WingetSource) { $tbSource.Text = [string]$cfg.PackagingDefaults.WingetSource }
            if ($cfg.PackagingDefaults.DefaultScope) {
              $scopeDef = [string]$cfg.PackagingDefaults.DefaultScope
              if (@('auto','machine','user') -contains $scopeDef) { $cbScope.SelectedItem = $scopeDef }
              if (@('','machine','user') -contains $scopeDef)    { $cbScopeEdit.SelectedItem = $scopeDef }
            }
            if ($cfg.PackagingDefaults.PreferArchitecture) {
              $arch = [string]$cfg.PackagingDefaults.PreferArchitecture
              try {
                $al = $arch.ToLower()
                if (@('x64','x86','arm64') -contains $al) { $script:PreferArchitecture = $al }
              } catch {}
            }
          }
        } catch {}

        # Notification defaults
        try {
          if ($cfg.Notification -and $cfg.Notification.Defaults) {
            if ($null -ne $cfg.Notification.Defaults.Enabled) { $chkNotifEnabled.Checked = [bool]$cfg.Notification.Defaults.Enabled }

            if ($cfg.Notification.Defaults.TimerMinutes) {
              $v = [int]$cfg.Notification.Defaults.TimerMinutes
              if ($v -lt [int]$numNotifMins.Minimum) { $v = [int]$numNotifMins.Minimum }
              if ($v -gt [int]$numNotifMins.Maximum) { $v = [int]$numNotifMins.Maximum }
              $numNotifMins.Value = [decimal]$v
            }

            if ($null -ne $cfg.Notification.Defaults.DeferralEnabled) { $chkDeferralEnabled.Checked = [bool]$cfg.Notification.Defaults.DeferralEnabled }

            if ($cfg.Notification.Defaults.DeferralHoursAllowed -ne $null) {
              $h = [int]$cfg.Notification.Defaults.DeferralHoursAllowed
              if ($h -lt [int]$numDefHours.Minimum) { $h = [int]$numDefHours.Minimum }
              if ($h -gt [int]$numDefHours.Maximum) { $h = [int]$numDefHours.Maximum }
              $numDefHours.Value = [decimal]$h
            }
          }
        } catch {}

      }
    }
  } catch {}
}
# ----- Main Form -----
$form = New-Object System.Windows.Forms.Form
$form.Text = "AutoPackager v3 - Winget to Intune Automation"
$form.StartPosition = 'CenterScreen'
$form.Width = 1200
$form.Height = 770
# Set custom window icon if a .ico is present (place AutoPackager.ico in script folder to brand the GUI)
try {
  $iconPathCandidates = @(
    (Join-Path $ScriptRoot 'AutoPackager.ico'),
    (Join-Path $ScriptRoot 'branding.ico'),
    (Join-Path $ScriptRoot 'icon.ico')
  )
  $ico = $iconPathCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if ($ico) { $form.Icon = New-Object System.Drawing.Icon($ico) }
} catch {}

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Left = 10; $tabs.Top = 10; $tabs.Width = $form.ClientSize.Width - 20; $tabs.Height = $form.ClientSize.Height - 20
$tabs.Anchor = 'Top,Left,Right,Bottom'
# Show tabs on multiple rows if there are many, so new tabs don't get hidden behind scroll arrows
try { $tabs.Multiline = $true } catch {}
$form.Controls.Add($tabs)

# ---------- Tab: Winget ----------
$tabWinget = New-Object System.Windows.Forms.TabPage
$tabWinget.Text = "Winget"
$tabs.TabPages.Add($tabWinget)

$lblWingetSearch = New-Label "Winget Search:" 10 15 100
$tbWingetSearch  = New-TextBox 110 12 260
$lblId = New-Label "Winget ID:" 10 50 100
$tbId  = New-TextBox 110 46 260
# Locale below Winget ID
$lblLocale = New-Label "Locale:" 10 80 100
$tbLocale  = New-TextBox 110 76 120
try { $tbLocale.Text = 'en-US' } catch {}

# New: Architecture selector (below Winget ID)
$lblArchWinget = New-Label "Architecture:" 750 15 100
$cbArchWinget  = New-Object System.Windows.Forms.ComboBox
$cbArchWinget.Left = 875
$cbArchWinget.Top  = 15
$cbArchWinget.Width = 120
$cbArchWinget.DropDownStyle = 'DropDownList'
$cbArchWinget.Items.AddRange(@('x64','x86','arm64'))
# Default to current preference if valid, else x64
try {
  $defArch = if ($script:PreferArchitecture -and @('x64','x86','arm64') -contains $script:PreferArchitecture) { $script:PreferArchitecture } else { 'x64' }
  $cbArchWinget.SelectedItem = $defArch
} catch {}
# Keep $script:PreferArchitecture in sync with selection
try {
  $cbArchWinget.Add_SelectedIndexChanged({
    try {
      $sel = [string]$cbArchWinget.SelectedItem
      if ($sel) {
        $script:PreferArchitecture = $sel.ToLower()
        # Sync to Recipe tab combo if present
        try { if ($cbArchRecipe) { $cbArchRecipe.SelectedItem = $sel } } catch {}
      }
    } catch {}
  })
} catch {}

# New: Installer Type selector (to the right of Architecture)
$lblInstTypeWinget = New-Label "Installer Type:" 750 50 100
$cbInstTypeWinget  = New-Object System.Windows.Forms.ComboBox
$cbInstTypeWinget.Left = 875
$cbInstTypeWinget.Top  = 46
$cbInstTypeWinget.Width = 120
$cbInstTypeWinget.DropDownStyle = 'DropDownList'
$cbInstTypeWinget.Items.AddRange(@('msi','exe'))
try { $cbInstTypeWinget.SelectedItem = 'msi' } catch {}
# Sync Installer Type selection from Winget tab to Recipe tab when changed
try {
  $cbInstTypeWinget.Add_SelectedIndexChanged({
    try {
      $selType = [string]$cbInstTypeWinget.SelectedItem
      if ($selType) {
        try { if ($cbInstTypeRecipe) { $cbInstTypeRecipe.SelectedItem = $selType.ToLower() } } catch {}
      }
    } catch {}
  })
} catch {}

$btnWingetRun  = New-Button "Search Winget" 400 10 140
$btnWingetShow = New-Button "Validate Winget ID" 400 42 140
$btnWingetDownload = New-Button "Download Installer" 790 74 140
$btnWingetShowYaml = New-Button "Show Installer YAML" 400 74 140

$txtWingetOut = New-TextBox 10 110 ($tabWinget.Width - 40) ($tabWinget.Height - 150) $true $true
$txtWingetOut.Anchor = 'Top,Left,Right,Bottom'

# Embedded results list (overlay on output area)
$lvWingetResults = New-Object System.Windows.Forms.ListView
$lvWingetResults.Left   = $txtWingetOut.Left
$lvWingetResults.Top    = $txtWingetOut.Top
$lvWingetResults.Width  = $txtWingetOut.Width
$lvWingetResults.Height = $txtWingetOut.Height
$lvWingetResults.Anchor = 'Top,Left,Right,Bottom'
$lvWingetResults.View   = 'Details'
$lvWingetResults.FullRowSelect = $true
$lvWingetResults.HideSelection = $false
# Columns: Name, Id, Version, Source
[void]$lvWingetResults.Columns.Add('Name', 260)
[void]$lvWingetResults.Columns.Add('Id', 280)
[void]$lvWingetResults.Columns.Add('Version', 120)
[void]$lvWingetResults.Columns.Add('Source', 120)
$lvWingetResults.Visible = $false
$tabWinget.Controls.Add($lvWingetResults)

# Selection handlers (double-click / Enter to choose, Esc to cancel)
$lvWingetResults.Add_DoubleClick({
  try {
    if ($lvWingetResults.SelectedItems.Count -gt 0) {
      $sel = $lvWingetResults.SelectedItems[0]
      $selId = ''
      try { $selId = [string]$sel.SubItems[1].Text } catch {}
      if ($selId) {
        try { $tbId.Text = $selId } catch {}
        try { Set-WingetIdAll $selId } catch {}
        try { Set-FindFromWinget $selId } catch {}
        Append-Output $txtWingetOut ("Selected: {0} [{1}]" -f $($sel.SubItems[0].Text), $selId)
      }
    }
  } catch {}
  $lvWingetResults.Visible = $false
  try { $txtWingetOut.Visible = $true } catch {}
})
$lvWingetResults.Add_KeyDown({
  param($sender,$e)
  try {
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
      if ($lvWingetResults.SelectedItems.Count -gt 0) {
        $sel = $lvWingetResults.SelectedItems[0]
        $selId = ''
        try { $selId = [string]$sel.SubItems[1].Text } catch {}
        if ($selId) {
          try { $tbId.Text = $selId } catch {}
          try { Set-WingetIdAll $selId } catch {}
          try { Set-FindFromWinget $selId } catch {}
          Append-Output $txtWingetOut ("Selected: {0} [{1}]" -f $($sel.SubItems[0].Text), $selId)
        }
      }
      $lvWingetResults.Visible = $false
      try { $txtWingetOut.Visible = $true } catch {}
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
      $lvWingetResults.Visible = $false
      try { $txtWingetOut.Visible = $true } catch {}
    }
  } catch {}
})

$tabWinget.Controls.AddRange(@($lblWingetSearch,$tbWingetSearch,$lblId,$tbId,$lblLocale,$tbLocale,$lblArchWinget,$cbArchWinget,$lblInstTypeWinget,$cbInstTypeWinget,$btnWingetRun,$btnWingetShow,$btnWingetDownload,$btnWingetShowYaml,$txtWingetOut))

$btnWingetShow.Add_Click({
  $id = $tbId.Text.Trim()
  if (-not $id) { [System.Windows.Forms.MessageBox]::Show("Enter a Winget ID.","Input",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null; return }
  try { $tbWingetForNew.Text = $id } catch {}

  # Validate using Microsoft.WinGet.Client (no winget.exe show)
  $txtWingetOut.Clear()
  $modName = 'Microsoft.WinGet.Client'
  $mod = Get-Module -ListAvailable -Name $modName | Select-Object -First 1
  if (-not $mod) {
    Append-Output $txtWingetOut "PowerShell module 'Microsoft.WinGet.Client' not found. Install it with:`r`n  Install-Module Microsoft.WinGet.Client -Scope CurrentUser"
    return
  }
  Import-Module $modName -ErrorAction SilentlyContinue | Out-Null

  $src = $null
  try { if ($tbSource -and $tbSource.Text) { $src = $tbSource.Text.Trim() } } catch {}
  $cmdMsg = "Find-WinGetPackage -Id `"$id`" -MatchOption Equals"
  if ($src) { $cmdMsg += " -Source `"$src`"" }
  Append-Output $txtWingetOut ("Running: " + $cmdMsg)

  $result = $null
  try {
    if ($src) { $result = Find-WinGetPackage -Id $id -MatchOption Equals -Source $src }
    else { $result = Find-WinGetPackage -Id $id -MatchOption Equals }
  } catch {
    Append-Output $txtWingetOut ("Validation error: " + $_.Exception.Message)
    $result = $null
  }

  if ($result) {
    $first = $null
    if ($result -is [System.Array]) {
      if ($result.Count -gt 0) { $first = $result[0] }
    } else {
      $first = $result
    }
    if ($first) {
      # Output validation details to the Winget output box (no popup)
      $nm=''; $idv=''; $ver=''; $srcv=''; $pub=''
      try { if ($first.Name)      { $nm  = [string]$first.Name } } catch {}
      try { if ($first.Id)        { $idv = [string]$first.Id } } catch {}
      try { if ($first.Version)   { $ver = [string]$first.Version } } catch {}
      try { if ($first.Source)    { $srcv= [string]$first.Source } } catch {}

      Append-Output $txtWingetOut "----- Validation (Success) -----"
      try { if ($nm)   { Append-Output $txtWingetOut ("Name: " + $nm) } } catch {}
      try { if ($idv)  { Append-Output $txtWingetOut ("Id: " + $idv) } } catch {}
      try { if ($ver)  { Append-Output $txtWingetOut ("Version: " + $ver) } } catch {}
      try { if ($srcv) { Append-Output $txtWingetOut ("Source: " + $srcv) } } catch {}

      try { Set-WingetIdAll $id } catch {}
    } else {
          Append-Output $txtWingetOut "----- Validation (Error) -----"
          Append-Output $txtWingetOut "No exact match returned."
          Append-Output $txtWingetOut "Winget IDs are Case Sensistive."
          Append-Output $txtWingetOut "Ensure ID is correct."
    }
  } else {
    Append-Output $txtWingetOut "----- Validation (Error) -----"
    Append-Output $txtWingetOut "No exact match returned."
    Append-Output $txtWingetOut "Winget IDs are Case Sensistive."
    Append-Output $txtWingetOut "Ensure ID is correct."
  }
})

# Show Installer YAML (prints the installer YAML to the Winget output box)
$btnWingetShowYaml.Add_Click({
  try {
    try { $txtWingetOut.Clear() } catch {}

    # Resolve Winget ID from available fields
    $idToUse = ''
    try { if ($tbId -and $tbId.Text) { $idToUse = $tbId.Text.Trim() } } catch {}
    if (-not $idToUse) { try { if ($tbWingetApps -and $tbWingetApps.Text) { $idToUse = $tbWingetApps.Text.Trim() } } catch {} }
    if (-not $idToUse) { try { if ($tbWingetForNew -and $tbWingetForNew.Text) { $idToUse = $tbWingetForNew.Text.Trim() } } catch {} }
    if (-not $idToUse) {
      [System.Windows.Forms.MessageBox]::Show("Enter a Winget ID on the Winget or Intune App(s) tab.","Show YAML",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
      return
    }

    # Architecture preference
    $archSel = 'x64'
    try {
      if ($cbArchWinget -and $cbArchWinget.SelectedItem) { $archSel = [string]$cbArchWinget.SelectedItem }
      elseif ($script:PreferArchitecture) { $archSel = [string]$script:PreferArchitecture }
    } catch {}

    Append-Output $txtWingetOut ("Fetching installer YAML for Id='{0}', Arch='{1}' ..." -f $idToUse, $archSel)

    $p = $null
    try {
      # Use GitHub manifest resolver; prefer machine scope, auto installer type
      $loc = 'en-US'
      try { if ($tbLocale -and $tbLocale.Text -and $tbLocale.Text.Trim()) { $loc = $tbLocale.Text.Trim() } } catch {}
      $p = Get-WingetManifestInfoFromGitHub -WingetId $idToUse -PreferArchitecture $archSel -PreferScope 'machine' -PreferInstallerType 'auto' -DesiredLocale $loc
    } catch {
      Append-Output $txtWingetOut ("GitHub resolve error: " + $_.Exception.Message)
      $p = $null
    }

    if (-not $p -or -not $p.InstallerYaml) {
      Append-Output $txtWingetOut "Installer YAML not available."
      return
    }

    Append-Output $txtWingetOut "----- Installer YAML -----"
    Append-Output $txtWingetOut $p.InstallerYaml
  } catch {
    Append-Output $txtWingetOut ("Show YAML error: " + $_.Exception.Message)
  }
})

$btnWingetRun.Add_Click({
  try {
    # Blank out Winget ID when a new search is initiated (also triggers sync + reset)
    try { if ($tbId) { $tbId.Text = '' } } catch {}
    try { $txtWingetOut.Clear() } catch {}
    $q = ''
    try { if ($tbWingetSearch -and $tbWingetSearch.Text) { $q = $tbWingetSearch.Text.Trim() } } catch {}
    if (-not $q) {
      [System.Windows.Forms.MessageBox]::Show("Enter a search term in 'Winget Search'.","Search Winget",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
      return
    }

    # Use Microsoft.WinGet.Client PowerShell module (no winget.exe)
    $modName = 'Microsoft.WinGet.Client'
    $mod = Get-Module -ListAvailable -Name $modName | Select-Object -First 1
    if (-not $mod) {
      [System.Windows.Forms.MessageBox]::Show("PowerShell module 'Microsoft.WinGet.Client' not found. Install it with:`r`nInstall-Module Microsoft.WinGet.Client -Scope CurrentUser","Search Winget",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
      return
    }
    Import-Module $modName -ErrorAction SilentlyContinue | Out-Null

    $args = @{ Query = $q }
    try {
      if ($tbSource -and $tbSource.Text -and $tbSource.Text.Trim()) { $args['Source'] = $tbSource.Text.Trim() }
    } catch {}

    $cmdMsg = "Find-WinGetPackage -Query `"$q`""
    try { if ($args.ContainsKey('Source')) { $cmdMsg += " -Source `"$($args['Source'])`"" } } catch {}
    Append-Output $txtWingetOut ("Running: " + $cmdMsg)

    $results = $null
    try {
      if ($args.ContainsKey('Source')) { $results = Find-WinGetPackage -Query $args.Query -Source $args.Source }
      else { $results = Find-WinGetPackage -Query $args.Query }
    } catch {
      Append-Output $txtWingetOut ("Search error: " + $_.Exception.Message)
      $results = $null
    }

    $items = @()
    if ($results) {
      foreach ($r in $results) {
        $id  = ''
        $nm  = ''
        $ver = ''
        $src = ''
        try { if ($r.Id) { $id = [string]$r.Id } } catch {}
        try { if (-not $id -and $r.PackageIdentifier) { $id = [string]$r.PackageIdentifier } } catch {}
        try { if ($r.Name) { $nm = [string]$r.Name } } catch {}
        try { if ($r.Version) { $ver = [string]$r.Version } } catch {}
        try { if ($r.Source) { $src = [string]$r.Source } } catch {}
        if ($id -or $nm) { $items += [pscustomobject]@{ Name=$nm; Id=$id; Version=$ver; Source=$src } }
      }
    }

    Append-Output $txtWingetOut ("Matches: " + ($items.Count))
    if (-not $items -or $items.Count -eq 0) {
      [System.Windows.Forms.MessageBox]::Show("No winget packages found for: $q","Search Winget",0,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
      return
    }

    if ($items.Count -eq 1) {
      $chosen = $items[0]
      $selId = ''
      try { $selId = [string]$chosen.Id } catch {}
      if ($selId) {
        try { $tbId.Text = $selId } catch {}
        try { Set-WingetIdAll $selId } catch {}
        try { Set-FindFromWinget $selId } catch {}
        Append-Output $txtWingetOut ("Selected: {0} [{1}]" -f ($chosen.DisplayName), $selId)
      } else {
        [System.Windows.Forms.MessageBox]::Show("Selected entry missing Id.","Search Winget",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
      }
    } else {
      # Populate embedded results list within the Winget tab (no popup)
      try { $lvWingetResults.Items.Clear() } catch {}
      foreach ($it in $items) {
        $nameText = if ($it.Name) { [string]$it.Name } elseif ($it.DisplayName) { [string]$it.DisplayName } else { '' }
        $idText   = if ($it.Id) { [string]$it.Id } else { '' }
        $verText  = if ($it.Version) { [string]$it.Version } else { '' }
        $srcText  = if ($it.Source) { [string]$it.Source } else { '' }
        $lvi = New-Object System.Windows.Forms.ListViewItem($nameText)
        [void]$lvi.SubItems.Add($idText)
        [void]$lvi.SubItems.Add($verText)
        [void]$lvi.SubItems.Add($srcText)
        $lvi.Tag = $it
        [void]$lvWingetResults.Items.Add($lvi)
      }
      Append-Output $txtWingetOut "Select a package from the list (double-click or press Enter). Press Esc to cancel."
      try { $txtWingetOut.Visible = $false } catch {}
      $lvWingetResults.Visible = $true
      return
    }
  } catch {
    Append-Output $txtWingetOut ("Search error: " + $_.Exception.Message)
  }
})

# Download Installer -> Testing\Publisher\Name\Version
$btnWingetDownload.Add_Click({
  try {
    try { $txtWingetOut.Clear() } catch {}

    # Resolve Winget ID
    $idToUse = ''
    try { if ($tbId -and $tbId.Text) { $idToUse = $tbId.Text.Trim() } } catch {}
    if (-not $idToUse) { try { if ($tbWingetApps -and $tbWingetApps.Text) { $idToUse = $tbWingetApps.Text.Trim() } } catch {} }
    if (-not $idToUse) { try { if ($tbWingetForNew -and $tbWingetForNew.Text) { $idToUse = $tbWingetForNew.Text.Trim() } } catch {} }
    if (-not $idToUse) {
      [System.Windows.Forms.MessageBox]::Show("Enter a Winget ID on the Winget or Intune App(s) tab.","Download",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
      return
    }

    # Prefer architecture from the Winget tab dropdown; fallback to current script preference
    $archSel = 'x64'
    try {
      if ($cbArchWinget -and $cbArchWinget.SelectedItem) { $archSel = [string]$cbArchWinget.SelectedItem }
      elseif ($script:PreferArchitecture) { $archSel = [string]$script:PreferArchitecture }
    } catch {}

    Append-Output $txtWingetOut ("Resolving installer via GitHub manifests for Id='{0}', Arch='{1}' ..." -f $idToUse, $archSel)

    # Installer Type preference from dropdown
    $typeSel = 'msi'
    try { if ($cbInstTypeWinget -and $cbInstTypeWinget.SelectedItem) { $typeSel = [string]$cbInstTypeWinget.SelectedItem } } catch {}

    $p = $null
    try {
      # Use GitHub API manifest logic (no winget.exe); prefer machine scope for installers
      $loc = 'en-US'
      try { if ($tbLocale -and $tbLocale.Text -and $tbLocale.Text.Trim()) { $loc = $tbLocale.Text.Trim() } } catch {}
      $p = Get-WingetManifestInfoFromGitHub -WingetId $idToUse -PreferArchitecture $archSel -PreferScope 'machine' -PreferInstallerType $typeSel -DesiredLocale $loc
    } catch {
      Append-Output $txtWingetOut ("GitHub resolve error: " + $_.Exception.Message)
      $p = $null
    }

    if (-not $p -or -not $p.InstallerUrl) {
      [System.Windows.Forms.MessageBox]::Show("Failed to resolve installer from GitHub manifests for:`r`n$idToUse","Download",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
      return
    }

    # Cache last parsed selection for downstream use
    try { $script:LastWingetParsed = $p } catch {}

    $url = $p.InstallerUrl
    # Normalize SourceForge '.../download' links to direct mirror URL for reliable binary download
    try {
      if ($url -match '^(?i)https?://sourceforge\.net/projects?/([^/]+)/files/(.+?)/download/?$') {
        $proj = $matches[1]; $pathSegs = $matches[2]
        $sfDirect = "https://downloads.sourceforge.net/project/$proj/$pathSegs"
        Append-Output $txtWingetOut ("SourceForge link detected; switching to direct mirror URL:`r`n  {0}" -f $sfDirect)
        $url = $sfDirect
      }
    } catch {}

    $name = if ($p.Name) { [string]$p.Name } elseif ($tbId.Text.Trim()) { $tbId.Text.Trim() } else { 'UnknownApp' }
    $publisher = if ($p.Publisher) { [string]$p.Publisher } else { 'UnknownPublisher' }
    $version = if ($p.Version) { [string]$p.Version } else { '0.0.0' }

    if (-not $url -or [string]::IsNullOrWhiteSpace($url)) {
      [System.Windows.Forms.MessageBox]::Show("Parsed InstallerUrl is empty. Ensure metadata is available for this Winget ID.","Download",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
      return
    }

    $pubSafe = Sanitize-Leaf $publisher
    $nameSafe = Sanitize-Leaf $name
    $verSafe = Sanitize-Leaf $version

    $root = Join-Path $ScriptRoot 'Testing'
    $targetDir = Join-Path (Join-Path (Join-Path $root $pubSafe) $nameSafe) $verSafe
    $null = New-Item -ItemType Directory -Path $targetDir -Force -ErrorAction SilentlyContinue

    # Derive filename from URL
    try { $u = [Uri]$url } catch { $u = $null }
    if ($u) {
      $fileName = [IO.Path]::GetFileName($u.LocalPath)
    } else {
      $fileName = ($url -split '\?')[0] -split '/' | Select-Object -Last 1
    }
    if (-not $fileName -or [string]::IsNullOrWhiteSpace($fileName)) {
      $fileName = ($nameSafe + '.bin')
    }
    $dest = Join-Path $targetDir $fileName

    Append-Output $txtWingetOut ""
    Append-Output $txtWingetOut ("Downloading:`r`n  Url: {0}`r`n  To:  {1}" -f $url, $dest)

    # Prefer TLS 1.2 and a common UA
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    $headers = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'; 'Accept'='*/*' }
    # SourceForge behaves differently with browser UAs; use a CLI-like UA to trigger direct mirror redirects
    try { if ($url -match '(?i)sourceforge\.net') { $headers['User-Agent'] = 'Wget/1.21.4' } } catch {}

    $downloaded = $false
    try {
      $prevPP = $ProgressPreference
      $ProgressPreference = 'SilentlyContinue'
      try {
        Invoke-WebRequest -Uri $url -OutFile $dest -Headers $headers -UseBasicParsing -TimeoutSec 300 -MaximumRedirection 10 -ErrorAction Stop
        $downloaded = $true
      } finally {
        $ProgressPreference = $prevPP
      }
    } catch {
      Append-Output $txtWingetOut ("Invoke-WebRequest failed: " + $_.Exception.Message)
    }

    # Attempt to resolve redirect (e.g., SourceForge mirrors) via HEAD Location and retry once
    if (-not $downloaded) {
      try {
        $redir = $null
        try {
          $resp = Invoke-WebRequest -Uri $url -Headers $headers -Method Head -MaximumRedirection 0 -ErrorAction Stop
        } catch {
          try { $resp = $_.Exception.Response } catch {}
        }
        if ($resp -and $resp.Headers -and $resp.Headers['Location']) { $redir = [string]$resp.Headers['Location'] }
        if ($redir) {
          try {
            $base2 = ($redir -split '\?')[0]
            $fileName2 = Split-Path -Leaf $base2
            if ($fileName2 -and ($fileName2 -ne $fileName)) {
              $dest = Join-Path $targetDir $fileName2
              Append-Output $txtWingetOut ("Redirect resolved. New file name: " + $fileName2)
            }
          } catch {}
          try {
            Invoke-WebRequest -Uri $redir -OutFile $dest -Headers $headers -UseBasicParsing -TimeoutSec 300 -MaximumRedirection 10 -ErrorAction Stop
            $downloaded = $true
          } catch {
            Append-Output $txtWingetOut ("Invoke-WebRequest (redirect) failed: " + $_.Exception.Message)
          }
        }
      } catch {}
    }

    if (-not $downloaded) {
      try {
        Start-BitsTransfer -Source $url -Destination $dest -ErrorAction Stop
        $downloaded = $true
      } catch {
        Append-Output $txtWingetOut ("BITS transfer failed: " + $_.Exception.Message)
      }
    }

    if ($downloaded -and (Test-Path -LiteralPath $dest)) {
      $fi = Get-Item -LiteralPath $dest -ErrorAction SilentlyContinue
      Append-Output $txtWingetOut ("Download complete ({0} bytes) -> {1}" -f ($fi.Length), $dest)
      [System.Windows.Forms.MessageBox]::Show("Download complete:`r`n$dest","Download",0,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } else {
      [System.Windows.Forms.MessageBox]::Show("Download failed. See output for details.","Download",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
  } catch {
    Append-Output $txtWingetOut ("Download error: " + $_.Exception.Message)
    [System.Windows.Forms.MessageBox]::Show("Download error: $($_.Exception.Message)","Download",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
  }
})

# ---------- Tab: Intune App(s) ----------
$tabApps = New-Object System.Windows.Forms.TabPage
$tabApps.Text = "Intune App(s)"
$tabs.TabPages.Add($tabApps)

# Winget ID (synced)
$lblWingetApps = New-Label "Winget ID:" 10 15 100
$tbWingetApps  = New-TextBox 110 12 260
$tabApps.Controls.AddRange(@($lblWingetApps,$tbWingetApps))


# Create App(s) group
$grpCreateApps = New-Group "Create App(s)" 10 50 520 130
$lblIcon   = New-Label "Icon:" 10 28 60
$tbIcon    = New-TextBox 70 25 300
$btnBrowseIcon = New-Button "Browse..." 380 23 100
$btnCreatePrimary   = New-Button "Create Primary App" 10 70 220
$btnCreateSecondary = New-Button "Create Required Update App" 240 70 220
$grpCreateApps.Controls.AddRange(@($lblIcon,$tbIcon,$btnBrowseIcon,$btnCreatePrimary,$btnCreateSecondary))
$tabApps.Controls.Add($grpCreateApps)

# App Id(s) group to the right of Create App(s)
$grpAppIds = New-Group "AppId(s)" 540 50 520 130
$lblPrimAppId = New-Label "Primary AppId:" 10 28 120
$tbAppsPrimId = New-TextBox 130 25 360
$lblSecAppId = New-Label "Required Update AppId:" 10 60 160
$tbAppsSecId = New-TextBox 170 57 320
$btnResetAppIds = New-Button "Reset AppId(s)" 370 90 140
# Make these fields read-only; they will be populated by Create/Find actions only
try { $tbAppsPrimId.ReadOnly = $true } catch {}
try { $tbAppsSecId.ReadOnly = $true } catch {}
# Reset button: clears AppId(s) on this tab and corresponding Recipe tab fields
$btnResetAppIds.Add_Click({
  try { $txtAppsOut.Clear() } catch {}
  try { $tbAppsPrimId.Text = '' } catch {}
  try { $tbAppsSecId.Text = '' } catch {}
  try { $tbIntuneId.Text = '' } catch {}
  try { $tbSecondary.Text = '' } catch {}
})
$grpAppIds.Controls.AddRange(@($lblPrimAppId,$tbAppsPrimId,$lblSecAppId,$tbAppsSecId,$btnResetAppIds))
$tabApps.Controls.Add($grpAppIds)

# Select Existing App(s) group
$grpSelectApps = New-Group "Select Existing App(s)" 10 190 520 120
$lblFind   = New-Label "Search Name:" 10 28 100
$tbFind    = New-TextBox 110 25 260
$btnFindPrimary   = New-Button "Find Primary App" 10 60 160
$btnFindSecondary = New-Button "Find Required Update App" 180 60 160
$grpSelectApps.Controls.AddRange(@($lblFind,$tbFind,$btnFindPrimary,$btnFindSecondary))
$tabApps.Controls.Add($grpSelectApps)

# Output box
$txtAppsOut = New-TextBox 10 320 ($tabApps.Width - 40) ($tabApps.Height - 360) $true $true
$txtAppsOut.Anchor = 'Top,Left,Right,Bottom'
$tabApps.Controls.Add($txtAppsOut)

# Icon picker
$ofdIcon = New-Object System.Windows.Forms.OpenFileDialog
$ofdIcon.Filter = "Image Files (*.png;*.jpg;*.jpeg)|*.png;*.jpg;*.jpeg|All files (*.*)|*.*"
try {
  $pref = Get-DefaultIconDirectory
  if ($pref) { $ofdIcon.InitialDirectory = $pref }
} catch {}
$btnBrowseIcon.Add_Click({
  try { $txtAppsOut.Clear() } catch {}
  try {
    # Prefer configured default directory
    $pref = Get-DefaultIconDirectory
    if ($pref) { $ofdIcon.InitialDirectory = $pref }
    # If textbox already points to a valid file/folder, prefer that folder
    $hint = $tbIcon.Text
    if ($hint -and (Test-Path -LiteralPath $hint)) {
      $cand = if (Test-Path -LiteralPath $hint -PathType Leaf) { Split-Path -Parent $hint } else { $hint }
      if ($cand -and (Test-Path -LiteralPath $cand)) { $ofdIcon.InitialDirectory = $cand }
    }
  } catch {}
  if ($ofdIcon.ShowDialog() -eq 'OK') { $tbIcon.Text = $ofdIcon.FileName }
})

# Sync Winget ID across tabs
function Set-FindFromWinget([string]$wingetId) {
  try {
    $vendor = $null
    if ($wingetId) {
      $parts = $wingetId -split '\.'
      if ($parts -and $parts[0]) { $vendor = $parts[0] }
    }
    if ($vendor) {
      # Bottom search box (existing)
      try {
        $current = $tbFind.Text
        if ([string]::IsNullOrWhiteSpace($current) -or ($current -eq $script:LastAutoFind)) {
          $tbFind.Text = $vendor
        }
      } catch {}
      # Top search box (new duplicate section)
      try {
        if ($tbFindTop) {
          $currentTop = $tbFindTop.Text
          if ([string]::IsNullOrWhiteSpace($currentTop) -or ($currentTop -eq $script:LastAutoFind)) {
            $tbFindTop.Text = $vendor
          }
        }
      } catch {}
      # Recipe tab search box (new)
      try {
        if ($tbFindRecipe) {
          $currentR = $tbFindRecipe.Text
          if ([string]::IsNullOrWhiteSpace($currentR) -or ($currentR -eq $script:LastAutoFind)) {
            $tbFindRecipe.Text = $vendor
          }
        }
      } catch {}
      # Reset tab search box
      try {
        if ($tbFindReset) {
          $currentReset = $tbFindReset.Text
          if ([string]::IsNullOrWhiteSpace($currentReset) -or ($currentReset -eq $script:LastAutoFind)) {
            $tbFindReset.Text = $vendor
          }
        }
      } catch {}
      $script:LastAutoFind = $vendor
    }
  } catch {}
}
try {
  $tbWingetApps.Add_TextChanged({
    try {
      if ($script:WingetSyncing) { return }
      Reset-GuiOnWingetChange
      Set-WingetIdAll ($tbWingetApps.Text)
      Set-FindFromWinget ($tbWingetApps.Text)
    } catch {}
  })
  $tbId.Add_TextChanged({
    try {
      if ($script:WingetSyncing) { return }
      Reset-GuiOnWingetChange
      Set-WingetIdAll ($tbId.Text)
      Set-FindFromWinget ($tbId.Text)
    } catch {}
  })
} catch {}

# Selection dialog for multiple Intune app matches
function Select-AppFromList([array]$apps, [string]$title = "Select App") {
  $form = New-Object System.Windows.Forms.Form
  $form.Text = $title
  $form.StartPosition = 'CenterParent'
  $form.Width = 700
  $form.Height = 400

  $lb = New-Object System.Windows.Forms.ListBox
  $lb.Left = 10; $lb.Top = 10
  $lb.Width = $form.ClientSize.Width - 20
  $lb.Height = $form.ClientSize.Height - 60
  $lb.Anchor = 'Top,Left,Right,Bottom'
  $lb.IntegralHeight = $false

  $display = @()
  foreach ($a in $apps) {
    $dn = if ($a.DisplayName) { [string]$a.DisplayName } else { '' }
    $pub = if ($a.Publisher) { [string]$a.Publisher } else { '' }
    $id  = if ($a.Id) { [string]$a.Id } else { '' }
    $display += ("{0}  ({1})  [{2}]" -f $dn, $pub, $id)
  }
  if ($display.Count -gt 0) { $lb.Items.AddRange($display) }
  $form.Controls.Add($lb)

  $btnOK = New-Object System.Windows.Forms.Button
  $btnOK.Text = 'OK'
  $btnOK.Width = 80
  $btnOK.Left = $form.ClientSize.Width - 180
  $btnOK.Top  = $form.ClientSize.Height - 40
  $btnOK.Anchor = 'Right,Bottom'

  $btnCancel = New-Object System.Windows.Forms.Button
  $btnCancel.Text = 'Cancel'
  $btnCancel.Width = 80
  $btnCancel.Left = $form.ClientSize.Width - 90
  $btnCancel.Top  = $form.ClientSize.Height - 40
  $btnCancel.Anchor = 'Right,Bottom'

  $form.Controls.AddRange(@($btnOK,$btnCancel))
  $selected = $null
  $btnOK.Add_Click({ if ($lb.SelectedIndex -ge 0) { $script:__selIdx = $lb.SelectedIndex; $form.DialogResult = [System.Windows.Forms.DialogResult]::OK } })
  $btnCancel.Add_Click({ $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel })
  $form.AcceptButton = $btnOK
  $form.CancelButton = $btnCancel

  $script:__selIdx = -1
  $null = $form.ShowDialog()
  if ($script:__selIdx -ge 0 -and $apps.Count -gt $script:__selIdx) {
    $selected = $apps[$script:__selIdx]
  }
  Remove-Variable -Name __selIdx -Scope Script -ErrorAction SilentlyContinue
  return $selected
}

# Helpers to build metadata from parsed winget
function Get-ParsedOrFallbackName() {
  try {
    if ($script:LastWingetParsed -and $script:LastWingetParsed.Name) { return [string]$script:LastWingetParsed.Name }
  } catch {}
  try {
    $idv = $tbId.Text; if ($idv -and $idv.Trim()) { return $idv.Trim() }
  } catch {}
  return 'App'
}
function Get-ParsedVersion() {
  try {
    if ($script:LastWingetParsed -and $script:LastWingetParsed.Version) { return [string]$script:LastWingetParsed.Version }
  } catch {}
  return ''
}

# Determine if Quick Edit has meaningful data to apply
function Has-QuickEditData {
  try {
    if ($tbIntuneId -and [string]::IsNullOrWhiteSpace($tbIntuneId.Text) -eq $false) { return $true }
    if ($tbSecondary -and [string]::IsNullOrWhiteSpace($tbSecondary.Text) -eq $false) { return $true }
    if ($cbScopeEdit -and $cbScopeEdit.SelectedItem -and [string]$cbScopeEdit.SelectedItem -ne '') { return $true }
    if ($tbInstallArgs -and [string]::IsNullOrWhiteSpace($tbInstallArgs.Text) -eq $false) { return $true }
    if ($tbUninstArgs -and [string]::IsNullOrWhiteSpace($tbUninstArgs.Text) -eq $false) { return $true }
    if ($chkForceUninstall -and $chkForceUninstall.Checked) { return $true }
    if ($tbFTC -and [string]::IsNullOrWhiteSpace($tbFTC.Text) -eq $false) { return $true }
    if ($chkNotifEnabled -and $chkNotifEnabled.Checked) { return $true }
    if ($chkDeferralEnabled -and $chkDeferralEnabled.Checked) { return $true }
    if ($tbRing1G -and [string]::IsNullOrWhiteSpace($tbRing1G.Text) -eq $false) { return $true }
    if ($tbRing2G -and [string]::IsNullOrWhiteSpace($tbRing2G.Text) -eq $false) { return $true }
    if ($tbRing3G -and [string]::IsNullOrWhiteSpace($tbRing3G.Text) -eq $false) { return $true }
  } catch {}
  return $false
}

# New helper: reset GUI to defaults when Winget ID changes
function Reset-GuiOnWingetChange {
  try {
    # Quick Edit clearing
    try { $tbIntuneId.Text = '' } catch {}
    try { $tbSecondary.Text = '' } catch {}
    try { if ($cbScopeEdit -and $cbScopeEdit.Items -and $cbScopeEdit.Items.Count -gt 0) { $cbScopeEdit.SelectedIndex = 0 } } catch {}
    try { $tbInstallArgs.Text = '' } catch {}
    try { $tbUninstArgs.Text = '' } catch {}
    try { $chkForceUninstall.Checked = $false } catch {}
    try { $chkAllowAvailUninst.Checked = $script:DefaultAllowAvailableUninstall } catch {}
    try { $tbFTC.Text = '' } catch {}
    # Notification defaults (baseline)
    try { $chkNotifEnabled.Checked = $false } catch {}
    try { $chkDeferralEnabled.Checked = $false } catch {}
    try { $numNotifMins.Value = [decimal]2 } catch {}
    try { $numDefHours.Value = [decimal]24 } catch {}
    # Rings reset
    try { $tbRing1G.Text = '' } catch {}
    try { $tbRing2G.Text = '' } catch {}
    try { $tbRing3G.Text = '' } catch {}
    try { $numRing1D.Value = [decimal][int]$script:DefaultRingDelay1 } catch {}
    try { $numRing2D.Value = [decimal][int]$script:DefaultRingDelay2 } catch {}
    try { $numRing3D.Value = [decimal][int]$script:DefaultRingDelay3 } catch {}
    # Clear ring filters and reset filter type to Include
    try { $tbRing1F.Text = '' } catch {}
    try { $tbRing2F.Text = '' } catch {}
    try { $tbRing3F.Text = '' } catch {}
    try { if ($cbRing1FT) { $cbRing1FT.SelectedIndex = 0 } } catch {}
    try { if ($cbRing2FT) { $cbRing2FT.SelectedIndex = 0 } } catch {}
    try { if ($cbRing3FT) { $cbRing3FT.SelectedIndex = 0 } } catch {}
    # AppId(s) reset across tabs
    try { $tbAppsPrimId.Text = '' } catch {}
    try { $tbAppsSecId.Text = '' } catch {}
    try { $tbPrim.Text = '' } catch {}
    try { $tbSecId.Text = '' } catch {}
    # Recipe and Run tab selected recipe paths
    try { $tbRecipePath.Text = '' } catch {}
    try { $tbRunPath.Text = '' } catch {}
    # Clear outputs
    try { if ($txtWingetOut) { $txtWingetOut.Clear() } } catch {}
    try { if ($txtAppsOut) { $txtAppsOut.Clear() } } catch {}
  } catch {}
}

# Create Primary
$btnCreatePrimary.Add_Click({
  try {
    try { $txtAppsOut.Clear() } catch {}
    if (-not (Test-Path -LiteralPath $PathCreateTemplate)) {
      [System.Windows.Forms.MessageBox]::Show("Helper not found:`r`n$PathCreateTemplate","Missing",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
      return
    }
    if (-not $script:LastWingetParsed -or -not $script:LastWingetParsed.Name -or ($tbId.Text.Trim() -and $script:LastWingetParsed.Id -ne $tbId.Text.Trim())) {
      $idToUse = $tbId.Text
      if (-not $idToUse -or -not $idToUse.Trim()) { $idToUse = $tbWingetApps.Text }
      $idToUse = $idToUse.Trim()
      if (-not $idToUse) {
        [System.Windows.Forms.MessageBox]::Show("Enter a Winget ID on the Winget or Intune App(s) tab.","Input",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
      }
      $parsed = Ensure-WingetParsed $idToUse
      if ($parsed) {
        $script:LastWingetParsed = $parsed
      } else {
        Append-Output $txtAppsOut "Failed to parse winget metadata for the specified ID."
      }
    }
    if (-not $script:LastWingetParsed) {
      [System.Windows.Forms.MessageBox]::Show("Failed to parse winget metadata for the specified ID.","Info",0,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
      return
    }
    $p = $script:LastWingetParsed
    $baseName = Get-ParsedOrFallbackName
    $ver = Get-ParsedVersion
    $display = ($baseName + ($(if ($ver) { " $ver" } else { "" })))
    $publisher = if ($p.Publisher) { [string]$p.Publisher } else { "UnknownPublisher" }
    $developer = if ($p.Author)    { [string]$p.Author } else { "" }
    $desc = if ($p.Description)    { [string]$p.Description } else { "" }
    if ($desc.Length -gt 1800) { $desc = $desc.Substring(0,1800) } # conservative cap
    $info = if ($p.Homepage)   { [string]$p.Homepage } else { "" }
    $priv = if ($p.PrivacyUrl) { [string]$p.PrivacyUrl } else { "" }
    $icon = $tbIcon.Text
    # Read AllowAvailableUninstall from AutoPackager.config.json (default: false)
    $allowUninstall = $false
    try {
      if (Test-Path -LiteralPath $PathConfig) {
        $cfg = Get-Content -LiteralPath $PathConfig -Raw | ConvertFrom-Json
        if ($cfg -and ($cfg.PSObject.Properties.Name -contains 'AllowAvailableUninstall') -and ($null -ne $cfg.AllowAvailableUninstall)) {
          $allowUninstall = [bool]$cfg.AllowAvailableUninstall
        }
      }
    } catch {}

    $cmd = "& `"$PathCreateTemplate`" -DisplayName `"$display`" -Publisher `"$publisher`""
    if ($icon -and $icon.Trim()) { $cmd += " -IconPath `"$($icon.Trim())`"" }
    # Always use placeholder version for created apps
    $boolToken = if ($allowUninstall) { '$true' } else { '$false' }
    $cmd += " -AppVersion '0.1' -AllowAvailableUninstall:$boolToken"

    Append-Output $txtAppsOut ("Running: " + $cmd)
    $res = Invoke-PSCapture -Command $cmd -NoProfile
    if ($res.StdOut) { Append-Output $txtAppsOut $res.StdOut.TrimEnd() }
    if ($res.StdErr) { Append-Output $txtAppsOut ("[stderr]`r`n" + $res.StdErr.TrimEnd()) }
    $appId = $null
    try {
      if ($res.StdOut -match 'AppId:\s*([0-9A-Fa-f-]{36})') { $appId = $matches[1] }
    } catch {}
    if ($appId) {
      try { $tbIntuneId.Text = $appId } catch {}
      try { $tbAppsPrimId.Text = $appId } catch {}
      [System.Windows.Forms.MessageBox]::Show("Primary App created.`r`nAppId: $appId","Create Primary",0,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } else {
      [System.Windows.Forms.MessageBox]::Show("Create Primary completed. AppId not detected in output; see log.","Create Primary",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
  } catch {
    Append-Output $txtAppsOut ("Create Primary error: " + $_.Exception.Message)
    [System.Windows.Forms.MessageBox]::Show("Create Primary error: $($_.Exception.Message)","Error",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
  }
})

# Create Secondary
$btnCreateSecondary.Add_Click({
  try {
    try { $txtAppsOut.Clear() } catch {}
    if (-not (Test-Path -LiteralPath $PathCreateTemplate)) {
      [System.Windows.Forms.MessageBox]::Show("Helper not found:`r`n$PathCreateTemplate","Missing",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
      return
    }
    if (-not $script:LastWingetParsed -or -not $script:LastWingetParsed.Name -or ($tbId.Text.Trim() -and $script:LastWingetParsed.Id -ne $tbId.Text.Trim())) {
      $idToUse = $tbId.Text
      if (-not $idToUse -or -not $idToUse.Trim()) { $idToUse = $tbWingetApps.Text }
      $idToUse = $idToUse.Trim()
      if (-not $idToUse) {
        [System.Windows.Forms.MessageBox]::Show("Enter a Winget ID on the Winget or Intune App(s) tab.","Input",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
      }
      $parsed = Ensure-WingetParsed $idToUse
      if ($parsed) {
        $script:LastWingetParsed = $parsed
      } else {
        Append-Output $txtAppsOut "Failed to parse winget metadata for the specified ID."
      }
    }
    if (-not $script:LastWingetParsed) {
      [System.Windows.Forms.MessageBox]::Show("Failed to parse winget metadata for the specified ID.","Info",0,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
      return
    }
    $p = $script:LastWingetParsed
    $baseName = Get-ParsedOrFallbackName
    $ver = Get-ParsedVersion
    # Determine suffix dynamically from AutoPackager.config.json (SecondaryRequiredApp.DisplayNameSuffix or Secondary.DisplayNameSuffix)
    $suffix = $null
    try {
      if (Test-Path -LiteralPath $PathConfig) {
        $cfg = Get-Content -LiteralPath $PathConfig -Raw | ConvertFrom-Json
        if ($cfg) {
          if ($cfg.SecondaryRequiredApp -and $cfg.SecondaryRequiredApp.DisplayNameSuffix) { $suffix = [string]$cfg.SecondaryRequiredApp.DisplayNameSuffix }
          elseif ($cfg.Secondary -and $cfg.Secondary.DisplayNameSuffix) { $suffix = [string]$cfg.Secondary.DisplayNameSuffix }
        }
      }
    } catch {}
    # If no suffix is defined in config, do not append any hard-coded default
    if (-not $suffix -or [string]::IsNullOrWhiteSpace($suffix)) { $suffix = '' }
    $display = ($baseName + ($(if ($ver) { " $ver" } else { "" })) + $suffix)
    $publisher = if ($p.Publisher) { [string]$p.Publisher } else { "UnknownPublisher" }
    $developer = if ($p.Author)    { [string]$p.Author } else { "" }
    $desc = if ($p.Description)    { [string]$p.Description } else { "" }
    if ($desc.Length -gt 1800) { $desc = $desc.Substring(0,1800) }
    $info = if ($p.Homepage)   { [string]$p.Homepage } else { "" }
    $priv = if ($p.PrivacyUrl) { [string]$p.PrivacyUrl } else { "" }
    $icon = $tbIcon.Text
    # Read AllowAvailableUninstall from AutoPackager.config.json (default: false)
    $allowUninstall = $false
    try {
      if (Test-Path -LiteralPath $PathConfig) {
        $cfg = Get-Content -LiteralPath $PathConfig -Raw | ConvertFrom-Json
        if ($cfg -and ($cfg.PSObject.Properties.Name -contains 'AllowAvailableUninstall') -and ($null -ne $cfg.AllowAvailableUninstall)) {
          $allowUninstall = [bool]$cfg.AllowAvailableUninstall
        }
      }
    } catch {}

    $cmd = "& `"$PathCreateTemplate`" -DisplayName `"$display`" -Publisher `"$publisher`""
    if ($icon -and $icon.Trim()) { $cmd += " -IconPath `"$($icon.Trim())`"" }
    # Always use placeholder version for created apps
    $boolToken = if ($allowUninstall) { '$true' } else { '$false' }
    $cmd += " -AppVersion '0.1' -AllowAvailableUninstall:$boolToken"

    Append-Output $txtAppsOut ("Running: " + $cmd)
    $res = Invoke-PSCapture -Command $cmd -NoProfile
    if ($res.StdOut) { Append-Output $txtAppsOut $res.StdOut.TrimEnd() }
    if ($res.StdErr) { Append-Output $txtAppsOut ("[stderr]`r`n" + $res.StdErr.TrimEnd()) }
    $appId = $null
    try {
      if ($res.StdOut -match 'AppId:\s*([0-9A-Fa-f-]{36})') { $appId = $matches[1] }
    } catch {}
    if ($appId) {
      try { $tbSecondary.Text = $appId } catch {}
      try { $tbAppsSecId.Text = $appId } catch {}
      [System.Windows.Forms.MessageBox]::Show("Secondary App created.`r`nAppId: $appId","Create Secondary",0,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } else {
      [System.Windows.Forms.MessageBox]::Show("Create Secondary completed. AppId not detected in output; see log.","Create Secondary",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
  } catch {
    Append-Output $txtAppsOut ("Create Secondary error: " + $_.Exception.Message)
    [System.Windows.Forms.MessageBox]::Show("Create Secondary error: $($_.Exception.Message)","Error",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
  }
})

# Find existing apps
$btnFindPrimary.Add_Click({
  try {
    try { $txtAppsOut.Text = '' } catch {}
    if (-not (Test-Path -LiteralPath $PathIntuneTools)) {
      [System.Windows.Forms.MessageBox]::Show("Helper not found:`r`n$PathIntuneTools","Missing",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
      return
    }
    $name = $tbFind.Text
    if (-not $name -or -not $name.Trim()) { $name = '*' }
    $cmd = "& `"$PathIntuneTools`" -Action FindApp -Name `"$name`" -AsJson:$true"
    Append-Output $txtAppsOut ("Running: " + $cmd)
    $res = Invoke-PSCapture -Command $cmd -NoProfile
    if ($res.StdErr) { Append-Output $txtAppsOut ("[stderr]`r`n" + $res.StdErr.TrimEnd()) }
    if ($res.StdOut) { Append-Output $txtAppsOut ($res.StdOut.TrimEnd()) }

    $apps = @()
    try {
      if ($res.StdOut -and $res.StdOut.Trim()) {
        $parsed = $res.StdOut | ConvertFrom-Json
        if ($parsed -is [System.Array]) { $apps = @($parsed) } elseif ($parsed) { $apps = @($parsed) }
      }
    } catch {
      Append-Output $txtAppsOut ("[parse] JSON parse error: " + $_.Exception.Message)
      $apps = @()
    }
    Append-Output $txtAppsOut ("Matches: " + ($apps.Count))

    if (-not $apps -or $apps.Count -eq 0) {
      [System.Windows.Forms.MessageBox]::Show("No apps found matching: $name","Select Primary",0,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
      return
    }

    $chosen = $null
    if ($apps.Count -eq 1) {
      $chosen = $apps[0]
    } else {
      $chosen = Select-AppFromList -apps $apps -title "Select Primary App"
      if (-not $chosen) { return }
    }

    $appId = if ($chosen.Id) { [string]$chosen.Id } else { '' }
    if ($appId) {
      try { $tbIntuneId.Text = $appId } catch {}
      try { $tbAppsPrimId.Text = $appId } catch {}
      try { $tbPrim.Text = $appId } catch {}
      Append-Output $txtAppsOut ("Selected Primary: {0} [{1}] (Publisher: {2})" -f ($chosen.DisplayName), $appId, ($chosen.Publisher))
      try {
        if ($script:ReturnToResetAfterFind) {
          $tabs.SelectedTab = $tabReset
          $script:ReturnToResetAfterFind = $false
        } elseif ($script:ReturnToRecipeAfterFind) {
          $tabs.SelectedTab = $tabRecipe
          $script:ReturnToRecipeAfterFind = $false
        }
      } catch {}
    } else {
      [System.Windows.Forms.MessageBox]::Show("Selection error: missing AppId.","Select Primary",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
  } catch {
    Append-Output $txtAppsOut ("Find Primary error: " + $_.Exception.Message)
  }
})

$btnFindSecondary.Add_Click({
  try {
    try { $txtAppsOut.Text = '' } catch {}
    if (-not (Test-Path -LiteralPath $PathIntuneTools)) {
      [System.Windows.Forms.MessageBox]::Show("Helper not found:`r`n$PathIntuneTools","Missing",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
      return
    }
    $name = $tbFind.Text
    if (-not $name -or -not $name.Trim()) {
      $name = '*'
    }
    $cmd = "& `"$PathIntuneTools`" -Action FindApp -Name `"$name`" -AsJson:$true"
    Append-Output $txtAppsOut ("Running: " + $cmd)
    $res = Invoke-PSCapture -Command $cmd -NoProfile
    if ($res.StdErr) { Append-Output $txtAppsOut ("[stderr]`r`n" + $res.StdErr.TrimEnd()) }
    if ($res.StdOut) { Append-Output $txtAppsOut ($res.StdOut.TrimEnd()) }

    $apps = @()
    try {
      if ($res.StdOut -and $res.StdOut.Trim()) {
        $parsed = $res.StdOut | ConvertFrom-Json
        if ($parsed -is [System.Array]) { $apps = @($parsed) } elseif ($parsed) { $apps = @($parsed) }
      }
    } catch {
      Append-Output $txtAppsOut ("[parse] JSON parse error: " + $_.Exception.Message)
      $apps = @()
    }
    Append-Output $txtAppsOut ("Matches: " + ($apps.Count))

    if (-not $apps -or $apps.Count -eq 0) {
      [System.Windows.Forms.MessageBox]::Show("No apps found matching: $name","Select Secondary",0,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
      return
    }

    $chosen = $null
    if ($apps.Count -eq 1) {
      $chosen = $apps[0]
    } else {
      $chosen = Select-AppFromList -apps $apps -title "Select Secondary App"
      if (-not $chosen) { return }
    }

    $appId = if ($chosen.Id) { [string]$chosen.Id } else { '' }
    if ($appId) {
      try { $tbSecondary.Text = $appId } catch {}
      try { $tbAppsSecId.Text = $appId } catch {}
      try { $tbSecId.Text = $appId } catch {}
      Append-Output $txtAppsOut ("Selected Secondary: {0} [{1}] (Publisher: {2})" -f ($chosen.DisplayName), $appId, ($chosen.Publisher))
      try {
        if ($script:ReturnToResetAfterFind) {
          $tabs.SelectedTab = $tabReset
          $script:ReturnToResetAfterFind = $false
        } elseif ($script:ReturnToRecipeAfterFind) {
          $tabs.SelectedTab = $tabRecipe
          $script:ReturnToRecipeAfterFind = $false
        }
      } catch {}
    } else {
      [System.Windows.Forms.MessageBox]::Show("Selection error: missing AppId.","Select Secondary",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
  } catch {
    Append-Output $txtAppsOut ("Find Secondary error: " + $_.Exception.Message)
  }
})


# Initialize Winget ID on this tab from known values
try {
  $initId = $tbId.Text
  if (-not $initId -or -not $initId.Trim()) { $initId = $tbWingetForNew.Text }
  if ($initId -and $initId.Trim()) { Set-WingetIdAll $initId.Trim() }
} catch {}

# ---------- Tab: Recipe ----------
$tabRecipe = New-Object System.Windows.Forms.TabPage
$tabRecipe.Text = "Recipe"
$tabs.TabPages.Add($tabRecipe)

$grpCreate = New-Group "Select / Modify Recipe" 10 50 520 120
$lblWingetForNew = New-Label "Winget ID:" 10 25 100
$tbWingetForNew  = New-TextBox 110 22 200
try {
  $tbWingetForNew.Add_TextChanged({
    try {
      if ($script:WingetSyncing) { return }
      Reset-GuiOnWingetChange
      Set-WingetIdAll ($tbWingetForNew.Text)
      Set-FindFromWinget ($tbWingetForNew.Text)
    } catch {}
  })
} catch {}
$btnNewFromWinget= New-Button "Create New Recipe" 350 20 180
$btnBrowseRecipe = New-Button "Browse Recipe..." 10 25 150
$tbRecipePath    = New-TextBox 170 27 330
$btnOpenRecipe   = New-Button "Open in Notepad" 10 60 150
$btnOpenRecipeFolder = New-Button "Open Recipe Folder" 170 60 150
$btnOpenNetworkRecipeFolder = New-Button "Open Network Recipe Folder" 330 60 180
# Open the network recipe folder from AutoPackager.config.json (Paths.RecipeNetworkFolder)
$btnOpenNetworkRecipeFolder.Add_Click({
  try {
    $dir = Get-DefaultRecipeNetworkDirectory
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) {
      [System.Windows.Forms.MessageBox]::Show("Network Recipe folder not found. Verify AutoPackager.config.json (Paths.RecipeNetworkFolder).","Open Network Recipe Folder",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
      return
    }
    Start-Process explorer.exe -ArgumentList "`"$dir`""
  } catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to open Network Recipe folder: $($_.Exception.Message)","Open Network Recipe Folder",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
  }
})

$grpCreate.Controls.AddRange(@($btnBrowseRecipe,$tbRecipePath,$btnOpenRecipe,$btnOpenRecipeFolder,$btnOpenNetworkRecipeFolder))

# Select Existing App(s) group on Recipe tab (under Winget ID)
$grpSelectAppsRecipe = New-Group "Select Existing App(s)" 540 50 520 120
$lblFindRecipe   = New-Label "Search Name:" 10 28 100
$tbFindRecipe    = New-TextBox 110 25 260
$btnFindPrimaryRecipe   = New-Button "Find Primary App" 10 60 160
$btnFindSecondaryRecipe = New-Button "Find Required Update App" 180 60 160
$grpSelectAppsRecipe.Controls.AddRange(@($lblFindRecipe,$tbFindRecipe,$btnFindPrimaryRecipe,$btnFindSecondaryRecipe))

$tabRecipe.Controls.AddRange(@($lblWingetForNew,$tbWingetForNew,$btnNewFromWinget,$grpSelectAppsRecipe,$grpCreate))

# Wire Recipe tab select buttons to reuse Intune App(s) find handlers
try {
  $btnFindPrimaryRecipe.Add_Click({
    try { $txtAppsOut.Text = '' } catch {}
    try { $tbFind.Text = $tbFindRecipe.Text } catch {}
    try { $script:ReturnToRecipeAfterFind = $true } catch {}
    try { $tabs.SelectedTab = $tabApps } catch {}
    try { $btnFindPrimary.PerformClick() } catch {}
  })
  $btnFindSecondaryRecipe.Add_Click({
    try { $txtAppsOut.Text = '' } catch {}
    try { $tbFind.Text = $tbFindRecipe.Text } catch {}
    try { $script:ReturnToRecipeAfterFind = $true } catch {}
    try { $tabs.SelectedTab = $tabApps } catch {}
    try { $btnFindSecondary.PerformClick() } catch {}
  })
} catch {}

$grpQuickEdit = New-Group "Quick Edit (IDs and Args)" 10 180 1160 510
$lblIntuneId  = New-Label "Primary AppId:" 10 28 150
$tbIntuneId   = New-TextBox 170 25 280

# Recipe tab: Architecture and Installer Type (copied from Winget tab) placed below Primary AppId
$lblArchRecipe = New-Label "Architecture:" 10 58 150
$cbArchRecipe  = New-Object System.Windows.Forms.ComboBox
$cbArchRecipe.Left=170; $cbArchRecipe.Top=55; $cbArchRecipe.Width=120
$cbArchRecipe.DropDownStyle='DropDownList'
$cbArchRecipe.Items.AddRange(@('x64','x86','arm64'))
try {
  $defArchRecipe = if ($script:PreferArchitecture -and @('x64','x86','arm64') -contains $script:PreferArchitecture) { $script:PreferArchitecture } else { 'x64' }
  $cbArchRecipe.SelectedItem = $defArchRecipe
} catch {}

$lblInstTypeRecipe = New-Label "Installer Type:" 310 58 120
$cbInstTypeRecipe  = New-Object System.Windows.Forms.ComboBox
$cbInstTypeRecipe.Left=430; $cbInstTypeRecipe.Top=55; $cbInstTypeRecipe.Width=100
$cbInstTypeRecipe.DropDownStyle='DropDownList'
$cbInstTypeRecipe.Items.AddRange(@('msi','exe'))
try { $cbInstTypeRecipe.SelectedItem = 'msi' } catch {}
# Pre-sync Recipe tab combos from Winget tab current selections (if set)
try { if ($cbArchWinget -and $cbArchWinget.SelectedItem) { $cbArchRecipe.SelectedItem = [string]$cbArchWinget.SelectedItem } } catch {}
try { if ($cbInstTypeWinget -and $cbInstTypeWinget.SelectedItem) { $cbInstTypeRecipe.SelectedItem = ([string]$cbInstTypeWinget.SelectedItem).ToLower() } } catch {}

$lblSecondary = New-Label "Required Update AppId:" 500 28 150
$tbSecondary  = New-TextBox 650 25 280


$lblScopeEdit = New-Label "Installer Scope:" 10 88 150
$cbScopeEdit  = New-Object System.Windows.Forms.ComboBox
$cbScopeEdit.Left=170; $cbScopeEdit.Top=85; $cbScopeEdit.Width=120
$cbScopeEdit.DropDownStyle='DropDownList'
$cbScopeEdit.Items.AddRange(@('','machine','user'))
$cbScopeEdit.SelectedIndex = 0


$lblInstallArgs = New-Label "InstallArgs:" 10 118 150
$tbInstallArgs  = New-TextBox 170 115 800
$lblUninstArgs  = New-Label "UninstallArgs:" 10 148 150
$tbUninstArgs   = New-TextBox 170 145 800

# New: ForceUninstall toggle
$chkForceUninstall = New-Object System.Windows.Forms.CheckBox
$chkForceUninstall.Text = "ForceUninstall"
$chkForceUninstall.Left = 10
$chkForceUninstall.Top  = 178
$chkForceUninstall.Width = 140

# New: Allow available uninstall toggle (defaults from config)
$chkAllowAvailUninst = New-Object System.Windows.Forms.CheckBox
$chkAllowAvailUninst.Text = "Allow available uninstall"
$chkAllowAvailUninst.Left = 160
$chkAllowAvailUninst.Top  = 178
$chkAllowAvailUninst.Width = 180
try { $chkAllowAvailUninst.Checked = $script:DefaultAllowAvailableUninstall } catch {}

# New: Notification Popup options
$grpNotif = New-Group "Notification Popup" 10 290 490 70
$chkNotifEnabled = New-Object System.Windows.Forms.CheckBox
$chkNotifEnabled.Text = "Enabled"
$chkNotifEnabled.Left = 10
$chkNotifEnabled.Top  = 24
$chkNotifEnabled.Width = 80

$lblNotifMins = New-Label "Timer (min):" 100 28 80
$numNotifMins = New-Object System.Windows.Forms.NumericUpDown
$numNotifMins.Left = 180
$numNotifMins.Top  = 24
$numNotifMins.Width = 60
$numNotifMins.Minimum = 1
$numNotifMins.Maximum = 120
$numNotifMins.Value = 2

$chkDeferralEnabled = New-Object System.Windows.Forms.CheckBox
$chkDeferralEnabled.Text = "Allow deferral"
$chkDeferralEnabled.Left = 260
$chkDeferralEnabled.Top  = 24
$chkDeferralEnabled.Width = 110

$lblDefHours = New-Label "Hours:" 380 28 50
$numDefHours = New-Object System.Windows.Forms.NumericUpDown
$numDefHours.Left = 430
$numDefHours.Top  = 24
$numDefHours.Width = 50
$numDefHours.Minimum = 0
$numDefHours.Maximum = 720
$numDefHours.Value = 24

$grpNotif.Controls.AddRange(@($chkNotifEnabled,$lblNotifMins,$numNotifMins,$chkDeferralEnabled,$lblDefHours,$numDefHours))

# New: ForceTaskClose editor (one per line)
$lblFTC = New-Label "ForceTaskClose (one per line):" 10 208 160
$tbFTC  = New-TextBox 170 205 400 70 $true $false

# New: Rings editor
$grpRings = New-Group "Required Update Deployment Rings" 10 370 1160 120
$lblRing1G = New-Label "Pilot Group:" 170 30 90
$tbRing1G  = New-TextBox 265 27 220
$lblRing1D = New-Label "Deadline (days):" 500 30 105
$numRing1D = New-Object System.Windows.Forms.NumericUpDown
$numRing1D.Left = 610; $numRing1D.Top = 27; $numRing1D.Width = 60
$numRing1D.Minimum = 0; $numRing1D.Maximum = 365; $numRing1D.Value = [decimal][int]$script:DefaultRingDelay1

$lblRing2G = New-Label "UAT Group:" 170 60 90
$tbRing2G  = New-TextBox 265 57 220
$lblRing2D = New-Label "Deadline (days):" 500 60 105
$numRing2D = New-Object System.Windows.Forms.NumericUpDown
$numRing2D.Left = 610; $numRing2D.Top = 57; $numRing2D.Width = 60
$numRing2D.Minimum = 0; $numRing2D.Maximum = 365; $numRing2D.Value = [decimal][int]$script:DefaultRingDelay2

$lblRing3G = New-Label "GA Group:" 170 90 90
$tbRing3G  = New-TextBox 265 87 220
$lblRing3D = New-Label "Deadline (days):" 500 90 105
$numRing3D = New-Object System.Windows.Forms.NumericUpDown
$numRing3D.Left = 610; $numRing3D.Top = 87; $numRing3D.Width = 60
$numRing3D.Minimum = 0; $numRing3D.Maximum = 365; $numRing3D.Value = [decimal][int]$script:DefaultRingDelay3

$btnLoadDefaultGroups = New-Button "Load Default Groups" 10 25 150
# New: Assignment Filter controls per ring
$lblRing1F = New-Label "Filter:" 700 30 50
$tbRing1F  = New-TextBox 755 27 220
$lblRing1FT = New-Label "Type:" 980 30 35
$cbRing1FT = New-Object System.Windows.Forms.ComboBox
$cbRing1FT.Left = 1020; $cbRing1FT.Top = 27; $cbRing1FT.Width = 80
$cbRing1FT.DropDownStyle = 'DropDownList'
$cbRing1FT.Items.AddRange(@('Include','Exclude'))
$cbRing1FT.SelectedIndex = 0

$lblRing2F = New-Label "Filter:" 700 60 50
$tbRing2F  = New-TextBox 755 57 220
$lblRing2FT = New-Label "Type:" 980 60 35
$cbRing2FT = New-Object System.Windows.Forms.ComboBox
$cbRing2FT.Left = 1020; $cbRing2FT.Top = 57; $cbRing2FT.Width = 80
$cbRing2FT.DropDownStyle = 'DropDownList'
$cbRing2FT.Items.AddRange(@('Include','Exclude'))
$cbRing2FT.SelectedIndex = 0

$lblRing3F = New-Label "Filter:" 700 90 50
$tbRing3F  = New-TextBox 755 87 220
$lblRing3FT = New-Label "Type:" 980 90 35
$cbRing3FT = New-Object System.Windows.Forms.ComboBox
$cbRing3FT.Left = 1020; $cbRing3FT.Top = 87; $cbRing3FT.Width = 80
$cbRing3FT.DropDownStyle = 'DropDownList'
$cbRing3FT.Items.AddRange(@('Include','Exclude'))
$cbRing3FT.SelectedIndex = 0

$grpRings.Controls.AddRange(@(
  $lblRing1G,$tbRing1G,$lblRing1D,$numRing1D,
  $lblRing2G,$tbRing2G,$lblRing2D,$numRing2D,
  $lblRing3G,$tbRing3G,$lblRing3D,$numRing3D,
  $btnLoadDefaultGroups,
  $lblRing1F,$tbRing1F,$lblRing1FT,$cbRing1FT,
  $lblRing2F,$tbRing2F,$lblRing2FT,$cbRing2FT,
  $lblRing3F,$tbRing3F,$lblRing3FT,$cbRing3FT
))

# Load default group names from AutoPackager.config.json into the three ring group fields
$btnLoadDefaultGroups.Add_Click({
  try {
    if (Test-Path -LiteralPath $PathConfig) {
      $cfg = Get-Content -LiteralPath $PathConfig -Raw | ConvertFrom-Json
      if ($cfg -and $cfg.RequiredUpdateDefaultGroups) {
        # Groups
        try { $tbRing1G.Text = [string]$cfg.RequiredUpdateDefaultGroups.PilotGroup } catch {}
        try { $tbRing2G.Text = [string]$cfg.RequiredUpdateDefaultGroups.UATGroup } catch {}
        try { $tbRing3G.Text = [string]$cfg.RequiredUpdateDefaultGroups.GAGroup } catch {}

        # Filters (text + type) - optional keys:
        #   PilotFilter, PilotFilterType
        #   UATFilter,   UATFilterType
        #   GAFilter,    GAFilterType
        try {
          if ($cfg.RequiredUpdateDefaultGroups.PSObject.Properties.Name -contains 'PilotFilter') {
            $tbRing1F.Text = [string]$cfg.RequiredUpdateDefaultGroups.PilotFilter
          }
          if ($cfg.RequiredUpdateDefaultGroups.PSObject.Properties.Name -contains 'PilotFilterType') {
            $t = [string]$cfg.RequiredUpdateDefaultGroups.PilotFilterType
            if ($t) {
              $t = $t.Trim().ToLower()
              if ($t -eq 'exclude') { $cbRing1FT.SelectedItem = 'Exclude' } else { $cbRing1FT.SelectedItem = 'Include' }
            }
          }
        } catch {}
        try {
          if ($cfg.RequiredUpdateDefaultGroups.PSObject.Properties.Name -contains 'UATFilter') {
            $tbRing2F.Text = [string]$cfg.RequiredUpdateDefaultGroups.UATFilter
          }
          if ($cfg.RequiredUpdateDefaultGroups.PSObject.Properties.Name -contains 'UATFilterType') {
            $t = [string]$cfg.RequiredUpdateDefaultGroups.UATFilterType
            if ($t) {
              $t = $t.Trim().ToLower()
              if ($t -eq 'exclude') { $cbRing2FT.SelectedItem = 'Exclude' } else { $cbRing2FT.SelectedItem = 'Include' }
            }
          }
        } catch {}
        try {
          if ($cfg.RequiredUpdateDefaultGroups.PSObject.Properties.Name -contains 'GAFilter') {
            $tbRing3F.Text = [string]$cfg.RequiredUpdateDefaultGroups.GAFilter
          }
          if ($cfg.RequiredUpdateDefaultGroups.PSObject.Properties.Name -contains 'GAFilterType') {
            $t = [string]$cfg.RequiredUpdateDefaultGroups.GAFilterType
            if ($t) {
              $t = $t.Trim().ToLower()
              if ($t -eq 'exclude') { $cbRing3FT.SelectedItem = 'Exclude' } else { $cbRing3FT.SelectedItem = 'Include' }
            }
          }
        } catch {}
        try { $numRing1D.Value = [decimal][int]$script:DefaultRingDelay1 } catch {}
        try { $numRing2D.Value = [decimal][int]$script:DefaultRingDelay2 } catch {}
        try { $numRing3D.Value = [decimal][int]$script:DefaultRingDelay3 } catch {}
      } else {
        [System.Windows.Forms.MessageBox]::Show("RequiredUpdateDefaultGroups not found in AutoPackager.config.json","Defaults",0,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
      }
    } else {
      [System.Windows.Forms.MessageBox]::Show("Config file not found: $PathConfig","Defaults",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
  } catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to load default groups: $($_.Exception.Message)","Defaults",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
  }
})

$btnSaveQuick   = New-Button "Save Recipe Update(s)" 540 20 200
$btnSaveQuick.Anchor = 'Top,Left'
$btnSaveToNetwork = New-Button "Save Recipe to Network" 750 20 220
$btnSaveToNetwork.Anchor = 'Top,Left'
$tabRecipe.Controls.AddRange(@($btnSaveQuick,$btnSaveToNetwork))

$btnSaveToNetwork.Add_Click({
  try {
    $p = $tbRecipePath.Text.Trim()
    if (-not $p -or -not (Test-Path -LiteralPath $p)) {
      [System.Windows.Forms.MessageBox]::Show("Select a valid recipe JSON first.","Save to Network",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
      return
    }

    # Use SaveFileDialog to provide an address bar and full path control
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Title = "Save Recipe to Network"
    $sfd.Filter = "Recipe JSON (*.json)|*.json|All files (*.*)|*.*"
    $sfd.AddExtension = $true
    $sfd.DefaultExt = "json"
    $sfd.OverwritePrompt = $true
    $sfd.CheckPathExists = $true

    try {
      $def = Get-DefaultRecipeNetworkDirectory
      if ($def) {
        try { if ($def -match '^[^:]+::') { $def = $def -replace '^[^:]+::','' } } catch {}
        $sfd.InitialDirectory = $def
      }
      $sfd.RestoreDirectory = $true
      $leaf = Split-Path -Leaf $p
      if ($leaf) {
        $sfd.FileName = $leaf
      }
    } catch {}

    if ($sfd.ShowDialog() -ne 'OK') { return }

    $dest = $sfd.FileName
    $destDir = Split-Path -Parent $dest
    try {
      if (-not (Test-Path -LiteralPath $destDir)) {
        $null = New-Item -ItemType Directory -Path $destDir -Force -ErrorAction SilentlyContinue
      }
    } catch {}

    Copy-Item -LiteralPath $p -Destination $dest -Force -ErrorAction Stop
    [System.Windows.Forms.MessageBox]::Show("Recipe saved to:`r`n$dest","Save to Network",0,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
  } catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to save to network: $($_.Exception.Message)","Save to Network",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
  }
})

$grpQuickEdit.Controls.AddRange(@(
  $lblIntuneId,$tbIntuneId,$lblArchRecipe,$cbArchRecipe,$lblInstTypeRecipe,$cbInstTypeRecipe,
  $lblSecondary,$tbSecondary,
  $lblScopeEdit,$cbScopeEdit,
  $lblInstallArgs,$tbInstallArgs,
  $lblUninstArgs,$tbUninstArgs,
  $chkForceUninstall,$chkAllowAvailUninst,
  $lblFTC,$tbFTC,
  $grpNotif,
  $grpRings
))
$tabRecipe.Controls.Add($grpQuickEdit)

$lblRecipeInfo = New-Label "Notes: Use Quick Edit for common fields, or open in Notepad for full editing. ForceTaskClose and Notification can be edited here or directly in JSON." 10 700 1000 40
$tabRecipe.Controls.Add($lblRecipeInfo)

$ofd = New-Object System.Windows.Forms.OpenFileDialog
$ofd.Filter = "Recipe JSON (*.json)|*.json|All files (*.*)|*.*"
$ofd.InitialDirectory = (Resolve-ExistingPath $PathRecipesDefault)

# Sync Winget ID from Winget tab into Recipe tab when leaving the Winget ID field
try {
  $tbId.Add_LostFocus({
    try {
      $val = $tbId.Text.Trim()
      if ($val) { $tbWingetForNew.Text = $val }
    } catch {}
  })
} catch {}

$btnNewFromWinget.Add_Click({
  $id = $tbWingetForNew.Text.Trim()
  if (-not $id) { [System.Windows.Forms.MessageBox]::Show("Enter a Winget ID to generate a recipe.","Input",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null; return }
  if (-not (Test-Path -LiteralPath $PathNewRecipe)) {
    [System.Windows.Forms.MessageBox]::Show("New-RecipeFromWinget.ps1 not found:`r`n$PathNewRecipe","Missing",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null; return
  }

  # Determine expected recipe path and handle existing file
  $expected = $null
  try { if ($PathRecipesDefault) { $expected = Join-Path $PathRecipesDefault ("{0}.json" -f $id) } } catch {}
  if ($expected -and (Test-Path -LiteralPath $expected)) {
    $text = "A recipe already exists:`r`n$expected`r`n`r`nWhat would you like to do?`r`n`r`nYes = Load existing into GUI`r`nNo = Overwrite`r`nCancel = Abort"
    $dr = [System.Windows.Forms.MessageBox]::Show($text, "Recipe Exists", [System.Windows.Forms.MessageBoxButtons]::YesNoCancel, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($dr -eq [System.Windows.Forms.DialogResult]::Yes) {
    try { $tbRecipePath.Text = $expected } catch {}
    try { $tbRunPath.Text = $expected } catch {}
    try { $btnLoadQuick.PerformClick() } catch {}
      return
    } elseif ($dr -eq [System.Windows.Forms.DialogResult]::Cancel) {
      return
    } else {
      try { Remove-Item -LiteralPath $expected -Force -ErrorAction Stop } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to overwrite existing recipe:`r`n$($_.Exception.Message)","Error",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
      }
    }
  }

  # Pass Architecture and Locale to New-RecipeFromWinget (no winget.exe path)
  $archSel = 'x64'
  try {
    if ($cbArchWinget -and $cbArchWinget.SelectedItem) { $archSel = [string]$cbArchWinget.SelectedItem }
    elseif ($script:PreferArchitecture) { $archSel = [string]$script:PreferArchitecture }
  } catch {}
  $loc = 'en-US'
  try { if ($tbLocale -and $tbLocale.Text -and $tbLocale.Text.Trim()) { $loc = $tbLocale.Text.Trim() } } catch {}

  $cmd = "& `"$PathNewRecipe`" -wingetid `"$id`" -Architecture $archSel -Locale `"$loc`""
  $res = Invoke-PSCapture -Command $cmd -NoProfile
  $msg = "Recipe generation completed."
  if ($res.ExitCode -ne 0) { $msg = "Recipe generation finished with exit code $($res.ExitCode)." }
  [System.Windows.Forms.MessageBox]::Show($msg,"New-RecipeFromWinget",0,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null

  # Point to the expected file if created, otherwise fall back to most recent .json
  if ($expected -and (Test-Path -LiteralPath $expected)) {
    try { $tbRecipePath.Text = $expected } catch {}
    try { $tbRunPath.Text = $expected } catch {}
    try { if (Has-QuickEditData) { $btnSaveQuick.PerformClick() } } catch {}
    try { $btnLoadQuick.PerformClick() } catch {}
  } elseif (Test-Path -LiteralPath $PathRecipesDefault) {
    try {
      $recent = Get-ChildItem -LiteralPath $PathRecipesDefault -Filter *.json -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
      if ($recent) {
        $tbRecipePath.Text = $recent.FullName
        try { $tbRunPath.Text = $recent.FullName } catch {}
        try { if (Has-QuickEditData) { $btnSaveQuick.PerformClick() } } catch {}
        try { $btnLoadQuick.PerformClick() } catch {}
      }
    } catch {}
  }
})

$btnBrowseRecipe.Add_Click({
  if ($ofd.ShowDialog() -eq 'OK') {
    $tbRecipePath.Text = $ofd.FileName
    try { $tbRunPath.Text = $ofd.FileName } catch {}
    try { $btnLoadQuick.PerformClick() } catch {}
  }
})

$btnOpenRecipe.Add_Click({
  $p = $tbRecipePath.Text.Trim()
  if (-not (Test-Path -LiteralPath $p)) { [System.Windows.Forms.MessageBox]::Show("Select a valid recipe JSON.","Open",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null; return }
  Start-Process notepad.exe -ArgumentList "`"$p`""
})

$btnOpenRecipeFolder.Add_Click({
  $p = $tbRecipePath.Text.Trim()
  $folder = if ($p -and (Test-Path -LiteralPath $p)) { Split-Path -Parent $p } else { $PathRecipesDefault }
  if (-not (Test-Path -LiteralPath $folder)) { $folder = $ScriptRoot }
  Start-Process explorer.exe -ArgumentList "`"$folder`""
})

$btnSaveQuick.Add_Click({
  $p = $tbRecipePath.Text.Trim()
  if (-not (Test-Path -LiteralPath $p)) { [System.Windows.Forms.MessageBox]::Show("Select a valid recipe JSON first.","Save",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null; return }
  try {
    $raw = Get-Content -LiteralPath $p -Raw
    $json = $raw | ConvertFrom-Json
    if (-not $json) { throw "Failed to parse JSON." }

    # Apply IDs (no GUID validation enforced)
    $idPrimary = $tbIntuneId.Text.Trim()
    if ($idPrimary) {
      $json.IntuneAppId = $idPrimary
    }

    $idSecondary = $tbSecondary.Text.Trim()
    if ($idSecondary) {
      $json.SecondaryAppId = $idSecondary
      # Do not create or modify nested 'Secondary'; preserve existing if present.
    }

    # Scope / Architecture / Locale
    if (-not $json.InstallerPreferences) { Add-Member -InputObject $json -NotePropertyName InstallerPreferences -NotePropertyValue ([pscustomobject]@{}) -Force }
    $prefs = $json.InstallerPreferences
    # Normalize InstallerPreferences to PSCustomObject (avoid hashtable dot-notation errors)
    try {
      if ($prefs -is [hashtable]) {
        $json.InstallerPreferences = [pscustomobject]$prefs
        $prefs = $json.InstallerPreferences
      }
    } catch {}
    $scopeVal = $cbScopeEdit.SelectedItem
    if ($scopeVal) { try { $prefs | Add-Member -NotePropertyName Scope -NotePropertyValue $scopeVal -Force } catch {} }
    # Recipe tab: persist Architecture and Installer Type into InstallerPreferences
    $archSel = $cbArchRecipe.SelectedItem
    if ($archSel) { try { $prefs | Add-Member -NotePropertyName Architecture -NotePropertyValue ([string]$archSel) -Force } catch {} }
    $typeSel = $cbInstTypeRecipe.SelectedItem
    if ($typeSel) { try { $prefs | Add-Member -NotePropertyName InstallerType -NotePropertyValue ([string]$typeSel) -Force } catch {} }


    # Args
    if ($tbInstallArgs.Text -ne $null) { $json.InstallArgs = $tbInstallArgs.Text }
    if ($tbUninstArgs.Text -ne $null)  { $json.UninstallArgs = $tbUninstArgs.Text }

    # ForceUninstall
    try {
      if ($json.PSObject.Properties.Name -contains 'ForceUninstall') {
        $json.ForceUninstall = [bool]$chkForceUninstall.Checked
      } else {
        Add-Member -InputObject $json -NotePropertyName ForceUninstall -NotePropertyValue ([bool]$chkForceUninstall.Checked)
      }
    } catch {}

    # AllowAvailableUninstall (persist per-recipe)
    try {
      if ($json.PSObject.Properties.Name -contains 'AllowAvailableUninstall') {
        $json.AllowAvailableUninstall = [bool]$chkAllowAvailUninst.Checked
      } else {
        Add-Member -InputObject $json -NotePropertyName AllowAvailableUninstall -NotePropertyValue ([bool]$chkAllowAvailUninst.Checked)
      }
    } catch {}

    # ForceTaskClose (multiline -> array)
    try {
      $arr = @()
      if ($tbFTC -and $tbFTC.Text -ne $null) {
        $raw = $tbFTC.Text -replace "`r`n","`n" -replace "`r","`n"
        $tokens = $raw -split "`n|,"
        $arr = $tokens | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique
      }
      if ($json.PSObject.Properties.Name -contains 'ForceTaskClose') {
        $json.ForceTaskClose = $arr
      } else {
        Add-Member -InputObject $json -NotePropertyName ForceTaskClose -NotePropertyValue $arr
      }
    } catch {}

    # Rings (ensure structure and set values)
    try {
      if (-not $json.Rings) { $json | Add-Member -NotePropertyName Rings -NotePropertyValue (@{}) -Force }
      foreach ($ring in 1,2,3) {
        if (-not ($json.Rings.PSObject.Properties.Name -contains ("Ring{0}" -f $ring))) {
          $json.Rings | Add-Member -NotePropertyName ("Ring{0}" -f $ring) -NotePropertyValue (@{}) -Force
        }
      }
      $json.Rings.Ring1 | Add-Member -NotePropertyName Group -NotePropertyValue ([string]$tbRing1G.Text) -Force
      $json.Rings.Ring2 | Add-Member -NotePropertyName Group -NotePropertyValue ([string]$tbRing2G.Text) -Force
      $json.Rings.Ring3 | Add-Member -NotePropertyName Group -NotePropertyValue ([string]$tbRing3G.Text) -Force
      $json.Rings.Ring1 | Add-Member -NotePropertyName DeadlineDelayDays -NotePropertyValue ([int]$numRing1D.Value) -Force
      $json.Rings.Ring2 | Add-Member -NotePropertyName DeadlineDelayDays -NotePropertyValue ([int]$numRing2D.Value) -Force
      $json.Rings.Ring3 | Add-Member -NotePropertyName DeadlineDelayDays -NotePropertyValue ([int]$numRing3D.Value) -Force

      Set-RingFilter $json.Rings.Ring1 ($tbRing1F.Text) ($(if ($cbRing1FT.SelectedItem){[string]$cbRing1FT.SelectedItem}else{'include'}))
      Set-RingFilter $json.Rings.Ring2 ($tbRing2F.Text) ($(if ($cbRing2FT.SelectedItem){[string]$cbRing2FT.SelectedItem}else{'include'}))
      Set-RingFilter $json.Rings.Ring3 ($tbRing3F.Text) ($(if ($cbRing3FT.SelectedItem){[string]$cbRing3FT.SelectedItem}else{'include'}))
    } catch {}

    # NotificationPopup
    try {
      if (-not ($json.PSObject.Properties.Name -contains 'NotificationPopup') -or -not $json.NotificationPopup) {
        Add-Member -InputObject $json -NotePropertyName NotificationPopup -NotePropertyValue ([pscustomobject]@{})
      }
      $json.NotificationPopup.Enabled = [bool]$chkNotifEnabled.Checked
      $json.NotificationPopup.NotificationTimerInMinutes = [int]$numNotifMins.Value
      $json.NotificationPopup.DeferralEnabled = [bool]$chkDeferralEnabled.Checked
      $json.NotificationPopup.DeferralHoursAllowed = [int]$numDefHours.Value
    } catch {}

    # Prune empty Secondary object if present to avoid schema mutation
    try {
      if ($json.PSObject.Properties.Name -contains 'Secondary') {
        $props = $json.Secondary.PSObject.Properties.Name
        if (-not $props -or $props.Count -eq 0) {
          [void]$json.PSObject.Properties.Remove('Secondary')
        }
      }
    } catch {}

    ($json | ConvertTo-Json -Depth 15) | Set-Content -LiteralPath $p -Encoding UTF8
    [System.Windows.Forms.MessageBox]::Show("Recipe updated.","Save",0,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
  } catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to update recipe: $($_.Exception.Message)","Error",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
  }
})

# Load Quick Edit fields from selected recipe (function, button removed)
function Load-RecipeIntoQuickEdit {
  $p = $tbRecipePath.Text.Trim()
  if (-not (Test-Path -LiteralPath $p)) {
    [System.Windows.Forms.MessageBox]::Show("Select a valid recipe JSON first.","Load",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    return
  }
  try {
    $raw = Get-Content -LiteralPath $p -Raw
    $json = $raw | ConvertFrom-Json
    if (-not $json) { throw "Failed to parse JSON." }

    # Populate fields
    try { $tbIntuneId.Text = if ($json.IntuneAppId) { [string]$json.IntuneAppId } else { '' } } catch {}
    try { if ($tbIntuneId.Text -and $tbIntuneId.Text.Trim()) { $tbPrim.Text = $tbIntuneId.Text.Trim() } } catch {}

    $sec = $null
    try {
      if ($json.SecondaryAppId -and $json.SecondaryAppId.ToString().Trim()) {
        $sec = $json.SecondaryAppId
      } elseif ($json.Secondary) {
        foreach ($k in @('IntuneAppId','AppId','Id')) {
          if ($json.Secondary.PSObject.Properties.Name -contains $k) {
            $v = [string]$json.Secondary.$k
            if ($v -and $v.Trim()) { $sec = $v; break }
          }
        }
      }
    } catch {}
    try { $tbSecondary.Text = if ($sec) { [string]$sec } else { '' } } catch {}
    try { if ($tbSecondary.Text -and $tbSecondary.Text.Trim()) { $tbSecId.Text = $tbSecondary.Text.Trim() } } catch {}

    try {
      if ($json.InstallerPreferences) {
        if ($json.InstallerPreferences.Scope) {
          $scp = [string]$json.InstallerPreferences.Scope
          if (@('','machine','user') -contains $scp) { $cbScopeEdit.SelectedItem = $scp }
        }
        # Recipe tab: load Architecture/Installer Type into the new controls
        if ($json.InstallerPreferences.Architecture) {
          $arch = [string]$json.InstallerPreferences.Architecture
          if (@('x64','x86','arm64') -contains $arch) { $cbArchRecipe.SelectedItem = $arch }
        }
        if ($json.InstallerPreferences.InstallerType) {
          $itype = [string]$json.InstallerPreferences.InstallerType
          try { $itype = $itype.ToLower() } catch {}
          if (@('msi','exe') -contains $itype) { $cbInstTypeRecipe.SelectedItem = $itype }
        }
      }
    } catch {}


    try { $tbInstallArgs.Text = if ($json.InstallArgs -ne $null) { [string]$json.InstallArgs } else { '' } } catch {}
    try { $tbUninstArgs.Text  = if ($json.UninstallArgs -ne $null) { [string]$json.UninstallArgs } else { '' } } catch {}

    try {
      if ($null -ne $json.ForceUninstall) { $chkForceUninstall.Checked = [bool]$json.ForceUninstall } else { $chkForceUninstall.Checked = $false }
    } catch {}

    # Load AllowAvailableUninstall (fallback to config default if not present)
    try {
      if ($json.PSObject.Properties.Name -contains 'AllowAvailableUninstall' -and $null -ne $json.AllowAvailableUninstall) {
        $chkAllowAvailUninst.Checked = [bool]$json.AllowAvailableUninstall
      } else {
        $chkAllowAvailUninst.Checked = $script:DefaultAllowAvailableUninstall
      }
    } catch {}

    # Load ForceTaskClose
    try {
      if ($json.ForceTaskClose) {
        if ($json.ForceTaskClose -is [System.Array]) {
          $tbFTC.Text = ($json.ForceTaskClose | ForEach-Object { [string]$_ } | Where-Object { $_ } -join "`r`n")
        } else {
          $tbFTC.Text = [string]$json.ForceTaskClose
        }
      } else { $tbFTC.Text = '' }
    } catch {}

    # Load Rings
    try {
      if ($json.Rings) {
        if ($json.Rings.Ring1) {
          if ($json.Rings.Ring1.Group -ne $null) { $tbRing1G.Text = [string]$json.Rings.Ring1.Group }
          if ($json.Rings.Ring1.DeadlineDelayDays -ne $null) { $numRing1D.Value = [decimal][int]$json.Rings.Ring1.DeadlineDelayDays }
          # Load filter (prefer FilterName, else FilterId)
          try {
            $tbRing1F.Text = ''
            if ($json.Rings.Ring1.PSObject.Properties.Name -contains 'FilterName' -and $json.Rings.Ring1.FilterName) {
              $tbRing1F.Text = [string]$json.Rings.Ring1.FilterName
            } elseif ($json.Rings.Ring1.PSObject.Properties.Name -contains 'FilterId' -and $json.Rings.Ring1.FilterId) {
              $tbRing1F.Text = [string]$json.Rings.Ring1.FilterId
            }
            $cbRing1FT.SelectedItem = 'include'
            if ($json.Rings.Ring1.PSObject.Properties.Name -contains 'FilterType' -and $json.Rings.Ring1.FilterType -and ([string]$json.Rings.Ring1.FilterType).Trim().ToLower() -eq 'exclude') {
              $cbRing1FT.SelectedItem = 'exclude'
            }
          } catch {}
        }
        if ($json.Rings.Ring2) {
          if ($json.Rings.Ring2.Group -ne $null) { $tbRing2G.Text = [string]$json.Rings.Ring2.Group }
          if ($json.Rings.Ring2.DeadlineDelayDays -ne $null) { $numRing2D.Value = [decimal][int]$json.Rings.Ring2.DeadlineDelayDays }
          try {
            $tbRing2F.Text = ''
            if ($json.Rings.Ring2.PSObject.Properties.Name -contains 'FilterName' -and $json.Rings.Ring2.FilterName) {
              $tbRing2F.Text = [string]$json.Rings.Ring2.FilterName
            } elseif ($json.Rings.Ring2.PSObject.Properties.Name -contains 'FilterId' -and $json.Rings.Ring2.FilterId) {
              $tbRing2F.Text = [string]$json.Rings.Ring2.FilterId
            }
            $cbRing2FT.SelectedItem = 'include'
            if ($json.Rings.Ring2.PSObject.Properties.Name -contains 'FilterType' -and $json.Rings.Ring2.FilterType -and ([string]$json.Rings.Ring2.FilterType).Trim().ToLower() -eq 'exclude') {
              $cbRing2FT.SelectedItem = 'exclude'
            }
          } catch {}
        }
        if ($json.Rings.Ring3) {
          if ($json.Rings.Ring3.Group -ne $null) { $tbRing3G.Text = [string]$json.Rings.Ring3.Group }
          if ($json.Rings.Ring3.DeadlineDelayDays -ne $null) { $numRing3D.Value = [decimal][int]$json.Rings.Ring3.DeadlineDelayDays }
          try {
            $tbRing3F.Text = ''
            if ($json.Rings.Ring3.PSObject.Properties.Name -contains 'FilterName' -and $json.Rings.Ring3.FilterName) {
              $tbRing3F.Text = [string]$json.Rings.Ring3.FilterName
            } elseif ($json.Rings.Ring3.PSObject.Properties.Name -contains 'FilterId' -and $json.Rings.Ring3.FilterId) {
              $tbRing3F.Text = [string]$json.Rings.Ring3.FilterId
            }
            $cbRing3FT.SelectedItem = 'include'
            if ($json.Rings.Ring3.PSObject.Properties.Name -contains 'FilterType' -and $json.Rings.Ring3.FilterType -and ([string]$json.Rings.Ring3.FilterType).Trim().ToLower() -eq 'exclude') {
              $cbRing3FT.SelectedItem = 'exclude'
            }
          } catch {}
        }
      } else {
        $tbRing1G.Text = ''; $tbRing2G.Text = ''; $tbRing3G.Text = ''
        $numRing1D.Value = [decimal][int]$script:DefaultRingDelay1; $numRing2D.Value = [decimal][int]$script:DefaultRingDelay2; $numRing3D.Value = [decimal][int]$script:DefaultRingDelay3
        try {
          $tbRing1F.Text = ''; $tbRing2F.Text = ''; $tbRing3F.Text = ''
          $cbRing1FT.SelectedItem = 'include'; $cbRing2FT.SelectedItem = 'include'; $cbRing3FT.SelectedItem = 'include'
        } catch {}
      }
    } catch {}

    try {
      if ($json.NotificationPopup) {
        if ($null -ne $json.NotificationPopup.Enabled) { $chkNotifEnabled.Checked = [bool]$json.NotificationPopup.Enabled }
        if ($json.NotificationPopup.NotificationTimerInMinutes) {
          $m = [int]$json.NotificationPopup.NotificationTimerInMinutes
          if ($m -lt [int]$numNotifMins.Minimum) { $m = [int]$numNotifMins.Minimum }
          if ($m -gt [int]$numNotifMins.Maximum) { $m = [int]$numNotifMins.Maximum }
          $numNotifMins.Value = [decimal]$m
        }
        if ($null -ne $json.NotificationPopup.DeferralEnabled) { $chkDeferralEnabled.Checked = [bool]$json.NotificationPopup.DeferralEnabled }
        if ($json.NotificationPopup.DeferralHoursAllowed -ne $null) {
          $h = [int]$json.NotificationPopup.DeferralHoursAllowed
          if ($h -lt [int]$numDefHours.Minimum) { $h = [int]$numDefHours.Minimum }
          if ($h -gt [int]$numDefHours.Maximum) { $h = [int]$numDefHours.Maximum }
          $numDefHours.Value = [decimal]$h
        }
      }
    } catch {}

    try {
      if ($json.WingetId) {
        $val = [string]$json.WingetId
        $script:WingetSyncing = $true
        try { $tbWingetForNew.Text = $val } finally { $script:WingetSyncing = $false }
        try { Set-WingetIdAll $val } catch {}
        try { Set-FindFromWinget $val } catch {}
      }
    } catch {}

  } catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to load recipe: $($_.Exception.Message)","Error",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
  }
}
# Back-compat shim for removed 'Load from Recipe' button
$btnLoadQuick = New-Object PSObject
$btnLoadQuick | Add-Member -MemberType ScriptMethod -Name PerformClick -Value { Load-RecipeIntoQuickEdit } -Force

# ---------- Tab: Run ----------
$tabRun = New-Object System.Windows.Forms.TabPage
$tabRun.Text = "Run"
$tabs.TabPages.Add($tabRun)

$grpMode = New-Group "Mode" 10 10 280 160
$rbPkg = New-Object System.Windows.Forms.RadioButton
$rbPkg.Text = "Package Only (Testing Output)"; $rbPkg.Left=15; $rbPkg.Top=25; $rbPkg.Checked = $true; $rbPkg.AutoSize = $true
$rbFull= New-Object System.Windows.Forms.RadioButton
$rbFull.Text= "Full Run (Update Intune)"; $rbFull.Left=15; $rbFull.Top=60; $rbFull.Checked = $false; $rbFull.AutoSize = $true

# Additional run flags
$chkNoAuth = New-Object System.Windows.Forms.CheckBox
$chkNoAuth.Text = "No Azure Authentication"; $chkNoAuth.Left=15; $chkNoAuth.Top=95; $chkNoAuth.Width=240

$grpMode.Controls.AddRange(@($rbPkg,$rbFull,$chkNoAuth))
$tabRun.Controls.Add($grpMode)

$grpTarget = New-Group "Target" 300 10 520 120
$btnPickFile = New-Button "Select Recipe File..." 10 20 160
$tbRunPath   = New-TextBox 180 22 320

$grpTarget.Controls.AddRange(@($btnPickFile,$tbRunPath))
$tabRun.Controls.Add($grpTarget)

$btnRun = New-Button "Run AutoPackager" 830 22 200 40
$tabRun.Controls.Add($btnRun)

$txtRunOut = New-TextBox 10 180 ($tabRun.Width - 40) ($tabRun.Height - 220) $true $true
$txtRunOut.Anchor = 'Top,Left,Right,Bottom'
$tabRun.Controls.Add($txtRunOut)

$ofdRecipe = New-Object System.Windows.Forms.OpenFileDialog
$ofdRecipe.Filter = "Recipe JSON (*.json)|*.json|All files (*.*)|*.*"
$ofdRecipe.InitialDirectory = (Resolve-ExistingPath $PathRecipesDefault)


$btnPickFile.Add_Click({
  if ($ofdRecipe.ShowDialog() -eq 'OK') {
    $tbRunPath.Text = $ofdRecipe.FileName
    try { $tbRecipePath.Text = $ofdRecipe.FileName } catch {}
    try { $btnLoadQuick.PerformClick() } catch {}
  }
})

function Build-RunCommand() {
  $args = @()
  if ($rbPkg.Checked) { $args += '-PackageOnly' }
  elseif ($rbFull.Checked) { $args += '-FullRun' }
  $file = $tbRunPath.Text.Trim()
  if ($file) {
    $args += @('-PathRecipes', ("`"$file`""))
  }
  if ($chkNoAuth.Checked) { $args += '-NoAuth' }
  $cmd = "& `"$PathAutoPackager`" " + ($args -join ' ')
  return $cmd
}

$btnRun.Add_Click({
  if (-not (Test-Path -LiteralPath $PathAutoPackager)) {
    [System.Windows.Forms.MessageBox]::Show("AutoPackagerv2.ps1 not found:`r`n$PathAutoPackager","Missing",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null; return
  }
  $p = $tbRunPath.Text.Trim()
  if (-not $p) {
    [System.Windows.Forms.MessageBox]::Show("Select a recipe JSON file first.","Run",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    return
  }
  if (-not (Test-Path -LiteralPath $p)) {
    [System.Windows.Forms.MessageBox]::Show("Selected recipe path is invalid or does not exist.","Run",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    return
  }
  $cmd = Build-RunCommand
  $txtRunOut.Clear()
  Append-Output $txtRunOut ("Running: " + $cmd)
  $res = Invoke-PSCapture -Command $cmd -NoProfile
  if ($res.StdOut) { Append-Output $txtRunOut $res.StdOut.TrimEnd() }
  if ($res.StdErr) { Append-Output $txtRunOut ("[stderr]`r`n" + $res.StdErr.TrimEnd()) }
  if (Test-Path -LiteralPath $PathLog) {
    Append-Output $txtRunOut ""
    Append-Output $txtRunOut "----- AutoPackager.log (tail 300) -----"
    try {
      $tail = Get-Content -LiteralPath $PathLog -Tail 300 -ErrorAction SilentlyContinue
      if ($tail) { Append-Output $txtRunOut ($tail -join "`r`n") }
    } catch {}
  }
  try {
    $hasErr = $false
    try { if ($res -and ($res.ExitCode -ne $null) -and ($res.ExitCode -ne 0)) { $hasErr = $true } } catch {}
    try { if ($res -and $res.StdErr -and $res.StdErr.Trim()) { $hasErr = $true } } catch {}

    $icon = [System.Windows.Forms.MessageBoxIcon]::Information
    if ($hasErr) { $icon = [System.Windows.Forms.MessageBoxIcon]::Warning }

    $summary = "AutoPackager run completed."
    try { if ($res -and ($res.ExitCode -ne $null)) { $summary += "`r`nExitCode: $($res.ExitCode)" } } catch {}
    if (Test-Path -LiteralPath $PathLog) { $summary += "`r`nLog: $PathLog" }

    [System.Windows.Forms.MessageBox]::Show($summary, "Run AutoPackager", 0, $icon) | Out-Null
  } catch {}
})


# ---------- Tab: Reset ----------
$tabReset = New-Object System.Windows.Forms.TabPage
$tabReset.Text = "Reset"
$tabs.TabPages.Add($tabReset)

$grpReset = New-Group "Reset Placeholder Apps" 10 10 540 150
$lblPrim = New-Label "Primary AppId:" 10 30 160
$tbPrim  = New-TextBox 180 27 330
try { $tbPrim.ReadOnly = $true } catch {}
try { $tbPrim.TabStop = $false } catch {}
$lblSec  = New-Label "Required Update AppId:" 10 60 160
$tbSecId = New-TextBox 180 57 330
try { $tbSecId.ReadOnly = $true } catch {}
try { $tbSecId.TabStop = $false } catch {}
$btnReset1 = New-Button "Primary AppId Reset" 10 95 250 34
$btnReset2 = New-Button "Required Update AppId Reset" 270 95 250 34

$grpReset.Controls.AddRange(@($lblPrim,$tbPrim,$lblSec,$tbSecId,$btnReset1,$btnReset2))
$tabReset.Controls.Add($grpReset)

# Add "Select Existing App(s)" to the right of Reset group
$grpSelectAppsReset = New-Group 'Select Existing App(s)' 560 10 520 150
$lblFindReset   = New-Label 'Search Name:' 10 28 100
$tbFindReset    = New-TextBox 110 25 260
$btnFindPrimaryReset   = New-Button 'Find Primary App' 10 60 160
$btnFindSecondaryReset = New-Button 'Find Required Update App' 180 60 160
$grpSelectAppsReset.Controls.AddRange(@($lblFindReset,$tbFindReset,$btnFindPrimaryReset,$btnFindSecondaryReset))
$tabReset.Controls.Add($grpSelectAppsReset)

# Wire Reset tab select buttons to reuse Intune App(s) find handlers and return to Reset tab
try {
  $btnFindPrimaryReset.Add_Click({
    try { $txtAppsOut.Text = '' } catch {}
    try { $tbFind.Text = $tbFindReset.Text } catch {}
    try { $script:ReturnToResetAfterFind = $true } catch {}
    try { $tabs.SelectedTab = $tabApps } catch {}
    try { $btnFindPrimary.PerformClick() } catch {}
  })
  $btnFindSecondaryReset.Add_Click({
    try { $txtAppsOut.Text = '' } catch {}
    try { $tbFind.Text = $tbFindReset.Text } catch {}
    try { $script:ReturnToResetAfterFind = $true } catch {}
    try { $tabs.SelectedTab = $tabApps } catch {}
    try { $btnFindSecondary.PerformClick() } catch {}
  })
} catch {}

$lblResetNote = New-Label "Note: If AppId is provided, output is shown below. If not, the reset script may prompt in an external PowerShell window." 10 170 1000 40
$tabReset.Controls.Add($lblResetNote)
# Output box for Reset tab
$txtResetOut = New-TextBox 10 210 ($tabReset.Width - 40) ($tabReset.Height - 250) $true $true
$txtResetOut.Anchor = 'Top,Left,Right,Bottom'
$tabReset.Controls.Add($txtResetOut)

$btnReset1.Add_Click({
  if (-not (Test-Path -LiteralPath $PathResetPrimary)) { [System.Windows.Forms.MessageBox]::Show("Reset script not found:`r`n$PathResetPrimary","Missing",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null; return }
  $primaryId = $null
  try { $primaryId = $tbPrim.Text.Trim() } catch {}
  if (-not $primaryId) { try { $primaryId = $tbIntuneId.Text.Trim() } catch {} }
  if (-not $primaryId) { try { $primaryId = $tbAppsPrimId.Text.Trim() } catch {} }
  if (-not $primaryId) {
    [System.Windows.Forms.MessageBox]::Show("Enter or select a Primary IntuneAppId GUID first on the Recipe or Intune App(s) tab.","Input",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    return
  }
  $cmd = "& `"$PathResetPrimary`" -AppId `"$primaryId`""
  try { $txtResetOut.Clear() } catch {}
  Append-Output $txtResetOut ("Running: " + $cmd)
  $res = $null
  try {
    $res = Invoke-PSCapture -Command $cmd -NoProfile
    if ($res.StdOut) { Append-Output $txtResetOut $res.StdOut.TrimEnd() }
    if ($res.StdErr) { Append-Output $txtResetOut ("[stderr]`r`n" + $res.StdErr.TrimEnd()) }
  } catch {
    Append-Output $txtResetOut ("Error: " + $_.Exception.Message)
    Launch-ExternalPS -file $PathResetPrimary -args ("-AppId `"$primaryId`"")
  }
  try {
    $hasErr = $false
    try { if ($res -and ($res.ExitCode -ne $null) -and ($res.ExitCode -ne 0)) { $hasErr = $true } } catch {}
    try { if ($res -and $res.StdErr -and $res.StdErr.Trim()) { $hasErr = $true } } catch {}
    $icon = [System.Windows.Forms.MessageBoxIcon]::Information
    if ($hasErr) { $icon = [System.Windows.Forms.MessageBoxIcon]::Warning }
    $summary = "Primary AppId reset completed."
    try { if ($res -and ($res.ExitCode -ne $null)) { $summary += "`r`nExitCode: $($res.ExitCode)" } } catch {}
    [System.Windows.Forms.MessageBox]::Show($summary, "Primary AppId Reset", 0, $icon) | Out-Null
  } catch {}
})
$btnReset2.Add_Click({
  if (-not (Test-Path -LiteralPath $PathResetSecondary)) { [System.Windows.Forms.MessageBox]::Show("Reset script not found:`r`n$PathResetSecondary","Missing",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null; return }
  $sec = $null
  try { $sec = $tbSecId.Text.Trim() } catch {}
  if ($sec) {
    $cmd = "& `"$PathResetSecondary`" -AppId `"$sec`""
    try { $txtResetOut.Clear() } catch {}
    Append-Output $txtResetOut ("Running: " + $cmd)
    $res = $null
    try {
      $res = Invoke-PSCapture -Command $cmd -NoProfile
      if ($res.StdOut) { Append-Output $txtResetOut $res.StdOut.TrimEnd() }
      if ($res.StdErr) { Append-Output $txtResetOut ("[stderr]`r`n" + $res.StdErr.TrimEnd()) }
    } catch {
      Append-Output $txtResetOut ("Error: " + $_.Exception.Message)
      Launch-ExternalPS -file $PathResetSecondary -args ("-AppId `"$sec`"")
    }
    try {
      $hasErr = $false
      try { if ($res -and ($res.ExitCode -ne $null) -and ($res.ExitCode -ne 0)) { $hasErr = $true } } catch {}
      try { if ($res -and $res.StdErr -and $res.StdErr.Trim()) { $hasErr = $true } } catch {}
      $icon = [System.Windows.Forms.MessageBoxIcon]::Information
      if ($hasErr) { $icon = [System.Windows.Forms.MessageBoxIcon]::Warning }
      $summary = "Required Update AppId reset completed."
      try { if ($res -and ($res.ExitCode -ne $null)) { $summary += "`r`nExitCode: $($res.ExitCode)" } } catch {}
      [System.Windows.Forms.MessageBox]::Show($summary, "Required Update AppId Reset", 0, $icon) | Out-Null
    } catch {}
  } else {
    Launch-ExternalPS -file $PathResetSecondary -args $null
  }
})

# ---------- Tab: Logs ----------
$tabLogs = New-Object System.Windows.Forms.TabPage
$tabLogs.Text = "Logs"
$tabs.TabPages.Add($tabLogs)

$btnRefreshLog = New-Button "Refresh Log" 10 10 120
$btnOpenWorking = New-Button "Open Working Folder" 140 10 160
$btnOpenLatestCsv = New-Button "Open Latest Summary CSV" 310 10 200

$txtLog = New-TextBox 10 45 ($tabLogs.Width - 40) ($tabLogs.Height - 80) $true $true
$txtLog.Anchor = 'Top,Left,Right,Bottom'

$tabLogs.Controls.AddRange(@($btnRefreshLog,$btnOpenWorking,$btnOpenLatestCsv,$txtLog))

$btnRefreshLog.Add_Click({
  $txtLog.Clear()
  if (Test-Path -LiteralPath $PathLog) {
    try {
      $tail = Get-Content -LiteralPath $PathLog -Tail 500 -ErrorAction SilentlyContinue
      if ($tail) { Append-Output $txtLog ($tail -join "`r`n") } else { Append-Output $txtLog "(Log is empty.)" }
    } catch { Append-Output $txtLog "Failed to read log: $($_.Exception.Message)" }
  } else {
    Append-Output $txtLog "Log not found at: $PathLog"
  }
})

$btnOpenWorking.Add_Click({
  $p = if (Test-Path -LiteralPath $PathWorking) { $PathWorking } else { $ScriptRoot }
  Start-Process explorer.exe -ArgumentList "`"$p`""
})
$btnOpenLatestCsv.Add_Click({
  try {
    if (Test-Path -LiteralPath $PathWorking) {
      $latest = Get-ChildItem -LiteralPath $PathWorking -Filter 'Summary_*.csv' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
      if ($latest) { Start-Process "`"$($latest.FullName)`"" } else { [System.Windows.Forms.MessageBox]::Show("No Summary_*.csv found in Working.","Info",0,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null }
    } else {
      [System.Windows.Forms.MessageBox]::Show("Working folder not found.","Info",0,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
  } catch {
    [System.Windows.Forms.MessageBox]::Show("Error opening latest CSV: $($_.Exception.Message)","Error",0,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
  }
})

# ---------- Tab: Config ----------
$tabCfg = New-Object System.Windows.Forms.TabPage
$tabCfg.Text = "Config"
$tabs.TabPages.Add($tabCfg)

$btnOpenCfg = New-Button "Open AutoPackager.config.json" 10 10 240
$btnOpenReadme = New-Button "Open readme.txt" 260 10 160
$btnOpenSysReadme = New-Button "Open SystemConfigReadMe.txt" 430 10 220
$tabCfg.Controls.AddRange(@($btnOpenCfg,$btnOpenReadme,$btnOpenSysReadme))

$btnOpenCfg.Add_Click({ if (Test-Path -LiteralPath $PathConfig) { Start-Process notepad.exe -ArgumentList "`"$PathConfig`"" } else { [System.Windows.Forms.MessageBox]::Show("Config not found: $PathConfig","Missing",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null } })
$btnOpenReadme.Add_Click({ if (Test-Path -LiteralPath $PathReadme) { Start-Process notepad.exe -ArgumentList "`"$PathReadme`"" } else { [System.Windows.Forms.MessageBox]::Show("readme.txt not found: $PathReadme","Missing",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null } })
$btnOpenSysReadme.Add_Click({
  $p = Join-Path $ScriptRoot 'SystemConfigReadMe.txt'
  if (Test-Path -LiteralPath $p) { Start-Process notepad.exe -ArgumentList "`"$p`"" } else { [System.Windows.Forms.MessageBox]::Show("SystemConfigReadMe.txt not found: $p","Missing",0,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null }
})

# ---------- Tab: Prerequisite Check ----------
$tabPrereq = New-Object System.Windows.Forms.TabPage
$tabPrereq.Text = "Prerequisite Check"

# Add it to ensure visibility, then move after Config if needed
try {
  if (-not ($tabs.TabPages.Contains($tabPrereq))) { $tabs.TabPages.Add($tabPrereq) }
} catch { $tabs.TabPages.Add($tabPrereq) }
try {
  $idxCfg = $tabs.TabPages.IndexOf($tabCfg)
  $idxNew = $tabs.TabPages.IndexOf($tabPrereq)
  if ($idxCfg -ge 0 -and $idxNew -gt ($idxCfg + 1)) {
    $tabs.TabPages.Remove($tabPrereq)
    $tabs.TabPages.Insert(($idxCfg + 1), $tabPrereq)
  }
} catch {}

# Single action button at top
$btnPrereq = New-Button "Run Prerequisite Check" 10 10 220 34
$tabPrereq.Controls.Add($btnPrereq)

# Large output window
# Compute safe size for output box (avoid negative dimensions before layout)
$outW = 0; $outH = 0
try { $outW = [int]($tabPrereq.Width - 40) } catch { $outW = 0 }
try { $outH = [int]($tabPrereq.Height - 90) } catch { $outH = 0 }
if ($outW -lt 300) { try { $outW = [int]($tabs.Width - 60) } catch { $outW = 1000 } }
if ($outW -lt 300) { $outW = 1000 }
if ($outH -lt 200) { try { $outH = [int]($tabs.Height - 120) } catch { $outH = 500 } }
if ($outH -lt 200) { $outH = 500 }
$txtPrereqOut = New-Object System.Windows.Forms.RichTextBox
$txtPrereqOut.Left = 10
$txtPrereqOut.Top = 50
$txtPrereqOut.Width = $outW
$txtPrereqOut.Height = $outH
$txtPrereqOut.ReadOnly = $true
$txtPrereqOut.Anchor = 'Top,Left,Right,Bottom'
try { $txtPrereqOut.DetectUrls = $false } catch {}
try { $txtPrereqOut.WordWrap = $false } catch {}
$tabPrereq.Controls.Add($txtPrereqOut)

# Button handler
$btnPrereq.Add_Click({
  try { $txtPrereqOut.Clear() } catch {}
  Append-Output $txtPrereqOut "Starting prerequisite checks..."

  # PowerShell version
  try {
    Append-Output $txtPrereqOut "Testing Powershell version..."
    $ver = $PSVersionTable.PSVersion
    if ($ver.Major -lt 5 -or ($ver.Major -eq 5 -and $ver.Minor -lt 1)) {
      Append-OutputColored $txtPrereqOut ("WARNING: PowerShell 5.1+ is recommended.") 'Red'
    }
    else {    
      Append-OutputColored $txtPrereqOut ("PowerShell version: " + $ver + " : OK") 'Green'
    }
  } catch {}

  # Required script files present  
  Append-Output $txtPrereqOut "Starting script file checks..."
  $PathSysReadme = Join-Path $ScriptRoot 'SystemConfigReadMe.txt'
  $PathIntuneWinFile = Join-Path $ScriptRoot 'Temp\install.intunewin'
  $files = @(
    @{ Name='AutoPackagerv2.ps1'; Path=$PathAutoPackager },
    @{ Name='New-RecipeFromWinget.ps1'; Path=$PathNewRecipe },
    @{ Name='IntuneAppTools.ps1'; Path=$PathIntuneTools },
    @{ Name='AutoPackager.config.json'; Path=$PathConfig },
    @{ Name='CreateWin32AppFromTemplate.ps1'; Path=$PathCreateTemplate },
    @{ Name='IntuneApplicationResetAll.ps1'; Path=$PathResetPrimary },
    @{ Name='install.intunewin'; Path=$PathIntuneWinFile },
    @{ Name='readme.txt'; Path=$PathReadme },
    @{ Name='SystemConfigReadMe.txt'; Path=$PathSysReadme }
  )
  foreach ($f in $files) {
    $ok = Test-Path -LiteralPath $f.Path
    if ($ok) {
      Append-OutputColored $txtPrereqOut ("{0}: OK" -f $f.Name) 'Green'
    } else {
      Append-OutputColored $txtPrereqOut ("{0}: MISSING" -f $f.Name) 'Red'
    }
  }

  # Required support files
  Append-Output $txtPrereqOut "Starting support file checks..."
  $PathIntuneWinUtil = Join-Path $ScriptRoot 'IntuneWinAppUtil.exe'
  $Supportfiles = @(
    @{ Name='IntuneWinAppUtil.exe'; Path=$PathIntuneWinUtil }
  )
  foreach ($S in $Supportfiles) {
    $ok = Test-Path -LiteralPath $S.Path
    if ($ok) {
      Append-OutputColored $txtPrereqOut ("{0}: OK" -f $S.Name) 'Green'
    } else {
      Append-OutputColored $txtPrereqOut ("{0}: MISSING - Will need to download from internet" -f $S.Name) 'Red'
    }
  }

  # Working folder write test
  Append-Output $txtPrereqOut "Checking for write access..."
  try {
    $dir = $PathWorking
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null }
    $tmp = Join-Path $dir ('_writetest_{0}.tmp' -f ([Guid]::NewGuid().ToString()))
    Set-Content -LiteralPath $tmp -Value 'test' -Encoding ASCII -ErrorAction Stop
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    Append-OutputColored $txtPrereqOut "Working folder write access: OK" 'Green'
  } catch { Append-OutputColored $txtPrereqOut ("Working folder write access: FAILED - " + $_.Exception.Message) 'Red' }

  #Testing Powershell Modules
  Append-Output $txtPrereqOut "Starting Powershell module checks..."
    # Microsoft.WinGet.Client module
    try {
      $mod = Get-Module -ListAvailable -Name 'Microsoft.WinGet.Client' | Select-Object -First 1
      if ($mod) { Append-OutputColored $txtPrereqOut "Microsoft.WinGet.Client module: FOUND" 'Green' } else { Append-OutputColored $txtPrereqOut "Microsoft.WinGet.Client module: NOT FOUND" 'Red' }
    } catch {}

    # powershell-yaml module (used for YAML parsing)
    try {
      $mod = Get-Module -ListAvailable -Name 'powershell-yaml' | Select-Object -First 1
      if (-not $mod) { $mod = Get-Module -ListAvailable -Name 'Powershell-YAML' | Select-Object -First 1 }
      if ($mod) { Append-OutputColored $txtPrereqOut "powershell-yaml module: FOUND" 'Green' } else { Append-OutputColored $txtPrereqOut "powershell-yaml module: NOT FOUND" 'Red' }
    } catch {}

    # IntuneWin32App module (used by Create/Find helpers)
    try {
      $mod = Get-Module -ListAvailable -Name 'IntuneWin32App' | Select-Object -First 1
      if ($mod) { Append-OutputColored $txtPrereqOut "IntuneWin32App module: FOUND" 'Green' } else { Append-OutputColored $txtPrereqOut "IntuneWin32App module: NOT FOUND" 'Red' }
    } catch {}

  # Config validation: AzureAuth + GitHubToken, then quick Azure auth test (client credentials)
Append-Output $txtPrereqOut "Looking for AzureAuth Config and GitHubToken Config..."
try {
    if (Test-Path -LiteralPath $PathConfig) {
      $cfg = $null
      try { $cfg = Get-Content -LiteralPath $PathConfig -Raw | ConvertFrom-Json } catch {}
      if ($cfg) {
        $az = $null
        try { $az = $cfg.AzureAuth } catch {}

        $tenant = ''; $client = ''; $secret = ''; $thumb = ''
        try { if ($az -and $az.TenantId) { $tenant = [string]$az.TenantId } } catch {}
        try { if ($az -and $az.ClientId) { $client = [string]$az.ClientId } } catch {}
        try { if ($az -and $az.ClientSecret) { $secret = [string]$az.ClientSecret } } catch {}
        try { if ($az -and $az.CertificateThumbprint) { $thumb = [string]$az.CertificateThumbprint } } catch {}

        $hasTenant = ($tenant -and $tenant.Trim())
        $hasClient = ($client -and $client.Trim())
        $hasSecret = ($secret -and $secret.Trim())
        $hasThumb  = ($thumb  -and $thumb.Trim())

        # Individual AzureAuth fields
        Append-OutputColored $txtPrereqOut ("Config.AzureAuth.TenantId: " + ($(if ($hasTenant) {'FOUND'} else {'MISSING - Intune upload features unavailable'}))) ($(if ($hasTenant) {'Green'} else {'Red'}))
        Append-OutputColored $txtPrereqOut ("Config.AzureAuth.ClientId: " + ($(if ($hasClient) {'FOUND'} else {'MISSING - Intune upload features unavailable'}))) ($(if ($hasClient) {'Green'} else {'Red'}))
        Append-OutputColored $txtPrereqOut ("Config.AzureAuth.ClientSecret: " + ($(if ($hasSecret) {'FOUND'} else {'MISSING - Intune upload features unavailable'}))) ($(if ($hasSecret) {'Green'} else {'Red'}))
        # CertificateThumbprint is optional and may be blank
        Append-OutputColored $txtPrereqOut ("Config.AzureAuth.CertificateThumbprint: " + ($(if ($hasThumb) {'PRESENT'} else {'BLANK (OK)'}))) 'Green'

        # Overall AzureAuth validity: require TenantId, ClientId, ClientSecret; CertificateThumbprint optional
        $azureOk = ($hasTenant -and $hasClient -and $hasSecret)
        Append-OutputColored $txtPrereqOut ("AzureAuth section: " + ($(if ($azureOk) {'OK'} else {'INVALID (require TenantId, ClientId, and ClientSecret; CertificateThumbprint optional)'}))) ($(if ($azureOk) {'Green'} else {'Red'}))

        # GitHubToken presence (do not echo value)
        $ghTok = ''
        try { if ($cfg.GitHubToken) { $ghTok = [string]$cfg.GitHubToken } } catch {}
        $hasGh = ($ghTok -and $ghTok.Trim())
        Append-OutputColored $txtPrereqOut ("Config.GitHubToken: " + ($(if ($hasGh) {'FOUND'} else {'MISSING - Limited api calls enforced'}))) ($(if ($hasGh) {'Green'} else {'Red'}))

        # If AzureAuth looks valid, perform a quick client credentials token request to Entra ID (MS Graph scope)
        if ($azureOk) {
          Append-Output $txtPrereqOut "Testing Azure authentication (client credentials)..."
          try {
            $tokenEndpoint = "https://login.microsoftonline.com/$tenant/oauth2/v2.0/token"
            $body = @{
              client_id     = $client
              client_secret = $secret
              scope         = 'https://graph.microsoft.com/.default'
              grant_type    = 'client_credentials'
            }
            $resp = Invoke-RestMethod -Method Post -Uri $tokenEndpoint -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
            if ($resp -and $resp.access_token) {
              Append-OutputColored $txtPrereqOut "Azure auth: SUCCESS (token acquired)" 'Green'
            } else {
              Append-OutputColored $txtPrereqOut "Azure auth: FAILED (no token received)" 'Red'
            }
          } catch {
            Append-OutputColored $txtPrereqOut ("Azure auth: FAILED - " + $_.Exception.Message) 'Red'
          }
        } else {
          Append-OutputColored $txtPrereqOut "Azure auth: SKIPPED (missing TenantId/ClientId/ClientSecret)" 'Red'
        }
      } else {
        Append-OutputColored $txtPrereqOut "Config parse failed. Cannot validate AzureAuth/GitHubToken." 'Red'
      }
    } else {
      Append-OutputColored $txtPrereqOut "Config file not found for auth checks." 'Red'
    }
  } catch {}


  Append-Output $txtPrereqOut "Prerequisite checks completed."
})

# ---------- Tab: Help ----------
$tabHelp = New-Object System.Windows.Forms.TabPage
$tabHelp.Text = "Help"
$tabs.TabPages.Add($tabHelp)

$lblHelp = New-Label "Created by: Tom Fritsche        Assisted by: Derek Musselman, Robert Flowers" 10 10 600 40
$txtHelp = New-TextBox 10 60 ($tabHelp.Width - 40) ($tabHelp.Height - 100) $true $true
$txtHelp.Anchor = 'Top,Left,Right,Bottom'
$btnHelpWindow = New-Button "Open Help in New Window" ($tabHelp.Width - 220) 10 200
$btnHelpWindow.Anchor = 'Top,Right'
$btnHelpWindow.Add_Click({
  try {
    $helpForm = New-Object System.Windows.Forms.Form
    $helpForm.Text = "AutoPackager Help"
    $helpForm.StartPosition = 'CenterParent'
    $helpForm.Width = 900
    $helpForm.Height = 600
    # Use the same icon as the main GUI window
    try { if ($form -and $form.Icon) { $helpForm.Icon = $form.Icon } } catch {}

    $tbHelpWin = New-TextBox 10 10 ($helpForm.ClientSize.Width - 20) ($helpForm.ClientSize.Height - 20) $true $true
    $tbHelpWin.Anchor = 'Top,Left,Right,Bottom'
    try { $tbHelpWin.ReadOnly = $true } catch {}
    try { $tbHelpWin.Text = $txtHelp.Text } catch {}

    $helpForm.Controls.Add($tbHelpWin)
    [void]$helpForm.Show()
  } catch {}
})
$tabHelp.Controls.AddRange(@($lblHelp,$txtHelp,$btnHelpWindow))
try {
  if (Test-Path -LiteralPath $PathReadme) {
    $txtHelp.Text = (Get-Content -LiteralPath $PathReadme -Raw)
  } else {
    $txtHelp.Text = "readme.txt not found at:`r`n$PathReadme"
  }
} catch { $txtHelp.Text = "Failed to load readme: $($_.Exception.Message)" }

# Apply defaults from config to GUI controls
Load-ConfigDefaults
# Reflect any configured architecture preference in the Winget tab dropdown
try { if ($cbArchWinget -and $script:PreferArchitecture) { $cbArchWinget.SelectedItem = $script:PreferArchitecture } } catch {}

# Select the Winget tab on startup
try { if ($tabWinget) { $tabs.SelectedTab = $tabWinget } } catch {}
# Show
[void]$form.ShowDialog()
