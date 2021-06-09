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
        param($param)
    CLS
    CLS
$text=@"
v1.1
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
    Invoke-WebRequest -Uri https://github.com/DellProSupportGse/PrivateCloud.DiagnosticInfo/archive/master.zip -OutFile $MyTemp\$branch.zip
    Expand-Archive -Path $MyTemp\$branch.zip -DestinationPath $MyTemp -Force
    $md = "$env:ProgramFiles\WindowsPowerShell\Modules"
    cp -Recurse $MyTemp\$module-$branch\$module $md -Force -ErrorAction Stop
    rm -Recurse $MyTemp\$module-$branch,$MyTemp\$branch.zip
    $ModulePath=$md+"\"+$module
    Import-Module $ModulePath -Force

# Clean up old SDDC's
    IF(Test-Path "$env:USERPROFILE\HealthTest-S2DCluster-*.zip"){Remove-Item $env:USERPROFILE\HealthTest-S2DCluster-*.zip -Force}    

# Run SDDC
    # Run SDDC if cluster service found on node
    IF(Get-Service clussvc -ErrorAction SilentlyContinue){
        Get-SddcDiagnosticInfo
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
                        Get-SDDCDiagnosticInfo -ClusterName $ClusterToCollectLogsFrom
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
            }Else{Write-Error "ERROR: $ClusterToCollectLogsFrom is not pingable."}
# Move to Logs if exists
IF(Test-Path -Path "$MyTemp\logs"){
        Copy-Item -Path "$env:USERPROFILE\HealthTest-S2DCluster-*.zip" -Destination "$MyTemp\logs\"
        }
}# End of Invoke-RunSDDC
