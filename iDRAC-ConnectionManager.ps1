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
Add-Type -AssemblyName System.Security

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:AppName      = "iDRAC Connection Manager"
$script:AppVersion   = "1.0.9"
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
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $script:SettingsFile -Encoding UTF8
    }
}

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

function New-iDRACKvmUrlDellMethod {
    param([Parameter(Mandatory=$true)]$Server)

    $idracHost = Get-iDRACHost $Server.Address
    $base = "https://$idracHost"
    $cred = Get-iDRACCredentialFromServer -Server $Server
    $userName = $cred.GetNetworkCredential().UserName
    $password = $cred.GetNetworkCredential().Password

    # 1. Create X-Auth-Token session.
    $script:Status.Text = "Creating X-Auth-Token session for $($Server.Name)..."
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
            }
        )
        Save-Servers
    }
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

            $node = New-Object System.Windows.Forms.TreeNode("$($s.Name) [$($s.Address)]$credTag")
            $node.Tag = $s
            [void]$gNode.Nodes.Add($node)
        }

        [void]$script:Tree.Nodes.Add($gNode)
        $gNode.Expand()
    }

    $script:Tree.EndUpdate()
    if ($script:MainSplit) { Resize-SideMenuToContent }
}

function Show-ServerDialog {
    param($Server)

    $isEdit = $null -ne $Server

    $f = New-Object System.Windows.Forms.Form
    $f.Text = if ($isEdit) { "Edit iDRAC" } else { "Add iDRAC" }
    $f.Width = 440
    $f.Height = 350
    $f.StartPosition = "CenterParent"
    $f.FormBorderStyle = "FixedDialog"
    $f.Font = $script:AppFont
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false

    $labels = @("Name","Address/IP","Group","Username","Password","Notes")
    $boxes = @{}

    for ($i=0; $i -lt $labels.Count; $i++) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $labels[$i]
        $lbl.Left = 12
        $lbl.Top = 18 + ($i * 38)
        $lbl.Width = 90
        $f.Controls.Add($lbl)

        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Left = 110
        $tb.Top = 14 + ($i * 38)
        $tb.Width = 290

        if ($labels[$i] -eq "Password") {
            $tb.UseSystemPasswordChar = $true
        }

        if ($labels[$i] -eq "Notes") {
            $tb.Multiline = $true
            $tb.Height = 48
        }
        else {
            $tb.Height = 23
        }

        $boxes[$labels[$i]] = $tb
        $f.Controls.Add($tb)
    }

    if ($isEdit) {
        $boxes["Name"].Text = $Server.Name
        $boxes["Address/IP"].Text = $Server.Address
        $boxes["Group"].Text = $Server.Group
        $boxes["Username"].Text = $Server.Username
        $boxes["Password"].Text = ConvertFrom-ProtectedString $Server.Password
        $boxes["Notes"].Text = $Server.Notes
    }

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "OK"
    $ok.Left = 235
    $ok.Top = 260
    $ok.Width = 75
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancel"
    $cancel.Left = 325
    $cancel.Top = 260
    $cancel.Width = 75
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $f.AcceptButton = $ok
    $f.CancelButton = $cancel
    $f.Controls.Add($ok)
    $f.Controls.Add($cancel)

    if ($f.ShowDialog($script:MainForm) -eq [System.Windows.Forms.DialogResult]::OK) {
        if ([string]::IsNullOrWhiteSpace($boxes["Name"].Text) -or [string]::IsNullOrWhiteSpace($boxes["Address/IP"].Text)) {
            [System.Windows.Forms.MessageBox]::Show("Name and Address/IP are required.") | Out-Null
            return
        }

        if ($isEdit) {
            $Server.Name = $boxes["Name"].Text.Trim()
            $Server.Address = $boxes["Address/IP"].Text.Trim()
            $Server.Group = $boxes["Group"].Text.Trim()
            $Server.Username = $boxes["Username"].Text.Trim()
            $Server.Password = ConvertTo-ProtectedString $boxes["Password"].Text
            $Server.Notes = $boxes["Notes"].Text
        }
        else {
            $script:Servers += [pscustomobject]@{
                Name = $boxes["Name"].Text.Trim()
                Address = $boxes["Address/IP"].Text.Trim()
                Group = $boxes["Group"].Text.Trim()
                Username = $boxes["Username"].Text.Trim()
                Password = ConvertTo-ProtectedString $boxes["Password"].Text
                Notes = $boxes["Notes"].Text
            }
        }

        Save-Servers
        Refresh-Tree
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

function Add-WebViewTab {
    param(
        [Parameter(Mandatory=$true)]$Server,
        [Parameter(Mandatory=$true)][string]$Url,
        [switch]$IsKvm
    )

    if (-not $script:WebViewReady) {
        [System.Windows.Forms.MessageBox]::Show(
            "WebView2 is not ready.`r`n`r`nInstall WebView2 Runtime or restart the script.",
            "WebView2 Not Ready"
        ) | Out-Null
        return
    }

    $tab = New-Object System.Windows.Forms.TabPage
    $tab.Text = $Server.Name

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
    $btnKvm.Add_Click({ Open-WebEmbedded })

    $info = New-Object System.Windows.Forms.Label
    $info.Left = 145
    $info.Top = 10
    $info.Width = 1200
    $info.Height = 22
    $info.Text = if ($IsKvm) {
        ""
    }
    else {
        ""
    }

    if ($IsKvm) {
        $bar.Controls.AddRange(@($btnClose,$btnKvm,$info))
    }
    else {
        $bar.Controls.AddRange(@($btnClose,$info))
    }

    $web = New-Object Microsoft.Web.WebView2.WinForms.WebView2
    $web.Dock = "Fill"
    $web.CreationProperties = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
    $web.CreationProperties.UserDataFolder = $script:WebDataRoot

    $outer.Controls.Add($web)
    $outer.Controls.Add($bar)
    $tab.Controls.Add($outer)

    [void]$script:Tabs.TabPages.Add($tab)
    $script:Tabs.SelectedTab = $tab

    try {
        $null = $web.EnsureCoreWebView2Async($script:WebViewEnvironment)

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
        })
$web.CoreWebView2.Navigate($Url)
        $tab.Tag = [pscustomobject]@{
            Server = $Server
            Url = $Url
            IsKvm = [bool]$IsKvm
            WebView = $web
            KvmSessionKey = $null
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
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to create KVM session.`r`n`r`n$($_.Exception.Message)",
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
            }
        }

        Save-Servers
        Refresh-Tree
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

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Multi View: $groupName"
    $lbl.Left = 85
    $lbl.Top = 8
    $lbl.Width = 500
    $lbl.Height = 22

    $bar.Controls.AddRange(@($btnClose,$lbl))

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
}


