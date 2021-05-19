    <#
    .Synopsis
       Invoke-SDDC
    .DESCRIPTION
       This script will remove old SDDC's, install new SDDC and Run SddcDiagnosticInfo
    .EXAMPLE
       Invoke-SDDC
    #>
    
Function Invoke-SDDC {
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High')]
        param($param)
    CLS
# Fix 8.3 temp paths
    $MyTemp=(Get-Item $env:temp).fullname
# Clean old PrivateCloud.DiagnosticInfo
    Write-Host "Cleaning PrivateCloud.DiagnosticInfo on all nodes..."
    Invoke-Command -ComputerName (Get-ClusterNode).Name -ScriptBlock {
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
    Get-SddcDiagnosticInfo

# Wait for new SDDC
    While (!(Test-Path "$env:USERPROFILE\HealthTest-S2DCluster-*.zip")) { Start-Sleep 60 }
    IF(Test-Path -Path "$MyTemp\logs"){
        Copy-Item -Path "$env:USERPROFILE\HealthTest-S2DCluster-*.zip" -Destination "$MyTemp\logs\"
        cd "$MyTemp\logs"
        Invoke-Expression "explorer ."
        
    }
}
