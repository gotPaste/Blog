Intune AutoPackager v3 - README

Overview
This project streamlines packaging and updating Win32 apps in Microsoft Intune using winget metadata and recipe-driven automation.

Two ways to use:
1) Windows Forms GUI (recommended): Start-AutoPackagerGUI.ps1
2) Command line: AutoPackagerv2.ps1 with flags

This README provides a GUI quick start, CLI quick start, and a reference background process. The GUI Help tab loads this file.


Prerequisites
- Windows PowerShell 5.1
- Install intunewin32app, powershell-yaml, Microsoft.winget.client powershell modules
  - Example: From an administrative powershell prompt run: "install-module intunewin32app" and accept agreements
- Internet connectivity
- For FullRun (Intune upload/updates): 
  - Azure AD App Registration with DeviceManagementApps.ReadWrite.All, and credentials (Client Secret or Certificate thumbprint) via:
  - AZInfo.csv next to AutoPackager.ps1, or
  - AutoPackager.config.json (AzureAuth), or
  - CLI parameters to AutoPackager.ps1


GUI Quick Start

Launch the GUI
- Right-click Start-AutoPackagerGUI.ps1 and "Run with PowerShell"
- Or run from console:
  powershell.exe -ExecutionPolicy Bypass -File .\Start-AutoPackagerGUI.ps1

Tabs and Workflow

1) Winget
- Winget Search: Enter search criteria of the software you are looking for
- Winget ID: Enter the package ID (e.g., zoom.zoom).
- Locale: Defaults to "en-US".
- Architecture (x64/x86/arm64): Sets the appropriate download needed.
- Installer Type (msi/exe: Sets the appropriate download needed.
- Buttons:
  - Search Winget
    - Searches winget for the criteria entered in winget search and displays the output for selection.  
    - If only one winget package matched then it will auto select and fill in the Winget ID field.
  - Validate Winget ID
    - Executes: Find-WingetPackage -id <WingetID> -MatchOption Equals
    - Displays raw output and also parses plain text to extract:
  - Show Installer YAML
    - Displays raw output of the installer YAML so you can determine what Architecture and Installer Types are available.
  - Download Installer
    - Downloads the parsed InstallerUrl (if available) into:
      Testing\Publisher\Name\Version
    - Behavior:
      - Safe filename/path sanitation
      - TLS 1.2 where possible; sets a common User-Agent
      - Tries Invoke-WebRequest first; falls back to Start-BitsTransfer
      - Shows the destination and byte size on success

2) Intune App(s)
- Winget ID here is synchronized with Winget and Recipe tabs (editing in one updates the others).
- Create App(s)
  - Icon: Pick an image (png/jpg/jpeg) to use as the app icon (when supported by auth method).
  - Create Primary App
  - Create Required Update App
    - Both use CreateWin32AppFromTemplate.ps1 to create minimal placeholder Win32 apps, using DisplayName derived from winget (Name + optional Version) and Publisher when available. The Required Update app appends a display name suffix from AutoPackager.config.json:
      SecondaryRequiredApp.DisplayNameSuffix (preferred) or Secondary.DisplayNameSuffix (fallback).
    - The new AppId is detected from command output and written into:
      - Recipe tab (Primary IntuneAppId or SecondaryAppId), and
      - Intune App(s) tab (read-only fields).
- AppId(s)
  - Read-only Primary AppId and Required Update AppId fields reflect results from Create/Find actions.
  - Reset AppId(s) clears those fields and the related fields on the Recipe tab.
- Select Existing App(s)
  - Search Name auto-populates with the vendor segment (e.g., "jabra.direct" -> "jabra") when empty; user edits are preserved.
  - Find Primary App / Find Required Update App:
    - Searches existing Win32 apps by display name contains.
    - On multiple matches, a pick-list is presented.
    - Selected AppId is written to both this tab and the Recipe tab.
- Output window shows echoed commands and results.

3) Recipe
- Create / Select
  - Winget ID (synced across tabs)
  - Create New Recipe: runs New-RecipeFromWinget.ps1 to generate a starter recipe file under .\Recipes.
  - Browse Recipe ... , Open in Notepad, Open recipe folder
- Select Existing App(s)
  - Search Name and Find buttons behave exactly like the Intune App(s) tab. When invoked here, the GUI switches to the Intune App(s) tab to show output/selection, then automatically returns.
- Quick Edit (IDs and Args)
  - Primary AppId (IntuneAppId), Required Update AppId (SecondaryAppId)
    - Note: The GUI does not enforce GUID format; it writes values as provided.
  - Installer Scope: Writes InstallerPreferences.Scope in the recipe ("", "machine", or "user"). Leave blank to honor defaults/CLI fallback.
  - Architecture: Writes to recipe. (used for application download selection)
  - Installer Type: Writes to recipe. (used for application download selection)
  - InstallArgs / UninstallArgs
  - ForceUninstall (boolean)
  - ForceTaskClose (multiline; one process name per line; .exe extension is optional)
  - Notification Popup
    - Enabled
    - Timer (minutes)
    - Allow deferral
    - Deferral hours (see CLI notes for how deferral horizon is computed at runtime)
  - Required Update Deployment Rings
    - Pilot Group + Deadline (days)
    - UAT Group + Deadline (days)
    - GA Group + Deadline (days)
    - Load Default Groups: reads RequiredUpdateDefaultGroups from AutoPackager.config.json
  - Save Recipe Update(s) 
    - Apply writes the current Quick Edit values back into the JSON (ConvertTo-Json -Depth 15).

