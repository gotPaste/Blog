#requires -Version 5.1
<#
IntuneAppTools.ps1
Helper for AutoPackager GUI to:
- Create placeholder Win32 apps in Intune with metadata from winget
- Find existing Win32 apps by (partial) display name
- Optionally set an icon on created apps

Auth:
- Reads AZInfo.csv from the repo root by default (next to AutoPackager.ps1)
- Supports app-only auth via ClientSecret (preferred here) or CertificateThumbprint (module path)

Usage examples:
- Create (Primary):
  powershell -ExecutionPolicy Bypass -File .\IntuneAppTools.ps1 -Action CreateApp `
    -DisplayName "Zoom 6.0.0" -Publisher "Zoom" -Developer "Zoom" `
    -Description "..." -InformationUrl "https://..." -PrivacyUrl "https://..." `
    -IconPath "C:\path\icon.png" -Type Primary

- Find by name:
  powershell -ExecutionPolicy Bypass -File .\IntuneAppTools.ps1 -Action FindApp -Name "Zoom"
#>

param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('CreateApp','FindApp')]
  [string]$Action,

  # CreateApp inputs
  [string]$DisplayName,
  [string]$Publisher,
  [string]$Developer,
  [string]$Description,
  [string]$InformationUrl,
  [string]$PrivacyUrl,
  [string]$IconPath,
  [ValidateSet('Primary','Secondary')]
  [string]$Type = 'Primary',

  # FindApp input
  [string]$Name,
  [object]$List,
  [object]$AsJson,
  [object]$UseModule,

  # Optional explicit auth overrides (else read from AZInfo.csv)
  [string]$TenantId,
  [string]$ClientId,
  [securestring]$ClientSecret,
  [string]$CertificateThumbprint
)

# Suppress noisy console output when returning JSON lists for GUI parsing
function Test-Switch($value) {
  try {
    if ($null -eq $value) { return $false }
    if ($value -is [bool]) { return [bool]$value }
    if ($value -is [string]) {
      if ([string]::IsNullOrWhiteSpace($value)) { return $false }
      if ($value -match '^(?i:true|1|yes)$') { return $true }
      if ($value -match '^(?i:false|0|no)$') { return $false }
      return [bool]::Parse($value)
    }
    if ($value -is [System.Array]) { return ($value.Length -gt 0) }
    if ($value -is [System.Management.Automation.SwitchParameter]) { return [bool]$value }
    return [bool]$value
  } catch { return $false }
}
$script:QuietOutput = $false
$__wantJson = ($PSBoundParameters.ContainsKey('List') -or $PSBoundParameters.ContainsKey('AsJson') -or (Test-Switch $List) -or (Test-Switch $AsJson))
if ($__wantJson) { $script:QuietOutput = $true }

$ErrorActionPreference = 'Stop'

# Resolve this script's directory and repo root
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot -or [string]::IsNullOrWhiteSpace($ScriptRoot)) {
  if ($PSCommandPath) { $ScriptRoot = Split-Path -Parent $PSCommandPath }
  elseif ($MyInvocation.MyCommand.Path) { $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
  else { $ScriptRoot = (Get-Location).Path }
}
$RepoRoot = $ScriptRoot

# Load AutoPackager.config.json (optional) for AzureAuth defaults
try {
  $cfgPath = Join-Path $RepoRoot 'AutoPackager.config.json'
  if (Test-Path -LiteralPath $cfgPath) {
    $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
    if ($cfg -and $cfg.AzureAuth) {
      if (-not $TenantId -and $cfg.AzureAuth.TenantId) { $TenantId = [string]$cfg.AzureAuth.TenantId }
      if (-not $ClientId -and $cfg.AzureAuth.ClientId) { $ClientId = [string]$cfg.AzureAuth.ClientId }
      if (-not $ClientSecret -and $cfg.AzureAuth.ClientSecret) {
        try { $ClientSecret = ConvertTo-SecureString -String ([string]$cfg.AzureAuth.ClientSecret) -AsPlainText -Force } catch {}
      }
      if (-not $CertificateThumbprint -and $cfg.AzureAuth.CertificateThumbprint) { $CertificateThumbprint = [string]$cfg.AzureAuth.CertificateThumbprint }
    }
  }
} catch { }

function Write-Info([string]$m) { if ($script:QuietOutput) { return }; Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Warn([string]$m) { if ($script:QuietOutput) { return }; Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err ([string]$m) { if ($script:QuietOutput) { [Console]::Error.WriteLine("[ERROR] $m") } else { Write-Host "[ERROR] $m" -ForegroundColor Red } }

# Load AZInfo.csv (optional)
try {
  $csvPathCandidates = @(
    (Join-Path $RepoRoot 'AZInfo.csv'),
    (Join-Path (Split-Path -Parent $RepoRoot) 'AZInfo.csv')
  )
  $csvPath = $csvPathCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if ($csvPath) {
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
      if (-not $TenantId)            { $TenantId = __GetCsvVal $row 'TenantId' }
      if (-not $ClientId)            { $ClientId = __GetCsvVal $row 'ClientId' }
      if (-not $ClientSecret) {
        $secPlain = __GetCsvVal $row 'ClientSecret'
        if ($secPlain) { try { $ClientSecret = ConvertTo-SecureString -String $secPlain -AsPlainText -Force } catch {} }
      }
      if (-not $CertificateThumbprint) { $CertificateThumbprint = __GetCsvVal $row 'CertificateThumbprint' }
    }
  }
} catch {
  Write-Warn "Failed to load AZInfo.csv: $($_.Exception.Message)"
}

function ConvertTo-Plain([securestring]$s) {
  if (-not $s) { return $null }
  $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringAuto($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

# Acquire Graph token for app-only (client credentials) - preferred for REST usage
function Get-GraphToken {
  if (-not $TenantId -or -not $ClientId) {
    throw "Missing TenantId/ClientId for Graph auth. Provide in AZInfo.csv or as parameters."
  }
  if (-not $ClientSecret -and -not $CertificateThumbprint) {
    throw "Provide either ClientSecret or CertificateThumbprint for app-only auth."
  }
  if ($ClientSecret) {
    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
      client_id     = $ClientId
      client_secret = (ConvertTo-Plain $ClientSecret)
      scope         = 'https://graph.microsoft.com/.default'
      grant_type    = 'client_credentials'
    }
    try {
      $resp = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
      if ($resp.access_token) { return $resp.access_token }
      throw "No access_token in response."
    } catch {
      throw "Failed to obtain Graph token via client secret: $($_.Exception.Message)"
    }
  } else {
    # Cert path (requires module session for Invoke-MSGraphRequest or building a JWT with cert - omitted here)
    # Prefer module-based session as fallback
    try {
      if (-not (Get-Module -ListAvailable -Name 'IntuneWin32App')) {
        Install-Module IntuneWin32App -Scope CurrentUser -Force -ErrorAction Stop
      }
      Import-Module IntuneWin32App -ErrorAction Stop | Out-Null
      Write-Info "Connecting to Intune (certificate thumbprint)..."
      Connect-MSIntuneGraph -TenantID $TenantId -ClientID $ClientId -CertificateThumbprint $CertificateThumbprint -ErrorAction Stop | Out-Null
      # IntuneWin32App exposes Invoke-MSGraphRequest which will use the connected session; we'll route requests through it when no raw token is available.
      return $null
    } catch {
      throw "Certificate-based module session failed: $($_.Exception.Message)"
    }
  }
}

function Invoke-HttpWithRetry {
  param(
    [Parameter()][ValidateSet('GET','POST','PATCH','DELETE','PUT')][string]$Method = 'GET',
    [Parameter(Mandatory=$true)][string]$Url,
    [Parameter()][hashtable]$Headers,
    [Parameter()][string]$ContentType = 'application/json',
    [Parameter()][string]$JsonBody,
    [Parameter()][byte[]]$BinaryBody,
    [int]$MaxAttempts = 8,
    [int]$BaseDelayMs = 500
  )
  $attempt = 0
  while ($true) {
    $attempt++
    try {
      if ($Method -in @('POST','PATCH')) {
        return Invoke-RestMethod -Method $Method -Uri $Url -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
      } elseif ($Method -eq 'PUT' -and $BinaryBody) {
        return Invoke-RestMethod -Method Put -Uri $Url -Headers $Headers -ContentType $ContentType -Body $BinaryBody -ErrorAction Stop
      } else {
        return Invoke-RestMethod -Method $Method -Uri $Url -Headers $Headers -ErrorAction Stop
      }
    } catch {
      $ex = $_.Exception
      $resp = $ex.Response
      $status = $null
      try { $status = [int]$resp.StatusCode } catch {}
      $retryAfter = $null
      if ($resp) {
        try { $retryAfter = $resp.Headers['Retry-After'] } catch {}
        if (-not $retryAfter) { try { $retryAfter = $resp.Headers['x-ms-retry-after-ms'] } catch {} }
      }
      $isThrottle = ($status -eq 429 -or $status -eq 503 -or ($retryAfter -ne $null -and $retryAfter -ne ''))
      if ($isThrottle -and $attempt -lt $MaxAttempts) {
        $delayMs = 0
        if ($retryAfter) {
          try {
            if ($retryAfter -is [string]) { $retryAfter = $retryAfter.Trim() }
            if ($retryAfter -match '^\d{1,6}$') {
              $delayMs = [int]$retryAfter * 1000
            } elseif ($retryAfter -match '^\d{7,}$') {
              $delayMs = [int]$retryAfter
            } else {
              $dt = [datetime]::Parse($retryAfter)
              $delta = $dt - (Get-Date)
              $delayMs = [int][math]::Max(0, $delta.TotalMilliseconds)
            }
          } catch {}
        }
        if ($delayMs -le 0) {
          $delayMs = [math]::Min(120000, [math]::Pow(2,$attempt) * $BaseDelayMs + (Get-Random -Minimum 100 -Maximum 500))
        }
        $reqId = $null; $diag = $null
        try { $reqId = $resp.Headers['request-id'] } catch {}
        try { $diag = $resp.Headers['x-ms-ags-diagnostic'] } catch {}
        Write-Warn ("Throttled (status={0}). Retrying in {1}s (attempt {2}/{3}). request-id={4}" -f $status, [math]::Ceiling($delayMs/1000), $attempt, $MaxAttempts, ($reqId -join ','))

        Start-Sleep -Milliseconds $delayMs
        continue
      }
      throw
    }
  }
}

function Invoke-MSGraphWithRetry {
  param(
    [Parameter(Mandatory=$true)][hashtable]$Params,
    [int]$MaxAttempts = 8,
    [int]$BaseDelayMs = 500
  )
  $attempt = 0
  while ($true) {
    $attempt++
    try {
      return Invoke-MSGraphRequest @Params
    } catch {
      $msg = $_.Exception.Message
      $status = $null
      try { $status = [int]$_.Exception.Response.StatusCode } catch {}
      $isThrottle = ($msg -match '(?i)(429|TooManyRequests|throttl|rate limit|ServiceUnavailable)' -or $status -eq 429 -or $status -eq 503)
      if ($isThrottle -and $attempt -lt $MaxAttempts) {
        $delayMs = [math]::Min(120000, [math]::Pow(2,$attempt) * $BaseDelayMs + (Get-Random -Minimum 100 -Maximum 500))
        Write-Warn ("Throttled (module path). Retrying in {0}s (attempt {1}/{2})." -f [math]::Ceiling($delayMs/1000), $attempt, $MaxAttempts)
        Start-Sleep -Milliseconds $delayMs
        continue
      }
      throw
    }
  }
}

function Invoke-Graph {
  param(
    [Parameter()][ValidateSet('GET','POST','PATCH','DELETE','PUT')][string]$Method = 'GET',
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter()][object]$Body,
    [Parameter()][byte[]]$BinaryBody,
    [Parameter()][string]$ContentType = 'application/json'
  )
  $base = 'https://graph.microsoft.com'
  # Prefer v1.0 unless caller passes absolute or beta path
  $url = if ($Path -match '^https?://') { $Path } else { "$base/v1.0$Path" }

  # Try raw token if available; else module session
  $token = $null
  try { $token = Get-GraphToken } catch {}
  if ($token) {
    $headers = @{ Authorization = "Bearer $token" }
    if ($Method -in @('POST','PATCH')) {
      $json = $null
      if ($Body) { $json = ($Body | ConvertTo-Json -Depth 20) }
      return Invoke-HttpWithRetry -Method $Method -Url $url -Headers $headers -ContentType $ContentType -JsonBody $json
    } elseif ($Method -eq 'PUT' -and $BinaryBody) {
      return Invoke-HttpWithRetry -Method 'PUT' -Url $url -Headers $headers -ContentType $ContentType -BinaryBody $BinaryBody
    } else {
      return Invoke-HttpWithRetry -Method $Method -Url $url -Headers $headers
    }
  } else {
    # Module session path (requires IntuneWin32App session)
    $cmd = Get-Command -Name Invoke-MSGraphRequest -ErrorAction SilentlyContinue
    if (-not $cmd) {
      try {
        # Attempt to ensure module and connect using available credentials
        if (-not (Get-Module -ListAvailable -Name 'IntuneWin32App')) {
          Install-Module IntuneWin32App -Scope CurrentUser -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Import-Module IntuneWin32App -ErrorAction SilentlyContinue | Out-Null
        # Attempt connection if creds available
        if ($TenantId -and $ClientId -and $ClientSecret) {
          Connect-MSIntuneGraph -TenantID $TenantId -ClientID $ClientId -ClientSecret (ConvertTo-Plain $ClientSecret) -ErrorAction SilentlyContinue | Out-Null
        } elseif ($TenantId -and $ClientId -and $CertificateThumbprint) {
          Connect-MSIntuneGraph -TenantID $TenantId -ClientID $ClientId -CertificateThumbprint $CertificateThumbprint -ErrorAction SilentlyContinue | Out-Null
        }
      } catch {}
      $cmd = Get-Command -Name Invoke-MSGraphRequest -ErrorAction SilentlyContinue
      if (-not $cmd) {
        throw "Intune connection not available. Provide AZInfo.csv or AutoPackager.config.json with TenantId, ClientId, and ClientSecret or CertificateThumbprint, or install/import IntuneWin32App."
      }
    }
    if ($Method -in @('POST','PATCH')) {
      $params = @{ Url = $url; OutputType = 'Json' }
      if ($cmd.Parameters.Keys -contains 'HttpMethod') { $params['HttpMethod'] = $Method } else { $params['Method'] = $Method }
      if ($Body) { $params['Body'] = $Body }
      return Invoke-MSGraphWithRetry -Params $params
    } elseif ($Method -eq 'PUT' -and $BinaryBody) {
      # Invoke-MSGraphRequest may not support raw binary PUT; fallback not supported here.
      throw "Binary PUT not supported with module path; use ClientSecret for icon upload."
    } else {
      $params = @{ Url = $url; OutputType = 'Json' }
      if ($cmd.Parameters.Keys -contains 'HttpMethod') { $params['HttpMethod'] = $Method } else { $params['Method'] = $Method }
      return Invoke-MSGraphWithRetry -Params $params
    }
  }
}

function Get-ContentTypeFromExtension([string]$path) {
  $ext = [IO.Path]::GetExtension($path)
  if (-not $ext) { $ext = '' }
  $ext = $ext.ToLower()
  switch ($ext) {
    '.png'  { return 'image/png' }
    '.jpg'  { return 'image/jpeg' }
    '.jpeg' { return 'image/jpeg' }
    default { throw "Unsupported icon type '$ext'. Allowed types are: .png, .jpg, .jpeg." }
  }
}

function Create-Win32PlaceholderApp {
  param(
    [Parameter(Mandatory=$true)][string]$DisplayName,
    [string]$Publisher, [string]$Developer, [string]$Description,
    [string]$InformationUrl, [string]$PrivacyUrl
  )
  # Minimal body for Win32LobApp create; content/files can be added later
  $body = @{
    '@odata.type'            = '#microsoft.graph.win32LobApp'
    displayName              = $DisplayName
    description              = $Description
    developer                = $Developer
    publisher                = $Publisher
    informationUrl           = $InformationUrl
    privacyInformationUrl    = $PrivacyUrl
    isFeatured               = $false
    notes                    = 'Created by Intune AutoPackager GUI'
    owner                    = $null
    # Provide a default install experience object to satisfy schema expectations
    installExperience        = @{
      '@odata.type' = '#microsoft.graph.win32LobAppInstallExperience'
      runAsAccount  = 'system'
      runAs32Bit    = $false
    }
  }

  try {
    $res = Invoke-Graph -Method 'POST' -Path '/deviceAppManagement/mobileApps' -Body $body
    $id = $null
    try { $id = [string]$res.id } catch {}
    if (-not $id) { throw "Create returned no id." }
    return $id
  } catch {
    throw "Create-Win32PlaceholderApp failed: $($_.Exception.Message)"
  }
}

function Set-AppLargeIcon {
  param([Parameter(Mandatory=$true)][string]$AppId, [Parameter(Mandatory=$true)][string]$IconPath)
  if (-not (Test-Path -LiteralPath $IconPath)) {
    throw "Icon file not found: $IconPath"
  }
  $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $IconPath))
  $ctype = Get-ContentTypeFromExtension -path $IconPath
  # Use beta endpoint for largeIcon content upload (v1.0 may not support raw $value for all types)
  $url = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$AppId/largeIcon/`$value"
  try {
    [void](Invoke-Graph -Method 'PUT' -Path $url -BinaryBody $bytes -ContentType $ctype)
    return $true
  } catch {
    Write-Warn "Icon upload failed: $($_.Exception.Message)"
    return $false
  }
}

