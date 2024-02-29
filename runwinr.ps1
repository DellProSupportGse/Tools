# Test WinRM connectivity and configuration
# Created By: Jim Gandy
# v1.0
Function Invoke-RunWinr{
$Name=@{
____    __    ____  __  .__   __. .______      
\   \  /  \  /   / |  | |  \ |  | |   _  \     
 \   \/    \/   /  |  | |   \|  | |  |_)  |    
  \            /   |  | |  . `  | |      /     
   \    /\    /    |  | |  |\   | |  |\  \----.
    \__/  \__/     |__| |__| \__| | _| `._____|
                                               
}
 $Name

# Define the remote computer name
$remoteComputerName = $ENV:ComputerName
 
$winrmService = Get-Service -Name WinRM -ComputerName $remoteComputerName
$winrmClient = Invoke-Command -ComputerName $remoteComputerName -ScriptBlock { Get-WSManInstance -ResourceURI winrm/config/client  }
$winrmListener = Invoke-Command -ComputerName $remoteComputerName -ScriptBlock { Get-WSManInstance -ResourceURI winrm/config/listener -Enumerate}
$winrmEventLog = Get-EventLog System -ComputerName $remoteComputerName -Source Microsoft-Windows-WinRM -ErrorAction SilentlyContinue
$winrmSpn = & setspn -L $ENV:Computername | FindStr /I "WSMAN"


# Initialize an empty object
$resultObject = New-Object PSObject

# Test WinRM service status
if ($winrmService.Status -eq "Running") {
    $resultObject | Add-Member -MemberType NoteProperty -Name "WinRMServiceRunning" -Value $True
} else {
    $resultObject | Add-Member -MemberType NoteProperty -Name "WinRMServiceRunning" -Value $False
}

# Test WinRM listener configuration
if ($winrmListener.Enabled -eq "True") {
    $resultObject | Add-Member -MemberType NoteProperty -Name "WinRMListenerConfigured" -Value $true
} else {
    $resultObject | Add-Member -MemberType NoteProperty -Name "WinRMListenerConfigured" -Value $false
}
# Test WinRM Firewall configuration
if ($winrmListener.Enabled -eq "True") {
    $resultObject | Add-Member -MemberType NoteProperty -Name "WinRMListenerConfigured" -Value $true
} else {
    $resultObject | Add-Member -MemberType NoteProperty -Name "WinRMListenerConfigured" -Value $false
}


# Test WinRM client configuration
if ($winrmClient.NetworkDelayms -eq "5000") {
    $resultObject | Add-Member -MemberType NoteProperty -Name "WinRMClientNetworkDelayms5000" -Value $true
} else {
    $resultObject | Add-Member -MemberType NoteProperty -Name "WinRMClientNetworkDelayms5000" -Value $false
}

# Test network connectivity
if (Test-Connection -ComputerName $remoteComputerName -Count 1 -Quiet) {
    $resultObject | Add-Member -MemberType NoteProperty -Name "TestConnectionResult" -Value $true
} else {
    $resultObject | Add-Member -MemberType NoteProperty -Name "TestConnectionResult" -Value $false
}

# Test event logs for WinRM-related errors or warnings
if ($winrmEventLog.count -gt 0) {
    $resultObject | Add-Member -MemberType NoteProperty -Name "WinRMEventErrors" -Value $True
} else {
    $resultObject | Add-Member -MemberType NoteProperty -Name "WinRMEventErrors" -Value $False
}

# Test WSMAN SPN
if ($winrmSpn.count -ge 2) {
    $resultObject | Add-Member -MemberType NoteProperty -Name "WSMAN SPN Count" -Value $True
} else {
    $resultObject | Add-Member -MemberType NoteProperty -Name "WSMAN SPN Count" -Value $False
}

$resultObject
}