4) Run
- Mode
  - Package Only (Testing Output)
  - Full Run (Update Intune)
  - Optional: No Azure Authentication (adds -NoAuth to backend)
- Target
  - Select Recipe File ...  (single .json file)
- Run AutoPackager
  - Safely builds and executes AutoPackager.ps1 with the selected options.
  - Output window shows stdout/stderr and a tail of AutoPackager.log when present.
- Notes
  - GUI Run tab targets one recipe file at a time. To process all recipes or run DryRun, use the CLI (see below) or set defaults in AutoPackager.config.json.

5) Reset
- Primary AppId Reset / Required Update AppId Reset
  - Uses IntuneApplicationResetAll.ps1 with -AppId when available.
  - If an AppId is provided, the GUI attempts to run in-process and capture output; otherwise an external PowerShell window may open for prompts (especially for the secondary button when no AppId is provided).

6) Logs
- Refresh Log: Tails AutoPackager.log (up to 500 lines)
- Open Working Folder
- Open Latest Summary CSV (Working\Summary_*.csv)

7) Config
- Open AutoPackager.config.json
- Open readme.txt (this file)
- Open SystemConfigReadMe.txt

8) Prerequisite Check
- Run Prerequisite Check

9) Help
- Loads the content of readme.txt into the window.


Config-driven defaults (GUI)
On GUI startup, when AutoPackager.config.json is present the GUI reads and applies:
- Run Mode default (PackagingDefaults.RunMode: PackageOnly or FullRun)
- Winget defaults (PackagingDefaults.WingetSource, PackagingDefaults.DefaultScope)
- Preferred architecture (PackagingDefaults.PreferArchitecture: x64/x86/arm64) for Winget parsing
- Notification defaults (Notification.Defaults: Enabled, TimerMinutes, DeferralEnabled, DeferralHoursAllowed)
- Default Required Update ring group names (RequiredUpdateDefaultGroups) via "Load Default Groups"
Note: Verification flags (SkipVerify, StrictVerify) are honored by the backend if configured, but they are not exposed as GUI toggles.


Command Line Quick Start

From the AutoPackager root folder:

Common patterns
- Package only, single recipe (default mode without -FullRun):
  powershell.exe -ExecutionPolicy Bypass -File .\AutoPackager.ps1 -PathRecipes ".\Recipes\your.app.json"

- Full run, all recipes in default Recipes folder:
  powershell.exe -ExecutionPolicy Bypass -File .\AutoPackager.ps1 -FullRun -AllRecipes

- Full run, one specific recipe:
  powershell.exe -ExecutionPolicy Bypass -File .\AutoPackager.ps1 -FullRun -PathRecipes ".\Recipes\your.app.json"

- Package-only without Intune authentication (skip connection):
  powershell.exe -ExecutionPolicy Bypass -File .\AutoPackager.ps1 -PackageOnly -PathRecipes ".\Recipes\your.app.json" -NoAuth

- Dry Run (no download/wrap/upload; compares Intune vs winget):
  powershell.exe -ExecutionPolicy Bypass -File .\AutoPackager.ps1 -DryRun

Credential sourcing
- AZInfo.csv (optional) next to AutoPackager.ps1:
  TenantId,ClientId,ClientSecret,CertificateThumbprint
  Non-empty values override CLI params; ClientSecret takes precedence over CertificateThumbprint.
- Or configure AutoPackager.config.json (AzureAuth), or pass CLI parameters directly.

Useful options
- -PreferArchitecture x64|x86|arm64
- -DefaultScope machine|user
  Note: Recipe InstallerPreferences.Scope (if set) is honored first; -DefaultScope applies when recipe scope is blank.
- -NoAuth (skip Intune connection for packaging/troubleshooting)
- -SkipVerify / -StrictVerify (control post-upload verification)
- -UpdateDetection / -NoUpdateDetection
- -NoUpdateCmds (skip install/uninstall command updates)

Logs and Outputs
- AutoPackager.log in the root (rotated/archived to Working\AutoPackager_yyyyMMdd_HHmmss.log)
- Working\Publisher\Name\Version\Download for downloaded installers (+ generated install/uninstall scripts are copied here)
- Working\Publisher\Name\Version\Scripts for generated scripts
- Working\Publisher\Name\Version\Output\Package\*.intunewin
- Working\Summary_*.csv for run summaries


Background Process (Reference)

1.0
Identify and verify winget package
- Use https://winget.run to find the Winget ID (e.g., zoom.zoom).
- Run: winget show --id <WingetID> to review metadata and installer URL(s).
- Ensure you will target a machine-scope installer when appropriate (the backend prefers machine scope when available).

