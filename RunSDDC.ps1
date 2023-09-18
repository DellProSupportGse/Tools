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
         [string] $CaseNumber,
        [Parameter(Mandatory=$False)]
         [string] $ClusterName=(Get-Cluster).Name,
        [Parameter(Mandatory=$False)]
         [string] $HoursOnEvent=168,
        [Parameter(Mandatory=$False)]
         [string] $PerfSamples=30

         )
    CLS
    CLS
$text=@"
v1.24
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
        $DellGSEPSRepository="C:\ProgramData\Dell\DellGSEPSRepository"
        New-Item -ItemType Directory -Path $DellGSEPSRepository -ErrorAction SilentlyContinue
        If (-not (Get-PSRepository | ? Name -eq "DellGSEPSRepository")) {
            $registerPSRepositorySplat = @{
                Name = 'DellGSEPSRepository'
                SourceLocation = '\\localhost\c$\ProgramData\Dell\DellGSEPSRepository'
                ScriptSourceLocation = '\\localhost\c$\ProgramData\Dell\DellGSEPSRepository'
                InstallationPolicy = 'Trusted'
            }
            Register-PSRepository @registerPSRepositorySplat
        }
        Remove-Item $DellGSEPSRepository\$module-$branch.zip -Force
        Invoke-WebRequest -Uri https://github.com/DellProSupportGse/PrivateCloud.DiagnosticInfo/archive/master.zip -OutFile $DellGSEPSRepository\$module-$branch.zip
        Expand-Archive -Path $DellGSEPSRepository\$module-$branch.zip -DestinationPath $DellGSEPSRepository\DellSDDCSource -Force
        $publishModuleSplat = @{
            Path = "$DellGSEPSRepository\DellSDDCsource\$module-$branch\$module"
            Repository = 'DellGSEPSRepository'
            NuGetApiKey = 'ProsupportGSE'
        }
        try {Publish-Module @publishModuleSplat} catch {}
        $DellSDDCInstalledVerson=try {(Get-InstalledModule $module -ErrorAction SilentlyContinue).Version} catch {}
        if ($DellSDDCInstalledVerson -eq $Null) {$DellSDDCInstalledVerson=[Version]'0.0.1.0'}
        if ($DellSDDCInstalledVerson -lt ((Find-Module $module -Repository DellGSEPSRepository).version)) {
            if ($DellSDDCInstalledVerson -gt [version]'0.9') {Update-Module $module -Verbose}
            else {Install-Module $module -Repository DellGSEPSRepository -Verbose -Force}
        }
    } catch {
        Invoke-WebRequest -Uri https://github.com/DellProSupportGse/PrivateCloud.DiagnosticInfo/archive/master.zip -OutFile $MyTemp\$branch.zip
        Expand-Archive -Path $MyTemp\$branch.zip -DestinationPath $MyTemp -Force
        $md = "$env:ProgramFiles\WindowsPowerShell\Modules"
        cp -Recurse $MyTemp\$module-$branch\$module $md -Force -ErrorAction Stop
        rm -Recurse $MyTemp\$module-$branch,$MyTemp\$branch.zip
        $ModulePath=$md+"\"+$module
        Import-Module $ModulePath -Force
    }
 

# Clean up old SDDC's
    IF(Test-Path "$env:USERPROFILE\HealthTest-*.zip"){Remove-Item $env:USERPROFILE\HealthTest-*.zip -Force}    
    IF(Test-Path "$Logs\HealthTest-*.zip"){Remove-Item $Logs\HealthTest-*.zip -Force}
# Run SDDC
    # Run SDDC if cluster service found on node
    IF(Get-Service clussvc -ErrorAction SilentlyContinue){
        Get-SddcDiagnosticInfo -ClusterName $ClusterName -HoursOfEvents $HoursOnEvent -PerfSamples $PerfSamples
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
                IF((Invoke-Command -ComputerName $ClusterToCollectLogsFrom -ErrorAction SilentlyContinue -ScriptBlock{(Get-cluster).name}) -imatch $ClusterToCollectLogsFrom){
                    Write-Host "    SUCCESS: Able to connect to cluster" -ForegroundColor Green
                    $CheckRSATClusteringPowerShell=IF((Get-WindowsFeature RSAT-Clustering-PowerShell).InstallState -eq 'Installed'){ 
                        Write-Host "Execute: Get-SDDCDiagnosticInfo -ClusterName $ClusterToCollectLogsFrom..."
                        Get-SDDCDiagnosticInfo -ClusterName $ClusterToCollectLogsFrom -IncludeReliabilityCounters -HoursOfEvents $HoursOnEvent -PerfSamples $PerfSamples
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
} # End of Invoke-RunSDDC
Invoke-RunSDDC -HoursOnEvent $HoursOnEvent -PerfSamples $PerfSamples
