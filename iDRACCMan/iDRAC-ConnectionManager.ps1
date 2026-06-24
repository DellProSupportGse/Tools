<#
.SYNOPSIS
    RDCMan-style connection manager for Dell iDRAC systems.

.DESCRIPTION
    iDRACCMan provides a PowerShell Windows Forms interface for managing Dell iDRAC
    GUI and console sessions from a grouped server tree.

    Features:
    - Embedded iDRAC GUI tabs using Microsoft Edge WebView2.
    - Embedded iDRAC console sessions using Dell Redfish GetKVMSession.
    - Multi View for viewing and controlling multiple console sessions at the same time.
    - Group-level credentials with server-level override.
    - DPAPI-encrypted passwords stored under Documents\iDRACCMan.
    - Redfish power actions.
    - CSV import/export.
    - Local settings and logging.

.NOTES
    Name: iDRACCMan
    Created By: Jim Gandy

    One-liner usage:
    $browser = New-Object System.Net.WebClient;$browser.Proxy.Credentials =[System.Net.CredentialCache]::DefaultNetworkCredentials;Echo iDRACCMan;[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="iDRACCMan";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('http'+'s://raw.githubusercontent.com/DellProSupportGse/Tools/main/iDRAC-ConnectionManager.ps1'));Invoke-iDRACCMan

    Direct usage:
    powershell.exe -STA -ExecutionPolicy Bypass -File .\iDRAC-ConnectionManager.ps1
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# WinForms DPI/font clipping fix
try {
    [System.Windows.Forms.Application]::EnableVisualStyles()
    [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
    if ([System.Windows.Forms.Application].GetMethod("SetHighDpiMode")) {
        [void][System.Windows.Forms.Application]::SetHighDpiMode([System.Windows.Forms.HighDpiMode]::SystemAware)
    }
}
catch {}

$script:UiFont        = New-Object System.Drawing.Font("Segoe UI", 9)
$script:UiFontSmall   = New-Object System.Drawing.Font("Segoe UI", 8)
$script:UiFontBold    = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$script:UiFontTitle   = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Regular)
$script:UiFontMetric  = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
Add-Type -AssemblyName System.Security

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:AppName      = "iDRAC Connection Manager"
$script:AppVersion   = "1.0.57"

# Telemetry run-once guard
$script:TelemetryStartupSent = $false
$script:TelemetryGeoResolved = $false
$script:HelpUrl      = "https://github.com/DellProSupportGse/Tools/blob/main/iDRACCMan/help.md"
$script:DocumentsRoot = [Environment]::GetFolderPath("MyDocuments")
$script:AppRoot      = Join-Path $script:DocumentsRoot "iDRACCMan"
$script:LibRoot      = Join-Path $script:AppRoot "lib"
$script:DataFile     = Join-Path $script:AppRoot "servers.json"
$script:GroupCredFile = Join-Path $script:AppRoot "groupCredentials.json"
$script:WebDataRoot  = Join-Path $script:AppRoot "WebView2UserData"
$script:SettingsFile = Join-Path $script:AppRoot "Settings.json"
$script:LogRoot      = Join-Path $script:AppRoot "Logs"
$script:NugetVersion = "1.0.2903.40"

$script:Servers      = @()
$script:GroupCredentials = @()
$script:MainForm     = $null
$script:Tree         = $null
$script:Tabs         = $null
$script:Status       = $null
$script:WebViewReady = $false
$script:WebViewEnvironment = $null
$script:AppFont = [System.Drawing.SystemFonts]::MessageBoxFont
$script:KvmSessions = @{}

New-Item -ItemType Directory -Path $script:AppRoot,$script:LibRoot,$script:WebDataRoot,$script:LogRoot -Force | Out-Null

function Write-iDRACCManLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    try {
        $logFile = Join-Path $script:LogRoot ("iDRACCMan_{0}.log" -f (Get-Date -Format "yyyyMMdd"))
        $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
        Add-Content -Path $logFile -Value $line -Encoding UTF8
    }
    catch {}
}

function Initialize-iDRACCManSettings {
    if (-not (Test-Path $script:SettingsFile)) {
        [pscustomobject]@{
            Version = $script:AppVersion
            StoragePath = $script:AppRoot
            AutoResizeSideMenu = $true
            DefaultDoubleClickAction = "Console"
            MultiViewEnabled = $true
            AutoContinueConsole = $true
            AutoContinueGui = $true
            AutoLoginGui = $true
            TelemetryEnabled = $true
            ConnectionsCollapsed = $false
            ConnectionsWidth = 260
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $script:SettingsFile -Encoding UTF8
    }
    else {
        try {
            $settings = Get-Content $script:SettingsFile -Raw | ConvertFrom-Json
            $changed = $false

            if (-not ($settings.PSObject.Properties.Name -contains "AutoContinueConsole")) {
                $settings | Add-Member -NotePropertyName AutoContinueConsole -NotePropertyValue $true -Force
                $changed = $true
            }

            if (-not ($settings.PSObject.Properties.Name -contains "AutoContinueGui")) {
                $settings | Add-Member -NotePropertyName AutoContinueGui -NotePropertyValue $true -Force
                $changed = $true
            }

            if (-not ($settings.PSObject.Properties.Name -contains "AutoLoginGui")) {
                $settings | Add-Member -NotePropertyName AutoLoginGui -NotePropertyValue $true -Force
                $changed = $true
            }

            if (-not ($settings.PSObject.Properties.Name -contains "TelemetryEnabled")) {
                $settings | Add-Member -NotePropertyName TelemetryEnabled -NotePropertyValue $true -Force
                $changed = $true
            }

            if (-not ($settings.PSObject.Properties.Name -contains "ConnectionsCollapsed")) {
                $settings | Add-Member -NotePropertyName ConnectionsCollapsed -NotePropertyValue $false -Force
                $changed = $true
            }

            if (-not ($settings.PSObject.Properties.Name -contains "ConnectionsWidth")) {
                $settings | Add-Member -NotePropertyName ConnectionsWidth -NotePropertyValue 260 -Force
                $changed = $true
            }

            if (-not ($settings.PSObject.Properties.Name -contains "Version")) {
                $settings | Add-Member -NotePropertyName Version -NotePropertyValue $script:AppVersion -Force
                $changed = $true
            }
            else {
                $settings.Version = $script:AppVersion
                $changed = $true
            }

            if ($changed) {
                $settings | ConvertTo-Json -Depth 5 | Set-Content -Path $script:SettingsFile -Encoding UTF8
            }
        }
        catch {}
    }
}

function Get-iDRACCManSetting {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        $Default = $null
    )

    try {
        if (-not (Test-Path $script:SettingsFile)) {
            Initialize-iDRACCManSettings
        }

        $settings = Get-Content $script:SettingsFile -Raw | ConvertFrom-Json
        $prop = $settings.PSObject.Properties[$Name]
        if ($prop) { return $prop.Value }
    }
    catch {}

    return $Default
}

function Set-iDRACCManSetting {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$Value
    )

    try {
        if (-not (Test-Path $script:SettingsFile)) {
            Initialize-iDRACCManSettings
        }

        $settings = Get-Content $script:SettingsFile -Raw | ConvertFrom-Json
        if (-not $settings) { $settings = [pscustomobject]@{} }

        if ($settings.PSObject.Properties.Name -contains $Name) {
            $settings.$Name = $Value
        }
        else {
            $settings | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
        }

        $settings | ConvertTo-Json -Depth 5 | Set-Content -Path $script:SettingsFile -Encoding UTF8
    }
    catch {
        Write-iDRACCManLog "Failed to save setting $Name. $($_.Exception.Message)" "WARN"
    }
}

# =====================================================
#region Telemetry Information
# =====================================================

$script:TelemetryReportID    = [guid]::NewGuid().Guid
$script:TelemetryGeoResolved = $false
$script:TelemetryGeoData     = @{}
$script:TelemetryStartupSent = $false
$script:uploadToAzure        = $true

function Write-Indent {
    param(
        [string]$Message,
        [int]$Level = 1,
        [string]$Color = "Gray"
    )

    try {
        $prefix = "  " * $Level
        Write-Host "$prefix$Message" -ForegroundColor $Color
    }
    catch {}
}

function Get-TelemetryMachineHash {
    try {
        $raw = "$env:USERDOMAIN\$env:USERNAME@$env:COMPUTERNAME"
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash)).Replace("-","").Substring(0,24)
    }
    catch {
        return ""
    }
}

function Resolve-TelemetryGeo {
    try {
        if ($script:TelemetryGeoResolved) { return }

        Write-Indent "Resolving Geo Location..."

        if (-not $global:GeoCache) {
            $global:GeoCache = Invoke-RestMethod "https://ipwho.is/" -TimeoutSec 5
        }

        $response = $global:GeoCache

        if ($response.success -eq $true) {
            $script:TelemetryGeoData = @{
                country     = [string]$response.country
                countryCode = [string]$response.country_code
                region      = [string]$response.region
                city        = [string]$response.city
                latitude    = [string]$response.latitude
                longitude   = [string]$response.longitude
                timezone    = [string]$response.timezone.id
            }

            Write-Indent "Country: $($script:TelemetryGeoData.country)" 2
            Write-Indent "Region : $($script:TelemetryGeoData.region)" 2
        }
    }
    catch {
        Write-Indent "WARN: ipwho lookup failed" 2 Yellow
        $script:TelemetryGeoData = @{}
    }
    finally {
        $script:TelemetryGeoResolved = $true
    }
}

function Send-ToolTelemetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TelemetryName,

        [Parameter(Mandatory=$true)]
        [string]$EventName,

        [Parameter(Mandatory=$true)]
        [string]$Version,

        [Parameter(Mandatory=$true)]
        [string]$Endpoint,

        [int]$ServerCount = 0,

        [int]$GroupCount = 0,

        [switch]$NoGeo,

        [switch]$DebugTelemetry
    )

    if (-not $script:uploadToAzure) { return }

    if ($EventName -match '^(Startup|Launch|AppStart|ToolStart|TelemetryStartup)$') {
        if ($script:TelemetryStartupSent) { return }
        $script:TelemetryStartupSent = $true
    }

    try {
        if (-not $NoGeo) {
            Resolve-TelemetryGeo
        }

        $rowKey = [guid]::NewGuid().Guid
        $partitionKey = $TelemetryName -replace 'TelemetryData$',''

        # ONLY requested table columns are placed in Data.
        $data = [ordered]@{
            PartitionKey = $partitionKey
            RowKey       = $rowKey
            PSVersion    = $PSVersionTable.PSVersion.ToString()
            Region       = $script:TelemetryGeoData.region
            countryCode  = $script:TelemetryGeoData.countryCode
            lon          = $script:TelemetryGeoData.longitude
            MachineHash  = Get-TelemetryMachineHash
            geoRegion    = $script:TelemetryGeoData.region
            lat          = $script:TelemetryGeoData.latitude
            Version      = $Version
            timezone     = $script:TelemetryGeoData.timezone
            ReportID     = $script:TelemetryReportID
            city         = $script:TelemetryGeoData.city
            country      = $script:TelemetryGeoData.country
        }

        # Envelope for the Function only. The Function should write Data only.
        $payload = @{
            TelemetryName = $TelemetryName
            TableName     = $TelemetryName
            Data          = $data
        }

        $body = $payload | ConvertTo-Json -Depth 10

        if ($DebugTelemetry) {
            Write-Host "Telemetry Request:" -ForegroundColor Cyan
            Write-Host $body
        }

        $response = Invoke-RestMethod `
            -Method Post `
            -Uri $Endpoint `
            -ContentType "application/json" `
            -Body $body `
            -TimeoutSec 15

        if ($DebugTelemetry) {
            Write-Host "Telemetry Response:" -ForegroundColor Green
            $response | ConvertTo-Json -Depth 10
        }
        else {
            Write-Indent "Telemetry recorded successfully" 1 Green
        }

    }
    catch {
        if ($DebugTelemetry) {
            Write-Warning "Telemetry failed: $($_.Exception.Message)"
            if ($_.ErrorDetails.Message) {
                Write-Warning $_.ErrorDetails.Message
            }
        }
        return
    }
}

#endregion

# Example:
 $telemetryParams = @{
     TelemetryName  = "iDRACCManTelemetryData"
     EventName      = "Startup"
     Version        = $script:AppVersion
     Endpoint       = "https://gsetools-bufhdqefb8e6ecc6.centralus-01.azurewebsites.net/api/PostTelemetryData"
     DebugTelemetry = $false
 }

 Send-ToolTelemetry @telemetryParams

function Open-iDRACCManDataFolder {
    Start-Process $script:AppRoot
}

function Open-iDRACCManLogFolder {
    Start-Process $script:LogRoot
}


# One-time migration: if the new Documents\iDRACCMan store is empty,
# copy the previous local servers.json so existing iDRAC entries appear.
# Passwords remain DPAPI-encrypted to the original Windows user/machine.
if (-not (Test-Path $script:DataFile)) {
    $oldDataCandidates = @(
        (Join-Path $env:LOCALAPPDATA "iDRACConnectionManagerCleanV22\servers.json"),
        (Join-Path $env:LOCALAPPDATA "iDRACConnectionManagerHybrid\servers.json"),
        (Join-Path $env:LOCALAPPDATA "iDRACConnectionManagerExternal\servers.json"),
        (Join-Path $env:LOCALAPPDATA "iDRACConnectionManager\servers.json")
    )

    foreach ($oldFile in $oldDataCandidates) {
        if (Test-Path $oldFile) {
            Copy-Item $oldFile $script:DataFile -Force
            break
        }
    }
}


function ConvertTo-ProtectedString {
    param([string]$PlainText)

    if ([string]::IsNullOrEmpty($PlainText)) { return "" }

    $bytes = [Text.Encoding]::UTF8.GetBytes($PlainText)
    $protected = [Security.Cryptography.ProtectedData]::Protect(
        $bytes,
        $null,
        [Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return [Convert]::ToBase64String($protected)
}

function ConvertFrom-ProtectedString {
    param([string]$ProtectedText)

    if ([string]::IsNullOrEmpty($ProtectedText)) { return "" }

    try {
        $bytes = [Convert]::FromBase64String($ProtectedText)
        $plain = [Security.Cryptography.ProtectedData]::Unprotect(
            $bytes,
            $null,
            [Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        return [Text.Encoding]::UTF8.GetString($plain)
    }
    catch {
        return ""
    }
}

function Enable-IgnoreSslCertificatePolicy {
    try {
        if (-not ("TrustAllCertsPolicy" -as [type])) {
            Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
        }

        [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    }
    catch {}
}

function Test-WebView2RuntimeInstalled {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
        'HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    )

    foreach ($p in $paths) {
        if (Test-Path $p) { return $true }
    }

    $dirs = @(
        "$env:ProgramFiles(x86)\Microsoft\EdgeWebView\Application",
        "$env:ProgramFiles\Microsoft\EdgeWebView\Application",
        "$env:LOCALAPPDATA\Microsoft\EdgeWebView\Application"
    )

    foreach ($d in $dirs) {
        if (Test-Path $d) { return $true }
    }

    return $false
}

function Get-WebView2RuntimeVersion {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
        'HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    )

    foreach ($p in $paths) {
        $x = Get-ItemProperty $p -ErrorAction SilentlyContinue
        if ($x -and $x.pv) { return $x.pv }
    }

    return "Unknown"
}

function Ensure-WebView2Assemblies {
    $pkgRoot = Join-Path $script:LibRoot "Microsoft.Web.WebView2.$($script:NugetVersion)"
    $pkg = Join-Path $script:LibRoot "Microsoft.Web.WebView2.$($script:NugetVersion).nupkg"

    if (-not (Test-Path $pkgRoot)) {
        if (-not (Test-Path $pkg)) {
            $url = "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/$($script:NugetVersion)"
            Invoke-WebRequest -Uri $url -OutFile $pkg -UseBasicParsing
        }

        New-Item -ItemType Directory -Path $pkgRoot -Force | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($pkg, $pkgRoot)
    }

    $coreDll = Get-ChildItem -Path $pkgRoot -Filter "Microsoft.Web.WebView2.Core.dll" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\lib\\net462\\" } |
        Select-Object -First 1

    $winformsDll = Get-ChildItem -Path $pkgRoot -Filter "Microsoft.Web.WebView2.WinForms.dll" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\lib\\net462\\" } |
        Select-Object -First 1

    if (-not $coreDll -or -not $winformsDll) {
        throw "Could not find Microsoft.Web.WebView2 .NET assemblies."
    }

    $arch = if ([Environment]::Is64BitProcess) { "x64" } else { "x86" }

    $nativeFolder = Get-ChildItem -Path $pkgRoot -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\runtimes\\win-$arch\\native$" } |
        Select-Object -First 1

    if (-not $nativeFolder) {
        throw "Could not find WebView2 native folder for architecture $arch."
    }

    # Do not copy WebView2Loader.dll. Just add the native folder to PATH.
    if ($env:PATH -notlike "*$($nativeFolder.FullName)*") {
        $env:PATH = "$($nativeFolder.FullName);$env:PATH"
    }

    $coreLoaded = [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq "Microsoft.Web.WebView2.Core" } |
        Select-Object -First 1

    $winFormsLoaded = [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq "Microsoft.Web.WebView2.WinForms" } |
        Select-Object -First 1

    if (-not $coreLoaded) {
        Add-Type -Path $coreDll.FullName
    }

    if (-not $winFormsLoaded) {
        Add-Type -Path $winformsDll.FullName
    }
}

function Initialize-WebView2 {
    if (-not (Test-WebView2RuntimeInstalled)) {
        $script:WebViewReady = $false
        return $false
    }

    try {
        Ensure-WebView2Assemblies

        $script:WebViewEnvironment =
            [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync(
                $null,
                $script:WebDataRoot
            ).GetAwaiter().GetResult()

        $script:WebViewReady = $true
        return $true
    }
    catch {
        $script:WebViewReady = $false
        [System.Windows.Forms.MessageBox]::Show(
            "WebView2 failed to initialize.`r`n`r`n$($_.Exception.Message)`r`n`r`nIf you ran older versions in ISE, close all ISE windows and start a new ISE session.",
            "WebView2 Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return $false
    }
}

function Get-iDRACBaseUrl {
    param([string]$Address)

    $Address = $Address.Trim()

    if ($Address -match '^https?://') {
        $u = [uri]$Address
        return "$($u.Scheme)://$($u.Host)"
    }

    return "https://$Address"
}

function Get-iDRACHost {
    param([string]$Address)
    return ([uri](Get-iDRACBaseUrl $Address)).Host
}


function Load-GroupCredentials {
    $script:GroupCredentials = @()

    if (Test-Path $script:GroupCredFile) {
        try {
            $items = Get-Content $script:GroupCredFile -Raw | ConvertFrom-Json
            if ($items) {
                $script:GroupCredentials = @($items)
            }
        }
        catch {
            $script:GroupCredentials = @()
        }
    }
}

function Save-GroupCredentials {
    $script:GroupCredentials | ConvertTo-Json -Depth 8 | Set-Content -Path $script:GroupCredFile -Encoding UTF8
}

function Get-GroupCredentialRecord {
    param([string]$GroupName)

    if ([string]::IsNullOrWhiteSpace($GroupName)) {
        $GroupName = "Ungrouped"
    }

    return $script:GroupCredentials |
        Where-Object { $_.Group -eq $GroupName } |
        Select-Object -First 1
}

function Get-GroupCredential {
    param([string]$GroupName)

    $rec = Get-GroupCredentialRecord -GroupName $GroupName

    if (-not $rec) { return $null }
    if ([string]::IsNullOrWhiteSpace($rec.Username)) { return $null }

    $pass = ConvertFrom-ProtectedString $rec.Password
    if ([string]::IsNullOrWhiteSpace($pass)) { return $null }

    $sec = ConvertTo-SecureString $pass -AsPlainText -Force
    return New-Object Management.Automation.PSCredential($rec.Username, $sec)
}

function Set-GroupCredential {
    param(
        [Parameter(Mandatory=$true)][string]$GroupName,
        [string]$Username,
        [string]$Password
    )

    if ([string]::IsNullOrWhiteSpace($GroupName)) {
        $GroupName = "Ungrouped"
    }

    $rec = Get-GroupCredentialRecord -GroupName $GroupName

    if (-not $rec) {
        $script:GroupCredentials += [pscustomobject]@{
            Group = $GroupName
            Username = $Username
            Password = ConvertTo-ProtectedString $Password
        }
    }
    else {
        $rec.Username = $Username
        $rec.Password = ConvertTo-ProtectedString $Password
    }

    Save-GroupCredentials
}

function Clear-GroupCredential {
    param([Parameter(Mandatory=$true)][string]$GroupName)

    $script:GroupCredentials = @(
        $script:GroupCredentials | Where-Object { $_.Group -ne $GroupName }
    )

    Save-GroupCredentials
}

function Show-GroupCredentialDialog {
    $node = $script:Tree.SelectedNode
    if (-not $node) { return }

    $groupName = $null

    if ($node.Tag) {
        $groupName = $node.Tag.Group
    }
    else {
        $groupName = $node.Text
    }

    if ([string]::IsNullOrWhiteSpace($groupName)) {
        $groupName = "Ungrouped"
    }

    $existing = Get-GroupCredentialRecord -GroupName $groupName

    $f = New-Object System.Windows.Forms.Form
    $f.Text = "Group Credentials - $groupName"
    $f.Width = 420
    $f.Height = 230
    $f.StartPosition = "CenterParent"
    $f.FormBorderStyle = "FixedDialog"
    $f.Font = $script:AppFont
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text = "Used when an iDRAC in this group has no server-level password."
    $lblInfo.Left = 12
    $lblInfo.Top = 12
    $lblInfo.Width = 380
    $lblInfo.Height = 24
    $f.Controls.Add($lblInfo)

    $lblUser = New-Object System.Windows.Forms.Label
    $lblUser.Text = "Username"
    $lblUser.Left = 12
    $lblUser.Top = 52
    $lblUser.Width = 90
    $f.Controls.Add($lblUser)

    $txtUser = New-Object System.Windows.Forms.TextBox
    $txtUser.Left = 110
    $txtUser.Top = 48
    $txtUser.Width = 260
    if ($existing) { $txtUser.Text = $existing.Username }
    $f.Controls.Add($txtUser)

    $lblPass = New-Object System.Windows.Forms.Label
    $lblPass.Text = "Password"
    $lblPass.Left = 12
    $lblPass.Top = 88
    $lblPass.Width = 90
    $f.Controls.Add($lblPass)

    $txtPass = New-Object System.Windows.Forms.TextBox
    $txtPass.Left = 110
    $txtPass.Top = 84
    $txtPass.Width = 260
    $txtPass.UseSystemPasswordChar = $true
    if ($existing) { $txtPass.Text = ConvertFrom-ProtectedString $existing.Password }
    $f.Controls.Add($txtPass)

    $btnClear = New-Object System.Windows.Forms.Button
    $btnClear.Text = "Clear"
    $btnClear.Left = 110
    $btnClear.Top = 130
    $btnClear.Width = 75
    $btnClear.Add_Click({
        Clear-GroupCredential -GroupName $groupName
        $f.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $f.Close()
    })
    $f.Controls.Add($btnClear)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "Save"
    $ok.Left = 215
    $ok.Top = 130
    $ok.Width = 75
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $f.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancel"
    $cancel.Left = 300
    $cancel.Top = 130
    $cancel.Width = 75
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $f.Controls.Add($cancel)

    $f.AcceptButton = $ok
    $f.CancelButton = $cancel

    $result = $f.ShowDialog($script:MainForm)

    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and -not $btnClear.Focused) {
        if ([string]::IsNullOrWhiteSpace($txtUser.Text) -and [string]::IsNullOrWhiteSpace($txtPass.Text)) {
            Clear-GroupCredential -GroupName $groupName
        }
        else {
            Set-GroupCredential -GroupName $groupName -Username $txtUser.Text.Trim() -Password $txtPass.Text
        }
    }

    Refresh-Tree
    Resize-SideMenuToContent
}

function Get-iDRACCredentialFromServer {
    param([Parameter(Mandatory=$true)]$Server)

    $user = $Server.Username
    $pass = ConvertFrom-ProtectedString $Server.Password

    if (-not [string]::IsNullOrWhiteSpace($user) -and -not [string]::IsNullOrWhiteSpace($pass)) {
        $sec = ConvertTo-SecureString $pass -AsPlainText -Force
        return New-Object Management.Automation.PSCredential($user, $sec)
    }

    $groupCred = Get-GroupCredential -GroupName $Server.Group
    if ($groupCred) {
        return $groupCred
    }

    return Get-Credential -Message "Credentials for $($Server.Name)"
}

function Invoke-iDRACWebRequest {
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [Parameter(Mandatory=$true)][string]$Method,
        [Parameter(Mandatory=$false)]$Credential,
        [Parameter(Mandatory=$false)]$Body,
        [Parameter(Mandatory=$false)]$Headers,
        [Parameter(Mandatory=$false)][string]$ContentType = "application/json"
    )

    Enable-IgnoreSslCertificatePolicy

    $params = @{
        Uri = $Uri
        Method = $Method
        UseBasicParsing = $true
        ErrorAction = "Stop"
        Headers = if ($Headers) { $Headers } else { @{ "Accept" = "application/json" } }
    }

    if ($Credential) {
        $params.Credential = $Credential
    }

    if ($Body) {
        if ($Body -is [string]) {
            $params.Body = $Body
        }
        else {
            $params.Body = ($Body | ConvertTo-Json -Compress -Depth 20)
        }
        $params.ContentType = $ContentType
    }

    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $params.SkipCertificateCheck = $true
        $params.SkipHeaderValidation = $true
    }

    return Invoke-WebRequest @params
}


function Get-iDRACCredentialCandidates {
    param(
        [Parameter(Mandatory=$true)]$Server,
        [switch]$AllowPrompt
    )

    $candidates = New-Object System.Collections.ArrayList

    # Preferred order: group credentials first, then server/node credentials.
    # This lets one shared group credential drive health refresh and console connect,
    # but still allows a node-level override/fallback when the group credential fails.
    try {
        $groupCred = Get-GroupCredential -GroupName $Server.Group
        if ($groupCred) {
            [void]$candidates.Add([pscustomobject]@{
                Source = "Group '$($Server.Group)'"
                Credential = $groupCred
            })
        }
    }
    catch {}

    try {
        $serverUser = [string]$Server.Username
        $serverPass = ConvertFrom-ProtectedString $Server.Password
        if (-not [string]::IsNullOrWhiteSpace($serverUser) -and -not [string]::IsNullOrWhiteSpace($serverPass)) {
            $sec = ConvertTo-SecureString $serverPass -AsPlainText -Force
            $serverCred = New-Object Management.Automation.PSCredential($serverUser, $sec)

            $isDuplicate = $false
            foreach ($existing in @($candidates)) {
                try {
                    $e = $existing.Credential.GetNetworkCredential()
                    if ($e.UserName -eq $serverUser -and $e.Password -eq $serverPass) {
                        $isDuplicate = $true
                        break
                    }
                }
                catch {}
            }

            if (-not $isDuplicate) {
                [void]$candidates.Add([pscustomobject]@{
                    Source = "Node '$($Server.Name)'"
                    Credential = $serverCred
                })
            }
        }
    }
    catch {}

    if ($AllowPrompt -and $candidates.Count -eq 0) {
        try {
            $promptCred = Get-Credential -Message "Credentials for $($Server.Name)"
            if ($promptCred) {
                [void]$candidates.Add([pscustomobject]@{
                    Source = "Prompt"
                    Credential = $promptCred
                })
            }
        }
        catch {}
    }

    return @($candidates)
}

function New-iDRACKvmUrlDellMethodUsingCredential {
    param(
        [Parameter(Mandatory=$true)]$Server,
        [Parameter(Mandatory=$true)]$Credential,
        [string]$CredentialSource = "Credential"
    )

    $idracHost = Get-iDRACHost $Server.Address
    $base = "https://$idracHost"
    $cred = $Credential
    $userName = $cred.GetNetworkCredential().UserName
    $password = $cred.GetNetworkCredential().Password

    # 1. Create X-Auth-Token session.
    $script:Status.Text = "Creating X-Auth-Token session for $($Server.Name) using $CredentialSource credentials..."
    [System.Windows.Forms.Application]::DoEvents()

    $sessionBody = @{
        UserName = $userName
        Password = $password
    } | ConvertTo-Json -Compress

    $sessionResp = Invoke-iDRACWebRequest `
        -Uri "$base/redfish/v1/SessionService/Sessions" `
        -Method "POST" `
        -Body $sessionBody `
        -Headers @{ "Accept" = "application/json" }

    if ($sessionResp.StatusCode -ne 201) {
        throw "Failed to create X-Auth-Token session. StatusCode: $($sessionResp.StatusCode)"
    }

    $tokenName = "X-Auth-Token"
    $xAuthToken = $sessionResp.Headers.$tokenName
    $sessionLocation = $sessionResp.Headers.Location

    if ($xAuthToken -is [array]) { $xAuthToken = $xAuthToken[0] }
    if ($sessionLocation -is [array]) { $sessionLocation = $sessionLocation[0] }

    if ([string]::IsNullOrWhiteSpace($xAuthToken)) {
        throw "X-Auth-Token was not returned by iDRAC."
    }

    $headers = @{
        "Accept" = "application/json"
        "X-Auth-Token" = $xAuthToken
    }

    try {
        # 2. Validate GetKVMSession action exists.
        $script:Status.Text = "Validating GetKVMSession support for $($Server.Name)..."
        [System.Windows.Forms.Application]::DoEvents()

        $svcResp = Invoke-iDRACWebRequest `
            -Uri "$base/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DelliDRACCardService" `
            -Method "GET" `
            -Headers $headers

        if ($svcResp.StatusCode -ne 200) {
            throw "DelliDRACCardService check failed. StatusCode: $($svcResp.StatusCode)"
        }

        $svcJson = $svcResp.Content | ConvertFrom-Json
        $kvmActionName = "#DelliDRACCardService.GetKVMSession"
        $kvmAction = $svcJson.Actions.$kvmActionName

        if (-not $kvmAction) {
            throw "This iDRAC does not show DelliDRACCardService.GetKVMSession support."
        }

        # 3. Export SSL certificate.
        $script:Status.Text = "Exporting iDRAC SSL certificate for $($Server.Name)..."
        [System.Windows.Forms.Application]::DoEvents()

        $certResp = Invoke-iDRACWebRequest `
            -Uri "$base/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DelliDRACCardService/Actions/DelliDRACCardService.ExportSSLCertificate" `
            -Method "POST" `
            -Body (@{ SSLCertType = "Server" } | ConvertTo-Json -Compress) `
            -Headers $headers

        if ($certResp.StatusCode -ne 200 -and $certResp.StatusCode -ne 202) {
            throw "ExportSSLCertificate failed. StatusCode: $($certResp.StatusCode)"
        }

        $certJson = $certResp.Content | ConvertFrom-Json
        $certText = $certJson.CertificateFile

        if ([string]::IsNullOrWhiteSpace($certText)) {
            throw "ExportSSLCertificate did not return CertificateFile."
        }

        # Dell's sample uses the literal filename idrac_cert_file.txt.
        $oldLocation = Get-Location
        Push-Location $script:AppRoot
        $certFileName = "idrac_cert_file.txt"
        Set-Content -Path $certFileName -Value $certText -Encoding ASCII -NoNewline

        try {
            # 4. Get temporary KVM username/password.
            $script:Status.Text = "Getting temporary KVM session for $($Server.Name)..."
            [System.Windows.Forms.Application]::DoEvents()

            $kvmResp = Invoke-iDRACWebRequest `
                -Uri "$base/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DelliDRACCardService/Actions/DelliDRACCardService.GetKVMSession" `
                -Method "POST" `
                -Body (@{ SessionTypeName = $certFileName } | ConvertTo-Json -Compress) `
                -Headers $headers

            if ($kvmResp.StatusCode -ne 200 -and $kvmResp.StatusCode -ne 202) {
                throw "GetKVMSession failed. StatusCode: $($kvmResp.StatusCode)"
            }

            $kvmJson = $kvmResp.Content | ConvertFrom-Json
            $tempUsername = $kvmJson.TempUsername
            $tempPassword = $kvmJson.TempPassword

            if ([string]::IsNullOrWhiteSpace($tempUsername) -or [string]::IsNullOrWhiteSpace($tempPassword)) {
                throw "GetKVMSession did not return TempUsername/TempPassword."
            }

            Add-Type -AssemblyName System.Web

            $encUser = [System.Web.HttpUtility]::UrlEncode($userName)
            $encTempUser = [System.Web.HttpUtility]::UrlEncode($tempUsername)
            $encTempPass = [System.Web.HttpUtility]::UrlEncode($tempPassword)

            
return [pscustomobject]@{
    Url = "https://$idracHost/console?username=$encUser&tempUsername=$encTempUser&tempPassword=$encTempPass"
    DeleteUri = if ($sessionLocation -match '^https?://') { $sessionLocation } else { "$base$sessionLocation" }
    Headers = $headers
}

        }
        finally {
            Remove-Item $certFileName -Force -ErrorAction SilentlyContinue
            Pop-Location
        }
    }
    finally {
        # Session is intentionally kept alive and is closed when the KVM tab is closed.
    }
}


