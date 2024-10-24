# Copyright (c) 2023 Dell Inc. or its subsidiaries. All Rights Reserved.
#
# This software contains the intellectual property of Dell Inc. or is licensed to Dell Inc. from third parties.
# Use of this software and the intellectual property contained therein is expressly limited to the terms and
# conditions of the License Agreement under which it is provided by or on behalf of Dell Inc. or its subsidiaries.


# Describe
#This script use to collect ECE log from node, if you Failed on create azure cluster step, maybe need to use this to collect
#
# User guide:
# 1.Please Login to primary node
#    - if primary node already join AD, please use AD account to login, if not join AD or can not login please use local admin account
# 2.Copy this script to node any path
# 3.Run command ./Anacortes_Day1_ECE_log_collection_tool.ps1 LocalAdminUser LocalAdminPswd AdUser AdPswd
#    - please replace LocalAdminUser,LocalAdminPswd,AdUser,AdPswd
# 4.The log zip will be generated in the directory where this script is located

Function Invoke-EceLogCollection{
	
# Gather creds without showing the Password
	$LocalAdminCreds=Get-Credential -UserName (Get-LocalUser | Where-Object { $_.SID -like '*-500' }).name -Message "Please enter the local administrator account credentials."
	$LocalAdminUser = $LocalAdminCreds.UserName
	$Ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($LocalAdminCreds.Password)
	$LocalAdminPswd = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($Ptr)
	[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Ptr)

	$LcmCreds=Get-Credential -Message "Please enter the LCM account credentials."
	$AdUser = $LcmCreds.UserName
	$Ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($LcmCreds.Password)
	$AdPswd = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($Ptr)
	[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Ptr)


param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
    [string]
    ${LocalAdminUser},

    [Parameter(Mandatory = $true, Position = 1, ValueFromPipelineByPropertyName = $true)]
    [string]
    ${LocalAdminPswd},

    [Parameter(Mandatory = $true, Position = 2, ValueFromPipelineByPropertyName = $true)]
    [string]
    ${AdUser},

    [Parameter(Mandatory = $true, Position = 3, ValueFromPipelineByPropertyName = $true)]
    [string]
    ${AdPswd}
)

function copyFile(){
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0, HelpMessage="Nodecredential")]
        [System.Management.Automation.PSCredential]
        $Nodecredential,

        [Parameter(Mandatory=$true, Position=1, HelpMessage="ADcredential")]
        [System.Management.Automation.PSCredential]
        $ADcredential,

        [Parameter(Mandatory=$true, Position=2, HelpMessage="node ip")]
        [String]
        $IP,

        [Parameter(Mandatory=$true, Position=3, HelpMessage="file path")]
        [String]
        $Path,

        [Parameter(Mandatory=$true, Position=4, HelpMessage="destination file path")]
        [String]
        $DestinationFile
    )

    New-Item -ItemType Directory -Path $DestinationFile -Force
    try {
        #use ad credential
        if ($ADcredential){
            Write-Host "use provided AD credential to copy file"
            Copy-Item -Path "\\$IP\$Path" -Destination $DestinationFile -Credential $ADcredential
        }else{
            Write-Host "use current logined account to copy file"
            Copy-Item -Path "\\$IP\$Path" -Destination $DestinationFile -Recurse
        }
    } catch {
        #use node credential
        try {
            if ($Nodecredential){
                Write-Host "use AD account fail, use provided node credential copy file"
                Copy-Item -Path "\\$IP\$Path" -Destination $DestinationFile -Credential $Nodecredential
            }else{
                Write-Host "use AD account fail, use current logined account to copy file"
                Copy-Item -Path "\\$IP\$Path" -Destination $DestinationFile -Recurse
            }
        } catch {
            Write-Host "use Node account fail, use logined account"
            Copy-Item -Path "\\$IP\$Path" -Destination $DestinationFile -Recurse
        }
    }

}

#node credential
if ($LocalAdminUser -and $LocalAdminPswd){
    $securePassword = ConvertTo-SecureString -String $LocalAdminPswd -AsPlainText -Force
    $Nodecredential = New-Object System.Management.Automation.PSCredential ($LocalAdminUser, $securePassword)
}else{
    $Nodecredential = $null
}
#AD credential
if ($AdUser -and $AdPswd){
    $securePassword = ConvertTo-SecureString -String $AdPswd -AsPlainText -Force
    $ADcredential = New-Object System.Management.Automation.PSCredential ($AdUser, $securePassword)
}else{
    $ADcredential = $null
}
# this script directory
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
#root folder name
$timestamp = Get-Date -Format "yyyy-MM-dd.HH-mm-ss"
$LogsRootDirectory = $scriptDirectory + "\ECELogs" + $timestamp
Write-Host "Log folder: $LogsRootDirectory"
# use ece payload to get node ip
$ecePayloadFile = "C:\config.json"
if(-not (Test-Path $ecePayloadFile)){
    #day1 post node clean will remove C:\config.json, so get node ip from this path
    $ecePayloadFile = "C:\CloudDeployment\DeploymentData\Unattended.json"
}
if(Test-Path $ecePayloadFile){
    # read ece payload
    $jsonContent = Get-Content -Path $ecePayloadFile -Raw | ConvertFrom-Json

    # get nodes from ece payload
    $nodes = $jsonContent.ScaleUnits[0].DeploymentData.PhysicalNodes
}

