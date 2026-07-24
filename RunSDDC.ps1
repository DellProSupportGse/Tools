    <#
    .Synopsis
       Invoke-SDDC
    .DESCRIPTION
       This script will remove old SDDC's, install new SDDC and Run SddcDiagnosticInfo
    .EXAMPLE
       Invoke-SDDC
    #>
    
Function Invoke-RunSDDC {
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High')]
        param(
        [Parameter(Mandatory=$False)]
          [int] $HoursOfEvents=168,
        [Parameter(Mandatory=$False)]
          [int] $PerfSamples=30,
        [Parameter(Mandatory=$False)]
         [string] $CaseNumber)
    CLS
    CLS
$text=@"
v1.41
  ___           ___ ___  ___   ___ 
 | _ \_  _ _ _ / __|   \|   \ / __|
 |   / || | ' \\__ \ |) | |) | (__ 
 |_|_\\_,_|_||_|___/___/|___/ \___|
                     By: Jim Gandy
"@
Write-Host $text
Write-Host ""
Write-Host "This tool is used to collect SDDC logs"
Write-Host "" 
$MyTemp=(Get-Item $env:temp).fullname
$Logs = $MyTemp + "\Logs\"
New-Item -ItemType Directory -Force -Path $Logs
if (-not ($Casenumber)) {$CaseNumber = Read-Host -Prompt "Please Provide the case number SDDC is being collected for"}

[int]$TimeoutSeconds = 20
[string]$DefaultValue = "6"
[string]$Prompt = "How many days to collect? [$DefaultValue]: "

[int]$DaysOfLogs = $DefaultValue
$finalInput=$null

# Verify Console is available (fails in ISE, works in standard console/terminal/VS Code)
if ($Host.Name -eq "Visual Studio Code Host" -or $null -eq [Console]::KeyAvailable) {
    # Fallback if Console API is unavailable
    Write-Warning "Console API not fully supported in this host. Using default value of $DefaultValue days."
    $
} else {
    Write-Host $Prompt -NoNewline
    $inputBuffer = New-Object System.Text.StringBuilder
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $timeoutMilliseconds = $TimeoutSeconds * 1000

    while ($stopwatch.ElapsedMilliseconds -lt $timeoutMilliseconds -and $finalInput -eq $null) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)

            # Case 1: User pressed Enter
            if ($key.Key -eq [ConsoleKey]::Enter) {
                Write-Host "" # Move to next line
                $finalInput = $inputBuffer.ToString()
                if (!([string]::IsNullOrEmpty($finalInput))) { $DaysOfLogs=$finalInput }

            }

            # Case 2: User pressed Backspace
            elseif ($key.Key -eq [ConsoleKey]::Backspace) {
                if ($inputBuffer.Length -gt 0) {
                    $inputBuffer.Remove($inputBuffer.Length - 1, 1) | Out-Null
                    # Erase character visually from console
                    Write-Host "`b `b" -NoNewline
                }
            }

            # Case 3: Enforce numeric input only
            elseif ($key.KeyChar -match '[0-9]') {
                $inputBuffer.Append($key.KeyChar) | Out-Null
                Write-Host $key.KeyChar -NoNewline
            }
        }
        else {
            Start-Sleep -Milliseconds 50 # Prevent high CPU utilization
        }
    }

    # Timeout reached
    Write-Host "" # Move to next line
    Write-Host "Timeout reached. Proceeding with default: $DefaultValue"
}
If ($HoursOfEvents -eq 168) {$HoursOfEvents=($DaysOfLogs+1)*24}
# Fix 8.3 temp paths
    $MyTemp=(Get-Item $env:temp).fullname