function Ensure-IntuneModuleConnected {
  if (-not (Get-Module -ListAvailable -Name 'IntuneWin32App')) {
    try { Install-Module IntuneWin32App -Scope CurrentUser -Force -ErrorAction Stop } catch { throw "IntuneWin32App module not available: $($_.Exception.Message)" }
  }
  Import-Module IntuneWin32App -ErrorAction Stop | Out-Null
  try {
    if ($TenantId -and $ClientId -and $ClientSecret) {
      Connect-MSIntuneGraph -TenantID $TenantId -ClientID $ClientId -ClientSecret (ConvertTo-Plain $ClientSecret) -ErrorAction SilentlyContinue | Out-Null
    } elseif ($TenantId -and $ClientId -and $CertificateThumbprint) {
      Connect-MSIntuneGraph -TenantID $TenantId -ClientID $ClientId -CertificateThumbprint $CertificateThumbprint -ErrorAction SilentlyContinue | Out-Null
    }
  } catch {}
}

function Find-Win32AppByNameModule {
  param([Parameter(Mandatory=$true)][string]$NameLike)
  Ensure-IntuneModuleConnected
  $term = ($NameLike | ForEach-Object { $_.ToString() }).Trim()
  if (-not $term) { return @() }
  $wild = "*$term*"
  try {
    $list = Get-IntuneWin32App -DisplayName $wild -ErrorAction Stop
  } catch {
    return @()
  }
  $out = @()
  foreach ($v in $list) {
    $pubVal = ''
    try { if ($v.PSObject.Properties.Name -contains 'publisher') { $pubVal = [string]$v.publisher } } catch {}
    $out += [pscustomobject]@{
      id          = [string]$v.id
      displayName = [string]$v.displayName
      publisher   = $pubVal
    }
  }
  return $out
}