function Resize-SideMenuToContent {
    try {
        if (-not $script:Tree -or -not $script:MainForm) { return }

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

        $miDeleteGroup = New-Object System.Windows.Forms.ToolStripMenuItem("Delete Group")
        $miDeleteGroup.Add_Click({ Delete-SelectedGroup })

        [void]$cm.Items.Add($miEditGroupCreds)
        [void]$cm.Items.Add($miMultiView)
        [void]$cm.Items.Add($miConnectAll)
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

        [void]$cm.Items.Add($miOpenConsole)
        [void]$cm.Items.Add($miOpenGui)
        [void]$cm.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        [void]$cm.Items.Add($miEditCredentials)
    }

    $cm.Show($script:Tree, $Location)
}

function Build-Gui {
    $script:MainForm = New-Object System.Windows.Forms.Form
    $script:MainForm.Text = "$script:AppName - Created By: Jim Gandy"
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
        $icon.Font = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
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
        $surface.Controls.Add((New-UiButton -Text "Refresh" -Left 360 -Top 58 -Width 90 -Click { Refresh-Tree; $script:Status.Text = "Tree refreshed" }))

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
        $recentTitle.Left = 14; $recentTitle.Top = 12; $recentTitle.Width = 400; $recentTitle.Height = 25
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
        [void]$list.Columns.Add("Host Name", 210)
        [void]$list.Columns.Add("IP / Address", 160)
        [void]$list.Columns.Add("Group", 150)
        [void]$list.Columns.Add("Credential", 130)
        [void]$list.Columns.Add("Notes", 210)
        foreach ($srv in @($script:Servers | Sort-Object Group,Name)) {
            $credText = if (-not [string]::IsNullOrWhiteSpace($srv.Username)) { "Server" } elseif (Get-GroupCredentialRecord -GroupName $srv.Group) { "Group" } else { "Prompt" }
            $item = New-Object System.Windows.Forms.ListViewItem($srv.Name)
            [void]$item.SubItems.Add($srv.Address)
            [void]$item.SubItems.Add($srv.Group)
            [void]$item.SubItems.Add($credText)
            [void]$item.SubItems.Add($srv.Notes)
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

    $topRight = New-Object System.Windows.Forms.Label
    $topRight.Text = "⌕   🔒   👤   ?"
    $topRight.Dock = "Right"
    $topRight.Width = 170
    $topRight.TextAlign = "MiddleCenter"
    $topRight.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 13)
    $topRight.ForeColor = [System.Drawing.Color]::White
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
    $miRefresh.Add_Click({ Refresh-Tree })

    $miOpenKvm = New-Object System.Windows.Forms.ToolStripMenuItem("Open Console")
    $miOpenKvm.Add_Click({ Open-KvmEmbedded })
    $miMultiView = New-Object System.Windows.Forms.ToolStripMenuItem("Multi View")
    $miMultiView.Add_Click({ Open-MultiViewForSelectedGroup })
    $miOpenWeb = New-Object System.Windows.Forms.ToolStripMenuItem("Open GUI")
    $miOpenWeb.Add_Click({ Open-WebEmbedded })

    $miCloseTab = New-Object System.Windows.Forms.ToolStripMenuItem("Close Current")
    $miCloseTab.Add_Click({ Close-CurrentTab })
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
    [void]$mTools.DropDownItems.Add($miCloseTab)
    [void]$mTools.DropDownItems.Add($miDiagnostics)
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
    $split.SplitterDistance = 260
    $split.FixedPanel = "Panel1"
    $split.BackColor = $colorBorder
    $split.Panel1.BackColor = $colorSide
    $split.Panel2.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)

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
    $split.Panel2.Controls.Add($script:Tabs)

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

        $script:MainForm.Add_FormClosing({
            while ($script:Tabs.TabPages.Count -gt 0) {
                $script:Tabs.SelectedTab = $script:Tabs.TabPages[0]
                Close-CurrentTab
            }
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