# Clean old PrivateCloud.DiagnosticInfo
Write-Host "Cleaning PrivateCloud.DiagnosticInfo on all nodes..."
IF(Get-Service clussvc -ErrorAction SilentlyContinue){
    $CNames=(Get-ClusterNode).Name
}Else{$CNames=$env:COMPUTERNAME}
Invoke-Command -ComputerName $CNames -ScriptBlock {
    # Remove PrivateCloud.DiagnosticInfo
        Remove-Module 'PrivateCloud.DiagnosticInfo' -Force -Confirm:$False -ErrorAction SilentlyContinue

    # Clean up PrivateCloud.DiagnosticInfo folders
        $PowerShellPaths=$Env:PSModulePath -split ';'
        ForEach ($p in $PowerShellPaths){
            Remove-Item "$p\PrivateCloud.DiagnosticInfo" -Force -Confirm:$False -Recurse -ErrorAction SilentlyContinue
        }
}

# Fresh import of PrivateCloud.DiagnosticInfo
# Allow Tls12 and Tls11 -- GitHub now requires Tls12
# If this is not set, the Invoke-WebRequest fails with "The request was aborted: Could not create SSL/TLS secure channel."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11
$module = 'PrivateCloud.DiagnosticInfo'; $branch = 'master'

try {
    (new-object net.webclient).DownloadFile('https://github.com/DellProSupportGse/PrivateCloud.DiagnosticInfo/archive/master.zip',"$MyTemp\$branch.zip")
} catch {
    Invoke-WebRequest -Uri https://github.com/DellProSupportGse/PrivateCloud.DiagnosticInfo/archive/master.zip -OutFile $MyTemp\$branch.zip
}
Unblock-File "$MyTemp\$branch.zip"
Expand-Archive -Path $MyTemp\$branch.zip -DestinationPath $MyTemp -Force
$md = "$env:ProgramFiles\WindowsPowerShell\Modules"
cp -Recurse $MyTemp\$module-$branch\$module $md -Force -ErrorAction Stop
rm -Recurse $MyTemp\$module-$branch,$MyTemp\$branch.zip
$ModulePath=$md+"\"+$module
Import-Module $ModulePath -Force -Verbose

 
# Clean up old SDDC's
    IF(Test-Path "$env:USERPROFILE\HealthTest-*.zip"){Remove-Item $env:USERPROFILE\HealthTest-*.zip -Force}    
    IF(Test-Path "$Logs\HealthTest-*.zip"){Remove-Item $Logs\HealthTest-*.zip -Force}
# Run SDDC

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public class Win32 {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public const int SW_MINIMIZE = 6;
}
"@

