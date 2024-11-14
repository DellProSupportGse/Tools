    <#
    .Synopsis
       Invoke-RunAPEXlogsCollector
    .DESCRIPTION
       This tool is used to collect logs from APEX VM
    .EXAMPLE
       Invoke-RunAPEXlogsCollector
    #>

Function Invoke-RunAPEXlogsCollector {
clear-host
$ver="1.2"
$titletext=@"
$ver
    _   ___ _____  __  _                 ___     _ _        _           
   /_\ | _ \ __\ \/ / | |   ___  __ _   / __|___| | |___ __| |_ ___ _ _ 
  / _ \|  _/ _| >  <  | |__/ _ \/ _| | | (__/ _ \ | / -_) _|  _/ _ \ '_|
 /_/ \_\_| |___/_/\_\ |____\___/\__, |  \___\___/_|_\___\__|\__\___/_|  
                                |___/                                   
"@
Write-host ""
Write-host $titletext

# Ask for APEX VM IP
[ipaddress]$axvmip=Read-host "Please enter the IP address of the APEX VM:"

# Ask for Root password
$rootpwd=Read-Host "Please enter the root password for the APEX VM:" -AsSecureString

# Download, run and remove log_collect.sh script
Write-host "Executing log collection..."
$Result = ssh mystic@$($axvmip.IPAddressToString) "curl -sSL https://raw.githubusercontent.com/DellProSupportGse/Tools/refs/heads/main/log_collect.sh -o ./log_collect.sh && rm -f manual_log* && chmod 755 log_collect.sh && echo ""$([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($rootpwd)))"" | sudo -S bash ./log_collect.sh && rm ./log_collect.sh"

# Clear root password
$rootpwd=""
Write-host "Cleared the stored root password."

# Find path to output
$logpath = $result | select -last 1
$logpath = ($logpath -split ": ")[-1]
$logname = Split-Path $logpath -leaf

# Copy local
Write-host "Please enter the password to enable SCP for log transfer:"
scp mystic@$($axvmip.IPAddressToString):$logpath $env:temp\$logname

Write-host "Log files are located at: $env:temp\$logname"
return "$env:temp\$logname"
}
