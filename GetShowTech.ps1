 <#
    .Synopsis
       GetShowTech.ps1
    .DESCRIPTION
       This script will collect Show Tech-Support from single or multiple switches
    .EXAMPLES
            Invoke-GetShowTech
    .Authors
            Jim Gandy
            Jonah Farve
    #>
Function Invoke-GetShowTech {
    [CmdletBinding(
    SupportsShouldProcess = $true,
    ConfirmImpact = 'High')]
    param(
    $param)
    
    Remove-Variable * -ErrorAction SilentlyContinue
    Clear-Host
        
    $DateTime=Get-Date -Format yyyyMMdd_HHmmss
    Start-Transcript -NoClobber -Path "C:\programdata\Dell\GetShowTech\GetShowTech_$DateTime.log"

$text=@"
v1.0
   ____      _   ____  _                   _____         _     
  / ___| ___| |_/ ___|| |__   _____      _|_   _|__  ___| |__  
 | |  _ / _ \ __\___ \| '_ \ / _ \ \ /\ / / | |/ _ \/ __| '_ \ 
 | |_| |  __/ |_ ___) | | | | (_) \ V  V /  | |  __/ (__| | | |
  \____|\___|\__|____/|_| |_|\___/ \_/\_/   |_|\___|\___|_| |_|
                                                               
                                                 By: Jim Gandy
"@
Write-Host $text
Write-Host ""
Write-Host "This tool is used to collect Dell switch logs"
Write-Host ""

    # Collect Show Techs
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
        Remove-Item "$ENV:Temp\ShowTechs" -Recurse -Confirm:$false -Force

    # Remove SSH if installed during this script
        IF($ChkIfSSHInstalled.state -ne 'Installed'){
            Write-Host "Removing SSH Client..."
            Remove-WindowsCapability -Online -Name $ChkIfSSHInstalled.name  > $null
        }
        
    # Remove Function:\Invoke-GetShowTech
        Remove-Item -Path Function:\Invoke-GetShowTech > $null

        Stop-Transcript

}# end of Invoke-GetShowTech
