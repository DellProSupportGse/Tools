Function Invoke-SDDCOffline {
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High')]
        param($param)
    CLS
$Run=Read-host "Ready to run? [y/n]"
IF($Run -ine "y"){break}
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
$SDDCFileCheck=Read-Host "Do you have the SDDC copied locally? [y/n]"
IF($SDDCFileCheck -ine "y"){Write-Host "Please download from https://github.com/DellProSupportGse/PrivateCloud.DiagnosticInfo/archive/master.zip";break}

# Fresh import of PrivateCloud.DiagnosticInfo
    # Allow Tls12 and Tls11 -- GitHub now requires Tls12
    # If this is not set, the Invoke-WebRequest fails with "The request was aborted: Could not create SSL/TLS secure channel."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11
    $module = 'PrivateCloud.DiagnosticInfo'; $branch = 'master'
    #Invoke-WebRequest -Uri https://github.com/DellProSupportGse/PrivateCloud.DiagnosticInfo/archive/master.zip -OutFile $MyTemp\$branch.zip
    Function Get-CatFile($initialDirectory)
            {
                [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
                $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog -Property @{Multiselect = $false}
                $OpenFileDialog.Title = "Please Select local SDDC ZIP file..."
                $OpenFileDialog.ShowHelp = 'Please download SDDDC from this link: https://github.com/DellProSupportGse/PrivateCloud.DiagnosticInfo/archive/master.zip'
                $OpenFileDialog.initialDirectory = $initialDirectory
                $OpenFileDialog.filter = "ZIP (*.zip)| *.zip"
                $OpenFileDialog.ShowDialog() | Out-Null
                $OpenFileDialog.filenames
            }
            $ProvidedSDDC=Get-CatFile("C:")
            Write-host $ProvidedSDDC
    Expand-Archive -Path $ProvidedSDDC -DestinationPath $MyTemp -Force
    $md = "$env:ProgramFiles\WindowsPowerShell\Modules"
    cp -Recurse $MyTemp\$module-$branch\$module $md -Force -ErrorAction Stop
    rm -Recurse $MyTemp\$module-$branch,$ProvidedSDDC
    $ModulePath=$md+"\"+$module
    Import-Module $ModulePath -Force -Verbose

    
# Run SDDC
    Get-SddcDiagnosticInfo
}
Invoke-SDDCOffline 