function New-iDRACKvmUrlDellMethod {
    param([Parameter(Mandatory=$true)]$Server)

    $candidates = @(Get-iDRACCredentialCandidates -Server $Server -AllowPrompt)
    if ($candidates.Count -eq 0) {
        throw "No group, node, or prompted credentials are available for $($Server.Name)."
    }

    $errors = New-Object System.Collections.ArrayList
    foreach ($candidate in $candidates) {
        try {
            return New-iDRACKvmUrlDellMethodUsingCredential -Server $Server -Credential $candidate.Credential -CredentialSource $candidate.Source
        }
        catch {
            [void]$errors.Add("$($candidate.Source): $($_.Exception.Message)")
            if ($script:Status) { $script:Status.Text = "Console credential failed for $($Server.Name): $($candidate.Source). Trying next credential..." }
            [System.Windows.Forms.Application]::DoEvents()
        }
    }

    throw "Console connection failed for $($Server.Name) using available credentials.`r`n`r`n$($errors -join "`r`n")"
}

function Invoke-iDRACRestMethod {
    param(
        [Parameter(Mandatory=$true)]$Server,
        [Parameter(Mandatory=$true)][string]$Path,
        [string]$Method = "GET",
        $Body = $null
    )

    $base = Get-iDRACBaseUrl $Server.Address
    $cred = Get-iDRACCredentialFromServer -Server $Server

    $response = Invoke-iDRACWebRequest `
        -Uri "$base$Path" `
        -Method $Method `
        -Credential $cred `
        -Body $Body

    if ([string]::IsNullOrWhiteSpace($response.Content)) {
        return $null
    }

    return ($response.Content | ConvertFrom-Json)
}



function Join-iDRACRedfishUri {
    param(
        [Parameter(Mandatory=$true)][string]$BaseUrl,
        [Parameter(Mandatory=$true)][string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $BaseUrl }
    if ($Path -match '^https?://') { return $Path }

    $b = $BaseUrl.TrimEnd("/")
    $p = $Path.TrimStart("/")
    return "$b/$p"
}

function Invoke-iDRACRedfishJson {
    param(
        [Parameter(Mandatory=$true)][string]$BaseUrl,
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$false)]$Credential,
        [Parameter(Mandatory=$false)]$Headers,
        [string]$Method = "GET",
        $Body = $null
    )

    $uri = Join-iDRACRedfishUri -BaseUrl $BaseUrl -Path $Path

    $resp = Invoke-iDRACWebRequest `
        -Uri $uri `
        -Method $Method `
        -Credential $Credential `
        -Headers $Headers `
        -Body $Body

    if ([string]::IsNullOrWhiteSpace($resp.Content)) { return $null }
    return ($resp.Content | ConvertFrom-Json)
}

function Get-iDRACFirstMemberUri {
    param($Collection)

    try {
        if ($Collection.Members -and $Collection.Members.Count -gt 0) {
            $first = @($Collection.Members)[0]
            $uri = $first.'@odata.id'
            if (-not [string]::IsNullOrWhiteSpace([string]$uri)) { return [string]$uri }
        }
    }
    catch {}

    return ""
}

function Test-iDRAC8LegacyKvmUnsupportedError {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }

    return ($Message -match "405|Method Not Allowed|GetKVMSession|DelliDRACCardService")
}

function Open-iDRAC8GuiFallback {
    param(
        [Parameter(Mandatory=$true)]$Server,
        [string]$Reason = ""
    )

    $title = "$($Server.Name) - iDRAC8: GUI only"
    $msg = "iDRAC8 / 13G direct console launch is not supported. GUI opened instead. Use Launch Virtual Console from the iDRAC GUI."

    try {
        $tab = Add-WebViewTab `
            -Server $Server `
            -Url (Get-iDRACBaseUrl $Server.Address) `
            -TabTitle $title `
            -HeaderMessage $msg

        if ($script:Status) {
            $script:Status.Text = "iDRAC8 direct console not supported. Opened GUI for $($Server.Name)."
        }

        try {
            Add-LogTab -Title "iDRAC8 Console Notice" -Text ("{0}`r`n`r`nServer: {1}`r`nAddress: {2}`r`nReason: {3}" -f $msg,$Server.Name,$Server.Address,$Reason)
        }
        catch {}

        Send-iDRACCManTelemetry -EventName "OpenConsoleIDRAC8GuiFallback" -Properties @{ Group = $Server.Group; Model = $Server.Model; Health = $Server.Health }
        return $tab
    }
    catch {
        throw "Unable to open iDRAC8 GUI fallback.`r`n$($_.Exception.Message)"
    }
}


function Get-RedfishValue {
    param(
        $Object,
        [string[]]$Paths
    )

    foreach ($path in $Paths) {
        try {
            $current = $Object
            foreach ($part in ($path -split '\.')) {
                if ($null -eq $current) { break }
                $prop = $current.PSObject.Properties[$part]
                if ($prop) {
                    $current = $prop.Value
                }
                else {
                    $current = $null
                    break
                }
            }

            if ($null -ne $current -and -not [string]::IsNullOrWhiteSpace([string]$current)) {
                return [string]$current
            }
        }
        catch {}
    }

    return ""
}

function Get-iDRACInventory {
    param(
        [Parameter(Mandatory=$true)][string]$Address,
        [Parameter(Mandatory=$true)][string]$Username,
        [Parameter(Mandatory=$true)][string]$Password
    )

    $base = Get-iDRACBaseUrl $Address
    $sessionLocation = $null
    $headers = $null
    $lastErrors = New-Object System.Collections.ArrayList

    $serviceTag = ""
    $model = ""
    $osHost = ""
    $health = ""
    $powerState = ""
    $managerName = ""

    try {
        try {
            $sessionBody = @{
                UserName = $Username
                Password = $Password
            }

            $sessionResp = Invoke-iDRACWebRequest `
                -Uri "$base/redfish/v1/SessionService/Sessions" `
                -Method "POST" `
                -Body $sessionBody `
                -Headers @{ "Accept" = "application/json" }

            $xAuthToken = $null
            try { $xAuthToken = $sessionResp.Headers["X-Auth-Token"] } catch {}
            if ([string]::IsNullOrWhiteSpace([string]$xAuthToken)) {
                try { $xAuthToken = $sessionResp.Headers.'X-Auth-Token' } catch {}
            }

            try { $sessionLocation = $sessionResp.Headers["Location"] } catch {}
            if ([string]::IsNullOrWhiteSpace([string]$sessionLocation)) {
                try { $sessionLocation = $sessionResp.Headers.Location } catch {}
            }

            if ($xAuthToken -is [array]) { $xAuthToken = $xAuthToken[0] }
            if ($sessionLocation -is [array]) { $sessionLocation = $sessionLocation[0] }

            if (-not [string]::IsNullOrWhiteSpace([string]$xAuthToken)) {
                $headers = @{
                    "Accept" = "application/json"
                    "X-Auth-Token" = [string]$xAuthToken
                }
            }
            else {
                [void]$lastErrors.Add("Session login did not return X-Auth-Token.")
            }
        }
        catch {
            # iDRAC8 / 13G frequently returns 405 on Redfish session POST.
            # That does not mean Redfish is unusable; Basic Auth GET discovery often still works.
            [void]$lastErrors.Add("Session login failed: $($_.Exception.Message)")
            $headers = $null
        }

        $basicCredential = $null
        if (-not $headers) {
            $sec = ConvertTo-SecureString $Password -AsPlainText -Force
            $basicCredential = New-Object Management.Automation.PSCredential($Username, $sec)
        }

        $root = $null
        try {
            $root = Invoke-iDRACRedfishJson -BaseUrl $base -Path "/redfish/v1" -Headers $headers -Credential $basicCredential
        }
        catch {
            [void]$lastErrors.Add("GET /redfish/v1 failed: $($_.Exception.Message)")
        }

        $system = $null
        $systemsUri = ""
        $systemUri = ""

        try {
            if ($root -and $root.Systems) {
                $systemsUri = [string]$root.Systems.'@odata.id'
            }
        }
        catch {}

        $systemCandidateUris = New-Object System.Collections.ArrayList

        if (-not [string]::IsNullOrWhiteSpace($systemsUri)) {
            try {
                $systemsCollection = Invoke-iDRACRedfishJson -BaseUrl $base -Path $systemsUri -Headers $headers -Credential $basicCredential
                $systemUri = Get-iDRACFirstMemberUri -Collection $systemsCollection
                if (-not [string]::IsNullOrWhiteSpace($systemUri)) {
                    [void]$systemCandidateUris.Add($systemUri)
                }
            }
            catch {
                [void]$lastErrors.Add("GET Systems collection failed: $($_.Exception.Message)")
            }
        }

        foreach ($candidate in @(
            "/redfish/v1/Systems/System.Embedded.1",
            "/redfish/v1/Systems/1",
            "/redfish/v1/Systems/System.Embedded.1/"
        )) {
            if (-not ($systemCandidateUris -contains $candidate)) {
                [void]$systemCandidateUris.Add($candidate)
            }
        }

        foreach ($candidate in @($systemCandidateUris)) {
            try {
                $system = Invoke-iDRACRedfishJson -BaseUrl $base -Path $candidate -Headers $headers -Credential $basicCredential
                if ($system) {
                    $systemUri = [string]$candidate
                    break
                }
            }
            catch {
                [void]$lastErrors.Add("GET $candidate failed: $($_.Exception.Message)")
            }
        }

        $idrac = $null
        $managersUri = ""
        $managerUri = ""

        try {
            if ($root -and $root.Managers) {
                $managersUri = [string]$root.Managers.'@odata.id'
            }
        }
        catch {}

        $managerCandidateUris = New-Object System.Collections.ArrayList

        if (-not [string]::IsNullOrWhiteSpace($managersUri)) {
            try {
                $mgrCollection = Invoke-iDRACRedfishJson -BaseUrl $base -Path $managersUri -Headers $headers -Credential $basicCredential
                $managerUri = Get-iDRACFirstMemberUri -Collection $mgrCollection
                if (-not [string]::IsNullOrWhiteSpace($managerUri)) {
                    [void]$managerCandidateUris.Add($managerUri)
                }
            }
            catch {
                [void]$lastErrors.Add("GET Managers collection failed: $($_.Exception.Message)")
            }
        }

        foreach ($candidate in @(
            "/redfish/v1/Managers/iDRAC.Embedded.1",
            "/redfish/v1/Managers/iDRAC.Embedded.1/",
            "/redfish/v1/Managers/1"
        )) {
            if (-not ($managerCandidateUris -contains $candidate)) {
                [void]$managerCandidateUris.Add($candidate)
            }
        }

        foreach ($candidate in @($managerCandidateUris)) {
            try {
                $idrac = Invoke-iDRACRedfishJson -BaseUrl $base -Path $candidate -Headers $headers -Credential $basicCredential
                if ($idrac) {
                    $managerUri = [string]$candidate
                    break
                }
            }
            catch {
                [void]$lastErrors.Add("GET $candidate failed: $($_.Exception.Message)")
            }
        }

        if ($system) {
            $serviceTag = Get-RedfishValue -Object $system -Paths @(
                "SKU",
                "SerialNumber",
                "Oem.Dell.DellSystem.ChassisServiceTag",
                "Oem.Dell.ChassisServiceTag"
            )
            $model = Get-RedfishValue -Object $system -Paths @(
                "Model",
                "Oem.Dell.DellSystem.SystemModelName",
                "Oem.Dell.SystemModelName"
            )
            $osHost = Get-RedfishValue -Object $system -Paths @(
                "HostName",
                "Oem.Dell.DellSystem.HostName",
                "Oem.Dell.HostName"
            )
            $health = Get-RedfishValue -Object $system -Paths @(
                "Status.HealthRollup",
                "Status.Health"
            )
            $powerState = Get-RedfishValue -Object $system -Paths @("PowerState")
        }

        if ($idrac) {
            $managerName = Get-RedfishValue -Object $idrac -Paths @("Name","Id","HostName")
            if ([string]::IsNullOrWhiteSpace($health)) {
                $health = Get-RedfishValue -Object $idrac -Paths @("Status.HealthRollup","Status.Health")
            }
            if ([string]::IsNullOrWhiteSpace($model)) {
                $model = Get-RedfishValue -Object $idrac -Paths @("Model","Oem.Dell.DelliDRACCard.Model")
            }
            if ([string]::IsNullOrWhiteSpace($serviceTag)) {
                $serviceTag = Get-RedfishValue -Object $idrac -Paths @("ServiceTag","SerialNumber")
            }
        }

        $redfishResponded = ($null -ne $root) -or ($null -ne $system) -or ($null -ne $idrac)
        if (-not $redfishResponded) {
            throw "Redfish did not return usable root, system, or manager data.`r`n$($lastErrors -join "`r`n")"
        }

        if ([string]::IsNullOrWhiteSpace($serviceTag)) { $serviceTag = "Unknown" }
        if ([string]::IsNullOrWhiteSpace($model))      { $model = "Unknown" }
        if ([string]::IsNullOrWhiteSpace($osHost))     { $osHost = "" }
        if ([string]::IsNullOrWhiteSpace($health))     { $health = "Unknown" }
        if ([string]::IsNullOrWhiteSpace($powerState)) { $powerState = "Unknown" }

        $displayName = if (-not [string]::IsNullOrWhiteSpace($osHost)) {
            $osHost
        }
        elseif ($serviceTag -ne "Unknown") {
            $serviceTag
        }
        elseif (-not [string]::IsNullOrWhiteSpace($managerName)) {
            $managerName
        }
        else {
            $Address
        }

        return [pscustomobject]@{
            Name = $displayName
            Address = $Address
            Username = $Username
            Password = ConvertTo-ProtectedString $Password
            ServiceTag = $serviceTag
            Model = $model
            OSHostname = $osHost
            Health = $health
            PowerState = $powerState
        }
    }
    catch {
        throw $_
    }
    finally {
        try {
            if ($headers -and -not [string]::IsNullOrWhiteSpace([string]$sessionLocation)) {
                $deleteUri = if ($sessionLocation -match '^https?://') { $sessionLocation } else { "$base$sessionLocation" }
                Invoke-iDRACWebRequest `
                    -Uri $deleteUri `
                    -Method "DELETE" `
                    -Headers $headers | Out-Null
            }
        }
        catch {}
    }
}

