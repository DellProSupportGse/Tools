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
Write-host ""
$ver="1.1"
$text=@"
$ver
    _   ___ _____  __  _                 ___     _ _        _           
   /_\ | _ \ __\ \/ / | |   ___  __ _   / __|___| | |___ __| |_ ___ _ _ 
  / _ \|  _/ _| >  <  | |__/ _ \/ _| | | (__/ _ \ | / -_) _|  _/ _ \ '_|
 /_/ \_\_| |___/_/\_\ |____\___/\__, |  \___\___/_|_\___\__|\__\___/_|  
                                |___/                                   

"@

$text

# Ask for APEX VM IP
[ipaddress]$axvmip=Read-host "Please provide APEX VM IP address "

# Ask for Root password
$rootpwd=Read-Host "Please provide root password" -AsSecureString

# Download, run and remove log_collect.sh script
$Result = ssh mystic@$($axvmip.IPAddressToString) "curl -sSL https://raw.githubusercontent.com/DellProSupportGse/Tools/refs/heads/main/log_collect.sh -o ./log_collect.sh && chmod 755 log_collect.sh && echo ""$([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($rootpwd)))"" | sudo -S bash ./log_collect.sh && rm ./log_collect.sh"

# Clear root password
$rootpwd=""

# Find path to output
$logpath = $result | select -last 1
$logpath = ($logpath -split ": ")[-1]
$logname = Split-Path $logpath -leaf

# Copy local
scp mystic@$($axvmip.IPAddressToString):$logpath $env:temp\$logname

Write-host "Logs can be found at: $env:temp\$logname"
return "$env:temp\$logname"
}