if (-not (gcm Get-SddcDiagnosticInfo)) {

    $minBlankWindows = [Win32+EnumWindowsProc]{
        param($hWnd, $lParam)
        if ([Win32]::IsWindowVisible($hWnd))
        {
            $len = [Win32]::GetWindowTextLength($hWnd)
            $sb = New-Object System.Text.StringBuilder ($len + 1)
            [Win32]::GetWindowText($hWnd, $sb, $sb.Capacity) | Out-Null
            $title = $sb.ToString()
            if ($title -like "*\WindowsPowershell\v1.0\powershell.exe*")
            {
                #Write-Host "Minimizing: $title"
                [Win32]::ShowWindow($hWnd, [Win32]::SW_MINIMIZE) | Out-Null
            }
        }
        $true
    }
    mkdir "$($env:USERPROFILE)\HealthTest" -ErrorAction SilentlyContinue
    $sharepath="\\$($env:COMPUTERNAME)\$(($env:USERPROFILE).replace('C:\','c$\'))\HealthTest"
    Write-Host "Getting Solution Update information..."
    Start-Job -Name "SolutionUpdateInfo" -ScriptBlock {
        Get-StampInformation | Export-CliXml "$($env:USERPROFILE)\HealthTest\GetStampInformation.xml"
        Get-SolutionUpdateEnvironment | Export-CliXml "$($env:USERPROFILE)\HealthTest\GetSolutionUpdateEnvironment.xml"
    }
    Start-Job -Name "GetSolutionUpdate" -ScriptBlock {
        Get-SolutionUpdate | Tee-Object -Variable GSUpd >$Null;$GSUpd | ForEach-Object{$_;$_.HealthCheckResult}
    }
    if ((gcm Get-ClusterNode)) {
        (Get-ClusterNode).Name | %{Invoke-Command -AsJob -JobName "SendDiags-$($_)" -ComputerName $_ -ScriptBlock {
		            $Rpath="C:\SendDiags"
                    Remove-Item $RPath -Recurse -Force -ErrorAction SilentlyContinue
                    New-Item -Path $RPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
                    Send-DiagnosticData -SaveToPath $Rpath
        } | Out-Null}
    
    } else { 
        Send-DiagnosticData -SaveToPath "$($env:USERPROFILE)\Healthtest"
    }
    $startTime=(Get-Date)
    Sleep 30
    While (Get-Job -Name "GetSolutionUpdate" | ? State -eq Running) {Sleep 5}
    $job=Get-Job -Name "GetSolutionUpdate"
    $LocalFile = $job.Name
    $output = Receive-Job $job
    $output | Format-Table -AutoSize | Out-File -Width 9999 -Encoding ascii -FilePath "$($env:USERPROFILE)\HealthTest\$LocalFile.txt"
    $output | Export-Clixml -Path "$($env:USERPROFILE)\HealthTest\$LocalFile.xml"
    #Find and minimize Send-DiagnosticData windows
    [Win32]::EnumWindows($minBlankWindows, [IntPtr]::Zero) | Out-Null
    $xx=0
    while ((Get-Job).State -match "Running" -and $xx -lt 120) {
        Get-Job -Name "SendDiags-*" | Receive-Job -ErrorAction SilentlyContinue
        $jobs=Get-Job | ? State -match "Running"
        $ddate=(Get-Date).ToString()
        Write-Host "--------------------------------------------------------------------------------------------------------------"
        Write-Host "[$ddate] Waiting on $($jobs.name -replace 'SendDiags-','' -join ',') to complete. Started $([int]((Get-Date) - $startTime).TotalMinutes) minutes ago"
        sleep 30
        $xx++
    }
  
    $jobs=Get-Job | ? State -match "Running"
    if ($jobs) {
        Write-Host "Jobs $($jobs.name -join ',') exceeded timeout"
    } else {
        Get-Job | Remove-Job
    }
    Write-Host ""
    Write-Host "Copying Diag logs...."
    Start-Job -Name "CopyJob" -ScriptBlock {foreach ($node in (Get-ClusterNode).Name) {
       	Move-Item "\\$node\c$\SendDiags\*" "$($env:USERPROFILE)\HealthTest"
    }} | Out-Null
    while ((Get-Job).State -match "Running") {Get-Job | ? State -eq Running | Receive-Job -ErrorAction SilentlyContinue;Write-Host "." -NoNewLine;sleep 5}
    Write-Host ""
    Write-Host "Zipping up files..."
    $ZipSuffix = '-' + ((Get-Date).ToString('yyyyMMdd-HHmm')) + '.ZIP'
    $ZipSuffix = '-' + ($CNames.Split('.',2)[0]) + $ZipSuffix
    $ZipPath = "$($env:USERPROFILE)\Healthtest" + $ZipSuffix

    try {
        Add-Type -Assembly System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory("$($env:USERPROFILE)\Healthtest\", $ZipPath, [System.IO.Compression.CompressionLevel]::Fastest, $false)
        $ZipPath = Convert-Path $ZipPath
        Write-Host "Zip File Name : $ZipPath"

        Write-Host "Cleaning up temporary directory $($env:USERPROFILE)\Healthtest\"
        Remove-Item -Path "$($env:USERPROFILE)\Healthtest\" -ErrorAction SilentlyContinue -Recurse

    } catch {
        Write-Warning "Error=$($_.Exception.Message)"
        Write-Host -ForegroundColor Red "Error creating the ZIP file!`nContent remains available at $($env:USERPROFILE)\Healthtest\"
    }
 } else {

    # Run SDDC if cluster service found on node
    IF(Get-Service clussvc -ErrorAction SilentlyContinue){
        Get-SddcDiagnosticInfo -HoursOfEvents $HoursOfEvents -PerfSamples $PerfSamples -IncludeReliabilityCounters -RunCluChk
    }Else{
        $ClusterToCollectLogsFrom=Read-Host "Please enter the name of the cluster to collect logs from"
        # Check if we can connect to the cluster
            Write-Host "Checking cluster connectivity..."
            $i=0
            While((Get-WmiObject -Class Win32_PingStatus -Filter "(Address='$ClusterToCollectLogsFrom') and timeout=1000").StatusCode -eq $null){
                $i++
                Write-Host "    WARNING: $ClusterToCollectLogsFrom not pingable. Please try again." -ForegroundColor Yellow
                $ClusterToCollectLogsFrom=Read-Host "Please enter the name of the cluster to collect logs from"
                IF($i -ge 3){
                    Write-Host "ERROR: Too many attempts. Exiting..." -ForegroundColor Red
                    break script
                }
            }
            Write-Host "    SUCCESS: Able to ping $ClusterToCollectLogsFrom" -ForegroundColor Green
              If ($ClusterToCollectLogsFrom -ieq 'local') {
                Get-SDDCDiagnosticInfo -IncludeReliabilityCounters -HoursOfEvents $HoursOfEvents -PerfSamples $PerfSamples -RunCluChk
              } else {
                IF((Invoke-Command -ComputerName $ClusterToCollectLogsFrom -ErrorAction SilentlyContinue -ScriptBlock{(Get-cluster).name}) -imatch $ClusterToCollectLogsFrom){
                    Write-Host "    SUCCESS: Able to connect to cluster" -ForegroundColor Green
                    $CheckRSATClusteringPowerShell=IF((Get-WindowsFeature RSAT-Clustering-PowerShell).InstallState -eq 'Installed'){ 
                        Write-Host "Execute: Get-SDDCDiagnosticInfo -ClusterName $ClusterToCollectLogsFrom..."
                        Get-SDDCDiagnosticInfo -ClusterName $ClusterToCollectLogsFrom -IncludeReliabilityCounters -HoursOfEvents $HoursOfEvents -PerfSamples $PerfSamples -RunCluChk
                    }Else{
                        Write-Host "Remote SDDC requires RSAT-Clustering-PowerShell which requires a rebooted." -ForegroundColor Yellow
                        IF((Read-Host "Would you like to install RSAT-Clustering-PowerShell [y/n]") -imatch 'y'){
                            Install-WindowsFeature RSAT-Clustering-PowerShell
                            IF((Get-WindowsFeature RSAT-Clustering-PowerShell).InstallState -eq 'InstallPending'){
                                Write-Host "  SUCCESS: RSAT-Clustering-PowerShell installed, but a reboot is required to compelete the installation." -ForegroundColor Green
                                IF((Read-Host "Reboot now [y/n]") -imatch 'y'){Restart-Computer -Force}Else{Write-Host "Please reboot to complete the installation" -ForegroundColor Yellow}
                            }
                        }Else{
                            Write-Host "    Please Install-WindowsFeature RSAT-Clustering-PowerShell, reboot and rerun" -ForegroundColor Yellow}
                        }
                }Else{
                    Write-Error "    ERROR: Failed to connect to cluster $ClusterToCollectLogsFrom. Please check the cluster name and run again."
                }
              }
            }
# Move to Logs 
IF(Test-Path -Path "$MyTemp\logs"){
        Copy-Item -Path "$env:USERPROFILE\HealthTest-*.zip" -Destination "$MyTemp\logs\"
        $HealthZip = Get-ChildItem $MyTemp\logs\Healthtest*.zip
        $HealthZipNew = $HealthZip.BaseName + "-" + $CaseNumber + ".zip"
        Rename-Item -Path $HealthZip -NewName $HealthZipNew
        $HealthZip = Get-ChildItem $MyTemp\logs\Healthtest*.zip
        #Get the File-Name without path
$name = (Get-Item $HealthZip).Name

}
}
} # End of Invoke-RunSDDC