function Update-iDRACInventoryForServer {
    param([Parameter(Mandatory=$true)]$Server)

    $candidates = @(Get-iDRACCredentialCandidates -Server $Server)
    if ($candidates.Count -eq 0) {
        throw "No group or node credentials are available to refresh inventory."
    }

    $errors = New-Object System.Collections.ArrayList

    foreach ($candidate in $candidates) {
        try {
            if ($script:Status) { $script:Status.Text = "Refreshing $($Server.Name) health using $($candidate.Source) credentials..." }
            [System.Windows.Forms.Application]::DoEvents()

            $nc = $candidate.Credential.GetNetworkCredential()
            $inv = Get-iDRACInventory -Address $Server.Address -Username $nc.UserName -Password $nc.Password

            $Server.Name = $inv.Name
            $Server.ServiceTag = $inv.ServiceTag
            $Server.Model = $inv.Model
            $Server.OSHostname = $inv.OSHostname
            $Server.Health = $inv.Health
            $Server.PowerState = $inv.PowerState

            if ([string]::IsNullOrWhiteSpace($Server.Notes)) {
                $Server.Notes = "Service Tag: $($inv.ServiceTag); Model: $($inv.Model); Health: $($inv.Health)"
            }

            Save-Servers
            Refresh-Tree
            return $inv
        }
        catch {
            [void]$errors.Add("$($candidate.Source): $($_.Exception.Message)")
        }
    }

    throw "Inventory refresh failed using group credentials first, then node credentials.`r`n$($errors -join "`r`n")"
}


