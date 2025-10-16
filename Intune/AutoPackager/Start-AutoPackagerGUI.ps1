#requires -Version 5.1
<#
Launcher for the Intune AutoPackager Windows Forms GUI.
- Ensures Windows PowerShell (powershell.exe) is used
- Uses STA, NoProfile, and ExecutionPolicy Bypass
- Starts in this folder so relative paths work (Recipes, config, etc.)

Usage:
  - Right-click this file and Run with PowerShell
  - Or run from a console: powershell -ExecutionPolicy Bypass -File .\Start-AutoPackagerGUI.ps1
#>

# Resolve this script's directory
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot -or [string]::IsNullOrWhiteSpace($ScriptRoot)) {
  if ($PSCommandPath) { $ScriptRoot = Split-Path -Parent $PSCommandPath }
  elseif ($MyInvocation.MyCommand.Path) { $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
  else { $ScriptRoot = (Get-Location).Path }
}

$guiPath = Join-Path $ScriptRoot 'AutoPackager.GUI.ps1'
if (-not (Test-Path -LiteralPath $guiPath)) {
  Write-Host "AutoPackager.GUI.ps1 not found at: $guiPath" -ForegroundColor Red
  exit 1
}

# Build argument list for Windows PowerShell
$argList = @(
  '-NoProfile',
  '-ExecutionPolicy','Bypass',
  '-STA',
  '-File', ('"{0}"' -f $guiPath)
)

try {
  Write-Host "Launching GUI..." -ForegroundColor Cyan
  Write-Host ("  powershell.exe {0}" -f ($argList -join ' ')) -ForegroundColor DarkGray
  $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WorkingDirectory $ScriptRoot -PassThru
  if ($proc) {
    Write-Host ("Started PID: {0}" -f $proc.Id) -ForegroundColor DarkGray
  }
} catch {
  Write-Host ("Failed to launch GUI: {0}" -f $_.Exception.Message) -ForegroundColor Red
  exit 1
}
