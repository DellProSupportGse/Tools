 <#
    .Synopsis
       GetShowTech.ps1
    .DESCRIPTION
       This script will collect Show Tech-Support from single or multiple switches
    .EXAMPLES
            Invoke-GetShowTech
    #>
Function Invoke-GetShowTech {
    [CmdletBinding(
    SupportsShouldProcess = $true,
    ConfirmImpact = 'High')]
    param(
    $param)

    # Collect Show Techs
        Remove-Variable * -ErrorAction SilentlyContinue
        Clear-Host
        Write-Host "Gathering Show Tech-Support(s)..."

    # Get switch IP addresses
        $SwIPs=Read-Host "Please enter comma delimited list of switch IP addresse(s)"
        $i=0
        IF($SwIPs -imatch ','){$SwIPs=$SwIPs -split ','}
        While(($SwIPs.count -eq ($SwIPs | %{[IPAddress]$_.Trim()}).count) -eq $False){
            $i++
            Write-Host "WARNING: Not a valid IP. Please try again." -ForegroundColor Yellow
            $SwIPs=Read-Host "Please enter comma delimited list of switch IP addresses"
            IF($SwIPs -imatch ','){$SwIPs=$SwIPs -split ','}
            IF($i -ge 2){
                Write-Host "ERROR: No valid IP found. Exiting..." -ForegroundColor Red
                break script
            }
        }

    # Get switch user
    

        IF($SwIPs.count -gt 1){
            $SwIPs=$SwIPs -split ','
            $SwSameUser=Read-Host "Use the same user for all switches?[Y/N]"
        }
        IF($SwSameUser -ieq 'y'){$SWUser=Read-Host "Please enter user name"}

    # Add SSH Client
        $ChkIfSSHInstalled=Get-WindowsCapability -Online -Name OpenSSH.Client*
        IF($ChkIfSSHInstalled.state -ne 'Installed'){
            Write-Host "Adding SSH Client..."
            Add-WindowsCapability -Online -Name OpenSSH.Client  > $null
        }

    # Clean up old switch logs
        Remove-Item "$ENV:Temp\ShowTechs" -Recurse -Confirm:$false -Force

    # Create temp folder
        Write-Host "Creating temp output location..."
        New-Item -Path $ENV:Temp -Name ShowTechs -ItemType Directory -Force > $null
        #Test-Path C:\Users\JIM~1.GAN\AppData\Local\Temp\ShowTechs

    # Gathering the show techs 
        ForEach($SwIp in $SwIPs){
            IF($SwSameUser -ine 'y'){
                 # Switch creds
                     $SwUser=Read-Host "Please enter user name for switch $SwIP"
            }

             # Connect to switch
                Write-Host "Collecting Show Tech-Support for $SwIP..."
                $Switchout=ssh $SwIp -l $SwUser -o StrictHostKeyChecking=no show tech-support
                $Switchout | Out-File -FilePath "$ENV:Temp\ShowTechs\$($SwIp)_ShowTech.log" -Force
         }

    # Zip up show techs
        Write-Host "Compressing show techs..."
        $DT=Get-Date -Format "yyyyMMddHHmm"
        Compress-Archive -Path "$ENV:Temp\ShowTechs\*.*" -DestinationPath "$ENV:Temp\ShowTechs_$($DT)"
        Write-Host "Logs can be found here: $ENV:Temp\ShowTechs_$($DT).zip"

    # Clean up show techs
        Write-Host "Clean up..."
        Remove-Item "$ENV:Temp\*_ShowTech.log" -Force

    # Remove SSH if installed during this script
        IF($ChkIfSSHInstalled.state -ne 'Installed'){
            Write-Host "Removing SSH Client..."
            Remove-WindowsCapability -Online -Name $ChkIfSSHInstalled.name  > $null
        }
}# end of Invoke-GetShowTech
