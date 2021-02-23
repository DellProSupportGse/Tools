# Clean old PrivateCloud.DiagnosticInfo
    Write-Host "Cleaning PrivateCloud.DiagnosticInfo on all nodes..."
    Invoke-Command -ComputerName (Get-ClusterNode -Cluster (Get-Cluster).Name) -ScriptBlock {
        # Remove PrivateCloud.DiagnosticInfo
            Remove-Module 'PrivateCloud.DiagnosticInfo' -Force -Confirm:$False -ErrorAction SilentlyContinue

        # Clean up PrivateCloud.DiagnosticInfo folders
            $PowerShellPaths=$Env:PSModulePath -split ';'
            ForEach ($p in $PowerShellPaths){
                Remove-Item "$p\PrivateCloud.DiagnosticInfo" -Force -WhatIf -ErrorAction SilentlyContinue
            }
    }

# Fresh install of PrivateCloud.DiagnosticInfo
    # Allow Tls12 and Tls11 -- GitHub now requires Tls12
    # If this is not set, the Invoke-WebRequest fails with "The request was aborted: Could not create SSL/TLS secure channel."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11

    $module = 'PrivateCloud.DiagnosticInfo'; $branch = 'master'
    Invoke-WebRequest -Uri https://github.com/DellProSupportGse/$module/archive/$branch.zip -OutFile $env:TEMP\$branch.zip
    Expand-Archive -Path $env:TEMP\$branch.zip -DestinationPath $env:TEMP -Force
    if (Test-Path $env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules\$module) {
           rm -Recurse $env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules\$module -ErrorAction Stop
           Remove-Module $module -ErrorAction SilentlyContinue
    } else {
           Import-Module $module -ErrorAction SilentlyContinue
    }
    if (-not ($m = Get-Module $module -ErrorAction SilentlyContinue)) {
           $md = "$env:ProgramFiles\WindowsPowerShell\Modules"
    } else {
           $md = (gi $m.ModuleBase -ErrorAction SilentlyContinue).PsParentPath
           Remove-Module $module -ErrorAction SilentlyContinue
           rm -Recurse $m.ModuleBase -ErrorAction Stop
    }
    cp -Recurse $env:TEMP\$module-$branch\$module $md -Force -ErrorAction Stop
    rm -Recurse $env:TEMP\$module-$branch,$env:TEMP\$branch.zip
    Import-Module $module -Force  
    
# Run SDDC
    Get-SddcDiagnosticInfo
