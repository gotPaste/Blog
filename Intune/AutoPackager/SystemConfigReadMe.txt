Intune AutoPackager System Configuration Reference
Location: AutoPackager.config.json (same folder as the script)
All keys are optional unless marked Required. When a key is missing, the script applies a safe default or built-in behavior. Paths may be absolute or relative to the script directory unless stated otherwise.

1) Paths
- WorkingRoot (string)
  Purpose: Root folder where working artifacts are produced (publisher/app/version, scripts, outputs, CSVs, archives of previous logs).
  Default: "Working"
  Examples:
    - "Working"
    - "D:\\Intune\\AutoPackager\\Working"
- LogPath (string)
  Purpose: Main runtime log file path. On each run, the active log is rotated into the Working folder with a timestamp.
  Default: "AutoPackager.log"
  Examples:
    - "AutoPackager.log"
    - ".\\Logs\\AutoPackager.log"
- RecipesRoot (string)
  Purpose: Folder where application recipe JSON files are stored. Used when -PathRecipes is omitted to locate recipes and optionally prompt for selection.
  Default: "Recipes"
- IntuneWinAppUtil (string | null)
  Purpose: Optional path to IntuneWinAppUtil.exe. If null/omitted, the script looks next to itself and then on PATH.
  Examples:
    - "IntuneWinAppUtil.exe" (next to script)
    - "C:\\Tools\\IntuneWinAppUtil.exe"
    - null (let the script auto-resolve)

2) Branding
- NotificationBrandTitle (string)
  Purpose: Prefix shown in user notification pop-ups during install (e.g., "OPENLANE IT - AppName").
  Default: "OPENLANE IT"

3) Email
- Enabled (bool) [optional]
  Purpose: Master enable switch for summary email sending.
  Default: true (if omitted)
- To (string[]), From (string)
  Purpose: Recipient list and sender address for summary email.
  Required: To and From must be present to send mail.
- SubjectPrefix (string)
  Purpose: Subject prefix for summary emails.
  Default: "Intune AutoPackager"
- AttachCsv (bool)
  Purpose: Attach Summary_*.csv generated in the Working folder.
  Default: false
- AttachLog (bool)
  Purpose: Attach the run log (copied to Working first) when failures are present.
  Default: true
- SendPolicy (string)
  Purpose: Controls when to send email.
  Allowed: "always" | "updatesOrFailures" | "failuresOnly" | "never"
  Default: "updatesOrFailures"
  Behavior:
    - always: Send after every run (if To/From/Smtp present)
    - updatesOrFailures: Send only if at least one app was updated or a failure occurred
    - failuresOnly: Send only if failures occurred
    - never: Do not send email
- Smtp (object)
  - Server (string) [Required to send]
  - Port (int) [Required to send]
  - UseSsl (bool) [Required to send]
  - User (string) [Optional; typical for SendGrid is "apikey"]
  - ApiKeyEnv (string) [Optional; e.g., "SENDGRID_API_KEY"]
  - ApiKey (string) [Optional; plaintext API key. Preferred over Password when both set]
  - Password (string) [Optional; plaintext SMTP password]
    Secret sourcing precedence:
      1) Email.Smtp.ApiKey (if set) else Email.Smtp.Password
      2) Environment variable named by Email.Smtp.ApiKeyEnv
      3) Environment variable SENDGRID_API_KEY
    Security note: Storing secrets in JSON is plaintext. Prefer environment variables or a secret store in production. Example for SendGrid:
      User: "apikey"
      Env var: SENDGRID_API_KEY=<your key>

4) AzureAuth 
- Purpose: Provide app-only authentication parameters for Intune Graph connections via config.
- Fields:
  - TenantId (string)
  - ClientId (string)
  - ClientSecret (string; plaintext in config; converted to SecureString at runtime)
  - CertificateThumbprint (string; for certificate-based auth from local cert store)
- Precedence with other sources: CLI parameters > Config.AzureAuth > AZInfo.csv
- Auth mode: Provide either ClientSecret or CertificateThumbprint. If both are present, ClientSecret is used.
- Security note: Avoid storing secrets in plaintext when possible. Prefer certificate auth or environment-based secret injection.
- Icon upload: The GUI’s IntuneAppTools helper only supports large icon upload when authenticated with a ClientSecret (app-only token). When using certificate-only/module session, icon upload is not performed and a warning is printed.
- Supported icon types for upload: .png, .jpg, .jpeg

