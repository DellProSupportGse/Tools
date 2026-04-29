Function Test-DellAzureLocalIssues {

param(
    [switch]$FixErrors,
    [switch]$FixWarningsAlso,
    [switch]$ErrorOnlyCheck,
    [switch]$ApproveAllFixesAutomatically
)
    $ver="0.1"
    # Check if the current session is running as Administrator
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host -ForegroundColor Yellow "Not running as Administrator. Please run the script with elevated privileges."
        Break
    }
    # Check if script running in a remote Powershell session
    if ($PSSenderInfo) {Write-Host -ForegroundColor Yellow "This script is not supported using a remote powershell session. Please run locally";Break}
    # Check if script is running on a cluster node
    If ((invoke-command -scriptblock {try {get-cluster -ErrorAction SilentlyContinue} catch {}}).Name -eq $null -or !(gcm Get-SolutionUpdate -ErrorAction SilentlyContinue)) {Write-Host -ForegroundColor DarkYellow "This script MUST be run locally on a Dell Azure Local cluster node.";Break}
    Function Write-ToHost {
    param(
        [string]$Message,
        [int]$Level=1, # 0=Verbose, 1=Info, 2=Warning, 3=Error, 4=Critical
        [int]$Checkmark=1 # 1=Green check, 2=Yellow check, 3=Red X
    )
        $Color=@("DarkGray","Green","DarkYellow","Red","Magenta")[$Level]
        If ($Checkmark) {$Message=@("","$([char]0x2713)","$([char]0x26A0)","$([char]0x2716)","$([char]0x2622)")[$Checkmark] + " $Message"}
        Write-Host -ForegroundColor $Color $Message
    }

    #region Test Scripts
    Function Test-SolutionUpdateCommand {
        $dtime=0
        Write-Host "Checking Solution Update command..."
        $SUJob=Start-Job -Name "SUJob" -ScriptBlock {Get-Solutionupdate}
        $testSU=$null
        While ($dtime -lt 12 -and $SUJob.State -eq "Running") {Write-Host "." -NoNewline;$dtime++;$testSU+=Receive-Job -Name "SUJob";sleep 5}
	Write-Host "."
	$testSU+=Receive-Job -Name "SUJob"
        If ($dtime -lt 12 -and $testSU.resourceid -gt "") {
            Write-ToHost "Get Solution Update command successful" -Checkmark 1 -Level 1
            return $false
        } else {
            Write-ToHost "Get Solution Update command FAILED" -Checkmark 3 -Level 3
            return $true
        }
    }
    Function Test-NetIntents {
        $failedNetIntent=@()
        Write-Host "Checking Net Intents..."
        $failedNetIntent+=$GetNetIntentStatus | ? {$_.LastSuccess -lt (Get-Date).AddMinutes(-40)}
        $failedNetIntent+=$GetNetIntentGlobalStatus | ? {$_.LastSuccess -lt (Get-Date).AddMinutes(-40)}
        $failedNetIntent=$failedNetIntent | ? {$_.Progress -gt ""}
        If ($failedNetIntent.Progress -gt "") {
           Foreach ($failedIntent in $failedNetIntent) {
               Write-ToHost "Net Intent $($failedIntent.Name) on Node $($failedIntent.Host) FAILED" -Checkmark 3 -Level 3
               return $true
           }
        } else {
           Write-ToHost "Net Intent check successful" -Checkmark 1 -Level 1
        }
        return $failedNetIntent
    }
    Function Test-iDracHostNicDHCP {
        Write-Host "Checking iDrac host nics have DHCP enabled..."
        $iDracDHCP=Invoke-Command -ComputerName $nodes -ScriptBlock {Get-NetAdapter -ifdesc *NDIS* | Get-NetIPInterface -AddressFamily IPv4 | Select PSComputerName,DHCP}
        Foreach($dIDrac in $iDracDHCP) {if ($dIDrac.DHCP -match "\d") {$dIDrac.DHCP=@("Disabled","Enabled")[$dIDrac.DHCP]}}
        If (($iDracDHCP.DHCP -notlike "Enabled*").count) {
            Write-ToHost "iDracs network adapters on host(s) $(($iDracDHCP | ? Dhcp -notlike "Enabled*").PSComputerName -join ',') have DHCP disabled!!" -Checkmark 3 -Level 3
        } else {
            Write-ToHost "All iDrac host network adapters have DHCP enabled" -Level 1 -Checkmark 1
        }
        return ($iDracDHCP | ? Dhcp -notlike "Enabled*")
    }
    Function Test-iDracRedfish {
        Write-Host "Checking iDrac redfish url..."
        $Redfish=Invoke-Command -ComputerName $nodes -ScriptBlock {
            add-type "using System.Net;using System.Security.Cryptography.X509Certificates;public class T : ICertificatePolicy {public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate,WebRequest request, int certificateProblem) {return true;}}";[System.Net.ServicePointManager]::CertificatePolicy = New-Object T
            $iDracIP=(Get-CimInstance win32_networkadapterconfiguration | ? Description -like "*NDIS*").DHCPServer
            $result=try {Invoke-RestMethod https://$iDracIP/redfish/v1/ } catch {}
            If ($result.Vendor -ne 'Dell') {$work=$false} else {$work=$true}
            [PSCustomObject]@{"PSComputerName"=$env:COMPUTERNAME;"Success"=$work}
        }
        $Redfish=$Redfish | ? Success -eq $false
        If ($Redfish.Success -match $false) {
            Write-ToHost "iDrac on host(s) $($Redfish.PSComputerName -join ',') have problems accessing the redfish url!" -Checkmark 3 -Level 3
        } else {
            Write-ToHost "All iDracs can access the redfish url" -Level 1 -Checkmark 1
        }
        return $Redfish
    }
    Function Test-OsBootTimeOver99Days {
        Write-Host "Testing that all nodes have been rebooted within 99 days..."
        $failedOSBootTimeOver99Days=@()
        $failedOSBootTimeOver99Days+=Get-CimInstance -ComputerName $nodes Win32_OperatingSystem | %{[PSCustomObject]@{"CsName"=$_.CsName;"OSBootOver99Days"=If(((Get-Date).AddDays(-99)-$_.LastBootUpTime) -gt 0) {$true} else {$false}}}
        $failedOSBootTimeOver99Days=$failedOSBootTimeOver99Days | ? OSBootOver99Day -eq $true
        If ($failedOSBootTimeOver99Days) {
           Write-ToHost "Node(s) $($failedOSBootTimeOver99Days.CsName -join ',') have not been rebooted for over 99 days" -Checkmark 2 -Level 2
        } else {
           Write-ToHost "All nodes have been rebooted within 99 days"
        }
        return $failedOSBootTimeOver99Days
    }
    Function Test-HWTimeout {
        Write-Host "Testing that all nodes have the HWTimeout registry key set to at least 10000..."
        $results = Invoke-Command -ComputerName $nodes -ScriptBlock {
            $path = "HKLM:\SYSTEM\CurrentControlSet\Services\spaceport\Parameters"
            $value = Get-ItemProperty -Path $path -Name HwTimeout -ErrorAction SilentlyContinue
            [PSCustomObject]@{
                Node      = $env:COMPUTERNAME
                HwTimeout = if ($value) { $value.HwTimeout } else { 0 }
            }
        }
        $nonCompliant = $null
        $nonCompliant = $results | Where-Object { $_.HwTimeout -lt 10000 }
        If ($nonCompliant) {
            Write-ToHost "Node(s) $($nonCompliant.Node) do(es) not have HWTimeout set to at least 10000" -Checkmark 3 -Level 3
        } else {
            Write-ToHost "All nodes have HWtimeout set to at least 10000"
        }
        return $nonCompliant
    }
    Function Test-NodesUpDisksinMaintMode {
        Write-Host "Testing if nodes are up but disks are still in maintenance mode..."
        $downNodes = Get-ClusterNode | Where-Object State -ne "Up"
        $disksInMaint=@()
        $disksInMaint += Get-PhysicalDisk | Where-Object {$_.OperationalStatus -contains "In Maintenance Mode"}
        If ($disksInMaint -and !($downNodes)) {
            Write-ToHost "Disks $($disksInMaint.SerialNumber -join ',') are in maintenance mode" -Checkmark 3 -Level 3
            return $disksInMaint
        } else {
            Write-ToHost "All disks are in proper status"
            return $null
        }
    }
    Function Test-TimeZone {
        Write-Host "Testing that all nodes have the same time zone..."
        $tzones = Invoke-Command -ComputerName $nodes -ScriptBlock {
            [PSCustomObject]@{"Node" = $env:COMPUTERNAME;"TimeZone" = (Get-TimeZone).Id}
        }
        $topGroup = ($tzones | Group-Object TimeZone | Sort-Object Count -Descending)[0]
        $global:dTimeZone=$topGroup.name
        $nonCompliant = @()
        If ($topGroup.count -ne ($nodes.count)) {
            If ($topGroup.count -le ($nodes.count/2)) {
                Write-ToHost "Time zone consistency not compliant and cannot determine correct time zone" -Checkmark 3 -Level 3
            } else {
                $nonCompliant += $tzones | Where-Object { $_.TimeZone -ne $topGroup.Name }
                If ($nonCompliant) {
                    Write-ToHost "Node(s) $($nonCompliant.Node) do(es) not have the correct time zone defined" -Checkmark 3 -Level 3
                }
            }
        } else {
            Write-ToHost "All nodes have the same time zone"
        }
        return $nonCompliant
    }
    Function Test-ClusterShutdownTime {
        Write-Host "Testing cluster shutdown timeout..."
        $CSTIM = (Get-Cluster).ShutdownTimeoutInMinutes
        $nodeResources=Invoke-Command -ComputerName $nodes -ScriptBlock {
            $mem=(Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum
            [PSCustomObject]@{"Node" = $env:COMPUTERNAME;"Memory" = $mem}
        }
        $nonCompliant = @()
        if ($CSTIM -lt 1440) {
            $nonCompliant+=$nodeResources | ? {($_.mem/1tb) -ge 1tb} 
        }
        If ($nonCompliant) {
            Write-ToHost "Cluster shutdown time in minutes is less than 1440 with nodes having at least 1TB of memory" -Checkmark 3 -Level 3
            return $true
        } else {
            Write-ToHost "Cluster shutdown time in minutes is set correctly"
            return $false
        }
        
    }
    Function Test-InvalidCAUReports {
        Write-Host "Testing for invalid CAU Reports..."
        $noncompliant=@()
        $noncompliant+=Invoke-Command -ComputerName $nodes -ScriptBlock {Get-Item C:\Windows\Cluster\Reports\CauReport-00000101000000.xml -ErrorAction SilentlyContinue}
        If ($nonCompliant) {
            Write-ToHost "Cluster nodes have invalid CAU Reports" -Checkmark 3 -Level 3
            return $true
        } else {
            Write-ToHost "Cluster nodes have no invalid CAU Reports"
            return $false
        }
    }
    Function Test-NetworkDirectOnComputeIntents {
        Write-Host "Testing for invalid compute Net Intent Network Direct configuration..."
        $GetNetIntentCompute = @()
        $FailedComputeIntents = @()
        $GetNetIntentCompute += $GetNetIntent | ? IsStorageIntentSet -eq $false
        Foreach ($GetNetIntentC in $GetNetIntentCompute) {
            If ($GetNetIntentC.AdapterAdvancedParametersOverride.NetworkDirect -gt 0) {
                If ($GetNetIntentC.AdapterAdvancedParametersOverride.NetworkDirectTechnology -le "") {
                    $FailedComputeIntents += $GetNetIntentC
                }
            }
        }
        If ($FailedComputeIntents) {
            Write-ToHost "Compute Net Intent(s) have Network Direct enabled" -Checkmark 3 -Level 3
        } else {
            Write-ToHost "Compute Net Intents Network Direct are configured correctly"
        }
        return $FailedComputeIntents
    }
    #endregion Test Scripts

    # Main Process
    New-Item C:\ProgramData\Dell -ErrorAction SilentlyContinue -ItemType Directory
    Start-Transcript -Append "C:\ProgramData\Dell\Test-DellAzureLocalIssues-$(Get-Date -Format "yyyyMMdd").txt"
    Write-Host @"
v$ver
 ______   ______     __         __    
/\__  _\ /\  __ \   /\ \       /\ \   
\/_/\ \/ \ \  __ \  \ \ \____  \ \ \  
   \ \_\  \ \_\ \_\  \ \_____\  \ \_\ 
    \/_/   \/_/\/_/   \/_____/   \/_/ 
                                      
                      by: Tommy Paulk
"@
    If ($FixErrors -or $FixWarningsAlso) {Write-Warning "Fix commands are in beta and SHOULD NOT be used without proper guidance";sleep 5}
    $nodes=(Get-ClusterNode).Name
    Write-Host ""
    If ((Get-Job -Name "SUJob" -ErrorAction SilentlyContinue).count) {
        Write-Host "Waiting for prevoius Get Solution Update command to timeout..."
        Get-Job -Name "SUJob" -ErrorAction SilentlyContinue | Remove-Job -Force
    }
    if (Test-SolutionUpdateCommand) {
        If ($FixErrors -or $FixWarningsAlso) {
            Write-Host "Fixing Get Solution Update command. Est Time is less than five minutes" -ForegroundColor Cyan
            Get-ClusterGroup "Azure Stack HCI Download Service Cluster Group","Azure Stack HCI Health Service Cluster Group","Azure Stack HCI Orchestrator Service Cluster Group","Azure Stack HCI Update Service Cluster Group" | Stop-ClusterGroup | Start-ClusterGroup
            Write-Host "Restarting cluster groups finished."
	    Write-Host "Waiting for Get Solution Update command to time out"
            While ((Get-Job "SUJob").State -eq "Running") {Write-Host "." -NoNewline;sleep 5}
            Write-Host "."
            Get-Job -Name "SUJob" -ErrorAction SilentlyContinue | Remove-Job -Force
            If (Test-SolutionUpdateCommand) {Write-ToHost "Fix Get Solution Update command FAILED!!!" -Level 4 -Checkmark 4}
        } else {
            Write-Host "Recommendation: Restart the Azure Stack HCI cluster groups and make sure they are Online"
        }
    }
    Write-Host ""
    $GetNetAdapterAll=Invoke-Command -ComputerName $nodes -ScriptBlock {Get-NetAdapter}
    $GetNetIntent=Get-NetIntent
    $GetNetIntentStatus=Get-NetIntentStatus
    $GetNetIntentGlobalStatus=Get-NetIntentStatus -GlobalOverrides
    $failedNetIntent=Test-NetIntents
    If ($failedNetIntent)  {
        If ($FixErrors -or $FixWarningsAlso) {
            Write-Host "Fixing Net Intents. Est Time is less than $($global:failedNetIntent.count+1) minutes" -ForegroundColor Cyan
            Get-service -ComputerName $nodes "NetworkAtc" | Stop-Service
            Get-service -ComputerName $nodes "NetworkAtc" | Start-Service -Verbose
            Foreach ($dNetAdapter in ($GetNetAdapterAll | ? {($GetNetIntent.NetAdapterNamesAsList) -match $_.name -and !($_.status -eq "Up" -or $_.ifOperStatus -eq "Up")})) {
                  Invoke-Command -ComputerName "$(($dNetAdapter).PSComputerName)" -ScriptBlock {Enable-NetAdapter -ifAlias "$($dNetAdapter.Name)" -Verbose}
            }
            Sleep 5
            $GetNetAdapterAll=Invoke-Command -ComputerName $nodes -ScriptBlock {Get-NetAdapter}
            $dnetAdapter=$null
            $dnetAdapter=($GetNetAdapterAll | ? {($GetNetIntent.NetAdapterNamesAsList) -match $_.name -and !($_.status -eq "Up" -or $_.ifOperStatus -eq "Up")})
            if ($dnetAdapter) {
                Write-ToHost "Net adapter(s) $($dnetAdapter.Name -join ',') on node(s) $($dNetAdapter.PSComputerName -join ",") in Net Intents are not working!!" -Level 4 -Checkmark 4
            }
            Foreach ($failedIntent in $failedNetIntent) {
                if ($failedIntent.IntentName -le "") {
                     Set-NetIntentRetryState -NodeName $failedIntent.Host -GlobalOverrides -Wait
                } else {
                     Set-NetIntentRetryState -NodeName $failedIntent.Host -Name $failedIntent.IntentName -Wait
                }
            }
            Sleep 5
            $failedNetIntent=Test-NetIntents
            If ($failedNetIntent) {Write-ToHost "Fix Net Intents FAILED!!!" -Level 4 -Checkmark 4}
        } else {
            $dnetAdapter=($GetNetAdapterAll | ? {($GetNetIntent.NetAdapterNamesAsList) -match $_.name -and !($_.status -eq "Up" -or $_.ifOperStatus -eq "Up")})
            if ($dnetAdapter) {
                Write-Host "Recommendation: Plug in and enable network adapters used in Net Intents and Retry the failed Net Intents"
            } else {
                Write-Host "Recommendation: Retry the failed Net Intents"
            }
        }
    }
    Write-Host ""
    #$IdracIP=((ipconfig /all | Select-String "NDIS" -Context 0,15).tostring().split('`n') | select-string -SimpleMatch "DHCP Server" | %{[regex]::Match($_,"(\b169\.254\.\d{1,3}\.\d{1,3}\b)")}).groups[1].value
    #$iDracIP=(Get-CimInstance win32_networkadapterconfiguration | ? Description -like "*NDIS*").DHCPServer
    add-type "using System.Net;using System.Security.Cryptography.X509Certificates;public class T : ICertificatePolicy {public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate,WebRequest request, int certificateProblem) {return true;}}";[System.Net.ServicePointManager]::CertificatePolicy = New-Object T
    $failediDracDHCP=Test-iDracHostNicDHCP
    if ($failediDracDHCP) {
        If ($FixErrors -or $FixWarningsAlso) {
            Write-Host "Fixing iDrac Host Nic DHCP. Est Time is less than one minute" -ForegroundColor Cyan
            Invoke-Command -ComputerName $failediDracDHCP.PSComputerName -ScriptBlock {
                Get-NetAdapter -ifdesc *NDIS* | Get-NetIPAddress | Remove-NetIPAddress -Confirm:$false -Verbose
                Get-NetAdapter -ifdesc *NDIS* | Set-NetIPInterface -Dhcp Enabled -Verbose
                Get-NetAdapter -ifdesc *NDIS* | Disable-NetAdapter -Confirm:$false -PassThru | Enable-NetAdapter -Verbose | Out-Null
            }
            Sleep 10
            $failediDracDHCP=Test-iDracHostNicDHCP
            If ($failediDracDHCP) {Write-ToHost "Fix iDrac Host Nic DHCP FAILED!!!" -Level 4 -Checkmark 4}
        } else {
            Write-Host "Recommendation: Enable DHCP on the iDrac host network adapter for all nodes"
        }
    }
    Write-Host ""
    <# New-NetFirewallRule -DisplayName "Block-Idrac-Https-a897gt98gydf" -Direction Outbound -Action Block -RemoteAddress 169.254.0.0/16 -Protocol TCP -RemotePort 443 -Enabled True #>
    $failediDracRedfish=@()
    $failediDracRedfish+=Test-iDracRedfish
    if ($failediDracRedfish) {
        If ($FixErrors -or $FixWarningsAlso) {
            Write-Host "Fixing iDrac Redfish. Est Time is five minutes" -ForegroundColor Cyan
            Write-Host "Please Enter IDrac Credentials for Host $($failediDracRedfish[0].PSComputerName)"
            Invoke-Command -ComputerName $nodes -ScriptBlock {Get-NetFirewallRule -DisplayName "Block-Idrac-Https-a897gt98gydf" -ErrorAction SilentlyContinue | Set-NetFirewallRule -Enabled False}
            Do {
                $credential=Get-Credential -Message "Please enter the iDrac creds for host $($failediDracRedfish[0].PSComputerName)" -UserName root;$cred2=Get-Credential -Message "Confirm iDRAC Password" -UserName $credential.GetNetworkCredential().UserName
            } while (($credential.GetNetworkCredential().Password -ne $cred2.GetNetworkCredential().Password) -or ($credential.GetNetworkCredential().UserName -ne $cred2.GetNetworkCredential().UserName))
            $IdracReboots=@()
            $IdracReboots+=$failediDracRedfish.PSComputerName | %{Invoke-Command -ComputerName $_ -ScriptBlock {
                add-type "using System.Net;using System.Security.Cryptography.X509Certificates;public class T : ICertificatePolicy {public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate,WebRequest request, int certificateProblem) {return true;}}";[System.Net.ServicePointManager]::CertificatePolicy = New-Object T
                $iDracIP=(Get-CimInstance win32_networkadapterconfiguration | ? Description -like "*NDIS*").DHCPServer
                $credential=$using:credential
                $post_result = Invoke-WebRequest -UseBasicParsing -Uri "https://$iDracIP/redfish/v1/Managers/iDRAC.Embedded.1/Actions/Manager.Reset" -Method Post -Body (@{"ResetType"="GracefulRestart"} | ConvertTo-Json -Compress) -ContentType 'application/json' -Headers @{"Accept" = "application/json"} -Credential $credential -ErrorVariable RespErr
                IF($RespErr -match 'The authentication credentials included with this request are missing or invalid.' -or $RespErr.Message -eq "The remote server returned an error: (401) Unauthorized."){
                    $RespErr=""
                    $password=Read-Host "Password incorrect for iDrac on host $($env:COMPUTERNAME). Please enter $($credential.UserName) password" -AsSecureString
                    $credential = New-Object System.Management.Automation.PSCredential($credential.UserName, $password)
                    $post_result = Invoke-WebRequest -UseBasicParsing -Uri "https://$iDracIP/redfish/v1/Managers/iDRAC.Embedded.1/Actions/Manager.Reset" -Method Post -Body (@{"ResetType"="GracefulRestart"} | ConvertTo-Json -Compress) -ContentType 'application/json' -Headers @{"Accept" = "application/json"} -Credential $credential -ErrorVariable RespErr
                }
                If ($RespErr) {Write-Warning $RespErr}
                if ($post_result.StatusCode -eq 204) {
                    Write-Host "iDRAC with ip $iDracIP will be back up within five minutes`n"
                    return $true
                } else {
                    Write-Host "IDrac with ip $iDracIP failed to intiate reboot!" -ForegroundColor Red
                    return $false
                }
            }}
            #$IdracReboots
            if ($IdracReboots.Contains($true)) {Invoke-Command -ComputerName $failediDracRedfish[$IdracReboots.IndexOf($true)].PSComputerName -ScriptBlock {
               $iDracIP=(Get-CimInstance win32_networkadapterconfiguration | ? Description -like "*NDIS*").DHCPServer
               Write-Host "Waiting for iDrac with ip $iDracIP to shutdown"
               $dtime=0
               While ($dtime -lt 30 -and (((Test-NetConnection -ComputerName 169.254.1.11 -WarningAction SilentlyContinue).PingSucceeded) -or ((Test-NetConnection -ComputerName 169.254.1.11 -WarningAction SilentlyContinue).PingSucceeded))) {Write-Host -NoNewline ".";sleep 10;$dtime++}
               Write-Host "."
               $dtime=0
               Write-Host "Waiting for iDrac with ip $iDracIP to boot"
               While ($dtime -lt 50 -and !((Test-NetConnection -ComputerName 169.254.1.11 -WarningAction SilentlyContinue).PingSucceeded)) {Write-Host -NoNewline ".";sleep 10;$dtime++}
               Write-Host "."
               Write-Host "Waiting 30 seconds for iDrac services to come up"
               (1..3) | %{Write-Host "." -NoNewline;sleep 10}
               Write-Host "."
            }}
            $failediDracRedfish=Test-iDracRedfish
            If ($failediDracRedfish) {Write-ToHost "Fix iDrac redfish FAILED! May need to drain flea power on host" -Level 4 -Checkmark 4}
        } else {
            Write-Host "Recommendation: Reboot iDrac on failing nodes and/or enable redfish on those iDracs"
        }
    }
    Write-Host ""
    If ((Test-OsBootTimeOver99Days)){
        Write-host "Recommendation: Manually Pause,Drain and Resume with failback these node(s) to avoid update issues"
    }
    Write-Host ""
    $nonCompliant=Test-HWTimeout
    If ($nonCompliant)  {
        If ($FixErrors -or $FixWarningsAlso) {
            Write-Host "Fixing HWTimeout registry key. Est Time is less than one minute" -ForegroundColor Cyan
            Invoke-Command -ComputerName $nonCompliant.Node -ScriptBlock {
                $path = "HKLM:\SYSTEM\CurrentControlSet\Services\spaceport\Parameters"
                if (-not (Test-Path $path)) {New-Item -Path $path -Force | Out-Null}
                New-ItemProperty -Path $path -Name HwTimeout -PropertyType DWord -Value 10000 -Force -ErrorAction SilentlyContinue -Verbose | Out-Null            
            }
            Write-Host "Reboot nodes to apply settings"
            $nonCompliant=Test-HWTimeout
            If ($nonCompliant) {Write-ToHost "Fix HWTimeout registry key failed!!!" -Level 4 -Checkmark 4}
        } else {
                Write-Host "Recommendation: Set HWTimeout registry key to at least 10000 on all nodes"
        }
    }
    Write-Host ""
    $disksInMaint= Test-NodesUpDisksinMaintMode
    If ($disksInMaint)  {
        If ($FixErrors -or $FixWarningsAlso) {
            $disksFixed=foreach ($disk in $disksInMaint) {
                try {
                    $disk | Get-PhysicalDisk | Disable-StorageMaintenanceMode -ErrorAction Stop
                    [PSCustomObject]@{
                        Disk         = $disk.FriendlyName
                        SerialNumber = $disk.SerialNumber
                        Action       = "Maintenance Mode Disabled"
                    }
                }
                catch {
                    [PSCustomObject]@{
                        Disk         = $disk.FriendlyName
                        SerialNumber = $disk.SerialNumber
                        Action       = "Failed"
                        Error        = $_.Exception.Message
                    }
                }
            }
            $disksError=$disksFixed | ? Action -eq "Failed"
            if ($disksError) {
                Write-Warning $disksError.Error
                Write-ToHost "Disks $($disksError.SerialNumber -join ',') failed to disable maintenance mode" -Level 4 -Checkmark 4
            } else {
                $disksInMaint = Test-NodesUpDisksinMaintMode
                If ($disksInMaint) {Write-ToHost "Fix take disks out of maintenance mode failed!!!" -Level 4 -Checkmark 4}
            }
        } else {
                Write-Host "Recommendation: Take disks out of maintenance mode if all nodes are up"
        }
    }
    Write-Host ""
    $nonCompliant=Test-TimeZone
    If ($nonCompliant)  {
        If ($FixErrors -or $FixWarningsAlso) {
            Write-Host "Fixing tome zone consistency. Est Time is less than one minute" -ForegroundColor Cyan
            $tz=$global:dTimeZone
            Invoke-Command -ComputerName $nonCompliant.Node -ScriptBlock {Set-TimeZone -Id $using:tz}
            $nonCompliant=Test-TimeZone
            If ($nonCompliant) {Write-ToHost "Fix time zone failed!!!" -Level 4 -Checkmark 4}
        } else {
            Write-Host "Recommendation: Set all nodes to the same time zone"
        }
    }
    Write-Host ""
    If (Test-ClusterShutdownTime) {
        if ($FixErrors -or $FixWarningsAlso) {
            (Get-Cluster).ShutdownTimeoutInMinutes=1440
            If (Test-ClusterShutdownTime) {Write-ToHost "Fix setting cluster shutdown timeout to 1440 minutes failed!!!" -Level 4 -Checkmark 4}
        } else {
            Write-Host "Recommendation: Set cluster shutdown timeout to 1440"
        }
    }
    Write-Host ""
    If (Test-InvalidCAUReports) {
        if ($FixErrors -or $FixWarningsAlso) {
            Invoke-Command -ComputerName $nodes -ScriptBlock {Remove-Item C:\Windows\Cluster\Reports\CauReport-00000101000000.xml -ErrorAction SilentlyContinue -Force}
            If (Test-InvalidCAUReports) {Write-ToHost "Fix removing invalid CAU reports failed!!!" -Level 4 -Checkmark 4}
        } else {
            Write-Host "Recommendation: Remove invalid CAU Reports named CauReport-00000101000000.xml"
        }
    }
    Write-Host ""
    $FailedComputeIntents=Test-NetworkDirectOnComputeIntents
    If ($FailedComputeIntents) {
        if ($FixErrors -or $FixWarningsAlso) {
            Foreach ($FailedComIntent in $FailedComputeIntents) {
                $AdapOver=(Get-NetIntent -Name "$($FailedComIntent.IntentName)").AdapterAdvancedParametersOverride
                $AdapOver.NetworkDirect=0
                Set-NetIntent -Name "$($FailedComIntent.IntentName)" -AdapterPropertyOverrides $AdapOver
            }
            $FailedComputeIntents=Test-NetworkDirectOnComputeIntents
            If ($FailedComputeIntents) {Write-ToHost "Fix invalid Net Intent Network Direct configuration failed!!!" -Level 4 -Checkmark 4}
        } else {
            Write-Host "Recommendation: Remove Network Direct setting on compute intents"
        }
    }
    Stop-Transcript -ErrorAction SilentlyContinue
}

