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
$ver="1.3"
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
$rootpwd = Read-Host "Enter root password for APEX VM (input will be hidden):" -AsSecureString

# Download, run and remove log_collect.sh script
Write-Host "Gathering logs..."
Write-Host "Please enter the SSH password for APEX VM access:"
$Result = ssh mystic@$($axvmip.IPAddressToString) "curl -sSL https://raw.githubusercontent.com/DellProSupportGse/Tools/refs/heads/main/log_collect.sh -o ./log_collect.sh && rm -f manual_log* && chmod 755 log_collect.sh && echo ""$([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($rootpwd)))"" | sudo -S bash ./log_collect.sh && rm ./log_collect.sh" *> $null 2>&1

# Clear root password
$rootpwd=""
Write-Host "Securely cleared the root password from memory."

# Find path to output
$logpath = $result | select -last 1
$logpath = ($logpath -split ": ")[-1]
$logname = Split-Path $logpath -leaf

# Copy local
Write-Host "Please enter the SCP password for log transfer:"
scp mystic@$($axvmip.IPAddressToString):$logpath $env:temp\$logname

Write-host "Log files are located at: $env:temp\$logname"
return "$env:temp\$logname"
}