5) GitHubToken
- Purpose: Remove api restriction when querying GitHub repository
- Fields:
  - GitHubToken (string)

6) PackagingDefaults
- PreferArchitecture (string)
  Purpose: Preferred installer architecture when multiple are available.
  Allowed: "x64" | "x86" | "arm64"
  Default: "x64"
- DefaultScope (string)
  Purpose: Default winget scope used for metadata queries if recipe does not specify.
  Allowed: "machine" | "user"
  Default: "machine"
- WingetSource (string)
  Purpose: Winget source name for queries.
  Default: "winget"
  Examples: "winget", "msstore"
- RunMode (string)
  Purpose: Default run mode when neither -FullRun nor -PackageOnly is specified on the CLI.
  Allowed: "FullRun" | "PackageOnly"
  Default: "PackageOnly"
- AllRecipes (bool)
  Purpose: When FullRun + no PathRecipes is provided, process all recipes in RecipesRoot instead of prompting for one.
  Default: false
- UpdateDetection (bool)
  Purpose: Default behavior for updating the detection script/rule. When false, behaves as if -NoUpdateDetection was set.
  Default: true
- UseScriptCommandLines (bool)
  Purpose: If true, install/uninstall command lines uploaded to Intune are set to run the generated "install.ps1" and "uninstall.ps1" (preferred). If false, vendor command lines are used instead.
  Default: true

7) IntuneUploadVerify
Controls the post-upload verification logic (module-based size/committedContentVersion comparison).
- TimeoutSeconds (int)
  Purpose: Max time to wait for Intune to reflect the new content update.
  Default: 600
- IntervalSeconds (int)
  Purpose: Poll interval during verification.
  Default: 10
- SkipVerify (bool)
  Purpose: If true, skip verification step.
  Default: false
- StrictVerify (bool)
  Purpose: If true, fail the run when verification does not converge.
  Default: false
- SizeTolerancePercent (int)
  Purpose: Accept difference tolerance between module-reported size and local .intunewin size when verifying.
  Default: 5

8) Notification
Defaults used when generating the install.ps1 that runs on endpoints. The popup appears only if:
- Notification.Defaults.Enabled is true (or recipe overrides enable), AND
- There are processes to close (from the recipe ForceTaskClose list) that are currently running.
- Notification popups honor a deferral window, computed from the script generation timestamp in install.ps1.

- Defaults.Enabled (bool)
  Purpose: Enable/disable user notification popups by default (recipe can override).
  Default: false
- Defaults.TimerMinutes (int)
  Purpose: How long the popup waits before auto-continue (in minutes).
  Default: 2
- Defaults.DeferralEnabled (bool)
  Purpose: Allow users to defer within a time window. (Computed at runtime inside install.ps1)
  Default: false
- Defaults.DeferralHoursAllowed (int)
  Purpose: Hours until deferral expires. When expired, popup informs user that installation must occur.
  Default: 24

9) SecondaryRequiredApp
Settings for a secondary app scenario (e.g., "Required Updates" ring).
Note: The script also supports an alternate top-level "Secondary" object with matching structure; if both are present, "SecondaryRequiredApp" takes precedence.

- DisplayNameSuffix (string)
  Purpose: Suffix appended to the secondary app display name on publish (e.g., " - Required Update").
  Default: " - Required Update"
- AssignmentDefaults (object)
  - Intent (string)
    Purpose: Assignment intent used for ring assignments.
    Allowed: "required" (typical)
    Default: "required"
  - Notifications (string)
    Purpose: User notifications policy for Win32 LOB app.
    Common: "showAll", "showReboot", "hideAll" (values passed through to Graph)
    Default: "showAll"
  - DeliveryOptimizationPriority (string)
    Purpose: DO priority for assignments.
    Common: "notConfigured", "foreground", "foregroundPriority"
    Default: "notConfigured"
  - ClearExistingBeforeAssign (bool)
    Purpose: When true, existing assignments are cleared before creating new ring assignments.
    Default: true
  - Deadline (object)
    Purpose: Local deadline time for each ring (date computed as Now + ring delay days + time-of-day below).
    Fields:
      - HourOfDay (int, 0-23)
      - MinuteOfHour (int, 0-59)
    Default: 23:59 local

