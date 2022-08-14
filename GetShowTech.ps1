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
        param($param)

    
    Remove-Variable * -ErrorAction SilentlyContinue
    Clear-Host
    
    $DateTime=Get-Date -Format yyyyMMdd_HHmmss
    Start-Transcript -NoClobber -Path "C:\programdata\Dell\GetShowTech\GetShowTech_$DateTime.log"

$text=@"
v1.1
   ___     _   ___ _               _____       _    
  / __|___| |_/ __| |_  _____ __ _|_   _|__ __| |_  
 | (_ / -_)  _\__ \ ' \/ _ \ V  V / | |/ -_) _| ' \ 
  \___\___|\__|___/_||_\___/\_/\_/  |_|\___\__|_||_|
                                                                                                                   
                                      By: Jim Gandy
"@
Write-Host $text
Write-Host ""
Write-Host "    This tool is used to collect Dell switch logs"
Write-Host ""
if ($PSCmdlet.ShouldProcess($param)) {
    # Check if OpenSSH.Client is avaliable in PowerShell
        Try{$ChkIfSSHInstalled=Get-WindowsCapability -Online -Name OpenSSH.Client*}
        Catch{
            $ChkIfSSHInstalled ="FAILED"
            Write-Host "    OpenSSH.Client NOT available for this OS. Please follow this link to manually collect Show Tech-Support" -BackgroundColor Red -ForegroundColor White
            Write-Host "    https://www.dell.com/support/kbdoc/en-gy/000116043/dell-emc-networking-how-to-use-putty-exe-to-save-output-to-a-file"
            Pause
            }
    IF($ChkIfSSHInstalled -ine "FAILED"){
    # Fix 8.3 temp paths
        $MyTemp=(Get-Item $ENV:Temp).fullname

    # Collect Show Techs
        Write-Host "Gathering Show Tech-Support(s)..."
    # Get Case #
    $CaseNumber=Read-Host "Please enter relevant case number or Service tag"
    
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
                Write-Host "ERROR: Too many attempts. Exiting..." -ForegroundColor Red
                break script
            }
        }

    # Get switch user
    

        IF($SwIPs.count -gt 1){
            $SwIPs=$SwIPs -split ','
            $SwSameUser=Read-Host "Use the same user for all switches?[Y/N]"
            Write-Host "For security reasons a password will need to be provided for each switch."
        }
        IF($SwSameUser -ieq 'y'){$SWUser=Read-Host "Please enter user name"}

    # Add SSH Client
        $ChkIfSSHInstalled=Get-WindowsCapability -Online -Name OpenSSH.Client*
        IF($ChkIfSSHInstalled.state -ne 'Installed'){
            Write-Host "Adding SSH Client..."
            Add-WindowsCapability -Online -Name OpenSSH.Client  > $null
        }

    # Clean up old switch logs
        IF(Test-Path $MyTemp\ShowTechs){Remove-Item "$MyTemp\ShowTechs" -Recurse -Confirm:$false -Force > $null}

    # Create temp folder
        Write-Host "Creating temp output location..."
        New-Item -Path $MyTemp -Name ShowTechs -ItemType Directory -Force > $null
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
                $Switchout | Out-File -FilePath "$MyTemp\ShowTechs\$($SwIp)_ShowTech.log" -Force
         }

   # Zip up show techs
        Write-Host "Compressing show techs..."
        $DT=Get-Date -Format "yyyyMMddHHmm"
        IF(Test-Path -Path "$MyTemp\logs"){
            $ZipPath="$MyTemp\logs\ShowTechs_$($CaseNumber)_$($DT).zip"
            Compress-Archive -Path "$MyTemp\ShowTechs\*.*" -DestinationPath "$MyTemp\logs\ShowTechs_$($CaseNumber)_$($DT)"
            Write-Host "Logs can be found here: $MyTemp\logs\ShowTechs_$($DT).zip"
        }Else{
            $OutFolder=$MyTemp+"\Logs"
            $ZipPath="$MyTemp\logs\ShowTechs_$($CaseNumber)_$($DT).zip"
            New-Item -ItemType Directory -Force -Path $OutFolder  >$null 2>&1
            Compress-Archive -Path "$MyTemp\ShowTechs\*.*" -DestinationPath "$MyTemp\logs\ShowTechs_$($CaseNumber)_$($DT)"
            Write-Host "Logs can be found here: ShowTechs_$($CaseNumber)_$($DT).zip"
        }
#Get the File-Name without path
$name = (Get-Item $ZipPath).Name

#The target URL wit SAS Token
$uri = "https://gsetools.blob.core.windows.net/showtech/$($name)?sp=acw&st=2022-08-14T20:19:23Z&se=2032-08-15T04:19:23Z&spr=https&sv=2021-06-08&sr=c&sig=XfWDMd2y4sQrXm1gxA6up6VRGV5XPrwPkxEINpKTKCs%3D"

#Define required Headers
$headers = @{
    'x-ms-blob-type' = 'BlockBlob'
            }

#Upload File...
Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -InFile $ZipPath -ErrorAction Continue
}
    # Clean up show techs
        Write-Host "Clean up..."
        Remove-Item "$MyTemp\ShowTechs" -Recurse -Confirm:$false -Force

    # Remove SSH if installed during this script
        IF($ChkIfSSHInstalled.state -ne 'Installed'){
            Write-Host "Removing SSH Client..."
            Remove-WindowsCapability -Online -Name $ChkIfSSHInstalled.name  > $null
        }
        
        
    # Remove Function:\Invoke-GetShowTech
        Remove-Item -Path Function:\Invoke-GetShowTech > $null

        Stop-Transcript
    }
} #end if ShouldProcess
}# end of Invoke-GetShowTech
