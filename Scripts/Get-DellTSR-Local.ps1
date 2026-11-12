#requires -Version 5.1
<#
.SYNOPSIS
    Collect a Dell SupportAssist Collection (TSR) locally and add OS PCI drivers.
.DESCRIPTION
    Uses Dell's installed iDRAC Service Module (iSM) Invoke-SupportAssistCollection.exe.
    If the collector is missing, optionally prompts to download/install a Dell-signed
    iDRACSvcMod.msi. Requires administrator privileges to collect or install.
    Does not require iDRAC credentials or RACADM.
    Dell MSI packages are model/OS specific. Supply -IsmInstallerPath or
    -IsmInstallerUrl, or provide one interactively when asked. The script does
    not guess a download based on the hardware model.
.EXAMPLE
    .\Get-DellTSR-Local.ps1 -CheckOnly
.EXAMPLE
    .\Get-DellTSR-Local.ps1 -OutputDirectory C:\Dell\TSR
.EXAMPLE
    .\Get-DellTSR-Local.ps1 -IsmInstallerPath C:\Temp\iDRACSvcMod.msi
.EXAMPLE
    .\Get-DellTSR-Local.ps1 -IsmInstallerUrl https://dl.dell.com/path/to/iDRACSvcMod.msi
.EXAMPLE
    .\Get-DellTSR-Local.ps1 -NoInstallIsm
.NOTES
    Version: 1.2.9
    Windows PowerShell 5.1+. Never installs without explicit approval.