function Find-Win32AppByName {
param([Parameter(Mandatory=$true)][string]$NameLike, [object]$ForceModule)
  # Consistent case-insensitive search: page all Win32 apps and filter client-side
  $term = ($NameLike | ForEach-Object { $_.ToString() }).Trim()
  if (-not $term) { return @() }
  if (Test-Switch $ForceModule) { return (Find-Win32AppByNameModule -NameLike $term) }

  $accum = @()
  try {
    $nextUrl = "/deviceAppManagement/mobileApps?`$filter=isof('microsoft.graph.win32LobApp')&`$top=200"
    do {
      $page = Invoke-Graph -Method 'GET' -Path $nextUrl
      $pageVals = @(); try { $pageVals = @($page.value) } catch {}
      if ($pageVals -and $pageVals.Count -gt 0) { $accum += $pageVals }
      $nextUrl = $null
      try { if ($page.'@odata.nextLink') { $nextUrl = [string]$page.'@odata.nextLink' } } catch {}
    } while ($nextUrl)
  } catch {
    $accum = @()
  }

  $vals = @()
  if ($accum -and $accum.Count -gt 0) {
    $re = [regex]::Escape($term)
    $vals = $accum | Where-Object {
      ($_.displayName -and ($_.displayName -imatch $re)) -or
      ($_.publisher   -and ($_.publisher   -imatch $re))
    }
  } else {
    $vals = @()
  }

  # If still no results or paging failed, try module wildcard search (case-insensitive)
  if (-not $vals -or $vals.Count -eq 0) {
    try { $vals = Find-Win32AppByNameModule -NameLike $term } catch {}
  }

  # Deterministic sort: exact match first, then starts-with, then contains; tie-break by DisplayName then Publisher
  try {
    if ($vals -and $vals.Count -gt 1) {
      $tl = $term.ToLowerInvariant()
      $vals = $vals | Sort-Object `
        @{ Expression = {
             $dn = ''; try { $dn = [string]$_.displayName } catch {}
             $dl = if ($dn) { $dn.ToLowerInvariant() } else { '' }
             if ($dl -eq $tl) { 0 }
             elseif ($dl.StartsWith($tl)) { 1 }
             else { 2 }
           } },
        @{ Expression = { [string]$_.displayName } },
        @{ Expression = { [string]$_.publisher } }
    }
  } catch {}

  # Map to basic objects
  $out = @()
  foreach ($v in $vals) {
    $out += [pscustomobject]@{
      Id          = [string]$v.id
      DisplayName = [string]$v.displayName
      Publisher   = [string]$v.publisher
    }
  }
  return $out
}

try {
  switch ($Action) {
    'CreateApp' {
      if (-not $DisplayName) { throw "DisplayName is required for CreateApp." }
      Write-Info "Creating Win32 placeholder app: $DisplayName"
      $appId = Create-Win32PlaceholderApp -DisplayName $DisplayName -Publisher $Publisher -Developer $Developer -Description $Description -InformationUrl $InformationUrl -PrivacyUrl $PrivacyUrl
      Write-Host "AppId: $appId"
      if ($IconPath) {
        Write-Info "Uploading icon: $IconPath"
        $ok = Set-AppLargeIcon -AppId $appId -IconPath $IconPath
        if ($ok) { Write-Info "Icon set successfully." } else { Write-Warn "Icon upload reported failure." }
      }
    }
    'FindApp' {
      if (-not $Name) { throw "Name is required for FindApp." }
      $useModuleBool = (Test-Switch $UseModule)
      if ($__wantJson) {
        $list = Find-Win32AppByName -NameLike $Name -ForceModule:$useModuleBool
        $list | ConvertTo-Json -Depth 5
      } else {
        Write-Info "Searching for Win32 apps containing: '$Name'"
        $list = Find-Win32AppByName -NameLike $Name -ForceModule:$useModuleBool
        if (-not $list -or $list.Count -eq 0) {
          Write-Host "AppId: " # blank
          Write-Warn "No apps found matching: $Name"
        } else {
          # print the top match and a compact list
          $top = $list | Select-Object -First 1
          Write-Host ("AppId: {0} Name: {1}" -f $top.Id, $top.DisplayName)
          if ($list.Count -gt 1) {
            Write-Info ("Other matches: " + (($list | Select-Object -Skip 1 | ForEach-Object { "{0} ({1})" -f $_.DisplayName, $_.Id }) -join '; '))
          }
        }
      }
    }
  }
  exit 0
} catch {
  Write-Err $_.Exception.Message
  exit 1
}