$adapter = Get-NetAdapter | Where-Object { $_.Name -like "vManagement*"}
$primaryIpAddress = $adapter | Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.SkipAsSource -eq $false } | Select-Object -ExpandProperty IPAddress

$logFiles = @(
@{
    Path = "C:\CloudDeployment\Logs\*"
    Name = "C_CloudDeployment_Logs"
    OnlyPrimary = $true
},
@{
    Path = "C:\CloudDeployment\DeploymentData\*"
    Name = "C_CloudDeployment_DeploymentData"
    OnlyPrimary = $true
},
@{
    Path = "C:\EceStore\*"
    Name = "C_EceStore"
    OnlyPrimary = $true
},
@{
    Path = "C:\MASLogs\*"
    Name = "C_MASLogs"
    OnlyPrimary = $false
},
@{
    Path = "D:\CloudContent\MASLogs\*"
    Name = "D_CloudContent_MASLogs"
    OnlyPrimary = $false
},
@{
    Path = "C:\Windows\Tasks\ArcForServers\RegisterArc_*.log"
    Name = "C_Windows_Tasks_ArcForServers"
    OnlyPrimary = $false
},
@{
    Path = "D:\CloudContent\RegisterHCI_*.log"
    Name = "D_CloudContent"
    OnlyPrimary = $false
},
@{
    Path = "D:\CloudContent\ArcForServerInstall_*.txt"
    Name = "D_CloudContent"
    OnlyPrimary = $false
},
@{
    Path = "C:\Windows\Temp\*"
    Name = "C_Window_Temp"
    OnlyPrimary = $true
},
@{
    Path = "C:\Dell\Logs\Lcm\*"
    Name = "C_Dell_Logs_Lcm"
    OnlyPrimary = $false
},
@{
    Path = "C:\Dell\Payload\Log\*"
    Name = "C_Dell_Payload_Log"
    OnlyPrimary = $false
},
@{
    Path = "C:\config.json"
    Name = "C_day1payload"
    OnlyPrimary = $true
},
@{
    Path = "C:\ProgramData\AzureConnectedMachineAgent\Log\*"
    Name = "C_ProgramData_AzureConnectedMachineAgent_Log"
    OnlyPrimary = $true
},
@{
    Path = "C:\ProgramData\GuestConfig\arc_policy_logs\gc_agent.log"
    Name = "C_ProgramData_GuestConfig_arc_policy_logs"
    OnlyPrimary = $true
},
@{
    Path = "C:\ProgramData\GuestConfig\ext_mgr_logs\gc_ext.log"
    Name = "C_ProgramData_GuestConfig_ext_mgr_logs"
    OnlyPrimary = $true
},
@{
    Path = "C:\ProgramData\GuestConfig\extension_logs"
    Name = "C_ProgramData_GuestConfig_extension_logs"
    OnlyPrimary = $true
}
)


# collect primary node logs
Write-Host "=====================collect log on primary==========================="
Write-Host "collect log on primary, ip: $primaryIpAddress"
foreach ($logFile in $logFiles) {
    $logPath = $logFile.Path
    $parentPath = Split-Path -Path $logPath -Parent
    $destinationFile = $LogsRootDirectory + "\$primaryIpAddress\" + $logFile.Name
    Write-Host "collect path from: $logPath to path: $destinationFile"
    #\* or \xxxx_*.xxx
    if ($logPath -like "*\`*") {
        if (Test-Path $parentPath) {
            New-Item -ItemType Directory -Path $destinationFile -Force
            Copy-item $logPath -Destination $destinationFile -Recurse
        }
        else {
            Write-Host "directory $( $logPath ) not exist"
        }
    }else{
        if (Test-Path $parentPath) {
            New-Item -ItemType Directory -Path $destinationFile -Force
            Copy-item $logPath -Destination $destinationFile
        }
    }
}
# collect non-primary node logs
Write-Host "=====================collect log on non-primary==========================="
if($nodes){
    foreach ($node in $nodes) {
        if ($node.IPv4Address -ne $primaryIpAddress){
            $ip = $node.IPv4Address
            Write-Host "collect log on non-primary, ip: $ip"
            #skip current node(primary node)
            foreach ($logFile in $logFiles) {
                if ($logFile.OnlyPrimary -eq $false){
                    $parentPath = Split-Path -Path $logFile.Path -Parent
                    $destinationFile = $LogsRootDirectory + "\$ip\" + $logFile.Name
                    $logPath = $logFile.Path
                    Write-Host "collect path from: $logPath to path: $destinationFile"
                    $path = $logPath.Replace(":", "$")
                    #\* or \xxxx_*.xxx
                    if ($logPath -like "*\`*") {
                        if (Test-Path $parentPath) {
                            copyFile $Nodecredential $ADcredential $ip $path $destinationFile
                        }
                        else {
                            Write-Host "directory $( $logPath ) not exist"
                        }
                    }else{
                        if (Test-Path $parentPath) {
                            copyFile $Nodecredential $ADcredential $ip $path $destinationFile
                        }
                    }
                }
            }
        }
    }
}else{
    Write-Host "can not get nodes ip from C:\config.json"
}
Write-Host "=====================Compress log==========================="
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipFilePath = "$LogsRootDirectory.zip"

[System.IO.Compression.ZipFile]::CreateFromDirectory($LogsRootDirectory, $zipFilePath)
Write-Host "=====================remove log folder==========================="
Remove-Item -Path $LogsRootDirectory -Force -Recurse
Write-Host "collect finish!"
Write-Host "zip path: $zipFilePath"
}