2.0
Test Install and Uninstall
- Test run the installer to gather and document the install silent switches for the recipe file
- Test run the Uninstaller to gather and document the uninstall silent switches for the recipe file
  Uninstall command lines can generally be found in the registry under 
    HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\
    HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\

3.0
Create Primary and Required Update placeholder apps
- Option A (portal): Create two Win32 apps manually and record their AppId GUIDs.
- Option B (recommended): Use the GUI Intune App(s) tab "Create Primary App" and "Create Required Update App" buttons, optionally providing an icon. The GUI will write the new AppIds into the Recipe Quick Edit fields.

4.0
Create recipe
- From GUI: Recipe tab -> "Create New Recipe" from a Winget ID.
- Or from console: run New-RecipeFromWinget.ps1 (prompted or -wingetid parameter).
- The file is created in .\Recipes and can be edited in the GUI Quick Edit or a text editor.

5.0
Edit recipe
Required fields to validate/fill for production:
- IntuneAppId: Primary app GUID (if you intend FullRun)
- SecondaryAppId: Required Update app GUID (if you intend FullRun with secondary)
- InstallerPreferences.Scope: If you must force machine/user to resolve the correct installer
- InstallArgs / UninstallArgs: Silent switches, restart behavior, etc.
- ForceTaskClose: One process name per line that must be closed before install/upgrade/uninstall
Optional fields:
- ForceUninstall: Uninstall previous version before installing
- NotificationPopup:
  - Enabled
  - NotificationTimerInMinutes (default 2)
  - DeferralEnabled (default true)
  - DeferralHoursAllowed (default 24)
- Rings (for the Required Update app):
  - Ring1/2/3: Group (display name) and DeadlineDelayDays (int)

6.0
Test PackageOnly and Recipe output files
- GUI: Run tab -> Package Only -> select one recipe -> Run AutoPackager
- CLI:
  powershell.exe -ExecutionPolicy Bypass -File .\AutoPackager.ps1 -PackageOnly -PathRecipes ".\Recipes\your.app.json"
- Test run and validate successful Install/Uninstall/Detection/Requirement Scripts using PowerShell on a test machine
--- Install/Uninstall scripts located in the directory <AutoPackager V3\Working\Publisher\Name\Version\Download>
--- Detection/Requirement Scripts are located in the directory <AutoPackager V3\Working\Publisher\Name\Version\Scripts>

7.0
Verify Full Run and Test Intune Deployment
- GUI: Run tab -> Full Run -> select the recipe file -> Run AutoPackager
- CLI:
  powershell.exe -ExecutionPolicy Bypass -File .\AutoPackager.ps1 -FullRun -PathRecipes ".\Recipes\your.app.json"
- Verify the Intune App Metadata and Detection Scripts are properly set on primary application
- Verify the Intune App Metadata, Detection Script, and Requirement Script are properly set on secondary required application
- Advertise Primary App to a test group and validate Intune Application Deployment
- Advertise Secondary Required App to a test group and validate Intune Application Deployment

8.0
Reset placeholder apps (if needed for re-testing)
- Use the GUI Reset tab or run:
  .\IntuneApplicationResetAll.ps1 -AppId <GUID>

9.0
Production updates
- Update the recipe (InstallArgs, ForceTaskClose, NotificationPopup, Rings, etc.)
- Full Run with appropriate assignments/groups and deadlines for the Required Update app
- Confirm deployments and behavior through Intune for both Primary and Required Update Apps

10.0
Re-run reset (optional)
- If you need to re-stage for more testing, reset the apps again with:
  .\IntuneApplicationResetAll.ps1 -AppId <GUID>


Appendix: Recipe fields (overview)
- WingetId: Required (e.g., "zoom.zoom")
- IntuneAppId: Primary Win32 app GUID
- SecondaryAppId: Required Update Win32 app GUID (or Secondary.IntuneAppId/AppId/Id)
- InstallerPreferences:
  - Scope: "machine" | "user" | "" (blank for default behavior)
  - Architecture: "x64" | "x86" | "arm64" (optional)
- InstallArgs / UninstallArgs: Silent switches for vendor installer/uninstaller
- ForceUninstall: boolean
- ForceTaskClose: array or multiline string of process names to close
- NotificationPopup:
  - Enabled: boolean
  - NotificationTimerInMinutes: int
  - DeferralEnabled: boolean
  - DeferralHoursAllowed: int
- Rings:
  - Ring1/2/3: { Group: "display name of Entra group", DeadlineDelayDays: int }


Notes and alignment with the current code
- Winget parsing in the GUI uses plain-text parsing; scope in the Winget tab is a selection preference and not added to the winget command there. The backend (CLI) uses JSON where available and falls back to text, adding/removing --scope as needed for compatibility.
- GUI Run tab supports PackageOnly and FullRun for a single selected recipe; use the CLI if you want -AllRecipes or -DryRun from the console.
- Reset actions use IntuneApplicationResetAll.ps1 with -AppId. The GUI attempts inline execution when GUIDs are provided and falls back to an external PowerShell window if needed.
- Quick Edit does not enforce GUID format; it writes values exactly as provided.
- The GUI reads defaults from AutoPackager.config.json for run mode, winget preferences, and notification behavior.