10) Archive
Controls end-of-run archival and retention.
- Enabled (bool)
  Purpose: Enable archive-to-network step. When disabled, archival is skipped.
  Default: true
- NetworkArchiveRoot (string)
  Purpose: Destination root path (UNC/local) for copying Working subfolders at the end of the run.
  Example: "\\\\server\\share\\AutoPackagerArchive"
- RetentionDays (int)
  Purpose: Retention window for cleaning older Summary_*.csv, AutoPackager_*.log in Working and IntuneWinAppUtil logs under Working (stdout/stderr).
  Default: 14
- KeepVersionsPerApp (int)
  Purpose: At the archive root, keep only N newest version folders per app touched this run (older versions are removed).
  Default: 3

11) Cleanup
- PurgeWorkingOnStart (bool)
  Purpose: On start, delete all subfolders inside WorkingRoot to ensure a clean environment (root is kept so logs/CSV can be written).
  Default: true
  Caution: This removes old working folders before the run begins; ensure important artifacts are archived externally.

Additional Input Sources (outside JSON)
- AZInfo.csv (optional file next to the script)
  Purpose: Supplies TenantId, ClientId, ClientSecret, CertificateThumbprint (first row only; headers are case-insensitive). Precedence with other sources: CLI parameters > Config.AzureAuth > AZInfo.csv. If both ClientSecret and CertificateThumbprint are present, ClientSecret is used.
  Sample (ClientSecret):
    TenantId,ClientId,ClientSecret,CertificateThumbprint
    00000000-0000-0000-0000-000000000000,11111111-1111-1111-1111-111111111111,"<client-secret>",
  Sample (Certificate):
    TenantId,ClientId,ClientSecret,CertificateThumbprint
    00000000-0000-0000-0000-000000000000,11111111-1111-1111-1111-111111111111,,ABCDEF1234567890ABCDEF1234567890ABCDEF12

- Environment Variables
  SENDGRID_API_KEY (or custom via Email.Smtp.ApiKeyEnv)
  Purpose: Supplies the SMTP API key; never stored in the JSON. The script converts it to a SecureString and uses it for authenticated SMTP.

Behavior Notes
- Default Run Modes:
  - PackageOnly (no -FullRun and no -PackageOnly) is the default: packages one selected recipe; prompts to select a recipe when none specified; wraps into .intunewin; does not upload to Intune.
  - FullRun: downloads, wraps, uploads content, and updates metadata; can process all recipes via AllRecipes=true or single selection.
  - DryRun: only compares Winget vs Intune versions; no download/wrap/upload.
- Command Lines:
  - UseScriptCommandLines=true sets Intune install/uninstall to:
      powershell.exe -ExecutionPolicy Bypass -File "install.ps1"
      powershell.exe -ExecutionPolicy Bypass -File "uninstall.ps1"
    If false, vendor-provided commands are used.
- Detection:
  - UpdateDetection true triggers generation and update of a multi-source detection script. For MSI, ProductCode is read from the MSI file where possible.
- Verification:
  - Module-based size/version verification attempts to ensure Intune reflects the new content; tolerance is configurable; strict mode can fail the run if not converged.

Quick Defaults Summary (if omitted):
- Paths: WorkingRoot="Working", LogPath="AutoPackager.log", RecipesRoot="Recipes"
- Branding.NotificationBrandTitle="OPENLANE IT"
- Email: Enabled=true; SendPolicy="updatesOrFailures"; AttachCsv=false; AttachLog=true; Smtp required to send
- PackagingDefaults: PreferArchitecture="x64"; DefaultScope="machine"; WingetSource="winget"; RunMode="PackageOnly"; AllRecipes=false; UpdateDetection=true; UseScriptCommandLines=true
- IntuneUploadVerify: TimeoutSeconds=600; IntervalSeconds=10; SkipVerify=false; StrictVerify=false; SizeTolerancePercent=5
- Notification.Defaults: Enabled=false; TimerMinutes=2; DeferralEnabled=false; DeferralHoursAllowed=24
- SecondaryRequiredApp: DisplayNameSuffix=" - Required Update"; ClearExistingBeforeAssign=true; Deadline=23:59 local
- Archive: Enabled=true; RetentionDays=14; KeepVersionsPerApp=3
- Cleanup.PurgeWorkingOnStart=true