.CREATOR
    Jim Gandy
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path ([Environment]::GetFolderPath('CommonDocuments')) 'DellTSR'),
    [string]$CollectorPath,
    [switch]$CheckOnly,
    [switch]$NoInstallIsm,
    [string]$IsmInstallerPath,
    [string]$IsmInstallerUrl
)
$ErrorActionPreference = 'Stop'
$Ver = "1.2.9"
$Banner = @'
   ___     _       ___      _ _ _____ ___ ___     _                 _
  / __|___| |_ ___|   \ ___| | |_   _/ __| _ \___| |   ___  __ __ _| |
 | (_ / -_)  _|___| |) / -_) | | | | \__ \   /___| |__/ _ \/ _/ _` | |
  \___\___|\__|   |___/\___|_|_| |_| |___/_|_\   |____\___/\__\__,_|_|
'@
Write-Host $Banner -ForegroundColor Cyan
Write-Host "Version: $Ver  |  Created by Jim Gandy" -ForegroundColor Gray
Write-Host ""
function Find-DellCollector {
    param([string]$Explicit)
    if ($Explicit) {
        if (-not (Test-Path -LiteralPath $Explicit -PathType Leaf)) { throw "Collector not found: $Explicit" }
        return (Resolve-Path -LiteralPath $Explicit).ProviderPath
    }
    $command = Get-Command 'Invoke-SupportAssistCollection.exe' -ErrorAction SilentlyContinue
    if ($command -and $command.Source -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        return $command.Source
    }
    $roots = @(
        if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Dell' }
        if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Dell' }
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
    foreach ($root in $roots) {
        $match = Get-ChildItem -LiteralPath $root -Filter 'Invoke-SupportAssistCollection.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($match) { return $match.FullName }
    }
    return $null
}
function Test-IsmInstalled {
    # Query uninstall registry only, never Win32_Product (which can trigger MSI repair).
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($root in $roots) {
        $matches = @(Get-ItemProperty -Path $root -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match 'iDRAC Service Module' })
        if ($matches.Count -gt 0) { return $true }
    }
    return $false
}
function Request-Approval {
    param([string]$Message)
    if (-not [Environment]::UserInteractive) { return $false }
    try {
        $answer = Read-Host "$Message [y/N]"
        return ($answer -match '^(?i:y|yes)$')
    } catch { return $false }
}
function Test-DellMsiSignature {
    param([Parameter(Mandatory=$true)][string]$Path)
    if ([IO.Path]::GetExtension($Path) -ine '.msi') { throw 'Only Dell-signed iDRACSvcMod.msi packages are accepted for automatic installation.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) {
        throw "Installer signature is not valid ($($signature.Status)). Refusing installation: $Path"
    }
    $subject = [string]$signature.SignerCertificate.Subject
    if ($subject -notmatch '(?i)\bDell\b') {
        throw "Installer signer is not Dell ($subject). Refusing installation."
    }
    Write-Host "Verified Dell digital signature: $subject" -ForegroundColor Green
}
function Install-DellIsmIfApproved {
    param([string]$LocalInstaller, [string]$InstallerUrl)
    if (-not (Request-Approval 'Dell SupportAssist collector is missing. Download/install Dell iDRAC Service Module (iSM) now?')) {
        Write-Host 'iSM installation declined.' -ForegroundColor Yellow
        return $false
    }
    if ($LocalInstaller -and $InstallerUrl) { throw 'Specify only one of -IsmInstallerPath or -IsmInstallerUrl.' }
    if (-not $LocalInstaller -and -not $InstallerUrl) {
        Write-Host 'Provide the Windows iDRACSvcMod.msi for this server and OS, from Dell Support.'
        Write-Host 'Dell support: https://www.dell.com/support/home'
        if (-not [Environment]::UserInteractive) { throw 'Installer path or URL is required in noninteractive execution.' }
        $choice = Read-Host 'Enter a local MSI path or official Dell HTTPS MSI URL (blank to cancel)'
        if (-not $choice) { Write-Host 'Installation canceled.'; return $false }
        if ($choice -match '^https://') { $InstallerUrl = $choice }
        else { $LocalInstaller = $choice.Trim('"') }
    }
    $tempDir = $null
    $msiPath = $null
    try {
        if ($InstallerUrl) {
            $uri = $null
            if (-not [Uri]::TryCreate($InstallerUrl, [UriKind]::Absolute, [ref]$uri) -or
                $uri.Scheme -ne 'https' -or
                $uri.Host -notin @('dl.dell.com', 'downloads.dell.com') -or
                -not $uri.AbsolutePath.EndsWith('.msi', [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Installer URL must point directly to an HTTPS .msi on dl.dell.com or downloads.dell.com.'
            }
            $tempDir = Join-Path ([IO.Path]::GetTempPath()) ('DellIsm-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            $msiPath = Join-Path $tempDir 'iDRACSvcMod.msi'
            Write-Host "Downloading Dell iSM MSI from $($uri.AbsoluteUri)"
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $uri.AbsoluteUri -OutFile $msiPath -UseBasicParsing -MaximumRedirection 0
        } else {
            if (-not (Test-Path -LiteralPath $LocalInstaller -PathType Leaf)) { throw "Installer not found: $LocalInstaller" }
            $msiPath = (Resolve-Path -LiteralPath $LocalInstaller).ProviderPath
        }
        Test-DellMsiSignature -Path $msiPath
        Write-Host 'Starting Dell iSM silent installation (no automatic reboot)...'
        $logFile = Join-Path ([IO.Path]::GetTempPath()) ('DellIsmInstall-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
        $arguments = '/i "{0}" /qn /norestart /L*v "{1}"' -f $msiPath, $logFile
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru
        Write-Host "iSM install log: $logFile"
        if ($process.ExitCode -notin @(0, 3010, 1641)) {
            throw "Dell iSM MSI installation failed with exit code $($process.ExitCode). Review: $logFile"
        }
        if ($process.ExitCode -in @(3010, 1641)) {
            Write-Warning 'Dell iSM installation indicates a reboot may be required. No reboot will be initiated by this script.'
        }
        return $true
    }
    finally {
        if ($tempDir -and (Test-Path -LiteralPath $tempDir)) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
function Get-OsPciDriverInventory {
    $signedDrivers = @(Get-CimInstance -ClassName Win32_PnPSignedDriver |
        Where-Object { $_.DeviceID -like 'PCI\*' })
    $records = @(
        foreach ($driver in $signedDrivers) {
            $instanceId = [string]$driver.DeviceID
            $vendor = ''; $device = ''; $subVendor = ''; $subDevice = ''; $revision = ''
            if ($instanceId -match 'VEN_([0-9A-F]{4})') { $vendor = $Matches[1].ToUpperInvariant() }
            if ($instanceId -match 'DEV_([0-9A-F]{4})') { $device = $Matches[1].ToUpperInvariant() }
            if ($instanceId -match 'SUBSYS_([0-9A-F]{4})([0-9A-F]{4})') {
                $subDevice = $Matches[1].ToUpperInvariant()
                $subVendor = $Matches[2].ToUpperInvariant()
            }
            if ($instanceId -match 'REV_([0-9A-F]{2})') { $revision = $Matches[1].ToUpperInvariant() }
            [pscustomobject]@{
                DeviceName    = [string]$driver.DeviceName
                VendorID      = $vendor
                DeviceID      = $device
                SubVendorID   = $subVendor
                SubDeviceID   = $subDevice
                Revision      = $revision
                DriverVersion = [string]$driver.DriverVersion
                DriverDate    = if ($driver.DriverDate) { ([datetime]$driver.DriverDate).ToString('yyyy-MM-dd') } else { $null }
                Provider      = [string]$driver.DriverProviderName
                INF           = [string]$driver.InfName
                InstanceId    = $instanceId
            }
        }
    )
    $unique = @(
        foreach ($group in ($records | Group-Object -Property VendorID, DeviceID, SubVendorID, SubDeviceID)) {
            $instances = @($group.Group | Sort-Object InstanceId)
            $first = $instances[0]
            [pscustomobject]@{
                DeviceName      = $first.DeviceName
                VendorID        = $first.VendorID
                DeviceID        = $first.DeviceID
                SubVendorID     = $first.SubVendorID
                SubDeviceID     = $first.SubDeviceID
                Revision        = $first.Revision
                DriverVersion   = $first.DriverVersion
                DriverDate      = $first.DriverDate
                Provider        = $first.Provider
                INF             = $first.INF
                InstanceCount   = $instances.Count
                Instances       = $instances
                DellComponentID = $null
            }
        }
    )
    return [pscustomobject]@{
        SchemaVersion      = 1
        CollectedAtUtc     = (Get-Date).ToUniversalTime().ToString('o')
        ComputerName       = $env:COMPUTERNAME
        TotalPciInstances  = $records.Count
        UniquePciDevices   = $unique.Count
        Devices            = @($unique)
    }
}
function Add-OsDriversToTsrZip {
    param([Parameter(Mandatory=$true)][string]$ZipPath)
    Write-Host 'Collecting Windows PCI driver inventory...'
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $data = Get-OsPciDriverInventory
    $json = ConvertTo-Json -InputObject $data -Depth 12
    $watch.Stop()
    Write-Host ('PCI instances: {0}; unique PCI hardware IDs: {1}; elapsed: {2:N1}s' -f `
        $data.TotalPciInstances, $data.UniquePciDevices, $watch.Elapsed.TotalSeconds)
    Add-Type -AssemblyName System.IO.Compression
    $stream = $null; $zip = $null; $entryStream = $null; $writer = $null
    try {
        $stream = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $zip = [System.IO.Compression.ZipArchive]::new($stream,
            [System.IO.Compression.ZipArchiveMode]::Update, $false)
        $old = $zip.GetEntry('osdrivers.json')
        if ($old) { $old.Delete() }
        $entry = $zip.CreateEntry('osdrivers.json', [System.IO.Compression.CompressionLevel]::Optimal)
        $entryStream = $entry.Open()
        $writer = [System.IO.StreamWriter]::new($entryStream, [System.Text.UTF8Encoding]::new($false))
        $writer.Write($json)
        $writer.Flush()
        Write-Host "Added osdrivers.json to $ZipPath" -ForegroundColor Green
    }
    finally {
        if ($writer) { $writer.Dispose() }
        elseif ($entryStream) { $entryStream.Dispose() }
        if ($zip) { $zip.Dispose() }
        if ($stream) { $stream.Dispose() }
    }
}
if ($IsmInstallerPath -and $IsmInstallerUrl) { throw 'Choose either -IsmInstallerPath or -IsmInstallerUrl, not both.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ipmi = Get-CimInstance -Namespace 'root\wmi' -ClassName 'Microsoft_IPMI' -ErrorAction SilentlyContinue |
    Where-Object { $_.Active } | Select-Object -First 1
$collector = Find-DellCollector -Explicit $CollectorPath
$ismInstalled = Test-IsmInstalled
Write-Host "Get-DellTSR-Local.ps1 v$Ver"
Write-Host "Administrator: $isAdmin"
Write-Host "Local IPMI active: $([bool]$ipmi)"
Write-Host "Dell iSM installed (registry): $ismInstalled"
Write-Host "Dell iSM collector: $(if($collector){$collector}else{'Not found'})"
if ($CheckOnly) {
    [pscustomobject]@{
        IsAdministrator = $isAdmin
        IpmiActive      = [bool]$ipmi
        IsmInstalled    = $ismInstalled
        CollectorPath   = $collector
        ReadyToAttempt  = ($isAdmin -and [bool]$collector)
    }
    return
}
if (-not $isAdmin) { throw 'Run this script from an elevated PowerShell session on the Dell server.' }
if (-not $collector -and -not $NoInstallIsm) {
    $installed = Install-DellIsmIfApproved -LocalInstaller $IsmInstallerPath -InstallerUrl $IsmInstallerUrl
    if ($installed) {
        $collector = Find-DellCollector -Explicit $CollectorPath
        Write-Host "Dell collector after install: $(if($collector){$collector}else{'Not found'})"
    }
}
if (-not $collector) {
    throw 'Dell iSM SupportAssist collector was not found. Install a supported Dell iSM package with the SupportAssist feature, then rerun. No TSR was generated.'
}
if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$destination = (Resolve-Path -LiteralPath $OutputDirectory).ProviderPath
$started = Get-Date
Write-Host "Starting Dell SupportAssist Collection; destination: $destination"
# Dell iSM allows only one active SupportAssist collection.
# Ask whether to wait; never terminate an existing collection.
$existingCollector = @(Get-CimInstance Win32_Process -Filter "Name='Invoke-SupportAssistCollection.exe'" -ErrorAction SilentlyContinue)
if ($existingCollector.Count -gt 0) {
    $details = ($existingCollector | ForEach-Object { "PID $($_.ProcessId) (started $($_.CreationDate))" }) -join '; '
    Write-Warning "Another Dell SupportAssist collection is already running: $details"
    # A missing response must not leave unattended LogCollector sessions waiting indefinitely.
    # Timeout is 15 seconds; only an explicit Y/Yes authorizes waiting.
    $answer = $null
    $timeoutSeconds = 15
    Write-Host "Wait for the existing collection to finish, then start a new collection? [y/N] (15 seconds): " -NoNewline
    try {
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while ($timer.Elapsed.TotalSeconds -lt $timeoutSeconds) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.KeyChar -eq 'y' -or $key.KeyChar -eq 'Y') {
                    Write-Host 'Y'
                    $answer = 'Y'
                    break
                }
                if ($key.Key -eq [ConsoleKey]::Enter -or
                    $key.KeyChar -eq 'n' -or $key.KeyChar -eq 'N') {
                    Write-Host 'N'
                    $answer = 'N'
                    break
                }
            }
            Start-Sleep -Milliseconds 100
        }
    }
    catch {
        Write-Warning "This PowerShell host does not support timed console key input: $($_.Exception.Message)"
    }
    if ($null -eq $answer) {
        Write-Host ''
        Write-Host 'No valid response within 15 seconds (or console input unavailable). Existing collection left running.' -ForegroundColor Yellow
        return
    }
    if ($answer -ne 'Y') {
        Write-Host 'Wait declined. Existing collection left running; no new collection started.' -ForegroundColor Yellow
        return
    }
    Write-Host 'Waiting for the existing Dell SupportAssist collection (Ctrl+C to cancel waiting)...' -ForegroundColor Cyan
    while ($true) {
        $existingCollector = @(Get-CimInstance Win32_Process -Filter "Name='Invoke-SupportAssistCollection.exe'" -ErrorAction SilentlyContinue)
        if ($existingCollector.Count -eq 0) { break }
        Write-Progress -Id 2 -Activity 'Waiting for existing Dell TSR collection' `
            -Status ("Active PID(s): " + (($existingCollector | ForEach-Object { $_.ProcessId }) -join ', '))
        Start-Sleep -Seconds 3
    }
    Write-Progress -Id 2 -Activity 'Waiting for existing Dell TSR collection' -Completed
    Write-Host 'Existing collection finished. Starting a new local TSR collection.' -ForegroundColor Green
}
# Start time must be after the wait so previously generated ZIPs are not mistaken for this run.
$started = Get-Date
# Run the Dell collector attached to this console.
# iSM renders its own live progress, which can be buffered or lost if redirected.
# Do not pipe, redirect, or launch it in a hidden window.
Write-Host 'Dell native collection progress follows:' -ForegroundColor Cyan
$global:LASTEXITCODE = $null
& $collector -f $destination
$exitCode = $LASTEXITCODE
if ($null -eq $exitCode) {
    throw 'Dell collector did not return an exit code; treating collection as failed.'
}
if ($exitCode -ne 0) {
    throw "Dell collector exited with code $exitCode. Check iSM service status and communication with iDRAC."
}
$files = @(Get-ChildItem -LiteralPath $destination -Filter '*.zip' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $started.AddSeconds(-5) } | Sort-Object LastWriteTime -Descending)
if ($files.Count -eq 0) {
    Write-Warning 'Dell collector exited successfully, but no new ZIP was detected in the requested directory.'
    return
}
foreach ($file in $files) { Add-OsDriversToTsrZip -ZipPath $file.FullName }
Write-Host 'SupportAssist Collection file(s):' -ForegroundColor Green
$files | Select-Object FullName,Length,LastWriteTime