function Refresh-iDRACHealthBatch {
    param(
        [Parameter(Mandatory=$true)][object[]]$ServersToRefresh,
        [string]$Title = "Refresh Health"
    )

    $servers = @($ServersToRefresh | Where-Object { $_ })
    if ($servers.Count -eq 0) { return }

    $okCount = 0
    $failCount = 0
    $log = New-Object System.Text.StringBuilder
    [void]$log.AppendLine("$Title")
    [void]$log.AppendLine("Started: $(Get-Date)")
    [void]$log.AppendLine("")

    foreach ($srv in $servers) {
        try {
            if ($script:Status) { $script:Status.Text = "Refreshing health for $($srv.Name)..." }
            [System.Windows.Forms.Application]::DoEvents()

            $oldHealth = $srv.Health
            $oldPower = $srv.PowerState
            $inv = Update-iDRACInventoryForServer -Server $srv
            $okCount++

            [void]$log.AppendLine("OK: $($srv.Name) [$($srv.Address)] Health: $oldHealth -> $($inv.Health), Power: $oldPower -> $($inv.PowerState)")
        }
        catch {
            $failCount++
            [void]$log.AppendLine("FAILED: $($srv.Name) [$($srv.Address)] - $($_.Exception.Message)")
        }
    }

    Save-Servers
    Refresh-Tree
    Update-DashboardServerList

    if ($script:Status) {
        $script:Status.Text = "Health refresh complete. Success: $okCount  Failed: $failCount  Time: $(Get-Date -Format 'h:mm:ss tt')"
        Send-iDRACCManTelemetry -EventName "RefreshHealth" -Properties @{ Title = $Title; Success = $okCount; Failed = $failCount; Count = $servers.Count }
    }

    if ($failCount -gt 0) {
        Add-LogTab -Title "Health Refresh" -Text $log.ToString()
        [System.Windows.Forms.MessageBox]::Show(
            "Health refresh completed with $failCount failure(s). A Health Refresh tab was added with details.",
            "Refresh Health",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    }
    else {
        [System.Windows.Forms.MessageBox]::Show(
            "Health refresh complete.`r`n`r`nUpdated: $okCount iDRAC(s).",
            "Refresh Health",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
}

function Refresh-SelectediDRACHealth {
    $s = Get-SelectedServer
    if (-not $s) {
        [System.Windows.Forms.MessageBox]::Show("Select an iDRAC first.","Refresh Health") | Out-Null
        return
    }

    Refresh-iDRACHealthBatch -ServersToRefresh @($s) -Title "Refresh selected iDRAC health"
}

function Refresh-SelectedGroupHealth {
    $groupName = Get-SelectedGroupName
    if ([string]::IsNullOrWhiteSpace($groupName)) { return }

    $servers = @($script:Servers | Where-Object { $_.Group -eq $groupName })
    if ($servers.Count -eq 0) { return }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Refresh health for all $($servers.Count) iDRAC(s) in group '$groupName'?",
        "Refresh Group Health",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    Refresh-iDRACHealthBatch -ServersToRefresh $servers -Title "Refresh group health: $groupName"
}

function Refresh-AlliDRACHealth {
    $servers = @($script:Servers)
    if ($servers.Count -eq 0) { return }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Refresh health for all $($servers.Count) configured iDRAC(s)?",
        "Refresh All Health",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    Refresh-iDRACHealthBatch -ServersToRefresh $servers -Title "Refresh all iDRAC health"
}

function Add-MissingServerInventoryProperties {
    foreach ($s in @($script:Servers)) {
        if (-not ($s.PSObject.Properties.Name -contains "ServiceTag")) { $s | Add-Member -NotePropertyName ServiceTag -NotePropertyValue "" -Force }
        if (-not ($s.PSObject.Properties.Name -contains "Model")) { $s | Add-Member -NotePropertyName Model -NotePropertyValue "" -Force }
        if (-not ($s.PSObject.Properties.Name -contains "OSHostname")) { $s | Add-Member -NotePropertyName OSHostname -NotePropertyValue "" -Force }
        if (-not ($s.PSObject.Properties.Name -contains "Health")) { $s | Add-Member -NotePropertyName Health -NotePropertyValue "" -Force }
        if (-not ($s.PSObject.Properties.Name -contains "PowerState")) { $s | Add-Member -NotePropertyName PowerState -NotePropertyValue "" -Force }
    }
}


function New-iDRACServerRecordFromInventory {
    param(
        [Parameter(Mandatory=$true)]$Inventory,
        [Parameter(Mandatory=$true)][string]$GroupName
    )

    if ([string]::IsNullOrWhiteSpace($GroupName)) { $GroupName = "Ungrouped" }

    $record = [pscustomobject]@{
        Name       = [string]$Inventory.Name
        Address    = [string]$Inventory.Address
        Group      = [string]$GroupName
        Username   = [string]$Inventory.Username
        Password   = [string]$Inventory.Password
        Notes      = "Service Tag: $($Inventory.ServiceTag); Model: $($Inventory.Model); Health: $($Inventory.Health)"
        ServiceTag = [string]$Inventory.ServiceTag
        Model      = [string]$Inventory.Model
        OSHostname = [string]$Inventory.OSHostname
        Health     = [string]$Inventory.Health
        PowerState = [string]$Inventory.PowerState
    }

    foreach ($propName in @("Name","Address","Group","Username","Password","Notes","ServiceTag","Model","OSHostname","Health","PowerState")) {
        if ($null -eq $record.$propName) { $record.$propName = "" }
    }

    return $record
}

function Add-iDRACServerRecord {
    param(
        [Parameter(Mandatory=$true)]$Inventory,
        [Parameter(Mandatory=$true)][string]$GroupName
    )

    $record = New-iDRACServerRecordFromInventory -Inventory $Inventory -GroupName $GroupName

    # Force a new array assignment so TreeView and dashboard refresh read the same updated collection.
    $script:Servers = @($script:Servers) + @($record)

    Add-MissingServerInventoryProperties
    Save-Servers

    try { Load-Servers } catch {}

    if ($script:Tree) {
        Refresh-Tree
        try {
            foreach ($gNode in $script:Tree.Nodes) {
                if ($gNode.Tag -and $gNode.Tag.Group -eq $record.Group) {
                    $gNode.Expand()
                    foreach ($child in $gNode.Nodes) {
                        if ($child.Tag -and $child.Tag.Address -eq $record.Address) {
                            $script:Tree.SelectedNode = $child
                            $child.EnsureVisible()
                            break
                        }
                    }
                    break
                }
            }
            $script:Tree.Refresh()
        }
        catch {}
    }

    Update-DashboardServerList
    try { [System.Windows.Forms.Application]::DoEvents() } catch {}

    return $record
}

function Load-Servers {
    if (Test-Path $script:DataFile) {
        try {
            $items = Get-Content $script:DataFile -Raw | ConvertFrom-Json
            if ($items) { $script:Servers = @($items) }
        }
        catch {
            $script:Servers = @()
        }
    }

    if (-not $script:Servers -or $script:Servers.Count -eq 0) {
        $script:Servers = @(
            [pscustomobject]@{
                Name = "Node1"
                Address = "192.168.10.1"
                Group = "iDRAC"
                Username = "root"
                Password = ""
                Notes = ""
                ServiceTag = ""
                Model = ""
                OSHostname = ""
                Health = ""
                PowerState = ""
            }
        )
        Save-Servers
    }

    Add-MissingServerInventoryProperties
}

function Save-Servers {
    $script:Servers | ConvertTo-Json -Depth 8 | Set-Content -Path $script:DataFile -Encoding UTF8
}

function Get-SelectedServer {
    if (-not $script:Tree.SelectedNode) { return $null }
    if (-not $script:Tree.SelectedNode.Tag) { return $null }

    $tag = $script:Tree.SelectedNode.Tag
    try {
        if ($tag.IsGroup) { return $null }
    }
    catch {}

    return $tag
}

function Refresh-Tree {
    $script:Tree.BeginUpdate()
    $script:Tree.Nodes.Clear()

    foreach ($g in ($script:Servers | Group-Object Group | Sort-Object Name)) {
        $gName = if ([string]::IsNullOrWhiteSpace($g.Name)) { "Ungrouped" } else { $g.Name }
        $hasGroupCred = $null -ne (Get-GroupCredentialRecord -GroupName $gName)
        $displayName = if ($hasGroupCred) { "$gName" } else { $gName }

        $gNode = New-Object System.Windows.Forms.TreeNode($displayName)
        $gNode.Tag = [pscustomobject]@{
            IsGroup = $true
            Group = $gName
        }

        foreach ($s in ($g.Group | Sort-Object Name)) {
            $credTag = ""
            if (-not [string]::IsNullOrWhiteSpace($s.Username)) {
                $credTag = ""
            }
            elseif ($hasGroupCred) {
                $credTag = ""
            }

            $healthText = ""
            try {
                if (-not [string]::IsNullOrWhiteSpace($s.Health)) {
                    $healthText = " - $($s.Health)"
                }
            }
            catch {}

            $node = New-Object System.Windows.Forms.TreeNode("$($s.Name) [$($s.Address)]$healthText$credTag")
            $node.Tag = $s
            try {
                switch -Regex ($s.Health) {
                    "Critical" { $node.ForeColor = [System.Drawing.Color]::FromArgb(222,43,43); break }
                    "Warning"  { $node.ForeColor = [System.Drawing.Color]::FromArgb(245,146,0); break }
                    "OK"       { $node.ForeColor = [System.Drawing.Color]::FromArgb(36,152,50); break }
                }
            }
            catch {}
            [void]$gNode.Nodes.Add($node)
        }

        [void]$script:Tree.Nodes.Add($gNode)
        $gNode.Expand()
    }

    $script:Tree.EndUpdate()
    if ($script:MainSplit) { Resize-SideMenuToContent }
}

function Update-DashboardServerList {
    try {
        if (-not $script:Tabs) { return }

        $dash = $script:Tabs.TabPages | Where-Object { $_.Text -eq "Dashboard" } | Select-Object -First 1
        if (-not $dash) { return }

        $queue = New-Object System.Collections.Queue
        $queue.Enqueue($dash)
        $lists = @()

        while ($queue.Count -gt 0) {
            $ctrl = $queue.Dequeue()
            if ($ctrl -is [System.Windows.Forms.ListView]) { $lists += $ctrl }
            foreach ($child in $ctrl.Controls) { $queue.Enqueue($child) }
        }

        foreach ($list in $lists) {
            if ($list.Columns.Count -ge 7) {
                $list.BeginUpdate()
                $list.Items.Clear()
                foreach ($srv in @($script:Servers | Sort-Object Group,Name)) {
                    $item = New-Object System.Windows.Forms.ListViewItem($srv.Name)
                    [void]$item.SubItems.Add($srv.Address)
                    [void]$item.SubItems.Add($srv.ServiceTag)
                    [void]$item.SubItems.Add($srv.Model)
                    [void]$item.SubItems.Add($srv.OSHostname)
                    [void]$item.SubItems.Add($srv.Health)
                    [void]$item.SubItems.Add($srv.Group)
                    if ($list.Columns.Count -ge 8) {
                        $credText = if (-not [string]::IsNullOrWhiteSpace($srv.Username)) { "Server" } elseif (Get-GroupCredentialRecord -GroupName $srv.Group) { "Group" } else { "Prompt" }
                        [void]$item.SubItems.Add($credText)
                    }
                    [void]$list.Items.Add($item)
                }
                $list.EndUpdate()
            }
        }
    }
    catch {}
}


function Split-iDRACAddressInput {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

    return @(
        $Text -split '[,;`\r`\n]+' |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )
}

function Test-iDRACAddressFast {
    param(
        [Parameter(Mandatory=$true)][string]$Address,
        [int]$TimeoutMs = 1200
    )

    try {
        $hostName = Get-iDRACHost $Address
        $p = New-Object System.Net.NetworkInformation.Ping
        $reply = $p.Send($hostName, $TimeoutMs)
        return ($reply -and $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
    }
    catch {
        return $false
    }
}


function Show-ServerDialog {
    param($Server)

    $isEdit = $null -ne $Server
    $selectedGroup = Get-SelectedGroupName
    if ([string]::IsNullOrWhiteSpace($selectedGroup)) { $selectedGroup = "iDRAC" }
    try {
        if ($Server -and $selectedGroup -eq $Server.Name) { $selectedGroup = $Server.Group }
    }
    catch {}
    if ([string]::IsNullOrWhiteSpace($selectedGroup)) { $selectedGroup = "iDRAC" }

    $f = New-Object System.Windows.Forms.Form
    $f.Text = if ($isEdit) { "Edit iDRAC" } else { "Add iDRAC - Connect and Discover" }
    $f.Width = if ($isEdit) { 520 } else { 720 }
    $f.Height = if ($isEdit) { 560 } else { 620 }
    $f.StartPosition = "CenterParent"
    $f.FormBorderStyle = "FixedDialog"
    $f.Font = $script:AppFont
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false

    if (-not $isEdit) {
        $script:PendingDiscoveredInventory = $null
        $discoveredInventory = $null

        $lblInfo = New-Object System.Windows.Forms.Label
        $lblInfo.Text = "Enter one iDRAC IP/hostname or multiple comma-separated iDRACs, then click Connect. Ping is checked first so offline iDRACs fail fast. After discovery completes, choose an existing group or type a new group, then click Add."
        $lblInfo.Left = 12
        $lblInfo.Top = 12
        $lblInfo.Width = 665
        $lblInfo.Height = 42
        $f.Controls.Add($lblInfo)

        $labels = @("IP / Hostname(s)","Username","Password")
        $boxes = @{}

        for ($i=0; $i -lt $labels.Count; $i++) {
            $lbl = New-Object System.Windows.Forms.Label
            $lbl.Text = $labels[$i]
            $lbl.Left = 12
            $lbl.Top = 65 + ($i * 34)
            $lbl.Width = 105
            $f.Controls.Add($lbl)

            $tb = New-Object System.Windows.Forms.TextBox
            $tb.Left = 125
            $tb.Top = 61 + ($i * 34)
            $tb.Width = 545
            if ($labels[$i] -eq "Password") { $tb.UseSystemPasswordChar = $true }
            $boxes[$labels[$i]] = $tb
            $f.Controls.Add($tb)
        }

        $lblGroup = New-Object System.Windows.Forms.Label
        $lblGroup.Text = "Group"
        $lblGroup.Left = 12
        $lblGroup.Top = 167
        $lblGroup.Width = 105
        $f.Controls.Add($lblGroup)

        $cmbGroup = New-Object System.Windows.Forms.ComboBox
        $cmbGroup.Left = 125
        $cmbGroup.Top = 163
        $cmbGroup.Width = 545
        $cmbGroup.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
        $groups = @($script:Servers | ForEach-Object { $_.Group } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        if ($groups.Count -eq 0) { $groups = @("iDRAC") }
        foreach ($g in $groups) { [void]$cmbGroup.Items.Add($g) }
        $cmbGroup.Text = $selectedGroup
        $f.Controls.Add($cmbGroup)

        $resultBox = New-Object System.Windows.Forms.TextBox
        $resultBox.Left = 12
        $resultBox.Top = 205
        $resultBox.Width = 665
        $resultBox.Height = 235
        $resultBox.Multiline = $true
        $resultBox.ReadOnly = $true
        $resultBox.ScrollBars = "None"
        $resultBox.Text = "Not connected yet."
        $f.Controls.Add($resultBox)

        $status = New-Object System.Windows.Forms.Label
        $status.Left = 12
        $status.Top = 455
        $status.Width = 665
        $status.Height = 22
        $status.Text = "Connect first. Add will enable after discovery and a group is provided."
        $f.Controls.Add($status)

        $connect = New-Object System.Windows.Forms.Button
        $connect.Text = "Connect"
        $connect.Left = 415
        $connect.Top = 505
        $connect.Width = 82

        $add = New-Object System.Windows.Forms.Button
        $add.Text = "Add"
        $add.Left = 505
        $add.Top = 505
        $add.Width = 82
        $add.Enabled = $false
        # Store the discovered inventory directly on the Add button.
        # This is more reliable than relying on PowerShell closure/script scope in WinForms events.
        $add.Tag = $null

        $cancel = New-Object System.Windows.Forms.Button
        $cancel.Text = "Cancel"
        $cancel.Left = 595
        $cancel.Top = 505
        $cancel.Width = 82
        $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

        $enableAdd = {
            $hasDiscovery = ($null -ne $add.Tag)
            $hasGroup = -not [string]::IsNullOrWhiteSpace(($cmbGroup.Text).Trim())
            $add.Enabled = ($hasDiscovery -and $hasGroup)
        }

        $cmbGroup.Add_TextChanged({ & $enableAdd }.GetNewClosure())
        $cmbGroup.Add_SelectedIndexChanged({ & $enableAdd }.GetNewClosure())

        $connect.Add_Click({
            $addresses = @(Split-iDRACAddressInput -Text $boxes["IP / Hostname(s)"].Text)
            if ($addresses.Count -eq 0 -or
                [string]::IsNullOrWhiteSpace($boxes["Username"].Text) -or
                [string]::IsNullOrWhiteSpace($boxes["Password"].Text)) {
                [System.Windows.Forms.MessageBox]::Show("At least one IP/Hostname, Username, and Password are required.","Add iDRAC") | Out-Null
                return
            }

            try {
                $script:PendingDiscoveredInventory = $null
                $discoveredInventory = $null
                $add.Tag = $null
                $f.AcceptButton = $connect
                & $enableAdd
                $connect.Enabled = $false
                $add.Enabled = $false

                $found = New-Object System.Collections.ArrayList
                $log = New-Object System.Text.StringBuilder
                [void]$log.AppendLine("Discovery started: $(Get-Date)")
                [void]$log.AppendLine("Targets: $($addresses -join ', ')")
                [void]$log.AppendLine("")

                $status.Text = "Checking ping before Redfish discovery..."
                $resultBox.Text = "Checking ping..."
                if ($script:Status) { $script:Status.Text = $status.Text }
                [System.Windows.Forms.Application]::DoEvents()

                foreach ($addr in $addresses) {
                    try {
                        $status.Text = "Pinging $addr..."
                        $resultBox.Text = $log.ToString() + "Pinging $addr..."
                        if ($script:Status) { $script:Status.Text = $status.Text }
                        [System.Windows.Forms.Application]::DoEvents()

                        if (-not (Test-iDRACAddressFast -Address $addr)) {
                            [void]$log.AppendLine("FAILED PING: $addr")
                            continue
                        }

                        [void]$log.AppendLine("PING OK: $addr")
                        $status.Text = "Reading Redfish inventory from $addr..."
                        $resultBox.Text = $log.ToString() + "Reading Redfish inventory from $addr..."
                        if ($script:Status) { $script:Status.Text = $status.Text }
                        [System.Windows.Forms.Application]::DoEvents()

                        $inv = Get-iDRACInventory `
                            -Address $addr `
                            -Username $boxes["Username"].Text.Trim() `
                            -Password $boxes["Password"].Text

                        [void]$found.Add($inv)
                        [void]$log.AppendLine("DISCOVERED: $($inv.Name) [$addr]")
                        [void]$log.AppendLine("  Service Tag: $($inv.ServiceTag)")
                        [void]$log.AppendLine("  Model      : $($inv.Model)")
                        [void]$log.AppendLine("  OS Hostname: $($inv.OSHostname)")
                        [void]$log.AppendLine("  Health     : $($inv.Health)")
                        [void]$log.AppendLine("  Power      : $($inv.PowerState)")
                        [void]$log.AppendLine("")
                    }
                    catch {
                        [void]$log.AppendLine("FAILED REDFISH: $addr - $($_.Exception.Message)")
                        [void]$log.AppendLine("")
                    }
                }

                if ($found.Count -eq 0) {
                    $script:PendingDiscoveredInventory = $null
                    $discoveredInventory = $null
                    $add.Tag = $null
                    $f.Tag = $null
                    $status.Text = "No iDRACs discovered."
                    $resultBox.Text = $log.ToString()
                    if ($script:Status) { $script:Status.Text = "Add iDRAC discovery found no reachable iDRACs" }

                    [System.Windows.Forms.MessageBox]::Show(
                        "No iDRACs were discovered.`r`n`r`nOffline systems failed fast at ping. Reachable systems failed Redfish discovery.",
                        "Add iDRAC Failed",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    ) | Out-Null
                    return
                }

                $script:PendingDiscoveredInventory = @($found)
                $discoveredInventory = @($found)
                $add.Tag = @($found)
                $f.Tag = @($found)

                $resultBox.Text = $log.ToString()
                $status.Text = "Discovery complete. $($found.Count) iDRAC(s) ready. Choose or type a group, then click Add."
                if ($script:Status) { $script:Status.Text = "Discovery complete for $($found.Count) iDRAC(s)" }
                & $enableAdd
                if (-not [string]::IsNullOrWhiteSpace(($cmbGroup.Text).Trim())) { $add.Enabled = $true }
                $f.AcceptButton = $add
            }
            catch {
                $script:PendingDiscoveredInventory = $null
                $discoveredInventory = $null
                $add.Tag = $null
                $f.Tag = $null
                $status.Text = "Connection failed."
                $resultBox.Text = "Connection failed.`r`n`r`n$($_.Exception.Message)"
                if ($script:Status) { $script:Status.Text = "Add iDRAC discovery failed" }

                [System.Windows.Forms.MessageBox]::Show(
                    "Could not connect to the iDRAC or read Redfish inventory.`r`n`r`n$($_.Exception.Message)",
                    "Add iDRAC Failed",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                ) | Out-Null
            }
            finally {
                $connect.Enabled = $true
            }
        }.GetNewClosure())

        $add.Add_Click({
            # Use the discovered inventory stored directly on this button. This avoids scope/closure issues
            # when the script is loaded through Invoke-Expression from GitHub.
            $invItems = @($add.Tag)
            if ($invItems.Count -eq 0 -or $null -eq $invItems[0]) { $invItems = @($f.Tag) }
            if ($invItems.Count -eq 0 -or $null -eq $invItems[0]) { $invItems = @($script:PendingDiscoveredInventory) }
            $groupName = $cmbGroup.Text.Trim()

            if ($invItems.Count -eq 0 -or $null -eq $invItems[0]) {
                [System.Windows.Forms.MessageBox]::Show("Click Connect first so the iDRAC can be discovered.","Add iDRAC") | Out-Null
                return
            }

            if ([string]::IsNullOrWhiteSpace($groupName)) {
                [System.Windows.Forms.MessageBox]::Show("Select an existing group or type a new group name.","Add iDRAC") | Out-Null
                return
            }

            $added = New-Object System.Collections.ArrayList
            $skipped = New-Object System.Collections.ArrayList

            foreach ($inv in $invItems) {
                try {
                    $exists = @($script:Servers | Where-Object { $_.Address -eq $inv.Address -or ($_.ServiceTag -and $_.ServiceTag -eq $inv.ServiceTag -and $inv.ServiceTag -ne "Unknown") })
                    if ($exists.Count -gt 0) {
                        $answer = [System.Windows.Forms.MessageBox]::Show(
                            "This iDRAC appears to already exist:`r`n`r`n$($inv.Name) [$($inv.Address)]`r`n`r`nAdd it anyway?",
                            "Possible Duplicate",
                            [System.Windows.Forms.MessageBoxButtons]::YesNo,
                            [System.Windows.Forms.MessageBoxIcon]::Warning
                        )
                        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                            [void]$skipped.Add($inv)
                            continue
                        }
                    }

                    $addedRecord = Add-iDRACServerRecord -Inventory $inv -GroupName $groupName
                    [void]$added.Add($addedRecord)
                    Send-iDRACCManTelemetry -EventName "AddiDRAC" -Properties @{ Group = $addedRecord.Group; Model = $addedRecord.Model; Health = $addedRecord.Health }
                }
                catch {
                    [void]$skipped.Add($inv)
                    try { Add-LogTab -Title "Add iDRAC Failed" -Text "Failed to add $($inv.Name) [$($inv.Address)]`r`n`r`n$($_.Exception.Message)" } catch {}
                }
            }

            if ($script:Status) { $script:Status.Text = "Added $($added.Count) iDRAC(s) to group $groupName. Skipped: $($skipped.Count)" }

            [System.Windows.Forms.MessageBox]::Show(
                "Add complete.`r`n`r`nAdded: $($added.Count)`r`nSkipped: $($skipped.Count)`r`nGroup: $groupName",
                "iDRAC Added",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null

            $script:PendingDiscoveredInventory = $null
            $discoveredInventory = $null
            $add.Tag = $null
            $f.Tag = $null
            $f.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $f.Close()
        }.GetNewClosure())

        $f.AcceptButton = $connect
        $f.CancelButton = $cancel
        $f.Controls.Add($connect)
        $f.Controls.Add($add)
        $f.Controls.Add($cancel)
        [void]$f.ShowDialog($script:MainForm)
        return
    }

    $labels = @("Name","Address/IP","Group","Username","Password","Service Tag","Model","OS Hostname","Health","Power State","Notes")
    $boxes = @{}

    for ($i=0; $i -lt $labels.Count; $i++) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $labels[$i]
        $lbl.Left = 12
        $lbl.Top = 18 + ($i * 32)
        $lbl.Width = 100
        $f.Controls.Add($lbl)

        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Left = 120
        $tb.Top = 14 + ($i * 32)
        $tb.Width = 350

        if ($labels[$i] -eq "Password") { $tb.UseSystemPasswordChar = $true }
        if ($labels[$i] -in @("Service Tag","Model","OS Hostname","Health","Power State")) { $tb.ReadOnly = $true }
        if ($labels[$i] -eq "Notes") { $tb.Multiline = $true; $tb.Height = 45 } else { $tb.Height = 23 }

        $boxes[$labels[$i]] = $tb
        $f.Controls.Add($tb)
    }

    $boxes["Name"].Text = $Server.Name
    $boxes["Address/IP"].Text = $Server.Address
    $boxes["Group"].Text = $Server.Group
    $boxes["Username"].Text = $Server.Username
    $boxes["Password"].Text = ConvertFrom-ProtectedString $Server.Password
    $boxes["Service Tag"].Text = $Server.ServiceTag
    $boxes["Model"].Text = $Server.Model
    $boxes["OS Hostname"].Text = $Server.OSHostname
    $boxes["Health"].Text = $Server.Health
    $boxes["Power State"].Text = $Server.PowerState
    $boxes["Notes"].Text = $Server.Notes

    $refresh = New-Object System.Windows.Forms.Button
    $refresh.Text = "Refresh Info"
    $refresh.Left = 190
    $refresh.Top = 450
    $refresh.Width = 100
    $refresh.Add_Click({
        try {
            $Server.Address = $boxes["Address/IP"].Text.Trim()
            $Server.Username = $boxes["Username"].Text.Trim()
            $Server.Password = ConvertTo-ProtectedString $boxes["Password"].Text

            $inv = Update-iDRACInventoryForServer -Server $Server
            $boxes["Name"].Text = $Server.Name
            $boxes["Service Tag"].Text = $inv.ServiceTag
            $boxes["Model"].Text = $inv.Model
            $boxes["OS Hostname"].Text = $inv.OSHostname
            $boxes["Health"].Text = $inv.Health
            $boxes["Power State"].Text = $inv.PowerState
            Update-DashboardServerList

            [System.Windows.Forms.MessageBox]::Show("Inventory refreshed.","iDRAC") | Out-Null
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Refresh failed.`r`n`r`n$($_.Exception.Message)","iDRAC Refresh Failed") | Out-Null
        }
    }.GetNewClosure())

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "Save"
    $ok.Left = 305
    $ok.Top = 450
    $ok.Width = 75
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancel"
    $cancel.Left = 395
    $cancel.Top = 450
    $cancel.Width = 75
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $f.AcceptButton = $ok
    $f.CancelButton = $cancel
    $f.Controls.Add($refresh)
    $f.Controls.Add($ok)
    $f.Controls.Add($cancel)

    if ($f.ShowDialog($script:MainForm) -eq [System.Windows.Forms.DialogResult]::OK) {
        if ([string]::IsNullOrWhiteSpace($boxes["Name"].Text) -or [string]::IsNullOrWhiteSpace($boxes["Address/IP"].Text)) {
            [System.Windows.Forms.MessageBox]::Show("Name and Address/IP are required.") | Out-Null
            return
        }

        $Server.Name = $boxes["Name"].Text.Trim()
        $Server.Address = $boxes["Address/IP"].Text.Trim()
        $Server.Group = $boxes["Group"].Text.Trim()
        $Server.Username = $boxes["Username"].Text.Trim()
        $Server.Password = ConvertTo-ProtectedString $boxes["Password"].Text
        $Server.Notes = $boxes["Notes"].Text

        Save-Servers
        Refresh-Tree
        Update-DashboardServerList
    }
}

function Add-LogTab {
    param([string]$Title, [string]$Text)

    $tab = New-Object System.Windows.Forms.TabPage
    $tab.Text = $Title

    $box = New-Object System.Windows.Forms.TextBox
    $box.Dock = "Fill"
    $box.Multiline = $true
    $box.ScrollBars = "Both"
    $box.Font = New-Object System.Drawing.Font("Consolas", 10)
    $box.ReadOnly = $true
    $box.WordWrap = $false
    $box.Text = $Text

    $tab.Controls.Add($box)
    [void]$script:Tabs.TabPages.Add($tab)
    $script:Tabs.SelectedTab = $tab
}

function Wait-WebViewReady {
    param($Web)

    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($null -eq $Web.CoreWebView2 -and $sw.Elapsed.TotalSeconds -lt 30) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
    }

    return ($null -ne $Web.CoreWebView2)
}


function Initialize-iDRACWebViewControl {
    param(
        [Parameter(Mandatory=$true)]$Web,
        [Parameter(Mandatory=$true)][string]$Url
    )

    $Web.CreationProperties = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
    $Web.CreationProperties.UserDataFolder = $script:WebDataRoot

    $null = $Web.EnsureCoreWebView2Async($script:WebViewEnvironment)

    if (-not (Wait-WebViewReady -Web $Web)) {
        throw "Timed out waiting for CoreWebView2."
    }

    $Web.CoreWebView2.Settings.AreDefaultContextMenusEnabled = $true
    $Web.CoreWebView2.Settings.AreDevToolsEnabled = $true
    $Web.CoreWebView2.Settings.IsScriptEnabled = $true

    $Web.CoreWebView2.add_ServerCertificateErrorDetected({
        param($sender, $args)
        try {
            $args.Action = [Microsoft.Web.WebView2.Core.CoreWebView2ServerCertificateErrorAction]::AlwaysAllow
        }
        catch {}
    })

    $Web.CoreWebView2.Navigate($Url)
}



function ConvertTo-JavaScriptStringLiteral {
    param([string]$Text)

    if ($null -eq $Text) { $Text = "" }
    return ($Text | ConvertTo-Json -Compress)
}

function Get-iDRACCredentialForBrowserLogin {
    param([Parameter(Mandatory=$true)]$Server)

    try {
        $candidates = @(Get-iDRACCredentialCandidates -Server $Server)
        if ($candidates.Count -gt 0) {
            return $candidates[0].Credential
        }
    }
    catch {}

    try {
        return Get-iDRACCredentialFromServer -Server $Server
    }
    catch {
        return $null
    }
}

function Set-ClipboardTextSafely {
    param([string]$Text)

    try {
        if ($null -eq $Text) { $Text = "" }
        [System.Windows.Forms.Clipboard]::SetText($Text)
        return $true
    }
    catch {
        return $false
    }
}


function New-iDRACGuiAutoLoginJavaScript {
    param([Parameter(Mandatory=$true)]$Server)

    $cred = Get-iDRACCredentialForBrowserLogin -Server $Server
    if (-not $cred) { return "" }

    $nc = $cred.GetNetworkCredential()
    $userName = $nc.UserName
    $password = $nc.Password

    if ([string]::IsNullOrWhiteSpace($userName) -or [string]::IsNullOrWhiteSpace($password)) { return "" }

    $userJson = ConvertTo-JavaScriptStringLiteral $userName
    $passJson = ConvertTo-JavaScriptStringLiteral $password

    return @"
(function(){
  try {
    // iDRAC10 is an Angular hash-route app.  At first load the URL can briefly be
    // /restgui/index.html before the #/login route and fields exist.  Older builds
    // saw that and stopped before typing.  This build waits for the actual fields.
    if (window.__idracCManAutoLoginTimer) {
      try { clearInterval(window.__idracCManAutoLoginTimer); } catch(e) {}
      window.__idracCManAutoLoginTimer = null;
    }

    window.__idracCManAutoLoginInstalled = true;
    window.__idracCManLoginSubmitted = false;
    window.__idracCManLoginState = 'installed-waiting-for-fields url=' + location.href;

    var USER = $userJson;
    var PASS = $passJson;
    var attempts = 0;

    function q(sel){ try { return document.querySelector(sel); } catch(e) { return null; } }
    function qa(sel){ try { return Array.prototype.slice.call(document.querySelectorAll(sel)); } catch(e) { return []; } }

    function visible(el){
      try {
        if (!el || el.disabled) { return false; }
        var r = el.getBoundingClientRect();
        var s = getComputedStyle(el);
        return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden';
      } catch(e) { return false; }
    }

    function fire(el, type, opts){
      try {
        var ev;
        opts = opts || {};
        if (type === 'input') {
          try { ev = new InputEvent('input', Object.assign({bubbles:true,cancelable:true,composed:true,inputType:'insertText'}, opts)); }
          catch(x) { ev = new Event('input', {bubbles:true,cancelable:true,composed:true}); }
        }
        else if (type.indexOf('key') === 0) {
          ev = new KeyboardEvent(type, Object.assign({bubbles:true,cancelable:true,composed:true}, opts));
        }
        else {
          ev = new Event(type, {bubbles:true,cancelable:true,composed:true});
        }
        el.dispatchEvent(ev);
      } catch(e) {}
    }

    function nativeSet(el, value){
      try {
        var proto = Object.getPrototypeOf(el);
        var desc = Object.getOwnPropertyDescriptor(proto, 'value') || Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
        if (desc && desc.set) { desc.set.call(el, value); }
        else { el.value = value; }
      } catch(e) {
        try { el.value = value; } catch(x) {}
      }
    }

    function userField(){
      return q('input[name="username"]') || q('#clr-form-control-1') || qa('input').filter(function(x){ return (x.type || '').toLowerCase() === 'text'; })[0] || null;
    }

    function passField(){
      var p = q('input[name="password"]') || q('#clr-form-control-2');
      if (p) { return p; }
      var visiblePass = qa('input[type="password"]').filter(function(x){
        try {
          var r = x.getBoundingClientRect();
          var s = getComputedStyle(x);
          return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden';
        } catch(e) { return false; }
      })[0];
      return visiblePass || q('input[type="password"]');
    }

    function loginButton(){
      return q('button.btn-login') || q('button[type="submit"]') || qa('button').filter(function(b){ return /log\s*in|login|sign\s*in/i.test((b.innerText || b.textContent || '')); })[0] || null;
    }

    function fillField(el, value){
      try {
        if (!el) { return false; }
        try { el.scrollIntoView({block:'center', inline:'center'}); } catch(e) {}
        // iDRAC9 / 16G often leaves the visible password box readonly until Angular sees username input.
        // Force it writable before setting the password.
        try { el.readOnly = false; el.removeAttribute('readonly'); } catch(e) {}
        try { el.disabled = false; el.removeAttribute('disabled'); } catch(e) {}
        try { el.focus(); } catch(e) {}
        try { el.click(); } catch(e) {}
        fire(el,'focus');

        // Clear then set using the native setter so Angular/Clarity sees an actual input update.
        nativeSet(el, '');
        fire(el,'input',{data:null,inputType:'deleteContentBackward'});
        fire(el,'change');

        nativeSet(el, value);
        fire(el,'keydown',{key:'a',code:'KeyA',keyCode:65,which:65});
        fire(el,'beforeinput',{data:value,inputType:'insertText'});
        fire(el,'input',{data:value,inputType:'insertText'});
        fire(el,'keyup',{key:'a',code:'KeyA',keyCode:65,which:65});
        fire(el,'change');

        // Some iDRAC10 builds only enable Log In after key events/blur.
        fire(el,'keydown',{key:'Tab',code:'Tab',keyCode:9,which:9});
        fire(el,'keyup',{key:'Tab',code:'Tab',keyCode:9,which:9});
        try { el.blur(); } catch(e) {}
        fire(el,'blur');
        return ((el.value || '') === value);
      } catch(e) { return false; }
    }

    function enableAndSubmit(btn, pass){
      try {
        if (btn) {
          btn.disabled = false;
          btn.removeAttribute('disabled');
          btn.classList.remove('disabled');
          btn.setAttribute('aria-disabled','false');
          fire(btn,'mouseover');
          fire(btn,'mousedown');
          fire(btn,'mouseup');
          btn.click();
          return 'clicked';
        }
        if (pass) {
          pass.focus();
          fire(pass,'keydown',{key:'Enter',code:'Enter',keyCode:13,which:13});
          fire(pass,'keypress',{key:'Enter',code:'Enter',keyCode:13,which:13});
          fire(pass,'keyup',{key:'Enter',code:'Enter',keyCode:13,which:13});
          return 'enter';
        }
      } catch(e) { return 'submit-error=' + e.message; }
      return 'no-submit-target';
    }

    function tick(){
      try {
        attempts++;
        var u = userField();
        var p = passField();
        var b = loginButton();

        if (!visible(u) || !visible(p)) {
          window.__idracCManLoginState = 'waiting-for-visible-fields attempt=' + attempts + ' url=' + location.href + ' inputCount=' + qa('input').length + ' userVisible=' + visible(u) + ' passVisible=' + visible(p) + ' passReadonly=' + (p ? p.readOnly : 'none');
          if (attempts > 120) { clearInterval(window.__idracCManAutoLoginTimer); }
          return;
        }

        var uok = fillField(u, USER);
        // Re-find password after username events because iDRAC9 may swap/enable the password control.
        p = passField();
        try { if (p) { p.readOnly = false; p.removeAttribute('readonly'); } } catch(e) {}
        var pok = fillField(p, PASS);
        var ulen = (u.value || '').length;
        var plen = (p.value || '').length;
        var disabled = b ? !!b.disabled : null;
        window.__idracCManLoginState = 'filled attempt=' + attempts + ' uok=' + uok + ' pok=' + pok + ' ulen=' + ulen + ' plen=' + plen + ' buttonDisabled=' + disabled + ' url=' + location.href;

        if (ulen > 0 && plen > 0) {
          window.__idracCManLoginSubmitted = true;
          clearInterval(window.__idracCManAutoLoginTimer);
          setTimeout(function(){
            var b2 = loginButton();
            var p2 = passField();
            var result = enableAndSubmit(b2, p2);
            window.__idracCManLoginState = 'submitted result=' + result + ' url=' + location.href;
          }, 350);
          return;
        }

        if (attempts > 120) {
          window.__idracCManLoginState = 'gave-up ' + window.__idracCManLoginState;
          clearInterval(window.__idracCManAutoLoginTimer);
        }
      } catch(e) {
        window.__idracCManLoginState = 'tick-error=' + e.message;
      }
    }

    tick();
    window.__idracCManAutoLoginTimer = setInterval(tick, 700);
    return 'installed';
  } catch(e) {
    window.__idracCManLoginState = 'install-error=' + e.message;
    return window.__idracCManLoginState;
  }
})();
"@
}

function Invoke-WebView2iDRACAutoLogin {
    param(
        [Parameter(Mandatory=$true)]$Web,
        [Parameter(Mandatory=$true)]$Server
    )

    try {
        if (-not $Web -or -not $Web.CoreWebView2 -or -not $Server) { return }

        $js = New-iDRACGuiAutoLoginJavaScript -Server $Server
        if ([string]::IsNullOrWhiteSpace($js)) {
            if ($script:Status) { $script:Status.Text = "GUI Auto Login skipped for $($Server.Name): no usable saved credentials." }
            return
        }

        [void]$Web.CoreWebView2.ExecuteScriptAsync($js)
        if ($script:Status) { $script:Status.Text = "GUI Auto Login attempted for $($Server.Name)" }
    }
    catch {
        try { Write-iDRACCManLog "GUI Auto Login failed for $($Server.Name): $($_.Exception.Message)" "WARN" } catch {}
    }
}

function Invoke-WebView2AdvancedContinue {
    param(
        [Parameter(Mandatory=$true)]$Web
    )

    try {
        if (-not $Web -or -not $Web.CoreWebView2) { return }

        # Edge/Chromium SSL interstitial uses details-button and proceed-link.
        # Run this a few times because the privacy page can finish rendering after NavigationCompleted.
        $js = @"
(function() {
    function clickBypass() {
        try {
            var advanced = document.getElementById('details-button') || document.querySelector('button[id="details-button"]');
            if (advanced) { advanced.click(); }

            setTimeout(function() {
                try {
                    var proceed = document.getElementById('proceed-link') || document.querySelector('a[id="proceed-link"]');
                    if (proceed) { proceed.click(); }
                } catch(e) {}
            }, 350);
        } catch(e) {}
    }

    clickBypass();
    setTimeout(clickBypass, 750);
    setTimeout(clickBypass, 1500);
    setTimeout(clickBypass, 2500);
    return 'advanced-continue-attempted';
})();
"@

        [void]$Web.CoreWebView2.ExecuteScriptAsync($js)
    }
    catch {}
}



function Start-WebView2GuiAutomationTimer {
    param(
        [Parameter(Mandatory=$true)]$Web,
        [Parameter(Mandatory=$false)]$Server,
        [Parameter(Mandatory=$true)]$AutoContinueCheckBox,
        [Parameter(Mandatory=$false)]$AutoLoginCheckBox,
        [bool]$IsKvm = $false
    )

    try {
        if (-not $Web -or -not $Web.CoreWebView2) { return }

        $tickCount = 0
        $loginAttempted = $false
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 1000
        $timer.Add_Tick({
            try {
                $tickCount++

                # Do not let the status bar stay on Loading forever while WebView2 is sitting
                # on the Chromium SSL privacy interstitial or while an iDRAC page does slow rendering.
                if ($script:Status -and $tickCount -ge 3) {
                    if ($script:Status.Text -like 'Loading*') {
                        $script:Status.Text = "Waiting for $($Server.Name)... Auto Continue active."
                    }
                }

                if ($AutoContinueCheckBox -and $AutoContinueCheckBox.Checked) {
                    Invoke-WebView2AdvancedContinue -Web $Web
                }

                # For GUI tabs, Auto Continue must get past the certificate page first.
                # Auto Login is fire-and-forget, so it is safe to retry without freezing WebView2.
                if (-not $IsKvm -and $AutoLoginCheckBox -and $AutoLoginCheckBox.Checked -and $tickCount -ge 5 -and (($tickCount % 2) -eq 1)) {
                    if ($Server) { Invoke-WebView2iDRACAutoLogin -Web $Web -Server $Server }
                }

                if ($tickCount -ge 45) {
                    $timer.Stop()
                    $timer.Dispose()
                    if ($script:Status -and $script:Status.Text -like 'Loading*') {
                        $script:Status.Text = "Opened $($Server.Name)."
                    }
                }
            }
            catch {
                try {
                    if ($tickCount -ge 18) {
                        $timer.Stop()
                        $timer.Dispose()
                    }
                }
                catch {}
            }
        }.GetNewClosure())

        $timer.Start()
    }
    catch {}
}


function Split-SetCookieHeaderValue {
    param($HeaderValue)

    $items = @()
    if (-not $HeaderValue) { return @() }

    foreach ($raw in @($HeaderValue)) {
        if ([string]::IsNullOrWhiteSpace([string]$raw)) { continue }

        $text = [string]$raw
        # Some PowerShell versions collapse multiple Set-Cookie headers into one comma-delimited string.
        # Split only on commas that look like the start of another cookie name=value pair.
        $parts = [regex]::Split($text, ',\s*(?=[^;,\s]+=)')
        foreach ($part in $parts) {
            if (-not [string]::IsNullOrWhiteSpace($part)) { $items += $part.Trim() }
        }
    }

    return @($items)
}

function New-iDRACGuiWebSession {
    param([Parameter(Mandatory=$true)]$Server)

    $hostName = Get-iDRACHost $Server.Address
    $base = "https://$hostName"
    $candidates = @(Get-iDRACCredentialCandidates -Server $Server -AllowPrompt)
    $lastError = $null

    foreach ($candidate in $candidates) {
        try {
            $nc = $candidate.Credential.GetNetworkCredential()
            if ([string]::IsNullOrWhiteSpace($nc.UserName) -or [string]::IsNullOrWhiteSpace($nc.Password)) { continue }

            $bodies = @(
                (@{ UserName = $nc.UserName; Password = $nc.Password } | ConvertTo-Json -Compress),
                (@{ username = $nc.UserName; password = $nc.Password } | ConvertTo-Json -Compress)
            )

            foreach ($body in $bodies) {
                try {
                    Enable-IgnoreSslCertificatePolicy
                    $params = @{
                        Uri = "$base/sysmgmt/2015/bmc/session"
                        Method = "POST"
                        Body = $body
                        ContentType = "application/json"
                        UseBasicParsing = $true
                        ErrorAction = "Stop"
                        TimeoutSec = 12
                        Headers = @{
                            "Accept" = "application/json, text/plain, */*"
                            "X-Requested-With" = "XMLHttpRequest"
                            "Origin" = $base
                            "Referer" = "$base/"
                        }
                    }
                    if ($PSVersionTable.PSVersion.Major -ge 6) {
                        $params.SkipCertificateCheck = $true
                        $params.SkipHeaderValidation = $true
                    }

                    $resp = Invoke-WebRequest @params
                    $setCookies = @()
                    try { $setCookies = @(Split-SetCookieHeaderValue $resp.Headers['Set-Cookie']) } catch {}

                    if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) {
                        return [pscustomobject]@{
                            BaseUrl = $base
                            Host = $hostName
                            CredentialSource = $candidate.Source
                            SetCookies = $setCookies
                            RawResponse = $resp.Content
                        }
                    }
                }
                catch {
                    $lastError = $_.Exception.Message
                }
            }
        }
        catch {
            $lastError = $_.Exception.Message
        }
    }

    if ($lastError) { throw "GUI session login failed. Last error: $lastError" }
    throw "GUI session login failed. No usable credentials were available."
}

function Add-iDRACGuiSessionCookiesToWebView2 {
    param(
        [Parameter(Mandatory=$true)]$Web,
        [Parameter(Mandatory=$true)]$Session
    )

    try {
        if (-not $Web -or -not $Web.CoreWebView2 -or -not $Session) { return $false }
        $mgr = $Web.CoreWebView2.CookieManager
        if (-not $mgr) { return $false }

        $added = 0
        foreach ($cookieText in @($Session.SetCookies)) {
            try {
                if ([string]::IsNullOrWhiteSpace($cookieText)) { continue }
                $first = ($cookieText -split ';', 2)[0]
                if ($first -notmatch '=') { continue }
                $name = ($first -split '=', 2)[0].Trim()
                $value = ($first -split '=', 2)[1]
                if ([string]::IsNullOrWhiteSpace($name)) { continue }

                $path = "/"
                $domain = $Session.Host
                foreach ($attr in ($cookieText -split ';')) {
                    $a = $attr.Trim()
                    if ($a -match '^path=(.+)$') { $path = $Matches[1] }
                    elseif ($a -match '^domain=(.+)$') { $domain = $Matches[1].TrimStart('.') }
                }

                $cookie = $mgr.CreateCookie($name, $value, $domain, $path)
                try { $cookie.IsSecure = $true } catch {}
                try { if ($cookieText -match '(?i)httponly') { $cookie.IsHttpOnly = $true } } catch {}
                $mgr.AddOrUpdateCookie($cookie)
                $added++
            }
            catch {}
        }

        return ($added -gt 0)
    }
    catch {
        return $false
    }
}

function Open-iDRACGuiWithSessionLogin {
    param(
        [Parameter(Mandatory=$true)]$Web,
        [Parameter(Mandatory=$true)]$Server,
        [Parameter(Mandatory=$true)][string]$Url
    )

    try {
        if (-not $Web -or -not $Web.CoreWebView2 -or -not $Server) { return $false }

        if ($script:Status) { $script:Status.Text = "Creating GUI web session for $($Server.Name)..." }
        [System.Windows.Forms.Application]::DoEvents()

        $session = New-iDRACGuiWebSession -Server $Server
        $cookiesAdded = Add-iDRACGuiSessionCookiesToWebView2 -Web $Web -Session $session

        if ($cookiesAdded) {
            if ($script:Status) { $script:Status.Text = "GUI session created for $($Server.Name) using $($session.CredentialSource) credentials." }
            $Web.CoreWebView2.Navigate($Url)
            return $true
        }
        else {
            if ($script:Status) { $script:Status.Text = "GUI session created but no cookies were returned for $($Server.Name)." }
            return $false
        }
    }
    catch {
        if ($script:Status) { $script:Status.Text = "GUI session login failed for $($Server.Name). Falling back to normal GUI." }
        Write-iDRACCManLog "GUI session login failed for $($Server.Name): $($_.Exception.Message)" "WARN"
        return $false
    }
}


function Show-WebView2GuiLoginDebug {
    param(
        $Web,
        $Server
    )

    try {
        if (-not $Server) {
            try {
                if ($script:Tabs -and $script:Tabs.SelectedTab -and $script:Tabs.SelectedTab.Tag) {
                    $Server = $script:Tabs.SelectedTab.Tag.Server
                }
            } catch {}
        }

        if (-not $Web) {
            try {
                if ($script:Tabs -and $script:Tabs.SelectedTab -and $script:Tabs.SelectedTab.Tag) {
                    $Web = $script:Tabs.SelectedTab.Tag.WebView
                }
            } catch {}
        }

        if (-not $Web -or -not $Web.CoreWebView2) {
            Add-LogTab -Title "GUI Login Debug Failed" -Text "No active WebView2 control was found for the selected tab. Close this GUI tab, reopen it, then click Login Debug again after the page starts loading."
            if ($script:Status) { $script:Status.Text = "GUI login debug failed: WebView2 was not found." }
            return
        }

        if (-not $Server) {
            $Server = [pscustomobject]@{ Name = "Unknown"; Address = "Unknown" }
        }

        $js = @"
(function() {
    function safeText(v) { try { return (v || '').toString().replace(/\s+/g,' ').trim().substring(0,160); } catch(e) { return ''; } }
    function visible(el) {
        try {
            var r = el.getBoundingClientRect();
            var s = window.getComputedStyle(el);
            return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden';
        } catch(e) { return false; }
    }
    function describe(el) {
        try {
            return {
                tag: (el.tagName || '').toLowerCase(),
                type: el.type || '',
                id: el.id || '',
                name: el.name || '',
                className: el.className || '',
                placeholder: el.placeholder || '',
                autocomplete: el.autocomplete || '',
                aria: el.getAttribute('aria-label') || '',
                text: safeText(el.innerText || el.value || ''),
                visible: visible(el),
                disabled: !!el.disabled,
                readonly: !!el.readOnly
            };
        } catch(e) { return { error: e.toString() }; }
    }
    var inputs = [];
    var buttons = [];
    var frames = [];
    try { document.querySelectorAll('input,textarea').forEach(function(x){ inputs.push(describe(x)); }); } catch(e) {}
    try { document.querySelectorAll('button,a,input[type=submit],input[type=button]').forEach(function(x){ buttons.push(describe(x)); }); } catch(e) {}
    try { document.querySelectorAll('iframe,frame').forEach(function(x){ frames.push({src:x.src||'', id:x.id||'', name:x.name||'', visible:visible(x)}); }); } catch(e) {}
    return JSON.stringify({
        href: location.href,
        title: document.title,
        readyState: document.readyState,
        autoLoginInstalled: !!window.__idracCManAutoLoginInstalled,
        autoLoginState: window.__idracCManLoginState || '',
        autoLoginSubmitted: !!window.__idracCManLoginSubmitted,
        bodyTextSample: safeText(document.body ? document.body.innerText : ''),
        inputCount: inputs.length,
        buttonCount: buttons.length,
        frameCount: frames.length,
        inputs: inputs,
        buttons: buttons,
        frames: frames
    }, null, 2);
})();
"@

        if ($script:Status) { $script:Status.Text = "Collecting GUI login debug for $($Server.Name)..." }

        # Do NOT wait synchronously on ExecuteScriptAsync from the WinForms UI thread.
        # Waiting with GetResult() can deadlock/hang WebView2. Poll the task with a timer instead.
        $task = $Web.CoreWebView2.ExecuteScriptAsync($js)
        $started = Get-Date
        $debugServer = $Server
        $debugWeb = $Web
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 250
        $timer.Add_Tick({
            try {
                if ($task.IsCompleted) {
                    $timer.Stop()
                    $timer.Dispose()

                    if ($task.IsFaulted) {
                        $err = $task.Exception.InnerException.Message
                        if ([string]::IsNullOrWhiteSpace($err)) { $err = $task.Exception.Message }
                        Add-LogTab -Title "$($debugServer.Name) Login Debug Failed" -Text "ExecuteScriptAsync failed.`r`n`r`n$err"
                        if ($script:Status) { $script:Status.Text = "GUI login debug failed for $($debugServer.Name)" }
                        return
                    }

                    $raw = $task.GetAwaiter().GetResult()
                    $decoded = $raw
                    try { $decoded = $raw | ConvertFrom-Json } catch {}

                    if ($decoded -isnot [string]) {
                        try { $decoded = $decoded | ConvertTo-Json -Depth 25 } catch { $decoded = [string]$decoded }
                    }

                    $text = "GUI Login Debug for $($debugServer.Name)`r`nAddress: $($debugServer.Address)`r`nTime: $(Get-Date)`r`nCurrent URL: $($debugWeb.Source)`r`n`r`n$decoded"
                    Add-LogTab -Title "$($debugServer.Name) Login Debug" -Text $text
                    if ($script:Status) { $script:Status.Text = "GUI login debug captured for $($debugServer.Name)" }
                    return
                }

                if (((Get-Date) - $started).TotalSeconds -gt 12) {
                    $timer.Stop()
                    $timer.Dispose()
                    $text = "GUI Login Debug timed out waiting for WebView2 script execution.`r`n`r`nServer: $($debugServer.Name)`r`nAddress: $($debugServer.Address)`r`nCurrent URL: $($debugWeb.Source)`r`nTime: $(Get-Date)`r`n`r`nThis usually means the page is still on a browser/security/interstitial page or WebView2 is busy. Try clicking Login Debug after the visible login page fully appears."
                    Add-LogTab -Title "$($debugServer.Name) Login Debug Timeout" -Text $text
                    if ($script:Status) { $script:Status.Text = "GUI login debug timed out for $($debugServer.Name)" }
                    return
                }
            }
            catch {
                try { $timer.Stop(); $timer.Dispose() } catch {}
                Add-LogTab -Title "$($debugServer.Name) Login Debug Failed" -Text $_.Exception.Message
                if ($script:Status) { $script:Status.Text = "GUI login debug failed for $($debugServer.Name)" }
            }
        }.GetNewClosure())
        $timer.Start()
    }
    catch {
        Add-LogTab -Title "$($Server.Name) Login Debug Failed" -Text $_.Exception.Message
        if ($script:Status) { $script:Status.Text = "GUI login debug failed." }
    }
}


function New-WebView2IsolatedEnvironment {
    param(
        [string]$ServerName,
        [switch]$IsKvm
    )

    # KVM temp sessions and normal GUI sessions cannot safely share the same
    # WebView2 browser profile.  If they share cookies/local storage, opening GUI
    # from a console tab can authenticate and then immediately hit RAC0508/log out.
    # Give each GUI/KVM tab its own small profile under Documents\iDRACCMan\WebView2UserData.
    $mode = if ($IsKvm) { "KVM" } else { "GUI" }
    $safeName = if ([string]::IsNullOrWhiteSpace($ServerName)) { "iDRAC" } else { $ServerName }
    $safeName = ($safeName -replace '[^a-zA-Z0-9_.-]', '_')
    if ($safeName.Length -gt 50) { $safeName = $safeName.Substring(0,50) }

    $folderName = "{0}_{1}_{2}" -f $mode, $safeName, ([DateTime]::Now.ToString('yyyyMMddHHmmssfff'))
    $folder = Join-Path $script:WebDataRoot $folderName
    New-Item -ItemType Directory -Path $folder -Force | Out-Null

    $env = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $folder).GetAwaiter().GetResult()

    return [pscustomobject]@{
        Environment = $env
        UserDataFolder = $folder
    }
}

function Add-WebViewTab {
    param(
        [Parameter(Mandatory=$true)]$Server,
        [Parameter(Mandatory=$true)][string]$Url,
        [switch]$IsKvm,
        [Parameter(Mandatory=$false)][string]$TabTitle,
        [Parameter(Mandatory=$false)][string]$HeaderMessage
    )

    if (-not $script:WebViewReady) {
        [System.Windows.Forms.MessageBox]::Show(
            "WebView2 is not ready.`r`n`r`nInstall WebView2 Runtime or restart the script.",
            "WebView2 Not Ready"
        ) | Out-Null
        return
    }

    $tab = New-Object System.Windows.Forms.TabPage
    $tab.Text = if ([string]::IsNullOrWhiteSpace($TabTitle)) { $Server.Name } else { $TabTitle }

    $outer = New-Object System.Windows.Forms.Panel
    $outer.Dock = "Fill"

    $bar = New-Object System.Windows.Forms.Panel
    $bar.Dock = "Top"
    $bar.Height = 38

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Left = 4
    $btnClose.Top = 4
    $btnClose.Width = 78
    $btnClose.Height = 28
    $btnClose.Add_Click({ Close-CurrentTab })


    $btnKvm = New-Object System.Windows.Forms.Button
    $btnKvm.Text = "GUI"
    $btnKvm.Left = 82
    $btnKvm.Top = 4
    $btnKvm.Width = 60
    $btnKvm.Height = 28
    $btnKvm.Add_Click({
        try {
            $targetServer = $null

            # When this button is clicked from a KVM tab, do not trust the PowerShell
            # closure variable. In PowerShell ISE / Invoke-Expression it can be null.
            # Always recover the server from the selected tab first.
            try {
                if ($script:Tabs -and $script:Tabs.SelectedTab -and $script:Tabs.SelectedTab.Tag -and $script:Tabs.SelectedTab.Tag.Server) {
                    $targetServer = $script:Tabs.SelectedTab.Tag.Server
                }
            } catch {}

            if (-not $targetServer) { $targetServer = $Server }

            if (-not $targetServer) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Could not determine which iDRAC this tab belongs to.",
                    "Open GUI",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) | Out-Null
                return
            }

            Add-WebViewTab -Server $targetServer -Url (Get-iDRACBaseUrl $targetServer.Address)
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Unable to open GUI from this console tab.`r`n`r`n$($_.Exception.Message)",
                "Open GUI Failed",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    }.GetNewClosure())

    $autoContinueSettingName = if ($IsKvm) { "AutoContinueConsole" } else { "AutoContinueGui" }

    $chkAutoContinue = New-Object System.Windows.Forms.CheckBox
    $chkAutoContinue.Text = "Auto Continue"
    $chkAutoContinue.Left = if ($IsKvm) { 150 } else { 195 }
    $chkAutoContinue.Top = 9
    $chkAutoContinue.Width = 120
    $chkAutoContinue.Height = 22
    $chkAutoContinue.Checked = [bool](Get-iDRACCManSetting -Name $autoContinueSettingName -Default $true)
    $chkAutoContinue.Add_CheckedChanged({
        try {
            Set-iDRACCManSetting -Name $autoContinueSettingName -Value ([bool]$chkAutoContinue.Checked)
            if ($chkAutoContinue.Checked -and $web -and $web.CoreWebView2) {
                Invoke-WebView2AdvancedContinue -Web $web
            }
        }
        catch {}
    }.GetNewClosure())

    $chkAutoLogin = New-Object System.Windows.Forms.CheckBox
    $chkAutoLogin.Text = "Auto Login"
    $chkAutoLogin.Left = 85
    $chkAutoLogin.Top = 9
    $chkAutoLogin.Width = 105
    $chkAutoLogin.Height = 22
    $chkAutoLogin.Checked = [bool](Get-iDRACCManSetting -Name "AutoLoginGui" -Default $true)
    $chkAutoLogin.Add_CheckedChanged({
        try {
            Set-iDRACCManSetting -Name "AutoLoginGui" -Value ([bool]$chkAutoLogin.Checked)
            if ($chkAutoLogin.Checked -and $web -and $web.CoreWebView2) {
                $loginServer = $Server
                try {
                    if (-not $loginServer -and $script:Tabs -and $script:Tabs.SelectedTab -and $script:Tabs.SelectedTab.Tag -and $script:Tabs.SelectedTab.Tag.Server) {
                        $loginServer = $script:Tabs.SelectedTab.Tag.Server
                    }
                } catch {}
                if ($loginServer) { Invoke-WebView2iDRACAutoLogin -Web $web -Server $loginServer }
            }
        }
        catch {}
    }.GetNewClosure())
$info = New-Object System.Windows.Forms.Label
    $info.Left = if ($IsKvm) { 275 } else { 320 }
    $info.Top = 10
    $info.Width = 1200
    $info.Height = 22
    $info.Text = if (-not [string]::IsNullOrWhiteSpace($HeaderMessage)) {
        $HeaderMessage
    }
    elseif ($IsKvm) {
        ""
    }
    else {
        ""
    }

    if ($IsKvm) {
        $bar.Controls.AddRange(@($btnClose,$btnKvm,$chkAutoContinue,$info))
    }
    else {
        $bar.Controls.AddRange(@($btnClose,$chkAutoLogin,$chkAutoContinue,$info))
    }

    $web = New-Object Microsoft.Web.WebView2.WinForms.WebView2
    $web.Dock = "Fill"

    $isolatedWebView = $null
    try {
        $isolatedWebView = New-WebView2IsolatedEnvironment -ServerName $Server.Name -IsKvm:([bool]$IsKvm)
    }
    catch {
        $isolatedWebView = $null
    }

    $web.CreationProperties = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
    if ($isolatedWebView -and $isolatedWebView.UserDataFolder) {
        $web.CreationProperties.UserDataFolder = $isolatedWebView.UserDataFolder
    }
    else {
        $web.CreationProperties.UserDataFolder = $script:WebDataRoot
    }

    $outer.Controls.Add($web)
    $outer.Controls.Add($bar)
    $tab.Controls.Add($outer)

    [void]$script:Tabs.TabPages.Add($tab)
    $script:Tabs.SelectedTab = $tab

    # Store the WebView on the tab before navigation/debug buttons can be clicked.
    # The real KVM session key is filled in later by Open-KvmEmbedded.
    $tab.Tag = [pscustomobject]@{
        Server = $Server
        Url = $Url
        IsKvm = [bool]$IsKvm
        WebView = $web
        KvmSessionKey = $null
        UserDataFolder = if ($isolatedWebView) { $isolatedWebView.UserDataFolder } else { $script:WebDataRoot }
    }

    try {
        $tabEnvironment = if ($isolatedWebView -and $isolatedWebView.Environment) { $isolatedWebView.Environment } else { $script:WebViewEnvironment }
        $null = $web.EnsureCoreWebView2Async($tabEnvironment)

        if (-not (Wait-WebViewReady -Web $web)) {
            throw "Timed out waiting for CoreWebView2."
        }

        $web.CoreWebView2.Settings.AreDefaultContextMenusEnabled = $true
        $web.CoreWebView2.Settings.AreDevToolsEnabled = $true
        $web.CoreWebView2.Settings.IsScriptEnabled = $true

        # Allow self-signed iDRAC certificates inside this tool.
        # This prevents the "Your connection isn't private" WebView2 page.
        $web.CoreWebView2.add_ServerCertificateErrorDetected({
            param($sender, $args)
            try {
                $args.Action = [Microsoft.Web.WebView2.Core.CoreWebView2ServerCertificateErrorAction]::AlwaysAllow
            }
            catch {}
        })

        $web.CoreWebView2.add_NavigationStarting({
            param($sender, $args)
            $script:Status.Text = "Loading $($args.Uri)"
        })

        $web.CoreWebView2.add_NavigationCompleted({
            param($sender, $args)
            if ($args.IsSuccess) {
                $script:Status.Text = "Opened $($web.Source.AbsoluteUri)"
            }
            else {
                $script:Status.Text = "Navigation failed: $($args.WebErrorStatus)"
            }

            try {
                if ($IsKvm) {
                    if ($chkAutoContinue -and $chkAutoContinue.Checked) {
                        Invoke-WebView2AdvancedContinue -Web $web
                        $script:Status.Text = "Opened console. Auto Continue attempted."
                    }
                }
                else {
                    if ($chkAutoContinue -and $chkAutoContinue.Checked) {
                        Invoke-WebView2AdvancedContinue -Web $web
                    }
                    # GUI Auto Login is handled by the non-blocking timer so NavigationCompleted
                    # never blocks WebView2 during slow iDRAC page loads.
                    if (($chkAutoContinue -and $chkAutoContinue.Checked) -or ($chkAutoLogin -and $chkAutoLogin.Checked)) {
                        $script:Status.Text = "Opened GUI. Auto Continue active; Auto Login will retry after the login page appears."
                    }
                }
            }
            catch {}
        }.GetNewClosure())
# For GUI tabs, inject the auto-login retry script before normal navigation.
# This is more reliable with iDRAC10 because the script starts inside the /restgui page
# as soon as the login app is created, then keeps retrying until the fields exist.
if (-not $IsKvm -and $chkAutoLogin -and $chkAutoLogin.Checked -and $Server) {
    try {
        $startupLoginJs = New-iDRACGuiAutoLoginJavaScript -Server $Server
        if (-not [string]::IsNullOrWhiteSpace($startupLoginJs)) {
            [void]$web.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync($startupLoginJs)
        }
    } catch {}
}
$web.CoreWebView2.Navigate($Url)

# Start a non-blocking automation timer. This fixes cases where NavigationCompleted does not fire
# while WebView2 is showing the Chromium certificate interstitial. The timer repeatedly tries
# Advanced/Continue and then runs GUI Auto Login only after the page has had time to move forward.
Start-WebView2GuiAutomationTimer -Web $web -Server $Server -AutoContinueCheckBox $chkAutoContinue -AutoLoginCheckBox $chkAutoLogin -IsKvm ([bool]$IsKvm)
        $tab.Tag = [pscustomobject]@{
            Server = $Server
            Url = $Url
            IsKvm = [bool]$IsKvm
            WebView = $web
            KvmSessionKey = $null
            UserDataFolder = if ($isolatedWebView) { $isolatedWebView.UserDataFolder } else { $script:WebDataRoot }
        }
        $script:Status.Text = "Opened: $Url"
        return $tab
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "WebView2 tab failed.`r`n`r`n$($_.Exception.Message)",
            "WebView2 Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}


function Close-CurrentTab {
    if ($script:Tabs.TabPages.Count -eq 0) { return }

    $tab = $script:Tabs.SelectedTab
    if (-not $tab) { return }

    $tabName = $tab.Text

    # Multi View: close all WebView controls and delete all Redfish sessions tied to this page.
    try {
        if ($tab.Tag -and $tab.Tag.IsMultiView -and $tab.Tag.KvmSessions) {
            foreach ($entry in @($tab.Tag.KvmSessions)) {
                try {
                    if ($entry.WebView -and $entry.WebView.CoreWebView2) {
                        $entry.WebView.CoreWebView2.Navigate("about:blank")
                        [System.Windows.Forms.Application]::DoEvents()
                    }
                }
                catch {}

                try {
                    Invoke-iDRACWebRequest `
                        -Uri $entry.Session.DeleteUri `
                        -Method "DELETE" `
                        -Headers $entry.Session.Headers | Out-Null
                }
                catch {}
            }

            Start-Sleep -Milliseconds 500
        }
    }
    catch {}

    $sessionKey = $null
    $webView = $null
    $isKvm = $false

    try {
        if ($tab.Tag) {
            $isKvm = [bool]$tab.Tag.IsKvm
            $webView = $tab.Tag.WebView
            $sessionKey = $tab.Tag.KvmSessionKey
        }
    }
    catch {}

    # First disconnect the actual WebView2 console page.
    if ($isKvm -and $webView) {
        try {
            if ($webView.CoreWebView2) {
                $webView.CoreWebView2.Navigate("about:blank")
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 750
            }
        }
        catch {}
    }

    # Then delete the Redfish API session we created for GetKVMSession.
    if ($sessionKey -and $script:KvmSessions.ContainsKey($sessionKey)) {
        try {
            $session = $script:KvmSessions[$sessionKey]

            Invoke-iDRACWebRequest `
                -Uri $session.DeleteUri `
                -Method "DELETE" `
                -Headers $session.Headers | Out-Null

            $script:Status.Text = "Closed console session for $tabName"
        }
        catch {
            $script:Status.Text = "Closed console view but failed to delete Redfish session for ${tabName}: $($_.Exception.Message)"
        }

        $script:KvmSessions.Remove($sessionKey)
    }

    foreach ($c in @($tab.Controls)) {
        try { $c.Dispose() } catch {}
    }

    $script:Tabs.TabPages.Remove($tab)
    $tab.Dispose()
}


function Open-WebEmbedded {
    $s = Get-SelectedServer
    if (-not $s) { return }
    Add-WebViewTab -Server $s -Url (Get-iDRACBaseUrl $s.Address)
    Send-iDRACCManTelemetry -EventName "OpenGUI" -Properties @{ Group = $s.Group; Model = $s.Model; Health = $s.Health }
}

function Open-KvmEmbedded {
    $s = Get-SelectedServer
    if (-not $s) { return }

    try {
        $kvm = New-iDRACKvmUrlDellMethod -Server $s
        $tab = Add-WebViewTab -Server $s -Url $kvm.Url -IsKvm

        if ($tab) {
            $key = [string]$tab.GetHashCode()
            $script:KvmSessions[$key] = $kvm
            try { $tab.Tag.KvmSessionKey = $key } catch { $tab.Tag | Add-Member -NotePropertyName KvmSessionKey -NotePropertyValue $key -Force }
        }

        $script:Status.Text = "Opened embedded KVM for $($s.Name)"
        Send-iDRACCManTelemetry -EventName "OpenConsole" -Properties @{ Group = $s.Group; Model = $s.Model; Health = $s.Health }
    }
    catch {
        $err = $_.Exception.Message

        if (Test-iDRAC8LegacyKvmUnsupportedError -Message $err) {
            try {
                Open-iDRAC8GuiFallback -Server $s -Reason $err | Out-Null
                return
            }
            catch {
                $err = $_.Exception.Message
            }
        }

        [System.Windows.Forms.MessageBox]::Show(
            "Failed to create KVM session.`r`n`r`n$err",
            "KVM Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null

        $script:Status.Text = "KVM failed for $($s.Name)"
    }
}

function Invoke-PowerAction {
    param([string]$ResetType)

    $s = Get-SelectedServer
    if (-not $s) { return }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Send Redfish ResetType '$ResetType' to $($s.Name)?",
        "Confirm Power Action",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        Invoke-iDRACRestMethod `
            -Server $s `
            -Path "/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset" `
            -Method "POST" `
            -Body @{ ResetType = $ResetType } | Out-Null

        Add-LogTab -Title "$($s.Name) Power" -Text "Power action sent to $($s.Name): $ResetType"
        $script:Status.Text = "Power action sent: $ResetType"
        Send-iDRACCManTelemetry -EventName "PowerAction" -Properties @{ ResetType = $ResetType; Group = $s.Group; Model = $s.Model }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Power action failed.`r`n`r`n$($_.Exception.Message)",
            "Redfish Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null

        $script:Status.Text = "Power action failed for $($s.Name)"
    }
}

function Export-ServersCsv {
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
    $dlg.FileName = "idrac-servers.csv"

    if ($dlg.ShowDialog($script:MainForm) -eq [System.Windows.Forms.DialogResult]::OK) {
        $export = foreach ($s in $script:Servers) {
            [pscustomobject]@{
                Name = $s.Name
                Address = $s.Address
                Group = $s.Group
                Username = $s.Username
                ServiceTag = $s.ServiceTag
                Model = $s.Model
                OSHostname = $s.OSHostname
                Health = $s.Health
                PowerState = $s.PowerState
                Notes = $s.Notes
            }
        }

        $export | Export-Csv -Path $dlg.FileName -NoTypeInformation
        $script:Status.Text = "Exported CSV: $($dlg.FileName)"
    }
}

function Import-ServersCsv {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"

    if ($dlg.ShowDialog($script:MainForm) -eq [System.Windows.Forms.DialogResult]::OK) {
        $rows = Import-Csv -Path $dlg.FileName

        foreach ($r in $rows) {
            if (-not $r.Name -or -not $r.Address) { continue }

            $script:Servers += [pscustomobject]@{
                Name = $r.Name
                Address = $r.Address
                Group = $r.Group
                Username = $r.Username
                Password = ""
                Notes = $r.Notes
                ServiceTag = $r.ServiceTag
                Model = $r.Model
                OSHostname = $r.OSHostname
                Health = $r.Health
                PowerState = $r.PowerState
            }
        }

        Save-Servers
        Refresh-Tree
        Update-DashboardServerList
        $script:Status.Text = "Imported CSV: $($dlg.FileName)"
    }
}

function Show-Diagnostics {
    $txt = @"
PowerShell: $($PSVersionTable.PSVersion)
STA Thread: $([Threading.Thread]::CurrentThread.ApartmentState)

AppRoot:
$script:AppRoot

DataFile:
$script:DataFile

GroupCredFile:
$script:GroupCredFile

WebView2 Runtime Installed: $(Test-WebView2RuntimeInstalled)
WebView2 Runtime Version: $(Get-WebView2RuntimeVersion)
WebView2 Ready: $script:WebViewReady

Server count: $($script:Servers.Count)
Group credential count: $($script:GroupCredentials.Count)

KVM Method:
Dell Redfish DelliDRACCardService.GetKVMSession method.
No popup interception.
No external browser launch.
No WebView2Loader.dll copy/overwrite.

Storage:
Documents\iDRACCMan\servers.json
Server list roams with OneDrive if Documents is backed up.
Passwords are DPAPI-encrypted and only decrypt on the Windows profile/machine that saved them.
"@

    Add-LogTab -Title "Diagnostics" -Text $txt
}


function Connect-AllInSelectedGroup {
    $node = $script:Tree.SelectedNode
    if (-not $node -or -not $node.Tag) { return }

    try {
        if (-not $node.Tag.IsGroup) { return }
    }
    catch { return }

    $groupName = $node.Tag.Group
    $servers = @($script:Servers | Where-Object { $_.Group -eq $groupName })

    if ($servers.Count -eq 0) { return }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Open console connections to all $($servers.Count) iDRACs in group '$groupName'?",
        "Connect to All",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    foreach ($srv in $servers) {
        try {
            try {
                $kvm = New-iDRACKvmUrlDellMethod -Server $srv
                $tab = Add-WebViewTab -Server $srv -Url $kvm.Url -IsKvm

                if ($tab) {
                    $key = [string]$tab.GetHashCode()
                    $script:KvmSessions[$key] = $kvm
                    try {
                        $tab.Tag.KvmSessionKey = $key
                    }
                    catch {
                        $tab.Tag | Add-Member -NotePropertyName KvmSessionKey -NotePropertyValue $key -Force
                    }
                }
            }
            catch {
                $err = $_.Exception.Message
                if (Test-iDRAC8LegacyKvmUnsupportedError -Message $err) {
                    Open-iDRAC8GuiFallback -Server $srv -Reason $err | Out-Null
                }
                else {
                    throw
                }
            }
        }
        catch {
            Add-LogTab -Title "$($srv.Name) Connect Failed" -Text "Failed to connect to $($srv.Name)`r`n`r`n$($_.Exception.Message)"
        }
    }

    $script:Status.Text = "Connect to all completed for group $groupName"
}

function Delete-SelectedGroup {
    $node = $script:Tree.SelectedNode
    if (-not $node -or -not $node.Tag) { return }

    try {
        if (-not $node.Tag.IsGroup) { return }
    }
    catch { return }

    $groupName = $node.Tag.Group
    $count = @($script:Servers | Where-Object { $_.Group -eq $groupName }).Count

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Delete group '$groupName' and all $count iDRAC entries in it?",
        "Delete Group",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $script:Servers = @($script:Servers | Where-Object { $_.Group -ne $groupName })
    Clear-GroupCredential -GroupName $groupName
    Save-Servers
    Refresh-Tree
    $script:Status.Text = "Deleted group $groupName"
}


function Get-SelectedGroupName {
    $node = $script:Tree.SelectedNode
    if (-not $node) { return $null }

    if ($node.Tag) {
        try {
            if ($node.Tag.IsGroup) { return $node.Tag.Group }
        }
        catch {}

        try {
            if ($node.Tag.Group) { return $node.Tag.Group }
        }
        catch {}
    }

    return $node.Text
}


function Toggle-MultiViewCell {
    param(
        [Parameter(Mandatory=$true)]$Cell,
        [Parameter(Mandatory=$true)]$Table,
        [Parameter(Mandatory=$true)]$Tab
    )

    try {
        if (-not $Tab.Tag) { return }

        if (-not $Tab.Tag.IsCellMaximized) {
            # Maximize selected cell.
            foreach ($ctrl in @($Table.Controls)) {
                if ($ctrl -ne $Cell) {
                    $ctrl.Visible = $false
                }
            }

            $Table.SetColumn($Cell, 0)
            $Table.SetRow($Cell, 0)
            $Table.SetColumnSpan($Cell, $Table.ColumnCount)
            $Table.SetRowSpan($Cell, $Table.RowCount)

            $Cell.Visible = $true
            $Cell.BringToFront()

            $Tab.Tag.IsCellMaximized = $true
            $Tab.Tag.MaximizedCell = $Cell
            $script:Status.Text = "Multi View maximized. Double-click the title again to restore."
        }
        else {
            # Restore all cells to their original positions.
            foreach ($ctrl in @($Table.Controls)) {
                try {
                    if ($ctrl.Tag) {
                        $Table.SetColumn($ctrl, [int]$ctrl.Tag.OriginalColumn)
                        $Table.SetRow($ctrl, [int]$ctrl.Tag.OriginalRow)
                        $Table.SetColumnSpan($ctrl, 1)
                        $Table.SetRowSpan($ctrl, 1)
                    }
                    $ctrl.Visible = $true
                }
                catch {}
            }

            $Tab.Tag.IsCellMaximized = $false
            $Tab.Tag.MaximizedCell = $null
            $script:Status.Text = "Multi View restored."
        }

        $Table.PerformLayout()
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Unable to toggle Multi View.`r`n`r`n$($_.Exception.Message)",
            "Multi View Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

function Open-MultiViewForSelectedGroup {
    if (-not $script:WebViewReady) {
        [System.Windows.Forms.MessageBox]::Show(
            "WebView2 is not ready. Multi View requires WebView2.",
            "WebView2 Not Ready",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    $groupName = Get-SelectedGroupName
    if ([string]::IsNullOrWhiteSpace($groupName)) { return }

    $servers = @($script:Servers | Where-Object { $_.Group -eq $groupName })
    if ($servers.Count -eq 0) { return }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Open Multi View console connections to all $($servers.Count) iDRACs in group '$groupName'?",
        "Multi View",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $tab = New-Object System.Windows.Forms.TabPage
    $tab.Text = "$groupName Multi View"

    $outer = New-Object System.Windows.Forms.Panel
    $outer.Dock = "Fill"

    $bar = New-Object System.Windows.Forms.Panel
    $bar.Dock = "Top"
    $bar.Height = 34

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Left = 4
    $btnClose.Top = 4
    $btnClose.Width = 70
    $btnClose.Height = 26
    $btnClose.Add_Click({ Close-CurrentTab })

    $chkAutoContinueMulti = New-Object System.Windows.Forms.CheckBox
    $chkAutoContinueMulti.Text = "Auto Continue"
    $chkAutoContinueMulti.Left = 85
    $chkAutoContinueMulti.Top = 7
    $chkAutoContinueMulti.Width = 120
    $chkAutoContinueMulti.Height = 22
    $chkAutoContinueMulti.Checked = [bool](Get-iDRACCManSetting -Name "AutoContinueConsole" -Default $true)
    $chkAutoContinueMulti.Add_CheckedChanged({
        try {
            Set-iDRACCManSetting -Name "AutoContinueConsole" -Value ([bool]$chkAutoContinueMulti.Checked)
            if ($chkAutoContinueMulti.Checked -and $tab.Tag -and $tab.Tag.KvmSessions) {
                foreach ($entry in @($tab.Tag.KvmSessions)) {
                    try {
                        if ($entry.WebView -and $entry.WebView.CoreWebView2) {
                            Invoke-WebView2AdvancedContinue -Web $entry.WebView
                        }
                    }
                    catch {}
                }
                if ($script:Status) { $script:Status.Text = "Multi View Auto Continue attempted." }
            }
        }
        catch {}
    }.GetNewClosure())

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Multi View: $groupName"
    $lbl.Left = 215
    $lbl.Top = 8
    $lbl.Width = 500
    $lbl.Height = 22

    $bar.Controls.AddRange(@($btnClose,$chkAutoContinueMulti,$lbl))

    $table = New-Object System.Windows.Forms.TableLayoutPanel
    $table.Dock = "Fill"
    $table.CellBorderStyle = "Single"

    $count = $servers.Count
    $cols = [Math]::Ceiling([Math]::Sqrt($count))
    $rows = [Math]::Ceiling($count / $cols)

    $table.ColumnCount = [int]$cols
    $table.RowCount = [int]$rows

    for ($c = 0; $c -lt $cols; $c++) {
        [void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, (100 / $cols))))
    }

    for ($r = 0; $r -lt $rows; $r++) {
        [void]$table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, (100 / $rows))))
    }

    $outer.Controls.Add($table)
    $outer.Controls.Add($bar)
    $tab.Controls.Add($outer)

    $sessionEntries = New-Object System.Collections.ArrayList
    $tab.Tag = [pscustomobject]@{
        IsMultiView = $true
        Group = $groupName
        KvmSessions = $sessionEntries
        IsCellMaximized = $false
        MaximizedCell = $null
    }

    [void]$script:Tabs.TabPages.Add($tab)
    $script:Tabs.SelectedTab = $tab

    $i = 0
    foreach ($srv in $servers) {
        $cell = New-Object System.Windows.Forms.Panel
        $cell.Dock = "Fill"

        $title = New-Object System.Windows.Forms.Label
        $title.Dock = "Top"
        $title.Height = 22
        $title.Text = $srv.Name
        $title.TextAlign = "MiddleLeft"
        $title.Cursor = [System.Windows.Forms.Cursors]::Hand
        # Inline double-click handler instead of calling Toggle-MultiViewCell by name.
        # This avoids PowerShell scope loss when the tool is loaded with Invoke-Expression from GitHub.
        $title.Add_DoubleClick({
            try {
                if (-not $tab.Tag) { return }

                if (-not $tab.Tag.IsCellMaximized) {
                    foreach ($ctrl in @($table.Controls)) {
                        if ($ctrl -ne $cell) {
                            $ctrl.Visible = $false
                        }
                    }

                    $table.SetColumn($cell, 0)
                    $table.SetRow($cell, 0)
                    $table.SetColumnSpan($cell, $table.ColumnCount)
                    $table.SetRowSpan($cell, $table.RowCount)

                    $cell.Visible = $true
                    $cell.BringToFront()

                    $tab.Tag.IsCellMaximized = $true
                    $tab.Tag.MaximizedCell = $cell

                    if ($script:Status) {
                        $script:Status.Text = "Multi View maximized. Double-click the title again to restore."
                    }
                }
                else {
                    foreach ($ctrl in @($table.Controls)) {
                        try {
                            if ($ctrl.Tag) {
                                $table.SetColumn($ctrl, [int]$ctrl.Tag.OriginalColumn)
                                $table.SetRow($ctrl, [int]$ctrl.Tag.OriginalRow)
                                $table.SetColumnSpan($ctrl, 1)
                                $table.SetRowSpan($ctrl, 1)
                            }

                            $ctrl.Visible = $true
                        }
                        catch {}
                    }

                    $tab.Tag.IsCellMaximized = $false
                    $tab.Tag.MaximizedCell = $null

                    if ($script:Status) {
                        $script:Status.Text = "Multi View restored."
                    }
                }

                $table.PerformLayout()
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show(
                    "Unable to toggle Multi View.`r`n`r`n$($_.Exception.Message)",
                    "Multi View Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                ) | Out-Null
            }
        }.GetNewClosure())

        $web = New-Object Microsoft.Web.WebView2.WinForms.WebView2
        $web.Dock = "Fill"

        $cell.Controls.Add($web)
        $cell.Controls.Add($title)

        $row = [Math]::Floor($i / $cols)
        $col = $i % $cols

        $cell.Tag = [pscustomobject]@{
            OriginalRow = [int]$row
            OriginalColumn = [int]$col
            ServerName = $srv.Name
        }

        $table.Controls.Add($cell, [int]$col, [int]$row)

        try {
            $kvm = New-iDRACKvmUrlDellMethod -Server $srv
            Initialize-iDRACWebViewControl -Web $web -Url $kvm.Url

            try {
                $web.CoreWebView2.add_NavigationCompleted({
                    try {
                        if ($chkAutoContinueMulti -and $chkAutoContinueMulti.Checked) {
                            Invoke-WebView2AdvancedContinue -Web $web
                        }
                    }
                    catch {}
                }.GetNewClosure())
            }
            catch {}

            if ($chkAutoContinueMulti -and $chkAutoContinueMulti.Checked) {
                Invoke-WebView2AdvancedContinue -Web $web
            }

            [void]$sessionEntries.Add([pscustomobject]@{
                Server = $srv
                WebView = $web
                Session = $kvm
            })
        }
        catch {
            $title.Text = "$($srv.Name) - Failed"
            Add-LogTab -Title "$($srv.Name) Multi View Failed" -Text "Failed to connect to $($srv.Name)`r`n`r`n$($_.Exception.Message)"
        }

        $i++
        [System.Windows.Forms.Application]::DoEvents()
    }

    $script:Status.Text = "Opened Multi View for group $groupName"
    Send-iDRACCManTelemetry -EventName "OpenMultiView" -Properties @{ Group = $groupName; Count = $servers.Count }
}


function Resize-SideMenuToContent {
    try {
        if (-not $script:Tree -or -not $script:MainForm) { return }
        if ($script:MainSplit -and $script:MainSplit.Panel1Collapsed) { return }

        $font = $script:Tree.Font
        $maxWidth = 220

        foreach ($node in $script:Tree.Nodes) {
            $size = [System.Windows.Forms.TextRenderer]::MeasureText($node.Text, $font)
            if (($size.Width + 45) -gt $maxWidth) {
                $maxWidth = $size.Width + 45
            }

            foreach ($child in $node.Nodes) {
                $childSize = [System.Windows.Forms.TextRenderer]::MeasureText($child.Text, $font)
                if (($childSize.Width + 70) -gt $maxWidth) {
                    $maxWidth = $childSize.Width + 70
                }
            }
        }

        # Keep it reasonable so it doesn't take over the screen.
        $maxAllowed = [Math]::Min(650, [Math]::Max(260, [int]($script:MainForm.Width * 0.45)))
        if ($maxWidth -gt $maxAllowed) { $maxWidth = $maxAllowed }
        if ($maxWidth -lt 260) { $maxWidth = 260 }

        if ($script:MainSplit) {
            $script:MainSplit.SplitterDistance = [int]$maxWidth
        }
    }
    catch {
        # Do not interrupt the GUI for sizing issues.
    }
}




function New-iDRACRoundedRectanglePath {
    param(
        [Parameter(Mandatory=$true)][System.Drawing.Rectangle]$Rectangle,
        [int]$Radius = 8
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = [Math]::Max(2, ($Radius * 2))

    $arc = New-Object System.Drawing.Rectangle($Rectangle.X, $Rectangle.Y, $diameter, $diameter)
    $path.AddArc($arc, 180, 90)

    $arc.X = $Rectangle.Right - $diameter
    $path.AddArc($arc, 270, 90)

    $arc.Y = $Rectangle.Bottom - $diameter
    $path.AddArc($arc, 0, 90)

    $arc.X = $Rectangle.X
    $path.AddArc($arc, 90, 90)

    $path.CloseFigure()
    return $path
}

function Update-ConnectionsToggleTab {
    try {
        if (-not $script:ConnectionsToggleRail -or -not $script:MainSplit) { return }

        $parent = $script:ConnectionsToggleRail.Parent
        if (-not $parent) { return }

        $h = [int]$script:ConnectionsToggleRail.Height
        if ($h -lt 1) { $h = 68 }

        $panelH = [int]$parent.ClientSize.Height
        $script:ConnectionsToggleRail.Left = 0
        $script:ConnectionsToggleRail.Top = [Math]::Max(65, [int](($panelH - $h) / 2))

        if ($script:ConnectionsToggleButton) {
            if ($script:MainSplit.Panel1Collapsed) {
                $script:ConnectionsToggleButton.Text = '›'
                $script:ConnectionsToggleButton.Tag = 'Open'
                try { $script:ConnectionsToggleRail.AccessibleName = 'Open Connections menu' } catch {}
            }
            else {
                $script:ConnectionsToggleButton.Text = '‹'
                $script:ConnectionsToggleButton.Tag = 'Close'
                try { $script:ConnectionsToggleRail.AccessibleName = 'Collapse Connections menu' } catch {}
            }
        }

        try { $script:ConnectionsToggleRail.Invalidate() } catch {}
        $script:ConnectionsToggleRail.BringToFront()
    }
    catch {}
}

function Toggle-ConnectionsMenu {
    try {
        if (-not $script:MainSplit) { return }

        $script:MainSplit.SuspendLayout()

        if ($script:MainSplit.Panel1Collapsed) {
            $savedWidth = 260
            try { $savedWidth = [int](Get-iDRACCManSetting -Name 'ConnectionsWidth' -Default 260) } catch {}
            if ($savedWidth -lt 220) { $savedWidth = 260 }
            if ($savedWidth -gt 650) { $savedWidth = 650 }

            $script:MainSplit.Panel1Collapsed = $false
            $script:MainSplit.SplitterDistance = $savedWidth
            Set-iDRACCManSetting -Name 'ConnectionsCollapsed' -Value $false
            if ($script:Status) { $script:Status.Text = 'Connections menu opened' }
        }
        else {
            try {
                $width = [int]$script:MainSplit.SplitterDistance
                if ($width -ge 160) { Set-iDRACCManSetting -Name 'ConnectionsWidth' -Value $width }
            } catch {}

            $script:MainSplit.Panel1Collapsed = $true
            Set-iDRACCManSetting -Name 'ConnectionsCollapsed' -Value $true
            if ($script:Status) { $script:Status.Text = 'Connections menu collapsed' }
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Unable to toggle Connections menu.`r`n`r`n$($_.Exception.Message)",
            'Connections',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    }
    finally {
        try { $script:MainSplit.ResumeLayout($true) } catch {}
        Update-ConnectionsToggleTab
    }
}

function Show-ServerContextMenu {
    param(
        [Parameter(Mandatory=$true)]$Node,
        [Parameter(Mandatory=$true)]$Location
    )

    if (-not $Node) { return }

    $script:Tree.SelectedNode = $Node

    $cm = New-Object System.Windows.Forms.ContextMenuStrip
    $cm.Font = $script:AppFont

    $isGroup = $false
    if ($Node.Tag) {
        try { $isGroup = [bool]$Node.Tag.IsGroup } catch { $isGroup = $false }
    }

    if ($isGroup) {
        $miEditGroupCreds = New-Object System.Windows.Forms.ToolStripMenuItem("Edit Group Credentials")
        $miEditGroupCreds.Add_Click({ Show-GroupCredentialDialog })

        $miMultiView = New-Object System.Windows.Forms.ToolStripMenuItem("Multi View")
        $miMultiView.Add_Click({ Open-MultiViewForSelectedGroup })

        $miConnectAll = New-Object System.Windows.Forms.ToolStripMenuItem("Connect to All")
        $miConnectAll.Add_Click({ Connect-AllInSelectedGroup })

        $miRefreshGroupHealth = New-Object System.Windows.Forms.ToolStripMenuItem("Refresh Group Health")
        $miRefreshGroupHealth.Add_Click({ Refresh-SelectedGroupHealth })

        $miDeleteGroup = New-Object System.Windows.Forms.ToolStripMenuItem("Delete Group")
        $miDeleteGroup.Add_Click({ Delete-SelectedGroup })

        [void]$cm.Items.Add($miEditGroupCreds)
        [void]$cm.Items.Add($miMultiView)
        [void]$cm.Items.Add($miConnectAll)
        [void]$cm.Items.Add($miRefreshGroupHealth)
        [void]$cm.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        [void]$cm.Items.Add($miDeleteGroup)
    }
    else {
        $miOpenConsole = New-Object System.Windows.Forms.ToolStripMenuItem("Open Console")
        $miOpenConsole.Add_Click({ Open-KvmEmbedded })

        $miOpenGui = New-Object System.Windows.Forms.ToolStripMenuItem("Open GUI")
        $miOpenGui.Add_Click({ Open-WebEmbedded })

        $miEditCredentials = New-Object System.Windows.Forms.ToolStripMenuItem("Edit Credentials")
        $miEditCredentials.Add_Click({
            $s = Get-SelectedServer
            if ($s) { Show-ServerDialog -Server $s }
        })

        $miRefreshHealth = New-Object System.Windows.Forms.ToolStripMenuItem("Refresh Health")
        $miRefreshHealth.Add_Click({ Refresh-SelectediDRACHealth })

        [void]$cm.Items.Add($miOpenConsole)
        [void]$cm.Items.Add($miOpenGui)
        [void]$cm.Items.Add($miRefreshHealth)
        [void]$cm.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        [void]$cm.Items.Add($miEditCredentials)
    }

    $cm.Show($script:Tree, $Location)
}


function Get-iDRACCManSearchText {
    param([string]$Prompt = "Search iDRACs")

    $f = New-Object System.Windows.Forms.Form
    $f.Text = $Prompt
    $f.Width = 430
    $f.Height = 160
    $f.StartPosition = "CenterParent"
    $f.FormBorderStyle = "FixedDialog"
    $f.Font = $script:AppFont
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Search name, IP/address, service tag, model, OS hostname, group, health, or notes:"
    $lbl.Left = 12
    $lbl.Top = 14
    $lbl.Width = 390
    $lbl.Height = 28
    $f.Controls.Add($lbl)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Left = 12
    $txt.Top = 48
    $txt.Width = 390
    $f.Controls.Add($txt)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "Search"
    $ok.Left = 240
    $ok.Top = 82
    $ok.Width = 75
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $f.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancel"
    $cancel.Left = 325
    $cancel.Top = 82
    $cancel.Width = 75
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $f.Controls.Add($cancel)

    $f.AcceptButton = $ok
    $f.CancelButton = $cancel

    if ($f.ShowDialog($script:MainForm) -eq [System.Windows.Forms.DialogResult]::OK) {
        return $txt.Text.Trim()
    }

    return ""
}

function Test-iDRACServerMatchesSearch {
    param(
        [Parameter(Mandatory=$true)]$Server,
        [Parameter(Mandatory=$true)][string]$SearchText
    )

    if ([string]::IsNullOrWhiteSpace($SearchText)) { return $false }
    $q = $SearchText.Trim()

    $fields = @(
        $Server.Name,
        $Server.Address,
        $Server.ServiceTag,
        $Server.Model,
        $Server.OSHostname,
        $Server.Group,
        $Server.Health,
        $Server.PowerState,
        $Server.Notes,
        $Server.Username
    )

    foreach ($field in $fields) {
        if (-not [string]::IsNullOrWhiteSpace([string]$field)) {
            if ([string]$field -like "*$q*") { return $true }
        }
    }

    return $false
}

function Show-iDRACCManSearch {
    param([string]$InitialText = "")

    $query = $InitialText
    if ([string]::IsNullOrWhiteSpace($query)) {
        $query = Get-iDRACCManSearchText
    }

    if ([string]::IsNullOrWhiteSpace($query)) { return }

    try {
        $matches = @($script:Servers | Where-Object { Test-iDRACServerMatchesSearch -Server $_ -SearchText $query } | Sort-Object Group,Name)

        $tab = New-Object System.Windows.Forms.TabPage
        $tab.Text = "Search: $query"

        $outer = New-Object System.Windows.Forms.Panel
        $outer.Dock = "Fill"
        $outer.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)

        $bar = New-Object System.Windows.Forms.Panel
        $bar.Dock = "Top"
        $bar.Height = 46
        $bar.BackColor = [System.Drawing.Color]::White

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = "Search results for '$query'  ($($matches.Count) found)"
        $lbl.Left = 12
        $lbl.Top = 13
        $lbl.Width = 420
        $lbl.Height = 22
        $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $bar.Controls.Add($lbl)

        $btnClose = New-Object System.Windows.Forms.Button
        $btnClose.Text = "Close"
        $btnClose.Left = 445
        $btnClose.Top = 8
        $btnClose.Width = 70
        $btnClose.Height = 28
        $btnClose.Add_Click({ Close-CurrentTab })
        $bar.Controls.Add($btnClose)

        $btnNewSearch = New-Object System.Windows.Forms.Button
        $btnNewSearch.Text = "New Search"
        $btnNewSearch.Left = 525
        $btnNewSearch.Top = 8
        $btnNewSearch.Width = 95
        $btnNewSearch.Height = 28
        $btnNewSearch.Add_Click({ Show-iDRACCManSearch })
        $bar.Controls.Add($btnNewSearch)

        $list = New-Object System.Windows.Forms.ListView
        $list.Dock = "Fill"
        $list.View = "Details"
        $list.FullRowSelect = $true
        $list.GridLines = $true
        $list.HideSelection = $false
        $list.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        [void]$list.Columns.Add("Name", 190)
        [void]$list.Columns.Add("IP / Address", 145)
        [void]$list.Columns.Add("Service Tag", 110)
        [void]$list.Columns.Add("Model", 190)
        [void]$list.Columns.Add("OS Hostname", 170)
        [void]$list.Columns.Add("Health", 80)
        [void]$list.Columns.Add("Power", 75)
        [void]$list.Columns.Add("Group", 130)

        foreach ($srv in $matches) {
            $item = New-Object System.Windows.Forms.ListViewItem([string]$srv.Name)
            [void]$item.SubItems.Add([string]$srv.Address)
            [void]$item.SubItems.Add([string]$srv.ServiceTag)
            [void]$item.SubItems.Add([string]$srv.Model)
            [void]$item.SubItems.Add([string]$srv.OSHostname)
            [void]$item.SubItems.Add([string]$srv.Health)
            [void]$item.SubItems.Add([string]$srv.PowerState)
            [void]$item.SubItems.Add([string]$srv.Group)
            $item.Tag = $srv

            try {
                switch -Regex ($srv.Health) {
                    "Critical" { $item.ForeColor = [System.Drawing.Color]::FromArgb(222,43,43); break }
                    "Warning"  { $item.ForeColor = [System.Drawing.Color]::FromArgb(245,146,0); break }
                    "OK"       { $item.ForeColor = [System.Drawing.Color]::FromArgb(36,152,50); break }
                }
            }
            catch {}

            [void]$list.Items.Add($item)
        }

        $list.Add_DoubleClick({
            try {
                if ($list.SelectedItems.Count -eq 0) { return }
                $srv = $list.SelectedItems[0].Tag
                if (-not $srv) { return }

                foreach ($gNode in $script:Tree.Nodes) {
                    foreach ($child in $gNode.Nodes) {
                        if ($child.Tag -and $child.Tag.Address -eq $srv.Address) {
                            $gNode.Expand()
                            $script:Tree.SelectedNode = $child
                            $child.EnsureVisible()
                            break
                        }
                    }
                }

                Open-KvmEmbedded
            }
            catch {}
        }.GetNewClosure())

        $cm = New-Object System.Windows.Forms.ContextMenuStrip
        $miConsole = New-Object System.Windows.Forms.ToolStripMenuItem("Open Console")
        $miConsole.Add_Click({
            if ($list.SelectedItems.Count -gt 0) {
                $srv = $list.SelectedItems[0].Tag
                if ($srv) {
                    foreach ($gNode in $script:Tree.Nodes) {
                        foreach ($child in $gNode.Nodes) {
                            if ($child.Tag -and $child.Tag.Address -eq $srv.Address) {
                                $script:Tree.SelectedNode = $child
                                $child.EnsureVisible()
                                break
                            }
                        }
                    }
                    Open-KvmEmbedded
                }
            }
        }.GetNewClosure())
        $miGui = New-Object System.Windows.Forms.ToolStripMenuItem("Open GUI")
        $miGui.Add_Click({
            if ($list.SelectedItems.Count -gt 0) {
                $srv = $list.SelectedItems[0].Tag
                if ($srv) {
                    foreach ($gNode in $script:Tree.Nodes) {
                        foreach ($child in $gNode.Nodes) {
                            if ($child.Tag -and $child.Tag.Address -eq $srv.Address) {
                                $script:Tree.SelectedNode = $child
                                $child.EnsureVisible()
                                break
                            }
                        }
                    }
                    Open-WebEmbedded
                }
            }
        }.GetNewClosure())
        $miEdit = New-Object System.Windows.Forms.ToolStripMenuItem("Edit")
        $miEdit.Add_Click({
            if ($list.SelectedItems.Count -gt 0) {
                $srv = $list.SelectedItems[0].Tag
                if ($srv) { Show-ServerDialog -Server $srv }
            }
        }.GetNewClosure())
        [void]$cm.Items.Add($miConsole)
        [void]$cm.Items.Add($miGui)
        [void]$cm.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        [void]$cm.Items.Add($miEdit)
        $list.ContextMenuStrip = $cm

        $outer.Controls.Add($list)
        $outer.Controls.Add($bar)
        $tab.Controls.Add($outer)

        [void]$script:Tabs.TabPages.Add($tab)
        $script:Tabs.SelectedTab = $tab

        if ($script:Status) { $script:Status.Text = "Search found $($matches.Count) result(s) for '$query'." }
        Send-iDRACCManTelemetry -EventName "Search" -Properties @{ QueryLength = $query.Length; ResultCount = $matches.Count }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Search failed.`r`n`r`n$($_.Exception.Message)",
            "Search",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}



function Open-iDRACCManHelp {
    param([string]$Source = "Unknown")

    $helpUrl = "https://github.com/DellProSupportGse/Tools/blob/main/iDRACCMan/help.md"

    try {
        if ($script:HelpUrl -and -not [string]::IsNullOrWhiteSpace([string]$script:HelpUrl)) {
            $helpUrl = [string]$script:HelpUrl
        }
    }
    catch {}

    try {
        Start-Process -FilePath $helpUrl

        if ($script:Status) {
            $script:Status.Text = "Opened online documentation."
        }

        try {
            Send-iDRACCManTelemetry -EventName "OpenHelp" -Properties @{ Target = "help.md"; Source = $Source }
        }
        catch {}
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            ("Unable to open online documentation.`r`n`r`n{0}`r`n`r`n{1}" -f $helpUrl, $_.Exception.Message),
            "Documentation",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
}

function Build-Gui {
    $script:MainForm = New-Object System.Windows.Forms.Form
    $script:MainForm.Text = "$script:AppName $script:AppVersion - Simplified iDRAC Access. By: Jim Gandy"
    $script:MainForm.WindowState = "Maximized"
    $script:MainForm.StartPosition = "CenterScreen"
    $script:MainForm.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $script:MainForm.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)

    # iDRAC 10 inspired colors
    $colorBlue      = [System.Drawing.Color]::FromArgb(0,120,215)
    $colorBlueDark  = [System.Drawing.Color]::FromArgb(0,90,170)
    $colorSide      = [System.Drawing.Color]::FromArgb(250,251,253)
    $colorSelected  = [System.Drawing.Color]::FromArgb(232,241,251)
    $colorBorder    = [System.Drawing.Color]::FromArgb(218,222,228)
    $colorText      = [System.Drawing.Color]::FromArgb(32,43,54)
    $colorMuted     = [System.Drawing.Color]::FromArgb(90,99,110)
    $colorHealthy   = [System.Drawing.Color]::FromArgb(36,152,50)
    $colorWarn      = [System.Drawing.Color]::FromArgb(245,146,0)
    $colorCritical  = [System.Drawing.Color]::FromArgb(222,43,43)

    function New-UiButton {
        param(
            [string]$Text,
            [int]$Left,
            [int]$Top,
            [int]$Width = 105,
            [scriptblock]$Click
        )
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $Text
        $b.Left = $Left
        $b.Top = $Top
        $b.Width = $Width
        $b.Height = 32
        $b.FlatStyle = "Flat"
        $b.BackColor = $colorBlue
        $b.ForeColor = [System.Drawing.Color]::White
        $b.FlatAppearance.BorderColor = $colorBlueDark
        $b.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
        if ($Click) { $b.Add_Click($Click) }
        return $b
    }

    function New-Card {
        param([string]$Title,[string]$Value,[string]$SubText,[System.Drawing.Color]$Accent,[int]$Left,[int]$Top,[int]$Width,[int]$Height)
        $p = New-Object System.Windows.Forms.Panel
        $p.Left = $Left; $p.Top = $Top; $p.Width = $Width; $p.Height = $Height
        $p.BackColor = [System.Drawing.Color]::White
        $p.BorderStyle = "FixedSingle"

        $icon = New-Object System.Windows.Forms.Label
        $icon.Text = "●"
        $icon.Left = 18; $icon.Top = 22; $icon.Width = 40; $icon.Height = 38
        $icon.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Regular)
        $icon.ForeColor = $Accent
        $p.Controls.Add($icon)

        $v = New-Object System.Windows.Forms.Label
        $v.Text = $Value
        $v.Left = 68; $v.Top = 18; $v.Width = 120; $v.Height = 36
        $v.Font = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
        $v.ForeColor = $Accent
        $p.Controls.Add($v)

        $t = New-Object System.Windows.Forms.Label
        $t.Text = $Title
        $t.Left = 68; $t.Top = 55; $t.Width = $Width - 80; $t.Height = 22
        $t.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)
        $t.ForeColor = $colorText
        $p.Controls.Add($t)

        $s = New-Object System.Windows.Forms.Label
        $s.Text = $SubText
        $s.Left = 18; $s.Top = $Height - 32; $s.Width = $Width - 35; $s.Height = 20
        $s.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $s.ForeColor = $colorMuted
        $p.Controls.Add($s)

        return $p
    }

    function Add-DashboardTab {
        $dash = New-Object System.Windows.Forms.TabPage
        $dash.Text = "Dashboard"
        $dash.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)
        $dash.Padding = New-Object System.Windows.Forms.Padding(14)

        $surface = New-Object System.Windows.Forms.Panel
        $surface.Dock = "Fill"
        $surface.AutoScroll = $true
        $surface.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)
        $dash.Controls.Add($surface)

        $title = New-Object System.Windows.Forms.Label
        $title.Text = "Dashboard"
        $title.Left = 10; $title.Top = 10; $title.Width = 400; $title.Height = 36
        $title.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Regular)
        $title.ForeColor = $colorText
        $surface.Controls.Add($title)

        $surface.Controls.Add((New-UiButton -Text "Add iDRAC" -Left 10 -Top 58 -Width 100 -Click { Show-ServerDialog }))
        $surface.Controls.Add((New-UiButton -Text "Open Console" -Left 120 -Top 58 -Width 120 -Click { Open-KvmEmbedded }))
        $surface.Controls.Add((New-UiButton -Text "Open GUI" -Left 250 -Top 58 -Width 100 -Click { Open-WebEmbedded }))
        $surface.Controls.Add((New-UiButton -Text "Refresh" -Left 360 -Top 58 -Width 90 -Click { Refresh-Tree; Update-DashboardServerList; $script:Status.Text = "Tree refreshed" }))
        $surface.Controls.Add((New-UiButton -Text "Refresh Health" -Left 460 -Top 58 -Width 125 -Click { Refresh-AlliDRACHealth }))

        $total = @($script:Servers).Count
        $groups = @($script:Servers | Group-Object Group).Count
        $withServerCreds = @($script:Servers | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Username) }).Count
        $groupCreds = @($script:GroupCredentials).Count

        $surface.Controls.Add((New-Card -Title "Total iDRACs" -Value ([string]$total) -SubText "$groups groups configured" -Accent $colorBlue -Left 10 -Top 110 -Width 270 -Height 120))
        $surface.Controls.Add((New-Card -Title "Credentials" -Value ([string]($withServerCreds + $groupCreds)) -SubText "$withServerCreds server / $groupCreds group" -Accent $colorHealthy -Left 295 -Top 110 -Width 270 -Height 120))
        $surface.Controls.Add((New-Card -Title "WebView2" -Value $(if ($script:WebViewReady) { "Ready" } else { "Issue" }) -SubText "Runtime: $(Get-WebView2RuntimeVersion)" -Accent $(if ($script:WebViewReady) { $colorHealthy } else { $colorWarn }) -Left 580 -Top 110 -Width 330 -Height 120))

        $recentPanel = New-Object System.Windows.Forms.Panel
        $recentPanel.Left = 10; $recentPanel.Top = 250; $recentPanel.Width = 900; $recentPanel.Height = 360
        $recentPanel.BackColor = [System.Drawing.Color]::White
        $recentPanel.BorderStyle = "FixedSingle"
        $surface.Controls.Add($recentPanel)

        $recentTitle = New-Object System.Windows.Forms.Label
        $recentTitle.Text = "Configured iDRAC Connections"
        $recentTitle.Left = 14; $recentTitle.Top = 12; $recentTitle.Width = 400; $recentTitle.Height = 32
        $recentTitle.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
        $recentTitle.ForeColor = $colorText
        $recentPanel.Controls.Add($recentTitle)

        $list = New-Object System.Windows.Forms.ListView
        $list.Left = 14; $list.Top = 48; $list.Width = 870; $list.Height = 295
        $list.View = "Details"
        $list.FullRowSelect = $true
        $list.GridLines = $true
        $list.HideSelection = $false
        $list.BackColor = [System.Drawing.Color]::White
        $list.ForeColor = $colorText
        [void]$list.Columns.Add("Host Name", 170)
        [void]$list.Columns.Add("IP / Address", 135)
        [void]$list.Columns.Add("Service Tag", 105)
        [void]$list.Columns.Add("Model", 170)
        [void]$list.Columns.Add("OS Hostname", 150)
        [void]$list.Columns.Add("Health", 80)
        [void]$list.Columns.Add("Group", 105)
        [void]$list.Columns.Add("Credential", 95)
        foreach ($srv in @($script:Servers | Sort-Object Group,Name)) {
            $credText = if (-not [string]::IsNullOrWhiteSpace($srv.Username)) { "Server" } elseif (Get-GroupCredentialRecord -GroupName $srv.Group) { "Group" } else { "Prompt" }
            $item = New-Object System.Windows.Forms.ListViewItem($srv.Name)
            [void]$item.SubItems.Add($srv.Address)
            [void]$item.SubItems.Add($srv.ServiceTag)
            [void]$item.SubItems.Add($srv.Model)
            [void]$item.SubItems.Add($srv.OSHostname)
            [void]$item.SubItems.Add($srv.Health)
            [void]$item.SubItems.Add($srv.Group)
            [void]$item.SubItems.Add($credText)
            try {
                switch -Regex ($srv.Health) {
                    "Critical" { $item.ForeColor = $colorCritical; break }
                    "Warning"  { $item.ForeColor = $colorWarn; break }
                    "OK"       { $item.ForeColor = $colorHealthy; break }
                }
            }
            catch {}
            [void]$list.Items.Add($item)
        }
        $list.Add_DoubleClick({ Open-KvmEmbedded })
        $recentPanel.Controls.Add($list)

        [void]$script:Tabs.TabPages.Add($dash)
        $script:Tabs.SelectedTab = $dash
    }

    $root = New-Object System.Windows.Forms.Panel
    $root.Dock = "Fill"
    $root.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)

    $top = New-Object System.Windows.Forms.Panel
    $top.Dock = "Top"
    $top.Height = 50
    $top.BackColor = $colorBlue

    $logo = New-Object System.Windows.Forms.Label
    $logo.Text = "▣"
    $logo.Left = 12; $logo.Top = 8; $logo.Width = 32; $logo.Height = 32
    $logo.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 20, [System.Drawing.FontStyle]::Bold)
    $logo.ForeColor = [System.Drawing.Color]::White
    $top.Controls.Add($logo)

    $appTitle = New-Object System.Windows.Forms.Label
    $appTitle.Text = "iDRAC Connection Manager"
    $appTitle.Left = 50; $appTitle.Top = 13; $appTitle.Width = 520; $appTitle.Height = 26
    $appTitle.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $appTitle.ForeColor = [System.Drawing.Color]::White
    $top.Controls.Add($appTitle)

    $topRight = New-Object System.Windows.Forms.Panel
    $topRight.Dock = "Right"
    $topRight.Width = 320
    $topRight.BackColor = $colorBlue

    $txtTopSearch = New-Object System.Windows.Forms.TextBox
    $script:TopSearchBox = $txtTopSearch
    $txtTopSearch.Left = 8
    $txtTopSearch.Top = 12
    $txtTopSearch.Width = 175
    $txtTopSearch.Height = 24
    $txtTopSearch.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $txtTopSearch.BorderStyle = "FixedSingle"
    $txtTopSearch.Text = ""
    try {
        $txtTopSearch.ForeColor = [System.Drawing.Color]::FromArgb(80,80,80)
        $txtTopSearch.BackColor = [System.Drawing.Color]::White
    } catch {}
    $txtTopSearch.Add_KeyDown({
        try {
            if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
                $_.SuppressKeyPress = $true
                Show-iDRACCManSearch -InitialText $txtTopSearch.Text.Trim()
            }
        } catch {}
    }.GetNewClosure())
    $topRight.Controls.Add($txtTopSearch)

    $btnTopSearch = New-Object System.Windows.Forms.Label
    $btnTopSearch.Text = "⌕"
    $btnTopSearch.Left = 188
    $btnTopSearch.Top = 8
    $btnTopSearch.Width = 34
    $btnTopSearch.Height = 34
    $btnTopSearch.TextAlign = "MiddleCenter"
    $btnTopSearch.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 15)
    $btnTopSearch.ForeColor = [System.Drawing.Color]::White
    $btnTopSearch.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnTopSearch.Add_Click({
        try {
            Show-iDRACCManSearch -InitialText $txtTopSearch.Text.Trim()
        } catch {
            Show-iDRACCManSearch
        }
    }.GetNewClosure())
    $btnTopSearch.Add_MouseEnter({ $btnTopSearch.BackColor = $colorBlueDark }.GetNewClosure())
    $btnTopSearch.Add_MouseLeave({ $btnTopSearch.BackColor = $colorBlue }.GetNewClosure())
    $topRight.Controls.Add($btnTopSearch)

    $lblIssues = New-Object System.Windows.Forms.Label
    $lblIssues.Text = "👤"
    $lblIssues.Left = 232
    $lblIssues.Top = 8
    $lblIssues.Width = 34
    $lblIssues.Height = 34
    $lblIssues.TextAlign = "MiddleCenter"
    $lblIssues.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 13)
    $lblIssues.ForeColor = [System.Drawing.Color]::White
    $lblIssues.Cursor = [System.Windows.Forms.Cursors]::Hand
    $lblIssues.Add_MouseEnter({ $lblIssues.BackColor = $colorBlueDark }.GetNewClosure())
    $lblIssues.Add_MouseLeave({ $lblIssues.BackColor = $colorBlue }.GetNewClosure())
    $lblIssues.Add_Click({
        try {
            Start-Process "https://github.com/DellProSupportGse/Tools/issues"
            if ($script:Status) { $script:Status.Text = "Opened GitHub Issues & Feedback." }
            Send-iDRACCManTelemetry -EventName "OpenIssues" -Properties @{ Target = "GitHubIssues" }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Could not open GitHub Issues & Feedback.`r`n`r`nhttps://github.com/DellProSupportGse/Tools/issues",
                "Issues & Feedback",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
    }.GetNewClosure())
    $topRight.Controls.Add($lblIssues)

    $lblHelp = New-Object System.Windows.Forms.Label
    $lblHelp.Text = "?"
    $lblHelp.Left = 270
    $lblHelp.Top = 8
    $lblHelp.Width = 34
    $lblHelp.Height = 34
    $lblHelp.TextAlign = "MiddleCenter"
    $lblHelp.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
    $lblHelp.ForeColor = [System.Drawing.Color]::White
    $lblHelp.Cursor = [System.Windows.Forms.Cursors]::Hand
    $lblHelp.Add_MouseEnter({ $lblHelp.BackColor = $colorBlueDark }.GetNewClosure())
    $lblHelp.Add_MouseLeave({ $lblHelp.BackColor = $colorBlue }.GetNewClosure())
    $lblHelp.Add_Click({ Open-iDRACCManHelp -Source "TopRightIcon" }.GetNewClosure())
    $topRight.Controls.Add($lblHelp)

    $top.Controls.Add($topRight)

    $menu = New-Object System.Windows.Forms.MenuStrip
    $menu.Dock = "Top"
    $menu.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $menu.BackColor = [System.Drawing.Color]::White
    $menu.ForeColor = $colorText
    $menu.RenderMode = "System"

    $mFile = New-Object System.Windows.Forms.ToolStripMenuItem("File")
    $mServer = New-Object System.Windows.Forms.ToolStripMenuItem("Server")
    $mActions = New-Object System.Windows.Forms.ToolStripMenuItem("Actions")
    $mTools = New-Object System.Windows.Forms.ToolStripMenuItem("Tools")
    $mHelp = New-Object System.Windows.Forms.ToolStripMenuItem("Help")

    $miImport = New-Object System.Windows.Forms.ToolStripMenuItem("Import CSV")
    $miImport.Add_Click({ Import-ServersCsv })
    $miExport = New-Object System.Windows.Forms.ToolStripMenuItem("Export CSV")
    $miExport.Add_Click({ Export-ServersCsv })
    $miExit = New-Object System.Windows.Forms.ToolStripMenuItem("Exit")
    $miExit.Add_Click({ $script:MainForm.Close() })

    $miAdd = New-Object System.Windows.Forms.ToolStripMenuItem("Add iDRAC")
    $miAdd.Add_Click({ Show-ServerDialog })
    $miEdit = New-Object System.Windows.Forms.ToolStripMenuItem("Edit Selected")
    $miEdit.Add_Click({ $s = Get-SelectedServer; if ($s) { Show-ServerDialog -Server $s } })
    $miDelete = New-Object System.Windows.Forms.ToolStripMenuItem("Delete Selected")
    $miDelete.Add_Click({
        $s = Get-SelectedServer
        if (-not $s) { return }
        if ([System.Windows.Forms.MessageBox]::Show("Delete $($s.Name)?","Delete",[System.Windows.Forms.MessageBoxButtons]::YesNo) -eq [System.Windows.Forms.DialogResult]::Yes) {
            $script:Servers = @($script:Servers | Where-Object { -not (($_.Name -eq $s.Name) -and ($_.Address -eq $s.Address)) })
            Save-Servers
            Refresh-Tree
        }
    })
    $miGroupCreds = New-Object System.Windows.Forms.ToolStripMenuItem("Edit Credentials")
    $miGroupCreds.Add_Click({ Show-GroupCredentialDialog })
    $miRefresh = New-Object System.Windows.Forms.ToolStripMenuItem("Refresh Tree")
    $miRefresh.Add_Click({ Refresh-Tree; Update-DashboardServerList })

    $miOpenKvm = New-Object System.Windows.Forms.ToolStripMenuItem("Open Console")
    $miOpenKvm.Add_Click({ Open-KvmEmbedded })
    $miMultiView = New-Object System.Windows.Forms.ToolStripMenuItem("Multi View")
    $miMultiView.Add_Click({ Open-MultiViewForSelectedGroup })
    $miOpenWeb = New-Object System.Windows.Forms.ToolStripMenuItem("Open GUI")
    $miOpenWeb.Add_Click({ Open-WebEmbedded })
    $miRefreshSelectedHealth = New-Object System.Windows.Forms.ToolStripMenuItem("Refresh Selected Health")
    $miRefreshSelectedHealth.Add_Click({ Refresh-SelectediDRACHealth })
    $miRefreshAllHealth = New-Object System.Windows.Forms.ToolStripMenuItem("Refresh All Health")
    $miRefreshAllHealth.Add_Click({ Refresh-AlliDRACHealth })

    $miCloseTab = New-Object System.Windows.Forms.ToolStripMenuItem("Close Current")
    $miCloseTab.Add_Click({ Close-CurrentTab })

    $miTelemetryToggle = New-Object System.Windows.Forms.ToolStripMenuItem("Toggle Telemetry")
    $miTelemetryToggle.Add_Click({
        $current = [bool](Get-iDRACCManSetting -Name "TelemetryEnabled" -Default $true)
        Set-iDRACCManSetting -Name "TelemetryEnabled" -Value (-not $current)
        $state = if (-not $current) { "enabled" } else { "disabled" }
        if ($script:Status) { $script:Status.Text = "Telemetry $state." }
        [System.Windows.Forms.MessageBox]::Show("Telemetry is now $state.","Telemetry") | Out-Null
    })

    $miDiagnostics = New-Object System.Windows.Forms.ToolStripMenuItem("Diagnostics")
    $miDiagnostics.Add_Click({ Show-Diagnostics })
    $miOpenDataFolder = New-Object System.Windows.Forms.ToolStripMenuItem("Open Data Folder")
    $miOpenDataFolder.Add_Click({ Open-iDRACCManDataFolder })
    $miViewLogs = New-Object System.Windows.Forms.ToolStripMenuItem("View Logs")
    $miViewLogs.Add_Click({ Open-iDRACCManLogFolder })
    $miAbout = New-Object System.Windows.Forms.ToolStripMenuItem("About")
    $miAbout.Add_Click({
        [System.Windows.Forms.MessageBox]::Show(
            "iDRAC Connection Manager`r`nVersion: $script:AppVersion`r`nCreated By: Jim Gandy`r`n`r`nStorage:`r`n$script:AppRoot",
            "About",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    })

    $miDocumentation = New-Object System.Windows.Forms.ToolStripMenuItem("Documentation")
    $miDocumentation.Add_Click({ Open-iDRACCManHelp -Source "HelpMenu" })

    [void]$mFile.DropDownItems.Add($miImport)
    [void]$mFile.DropDownItems.Add($miExport)
    [void]$mFile.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$mFile.DropDownItems.Add($miExit)
    [void]$mServer.DropDownItems.Add($miAdd)
    [void]$mServer.DropDownItems.Add($miEdit)
    [void]$mServer.DropDownItems.Add($miDelete)
    [void]$mServer.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$mServer.DropDownItems.Add($miGroupCreds)
    [void]$mServer.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$mServer.DropDownItems.Add($miRefresh)
    [void]$mActions.DropDownItems.Add($miOpenKvm)
    [void]$mActions.DropDownItems.Add($miMultiView)
    [void]$mActions.DropDownItems.Add($miOpenWeb)
    [void]$mActions.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$mActions.DropDownItems.Add($miRefreshSelectedHealth)
    [void]$mActions.DropDownItems.Add($miRefreshAllHealth)
    [void]$mTools.DropDownItems.Add($miCloseTab)
    [void]$mTools.DropDownItems.Add($miTelemetryToggle)
    [void]$mTools.DropDownItems.Add($miDiagnostics)
    [void]$mHelp.DropDownItems.Add($miDocumentation)
    [void]$mHelp.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$mHelp.DropDownItems.Add($miOpenDataFolder)
    [void]$mHelp.DropDownItems.Add($miViewLogs)
    [void]$mHelp.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$mHelp.DropDownItems.Add($miAbout)
    [void]$menu.Items.Add($mFile)
    [void]$menu.Items.Add($mServer)
    [void]$menu.Items.Add($mActions)
    [void]$menu.Items.Add($mTools)
    [void]$menu.Items.Add($mHelp)

    $banner = New-Object System.Windows.Forms.Panel
    $banner.Dock = "Top"
    $banner.Height = 0
    $banner.BackColor = [System.Drawing.Color]::FromArgb(255,245,200)
    if (-not $script:WebViewReady) {
        $banner.Height = 40
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = "WebView2 is not ready. Embedded Web/KVM tabs require Microsoft Edge WebView2 Runtime."
        $lbl.Left = 10; $lbl.Top = 12; $lbl.Width = 700; $lbl.Height = 20
        $install = New-Object System.Windows.Forms.Button
        $install.Text = "Install WebView2"; $install.Left = 720; $install.Top = 8; $install.Width = 120
        $install.Add_Click({ Start-Process "https://go.microsoft.com/fwlink/p/?LinkId=2124703" })
        $banner.Controls.Add($lbl)
        $banner.Controls.Add($install)
    }

    $split = New-Object System.Windows.Forms.SplitContainer
    $script:MainSplit = $split
    $split.Dock = "Fill"

    $savedConnectionsWidth = [int](Get-iDRACCManSetting -Name "ConnectionsWidth" -Default 260)
    if ($savedConnectionsWidth -lt 220) { $savedConnectionsWidth = 260 }
    if ($savedConnectionsWidth -gt 650) { $savedConnectionsWidth = 650 }

    $split.SplitterDistance = $savedConnectionsWidth
    $split.FixedPanel = "Panel1"
    $split.BackColor = $colorBorder
    $split.Panel1.BackColor = $colorSide
    $split.Panel2.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)
    $split.Add_SplitterMoved({
        try {
            if (-not $script:MainSplit.Panel1Collapsed) {
                Set-iDRACCManSetting -Name "ConnectionsWidth" -Value ([int]$script:MainSplit.SplitterDistance)
            }
        }
        catch {}
    })

    $navHeader = New-Object System.Windows.Forms.Panel
    $navHeader.Dock = "Top"
    $navHeader.Height = 42
    $navHeader.BackColor = $colorSide
    $navTitle = New-Object System.Windows.Forms.Label
    $navTitle.Text = "Connections"
    $navTitle.Left = 18; $navTitle.Top = 12; $navTitle.Width = 210; $navTitle.Height = 22
    $navTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $navTitle.ForeColor = $colorText
    $navHeader.Controls.Add($navTitle)

    $script:Tree = New-Object System.Windows.Forms.TreeView
    $script:Tree.Dock = "Fill"
    $script:Tree.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $script:Tree.HideSelection = $false
    $script:Tree.BorderStyle = "None"
    $script:Tree.BackColor = $colorSide
    $script:Tree.ForeColor = $colorText
    $script:Tree.ShowLines = $false
    $script:Tree.ItemHeight = 26

    $script:Tree.Add_NodeMouseClick({
        if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
            Show-ServerContextMenu -Node $_.Node -Location $_.Location
        }
    })
    $script:Tree.Add_AfterSelect({
        try { $_.Node.BackColor = $colorSelected; $_.Node.ForeColor = $colorBlue } catch {}
    })
    $script:Tree.Add_NodeMouseDoubleClick({
        if ($_.Node.Tag) {
            $script:Tree.SelectedNode = $_.Node
            try {
                if ($_.Node.Tag.IsGroup) { Show-GroupCredentialDialog } else { Open-KvmEmbedded }
            }
            catch { Open-KvmEmbedded }
        }
    })

    $script:Tabs = New-Object System.Windows.Forms.TabControl
    $script:Tabs.Dock = "Fill"
    $script:Tabs.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $script:Tabs.Appearance = "Normal"

    $tabCm = New-Object System.Windows.Forms.ContextMenuStrip
    $tabCm.Font = $script:AppFont
    $miClose = New-Object System.Windows.Forms.ToolStripMenuItem("Close")
    $miClose.Add_Click({ Close-CurrentTab })
    [void]$tabCm.Items.Add($miClose)
    $script:Tabs.ContextMenuStrip = $tabCm

    $split.Panel1.Controls.Add($script:Tree)
    $split.Panel1.Controls.Add($navHeader)

    # Small modern centered side-tab used to collapse/open the Connections menu.
    # This only changes the toggle handle styling; the rest of the UI is left unchanged.
    $script:ConnectionsToggleHover = $false

    $connectionsToggleRail = New-Object System.Windows.Forms.Panel
    $script:ConnectionsToggleRail = $connectionsToggleRail
    $connectionsToggleRail.Width = 20
    $connectionsToggleRail.Height = 68
    $connectionsToggleRail.Left = 0
    $connectionsToggleRail.Top = 220
    $connectionsToggleRail.BackColor = $split.Panel2.BackColor
    $connectionsToggleRail.Cursor = [System.Windows.Forms.Cursors]::Hand
    $connectionsToggleRail.Anchor = [System.Windows.Forms.AnchorStyles]::Left
    $connectionsToggleRail.TabStop = $false
    try { $connectionsToggleRail.AccessibleName = 'Collapse Connections menu' } catch {}

    $connectionsToggle = New-Object System.Windows.Forms.Label
    $script:ConnectionsToggleButton = $connectionsToggle
    $connectionsToggle.Dock = 'Fill'
    $connectionsToggle.BackColor = [System.Drawing.Color]::Transparent
    $connectionsToggle.ForeColor = $colorBlue
    $connectionsToggle.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 13, [System.Drawing.FontStyle]::Bold)
    $connectionsToggle.TextAlign = 'MiddleCenter'
    $connectionsToggle.Cursor = [System.Windows.Forms.Cursors]::Hand
    $connectionsToggle.Text = '‹'
    $connectionsToggle.TabStop = $false

    $connectionsToggleRail.Add_Paint({
        param($sender, $e)
        try {
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

            $isHover = $false
            try { $isHover = [bool]$script:ConnectionsToggleHover } catch {}

            $shadowRect = New-Object System.Drawing.Rectangle(2, 2, ($sender.Width - 3), ($sender.Height - 3))
            $mainRect   = New-Object System.Drawing.Rectangle(0, 0, ($sender.Width - 3), ($sender.Height - 3))

            $shadowPath = New-iDRACRoundedRectanglePath -Rectangle $shadowRect -Radius 9
            $mainPath   = New-iDRACRoundedRectanglePath -Rectangle $mainRect -Radius 9

            $shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(35, 0, 0, 0))
            $g.FillPath($shadowBrush, $shadowPath)
            $shadowBrush.Dispose()
            $shadowPath.Dispose()

            if ($isHover) {
                $fillColor = [System.Drawing.Color]::FromArgb(0,120,215)
                $borderColor = [System.Drawing.Color]::FromArgb(0,90,170)
            }
            else {
                $fillColor = [System.Drawing.Color]::FromArgb(255,255,255)
                $borderColor = [System.Drawing.Color]::FromArgb(210,216,224)
            }

            $fillBrush = New-Object System.Drawing.SolidBrush($fillColor)
            $borderPen = New-Object System.Drawing.Pen($borderColor, 1)

            $g.FillPath($fillBrush, $mainPath)
            $g.DrawPath($borderPen, $mainPath)

            $fillBrush.Dispose()
            $borderPen.Dispose()
            $mainPath.Dispose()
        }
        catch {}
    }.GetNewClosure())

    $setToggleHoverOn = {
        try {
            $script:ConnectionsToggleHover = $true
            $connectionsToggle.ForeColor = [System.Drawing.Color]::White
            $connectionsToggleRail.Invalidate()
        }
        catch {}
    }.GetNewClosure()

    $setToggleHoverOff = {
        try {
            $script:ConnectionsToggleHover = $false
            $connectionsToggle.ForeColor = $colorBlue
            $connectionsToggleRail.Invalidate()
        }
        catch {}
    }.GetNewClosure()

    $connectionsToggleRail.Add_MouseEnter($setToggleHoverOn)
    $connectionsToggleRail.Add_MouseLeave($setToggleHoverOff)
    $connectionsToggle.Add_MouseEnter($setToggleHoverOn)
    $connectionsToggle.Add_MouseLeave($setToggleHoverOff)

    $connectionsToggle.Add_Click({ Toggle-ConnectionsMenu })
    $connectionsToggleRail.Add_Click({ Toggle-ConnectionsMenu })
    $connectionsToggleRail.Controls.Add($connectionsToggle)

    $split.Panel2.Controls.Add($script:Tabs)
    $split.Panel2.Controls.Add($connectionsToggleRail)
    $connectionsToggleRail.BringToFront()
    $split.Panel2.Add_Resize({ Update-ConnectionsToggleTab })

    $startCollapsed = $false
    try { $startCollapsed = [bool](Get-iDRACCManSetting -Name 'ConnectionsCollapsed' -Default $false) } catch {}
    if ($startCollapsed) {
        $split.Panel1Collapsed = $true
    }
    Update-ConnectionsToggleTab

    $script:Status = New-Object System.Windows.Forms.StatusBar
    $script:Status.Text = "Ready"

    $root.Controls.Add($split)
    $root.Controls.Add($banner)
    $root.Controls.Add($menu)
    $root.Controls.Add($top)

    $script:MainForm.Controls.Add($root)
    $script:MainForm.Controls.Add($script:Status)
    $script:MainForm.MainMenuStrip = $menu

    Refresh-Tree
    Add-DashboardTab
    Resize-SideMenuToContent
}


function Invoke-iDRACCMan {
    [CmdletBinding()]
    param()

    try {
        Write-iDRACCManLog "Starting iDRACCMan version $script:AppVersion"
        Initialize-iDRACCManSettings

        Load-Servers
        Load-GroupCredentials

        if ([Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
            [System.Windows.Forms.MessageBox]::Show(
                "STA mode is recommended.`r`n`r`nUse:`r`npowershell.exe -STA -ExecutionPolicy Bypass -File .\iDRAC-ConnectionManager.ps1",
                "STA Recommended"
            ) | Out-Null
        }

        [void](Initialize-WebView2)
        Build-Gui
        Send-iDRACCManTelemetry -EventName "AppReady" -Properties @{ ServerCount = @($script:Servers).Count; GroupCount = @($script:Servers | Group-Object Group).Count }

        $script:MainForm.Add_FormClosing({
            while ($script:Tabs.TabPages.Count -gt 0) {
                $script:Tabs.SelectedTab = $script:Tabs.TabPages[0]
                Close-CurrentTab
            }
            Send-iDRACCManTelemetry -EventName "AppClose" -Properties @{ ServerCount = @($script:Servers).Count }
            Write-iDRACCManLog "iDRACCMan closed"
        })

        [void][System.Windows.Forms.Application]::Run($script:MainForm)
    }
    catch {
        Write-iDRACCManLog $_.Exception.Message "ERROR"
        [System.Windows.Forms.MessageBox]::Show(
            "iDRACCMan failed to start.`r`n`r`n$($_.Exception.Message)",
            "iDRACCMan Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

# If run directly as a .ps1, launch the tool.
# If loaded with Invoke-Expression/dot-source, call Invoke-iDRACCMan manually.
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-iDRACCMan
}
