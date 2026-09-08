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
$ver="1.7"
$titletext=@"
$ver
    _   ___ _____  __  _                 ___     _ _        _           
   /_\ | _ \ __\ \/ / | |   ___  __ _   / __|___| | |___ __| |_ ___ _ _ 
  / _ \|  _/ _| >  <  | |__/ _ \/ _| | | (__/ _ \ | / -_) _|  _/ _ \ '_|
 /_/ \_\_| |___/_/\_\ |____\___/\__, |  \___\___/_|_\___\__|\__\___/_|  
                                |___/                                   
"@
Write-host $titletext
Write-host ""

# Ask for APEX VM IP
[ipaddress]$axvmip=Read-host "Please enter the IP address of the APEX VM:"

# Ask for Root password
$rootpwd = Read-Host "Enter root password for APEX VM (input will be hidden and encrypted)" -AsSecureString

# Download, run and remove log_collect.sh script
Write-Host "Gathering logs..."
$UserCheck = Read-host "Would you like to use the mystic account [y/n]?"
IF($UserCheck -imatch "y"){
    $SshUsername = "mystic"
    Write-Host "Please enter the SSH password for APEX VM access:"
    $Result = ssh $SshUsername@$($axvmip.IPAddressToString) "curl -sSL https://raw.githubusercontent.com/DellProSupportGse/Tools/refs/heads/main/log_collect.sh -o ./log_collect.sh && rm -f manual_log* && chmod 755 log_collect.sh && echo ""$([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($rootpwd)))"" | sudo -S bash ./log_collect.sh && rm ./log_collect.sh"
}Else{
    $SshUsername = Read-host "Please provide ssh user name"
    $Result = ssh $SshUsername@$($axvmip.IPAddressToString) "echo ""$([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($rootpwd)))"" | echo -e 'nameserver 172.28.177.1\nnameserver 8.8.8.8' | sudo tee /etc/resolv.conf > /dev/null && curl -sSL --insecure https://raw.githubusercontent.com/DellProSupportGse/Tools/refs/heads/main/log_collect.sh -o ./log_collect.sh && rm -f manual_log* && chmod 755 log_collect.sh && echo ""$([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($rootpwd)))"" | sudo -S bash ./log_collect.sh && rm ./log_collect.sh"
}

# Clear root password
$rootpwd=""
Write-Host "Securely cleared the root password from memory."

# Find path to output
$logpath = $result | select -last 1
$logpath = ($logpath -split ": ")[-1]
$logname = Split-Path $logpath -leaf

# Copy local
Write-Host "Please enter the SCP password for log transfer:"
scp $SshUsername@$($axvmip.IPAddressToString):$logpath $env:temp\$logname

Write-host "Log files are located at: $env:temp\$logname"
return "$env:temp\$logname"
}
