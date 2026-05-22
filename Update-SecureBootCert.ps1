#Requires -RunAsAdministrator

$SecureBootPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot"
$ServicingPath  = "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing"

Write-Host ""
Write-Host "=== Secure Boot 2026 Readiness State Machine ===" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# Secure Boot Check
# ------------------------------------------------------------

try {
    if (-not (Confirm-SecureBootUEFI)) {
        Write-Host "STATE: BLOCKED (Secure Boot disabled)" -ForegroundColor Red
        return 1
    }
}
catch {
    Write-Host "STATE: BLOCKED (Not UEFI or Secure Boot unavailable)" -ForegroundColor Red
    return 1
}

Write-Host "Secure Boot: ENABLED" -ForegroundColor Green

# ------------------------------------------------------------
# Read Core Properties
# ------------------------------------------------------------

$props = Get-ItemProperty -Path $ServicingPath -ErrorAction SilentlyContinue

$Status   = $props.UEFICA2023Status
$Capable  = $props.WindowsUEFICA2023Capable

$AvailableUpdates = (Get-ItemProperty -Path $SecureBootPath -Name AvailableUpdates -ErrorAction SilentlyContinue).AvailableUpdates

if ([string]::IsNullOrWhiteSpace($Status)) { 
    $State = "Blocked" 
    $BlockingReason = @( "UEFICA2023Status registry value not found", "BIOS may need to be updated","OS may require newer cumulative updates", "Secure Boot servicing framework may not be installed" ) }

# ------------------------------------------------------------
# Normalize Capable State (CRITICAL)
# ------------------------------------------------------------

$CapState = switch ($Capable) {
    0 { "Blocked" }
    1 { "Capable" }
    2 { "Optimal" }
    default { "Unknown" }
}

# ------------------------------------------------------------
# DB Check (CA2023 presence)
# ------------------------------------------------------------

$DbUpdated = $false

try {
    $DbBytes = (Get-SecureBootUEFI db).bytes
    $DbText  = [System.Text.Encoding]::ASCII.GetString($DbBytes)

    if ($DbText -match "Windows UEFI CA 2023") {
        $DbUpdated = $true
    }
} catch {}

# ------------------------------------------------------------
# Event signals (last 14 days)
# ------------------------------------------------------------

$StartTime = (Get-Date).AddDays(-14)

$Events = Get-WinEvent -FilterHashtable @{
    LogName   = 'System'
    Id        = @(1795,1799,1801,1808)
    StartTime = $StartTime
} -ErrorAction SilentlyContinue

$HasFailure   = $Events.Id -contains 1795 -or $Events.Id -contains 1801
$HasSuccess   = $Events.Id -contains 1808
$HasMadeProgress = $Events.Id -contains 1799

# ------------------------------------------------------------
# STATE MACHINE LOGIC
# ------------------------------------------------------------

$State = "Unknown"

# 1. Hard blockers first
if ($CapState -eq "Blocked") {
    $State = "Blocked"
} elseif ($CapState -eq "Capable") {
    $State = "Transitional"
} elseif ([string]::IsNullOrWhiteSpace($Status)) {
    if ($CapState -eq "Unknown" -and !((Get-ScheduledTaskInfo -TaskPath "\Microsoft\Windows\PI\" -TaskName "Secure-Boot-Update").LastRunTime -gt (Get-Date).AddMinutes(-60))) {
        $State = "NotStarted" 
    } else {
        $State = "Update OS"
    }
    #$BlockingReason = @( "UEFICA2023Status registry value not found", "OS may require newer cumulative updates", "BIOS may need to be updated", "Secure Boot servicing framework may not be installed" )
} elseif ($CapState -eq "Unknown") {
    $State = "Remediate BIOS First"
} elseif ($CapState -eq "Optimal") {
    if ($AvailableUpdates -eq 0x4000 -and $DbUpdated -and $HasSuccess) {
        $State = "Ready"
    }
} else {
    # 2. Firmware readiness checks
    if ($AvailableUpdates -eq 0x0040 -or $AvailableUpdates -eq 0x0044) {
        $State = "Remediate BIOS First"
   } elseif ($Status -eq "NotStarted") {
        $State = "NotStarted"
    } elseif ($AvailableUpdates -eq 0) {
        $State = "Update OS"
        #Remove-ItemProperty -Path $SecureBootPath -Name AvailableUpdates -ErrorAction SilentlyContinue -Confirm:$false
    } elseif ($Status -eq "InProgress" -and $HasMadeProgress) {
        $State = "RebootNow"
    } elseif ($HasFailure -and -not $HasSuccess) {
        $State = "Transitional"
    } elseif (($Status -ne "Updated" -or -not $DbUpdated) -and $Status -gt $null) {
        $State = "Transitional"
    } elseif ($Status -eq "InProgress") {
        $State = "Reboot"
    } else {
        $State = "Update OS"
    }
}

# ------------------------------------------------------------
# OUTPUT
# ------------------------------------------------------------

Write-Host ""
Write-Host "==========================" -ForegroundColor Cyan
Write-Host "FINAL STATE: $State" -ForegroundColor Cyan
Write-Host "==========================" -ForegroundColor Cyan
Write-Host ""

switch ($State) {

    "Ready" {
        Write-Host "System is fully compliant for Secure Boot 2026." -ForegroundColor Green
    }

    "Blocked" {
        Write-Host "Secure Boot with 2023 certs is disabled or unavailable. BIOS or OS may not be updated." -ForegroundColor Red
        $BlockingReason
    }

    "NotStarted" {
        Write-Host "Beginning remediation process" -ForegroundColor Green
    }

    "Update OS" {
        Write-Host "Update OS and BIOS first or wait 10 minutes and try script again" -ForegroundColor Red
    }

    "Reboot" {
        Write-Host "Wait 15 minutes and if you still get this the system may need another reboot" -ForegroundColor Red
    }

    "RebootNow" {
        Write-Host "Reboot to continue remediation" -ForegroundColor Red
    }

    "Transitional" {
        Write-Host "Secure Boot update is in progress or pending reboot cycle." -ForegroundColor Yellow
    }

    "Remediate BIOS First" {
        Write-Host "Firmware/BIOS is limiting Secure Boot update capability." -ForegroundColor Red
        Write-Host "Action: Update OEM BIOS/UEFI firmware and retry." -ForegroundColor Yellow
    }

    default {
        Write-Host "Unknown state. Manual investigation required." -ForegroundColor DarkYellow
    }
}
if (gcm Get-BitLockerVolume) {
    If ((Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue).ProtectionStatus -eq 'On') {
        Write-Warning "Bitlocker is enabled. Bitlocker should be Off before any remediation reboot or the key may be required"
    }
}
# ------------------------------------------------------------
# Optional remediation gate (only if NOT Ready or BIOS-blocked)
# ------------------------------------------------------------

$AllowRemediation = $State -in @("NotStarted")

if (-not $AllowRemediation) {

    Write-Host ""
    Write-Host "Remediation NOT triggered (state = $State)" -ForegroundColor Yellow
    return 0
}

Write-Host ""
Write-Host "Starting Secure Boot remediation..." -ForegroundColor Cyan

Set-ItemProperty `
    -Path $SecureBootPath `
    -Name AvailableUpdates `
    -Type DWord `
    -Value 0x5944

Start-ScheduledTask `
    -TaskPath "\Microsoft\Windows\PI\" `
    -TaskName "Secure-Boot-Update"

Write-Host "Remediation triggered successfully." -ForegroundColor Green
Write-Host "Reboot required. After reboot, wait 15 minutes" -ForegroundColor Yellow