Function Test-DellAzureLocalIssues {

param(
    [switch]$FixErrors,
    [switch]$FixWarningsAlso,
    [switch]$ErrorOnlyCheck,
    [switch]$ApproveAllFixesAutomatically,
    [switch]$IgnoreAzureLocalRequired
)
    $ver="0.591"

    # Check if the current session is running as Administrator
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host -ForegroundColor Yellow "Not running as Administrator. Please run the script with elevated privileges."
        Break
    }
    # Check if script running in a remote Powershell session
    if ($PSSenderInfo) {Write-Host -ForegroundColor Yellow "This script is not supported using a remote powershell session. Please run locally";Break}
    # Check if script is running on a cluster node
    If ((invoke-command -scriptblock {try {get-cluster -ErrorAction SilentlyContinue} catch {}}).Name -eq $null) {Write-Host -ForegroundColor DarkYellow "This script MUST be run locally on a cluster node.";Break}
    #Get-ClusterStorageSpacesDirect
    if (!(gcm Get-SolutionUpdate -ErrorAction SilentlyContinue) -and !($IgnoreAzureLocalRequired)) {Write-Host -ForegroundColor DarkYellow "This script must be run locally on a Dell Azure local node";break}
    $isNotS2d=try {((Get-ClusterStorageSpacesDirect).State -ne 'Enabled')} catch {$true}
    if ($isNotS2d) {
        Write-Host "Script must be run locally on an S2D cluster node" -ForegroundColor DarkYellow
        break
    }
    if ($IgnoreAzureLocalRequired) {
        Write-Host "Running on a non-Azure Local cluster. Fix scripts will be disabled" -ForegroundColor Yellow
        $FixErrors=$false
        $FixWarningsAlso=$false
    }
    $testReport=@()
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
        If ($dtime -lt 12 -and ($testSU.resourceid -gt "" -or ($testSU -le "" -and $SUJob.State -eq "Completed"))) {
            Write-ToHost "Get Solution Update command successful" -Checkmark 1 -Level 1
            return $false
        } else {
            Write-ToHost "Get Solution Update command FAILED" -Checkmark 3 -Level 3
            return $true
        }
    }
    Function Test-NetIntents {
        $failedNetIntent=@()
        $failedNetIntentGlobal=@()
        Write-Host "Checking Net Intents..."
        $failedNetIntent+=$GetNetIntentStatus | ? {$_.LastSuccess -lt (Get-Date).AddMinutes(-40)}
        $failedNetIntentGlobal+=$GetNetIntentGlobalStatus | ? {$_.LastSuccess -lt (Get-Date).AddMinutes(-40)}
        $failedNetIntent=$failedNetIntent | ? {$_.Progress -gt ""}
        $failedNetIntentGlobal=$failedNetIntentGlobal | ? {$_.Progress -gt ""}
        If ($failedNetIntent) {
           Foreach ($failedIntent in $failedNetIntent) {
               Write-ToHost "Net Intent $($failedIntent.IntentName) on Node $($failedIntent.Host) FAILED" -Checkmark 3 -Level 3
           }
        } elseif ($failedNetIntentGlobal) {
            Foreach ($failedIntent in $failedNetIntentGlobal) {
                Write-ToHost "Global Net Intent on Node $($failedIntent.Host) FAILED" -Checkmark 3 -Level 3
            }
        } else {
           Write-ToHost "Net Intent check successful" -Checkmark 1 -Level 1
        }
        return ($failedNetIntent+$failedNetIntentGlobal)
    }
    Function Test-iDracHostNicDHCP {
        Write-Host "Checking iDrac host nics have DHCP enabled..."
        $iDracDHCP=Invoke-Command -ComputerName $nodes -ScriptBlock {$idracnic=Get-NetAdapter -ifdesc *NDIS* | Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue ; [PSCustomObject]@{"PSComputerName"=$env:COMPUTERNAME;"DHCP"=$idracnic.DHCP}}
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
            $iDracIP=(Get-CimInstance win32_networkadapterconfiguration | ? Description -like "*NDIS*" -ErrorAction SilentlyContinue).DHCPServer
            $result=try {Invoke-RestMethod https://$iDracIP/redfish/v1/ -UseBasicParsing} catch {}
            If ($result.Vendor -ne 'Dell') {$work=$false} else {$work=$true}
            [PSCustomObject]@{"PSComputerName"=$env:COMPUTERNAME;"Success"=$work}
        }
        $Redfish=$Redfish | ? Success -eq $false
        If ($Redfish.Success -match $false) {
            Write-ToHost "iDrac on host(s) $($Redfish.PSComputerName -join ',') have problems accessing the redfish url!" -Checkmark 3 -Level 3
        } else {
            Write-ToHost "All hosts can access their iDrac redfish url" -Level 1 -Checkmark 1
        }
        return $Redfish
    }
    Function Test-OsBootTimeOver99Days {
        $OSBootTimeOver99Days=@()
        If ($ErrorOnlyCheck -eq $false) {
            Write-Host "Testing that all nodes have been rebooted within 99 days..."
            $OSBootTimeOver99Days+=Get-CimInstance -ComputerName $nodes Win32_OperatingSystem | %{[PSCustomObject]@{"CsName"=$_.CsName;"OSBootOver99Days"=(((Get-Date).AddDays(-99)-$_.LastBootUpTime) -gt 0)}}
            $failedOSBootTimeOver99Days=$OSBootTimeOver99Days | ? OSBootOver99Days -eq $true
            If ($failedOSBootTimeOver99Days) {
               Write-ToHost "Node(s) $($failedOSBootTimeOver99Days.CsName -join ',') have not been rebooted for over 99 days" -Checkmark 2 -Level 2
            } else {
               Write-ToHost "All nodes have been rebooted within 99 days"
            }
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
            Write-ToHost "Node(s) $($nonCompliant.Node -join ',') do(es) not have HWTimeout set to at least 10000" -Checkmark 3 -Level 3
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
                    Write-ToHost "Node(s) $($nonCompliant.Node -join ',') do(es) not have the correct time zone defined" -Checkmark 3 -Level 3
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
            $nonCompliant+=$nodeResources | ? {$_.Memory -ge 1tb} 
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
        $nonCompliant=@()
        $nonCompliant+=Invoke-Command -ComputerName $nodes -ScriptBlock {Get-Item C:\Windows\Cluster\Reports\CauReport-00000101000000.xml -ErrorAction SilentlyContinue}
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
     Function Test-NetworkDirectOnStorageIntents {
        Write-Host "Testing for invalid Net Intent Network Direct Technology configuration on storage intents..."
        $GetNetIntentStorage = @()
        $FailedStorageIntents = @()
        $GetNetIntentStorage += $GetNetIntent | ? IsStorageIntentSet -eq $true
        Foreach ($GetNetIntentC in $GetNetIntentStorage) {
            If ($GetNetIntentC.AdapterAdvancedParametersOverride.NetworkDirect -gt 0) {
                If ($GetNetIntentC.AdapterAdvancedParametersOverride.NetworkDirectTechnology -le "") {
                    $FailedStorageIntents += $GetNetIntentC
                }
            }
        }
        If ($FailedStorageIntents) {
            Write-ToHost "Storage Net Intent(s) do not have NetworkDirectTechnology defined" -Checkmark 3 -Level 3
        } else {
            Write-ToHost "Storage Net Intents Network Direct Technology are configured correctly"
        }
        return $FailedStorageIntents
    }
    function Test-AzLocalOverProvisionedVirtualDisks {
        [CmdletBinding()]
        param(
            [string]$StoragePoolName
        )
        Write-Host "Testing for Over Provisioned Virtual Disks on Storage Pool"

        try {
            # Resolve pool once
            $pool = if ($StoragePoolName) {
                Get-StoragePool -FriendlyName $StoragePoolName -ErrorAction Stop
            } else {
                Get-StoragePool | Where-Object IsPrimordial -eq $false | Select-Object -First 1
            }

            if (-not $pool) {
                throw "No storage pool found."
            }

            # Single-pass data collection
            $physicalDisks = $pool | Get-PhysicalDisk
            $vDisks        = $pool | Get-VirtualDisk
            $nodeCount     = (Get-ClusterNode).Count
            if ($nodeCount -gt 4) {$nodeCount = 4}

            # Core metrics
            $largestDisk     = ($physicalDisks | Measure-Object Size -Maximum).Maximum
            $totalAllocatedMax = ($vDisks | ForEach-Object {
                $copies = $_.NumberOfDataCopies
                $multiplier = if ($copies -in 1..6) {
                    $copies
                } else {
                    2
                }
                $_.Size * $multiplier
            } | Measure-Object -Sum).Sum
            $totalDiskCount   = $physicalDisks.Count
            $maxFootprint = ($vDisks | ForEach-Object {

                $copies = $_.NumberOfDataCopies

                $multiplier = if ($copies -in 1..6) {
                    $copies
                } else {
                    2
                }

                $_.Size * $multiplier

            } | Measure-Object -Sum).Sum
            # Failure reserve rule
            $failureReserve = if ($totalDiskCount -lt 11) {
                $largestDisk
            } else {
                $largestDisk * $nodeCount
            }

            # Survivable capacity
            $usableCapacity = $pool.Size - $pool.Reserved - $failureReserve
            if ($totalAllocatedMax -gt $usableCapacity) {
                If ($ErrorOnlyCheck -eq $false) { 
                    $userVdisks=$vDisks | ? FriendlyName -notlike "Infrastructure*" | ? FriendlyName -notlike "ClusterPerformanceHistory*"
                    $sysVdisks=$vDisks | ?{$_.FriendlyName -like "Infrastructure*" -or $_.FriendlyName -like "ClusterPerformanceHistory*"}
                    $sysVdiskSize=0
                    $sysVdisks | %{$sysVdiskSize=$sysVdiskSize+($_.size * $_.NumberOfDataCopies)}
                    $eachVD=($usableCapacity-$sysVdiskSize)/($userVdisks.count)/($userVdisks[0].NumberOfDataCopies)
                    Write-ToHost "If volumes are filled, there will not be enough space for disk repairs. $([int](($usableCapacity-$totalAllocatedMax)/1gb)) GB" -Checkmark 2 -Level 2
                    Write-Host "Each node virtual disk can be up to $([math]::Round($eachVD/1TB,2)-0.01) TB"
                }
            } else {
                Write-ToHost "Storage Pool space looks good"
            }

            return ($totalAllocatedMax -gt $usableCapacity)
        }
        catch {
            If ($ErrorOnlyCheck -eq $false) {Write-ToHost "Could not determine Over Provisioned Virtual Disks on Storage Pool" -Checkmark 2 -Level 2}
            return $false
        }
    }
    function Test-AzLocalThinProvisioningUtilization {
        [CmdletBinding()]
        param(
            [string]$StoragePoolName
        )

        Write-Host "Testing Virtual Disk Thin Provisioning Alert Threshold"

        try {
            $pool = if ($StoragePoolName) {
                Get-StoragePool -FriendlyName $StoragePoolName -ErrorAction SilentlyContinue
            } else {
                Get-StoragePool | Where-Object IsPrimordial -eq $false | Select-Object -First 1
            }

            # Default threshold always defined
            $threshold = 70

            if ($pool) {
                $poolName = $pool.FriendlyName

                if ($pool.ThinProvisioningAlertThresholds) {
                    $threshold = $pool.ThinProvisioningAlertThresholds[0]
                }

                $vDisks = $pool | Get-VirtualDisk

                $currentFootprint = ($vDisks | Measure-Object FootprintOnPool -Sum).Sum

                $maxFootprint = ($vDisks | ForEach-Object {

                    $copies = $_.NumberOfDataCopies

                    $multiplier = if ($copies -in 1..3) {
                        $copies
                    }
                    else {
                        2
                    }

                    $_.Size * $multiplier

                } | Measure-Object -Sum).Sum

                $usableCapacity = $pool.Size - $pool.Reserved

                if ($usableCapacity -gt 0) {
                    $currentPercent = [int](($currentFootprint / $usableCapacity) * 100)
                    $maxPercent     = [int](($maxFootprint / $usableCapacity) * 100)
                }
                else {
                    $currentPercent = 101	
                    $maxPercent = $null
                }

                If ($ErrorOnlyCheck -eq $false) {
                    if ($maxPercent -gt $threshold -and !($ErrorOnlyCheck)) {
                        $testpass=2
                         Write-ToHost (
                             "MAX thin provisioning usage exceeds threshold: $maxPercent% (Threshold: $threshold%)"
                         ) -Level 2 -Checkmark 2
                    }
                }
                if ($currentPercent -gt $threshold) {
                    $testpass=3
                    Write-ToHost (
                        "CURRENT thin provisioning usage exceeds threshold: $currentPercent% (Threshold: $threshold%)"
                    ) -Level 3 -Checkmark 3
                } 

                return [pscustomobject]@{
                    StoragePoolName = $poolName
                    Threshold        = $threshold
                    CurrentPercent   = [math]::Round($currentPercent, 2)
                    MaxPercent       = [math]::Round($maxPercent, 2)
                    UsableCapacity   = $usableCapacity
                    Error            = $null
                }
            }

            # NO POOL FOUND (but still structured output)
            return [pscustomobject]@{
                StoragePoolName = $null
                Threshold        = $threshold
                CurrentPercent   = $null
                MaxPercent       = $null
                UsableCapacity   = $null
                Error            = $null
            }
        }
        catch {
            return [pscustomobject]@{
                StoragePoolName = $null
                Threshold        = $threshold
                CurrentPercent   = $null
                MaxPercent       = $null
                UsableCapacity   = $null
                Error            = $null
            }
        }
    }
    function Test-AzLocalMemoryNMinusOne {
        [CmdletBinding()]
        param()

        Write-Host "Testing cluster memory N-1 resiliency (largest-node failure model)..."

        $clusterNodes = (Get-ClusterNode).Name

        # VM memory demand (cluster-wide)
        $vmTotal = (Get-VM -ComputerName $clusterNodes | ? State -eq Running |
            Measure-Object MemoryAssigned -Sum).Sum

        # Node memory capacities
        $nodeMemory = foreach ($node in $clusterNodes) {
            (Get-CimInstance -ComputerName $node Win32_ComputerSystem).TotalPhysicalMemory
        }

        # Total cluster capacity
        $clusterTotal = ($nodeMemory | Measure-Object -Sum).Sum

        # Largest node (failure domain)
        $largestNode = ($nodeMemory | Measure-Object -Maximum).Maximum

        # N-1 usable capacity
        $nMinusOneCapacity = $clusterTotal - $largestNode

        # Delta evaluation
        $delta = $nMinusOneCapacity - $vmTotal

        if ($delta -ge 0) {
            Write-ToHost "Cluster is N-1 safe for memory (headroom: $([int]($delta/1gb)) GB)" -Level 1 -Checkmark 1
            return $false   # PASS
        }
        else {
            Write-ToHost "Cluster is NOT N-1 SAFE (shortfall: $([int]([math]::Abs($delta)/1gb)) GB)" -Level 3 -Checkmark 3
            return $true    # FAIL
        }
    }
    function Test-AzLocalCpuNMinusOneOvercommit {
        [CmdletBinding()]
        param()
        If ($ErrorOnlyCheck -eq $false) {

            Write-Host "Testing cluster CPU vCPU overcommit risk (N-1 model, 200% threshold)..."

            $clusterNodes = (Get-ClusterNode).Name

            # Total VM vCPU demand (cluster-wide)
            $vmVcpus = (Get-VM -ComputerName $clusterNodes | ? State -eq Running |
                Measure-Object ProcessorCount -Sum).Sum

            # Logical processors per node
            $nodeCpu = foreach ($node in $clusterNodes) {
                [pscustomobject]@{
                    Node     = $node
                    Logical  = (Get-CimInstance -ComputerName $node Win32_ComputerSystem).NumberOfLogicalProcessors
                }
            }

            # Total cluster logical CPUs
            $clusterTotal = ($nodeCpu | Measure-Object Logical -Sum).Sum

            # Largest node failure domain
            $largestNode = ($nodeCpu | Measure-Object Logical -Maximum).Maximum

            # N-1 available CPU capacity
            $nMinusOneCpu = $clusterTotal - $largestNode

            # 200% overcommit threshold (your rule)
            $warningThreshold = $nMinusOneCpu * 2

            # Delta evaluation
            $delta = $warningThreshold - $vmVcpus

            if ($vmVcpus -gt $warningThreshold) {
                Write-ToHost "VM vCPU: $vmVcpus | N-1 Capacity: $nMinusOneCpu | Threshold: $warningThreshold" -Level 2 -Checkmark 2
                return $true   # WARNING condition
            }
            else {
                Write-ToHost "CPU overcommit within acceptable N-1 threshold" -Level 1 -Checkmark 1
                return $false  # OK
            }
        }
        return $false
    }
    function Test-AzLocalVmMigrationFailures {
        [CmdletBinding()]
        param()
        If ($ErrorOnlyCheck -eq $false) {

            Write-Host "Analyzing non-Windows VM live migration / failback failures (last 7 days across all nodes)..."

            $startTime = (Get-Date).AddDays(-7)
            $eventIds = 21502, 21503, 21504, 1069, 1205
            $events = Invoke-Command -ComputerName $nodes -ScriptBlock {
                param($startTime, $eventIds)

                Get-WinEvent -ErrorAction SilentlyContinue -FilterHashtable @{
                    LogName   = 'System'
                    Id        = $eventIds
                    StartTime = $startTime
                } | Select-Object TimeCreated,MachineName,Id,@{L="Message";E={$_.Properties.Value}}

            } -ArgumentList $startTime, $eventIds

            if (-not $events) {
                Write-ToHost "No migration or failback failures detected in last 7 days"
                return
            }

            # Extract VM names
            $vmFailures = foreach ($event in $events) {
                $match=[regex]::Match($event.message,"'Virtual Machine\s(.*?)'")
                if ($match.Success) {
                    [PSCustomObject]@{
                        VMName = $match.groups[1].value
                        Node   = $event.MachineName
                    }
                }
            }

            if (-not $vmFailures) {
                Write-ToHost "No VM-specific failures identified in event logs"
                return
            }

            # Aggregate counts
            $vmCounts = $vmFailures |
                Group-Object VMName |
                Select-Object Name, Count |
                Sort-Object Count -Descending
            if (($vmCounts.name).count -gt 1) {
                $offenderAverage=[int]((Measure-Object -Sum $vmCounts.count).Sum/($vmCounts.name).count)
            } else {
                $offenderAverage=0
            }
            $offenders = $vmCounts | Where-Object { $_.Count -ge ($offenderAverage*2) }
            $nonWindowsGroups=@()
            # 3. Resolve cluster groups from offender names
            $clusterGroups = foreach ($o in $offenders) {
                Get-ClusterGroup -Name $o.Name -ErrorAction SilentlyContinue
            }
            # 4. Resolve VM objects and filter NON-Windows only
            $nonWindowsGroups += foreach ($group in $clusterGroups) {
                $vm = Get-VM -ComputerName $nodes -Name $group.Name -ErrorAction SilentlyContinue | ? State -eq "Running"
                $VmWmi = gwmi -namespace root\virtualization\v2 -query "Select * From Msvm_ComputerSystem Where ElementName='$(($vm).Name)'" -ComputerName $vm.PSComputerName
                $Kvp = gwmi -namespace root\virtualization\v2 -query "Associators of {$VmWmi} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent" -ComputerName $vm.PSComputerName
                $OSPlatformId=$Kvp.GuestIntrinsicExchangeItems | %{
                    $xml = [xml]$_
                    if ($xml.INSTANCE.PROPERTY | Where-Object { $_.Name -eq 'Name' -and $_.VALUE -eq 'OSPlatformId' }) {
                        ($xml.INSTANCE.PROPERTY | Where-Object { $_.Name -eq 'Data' }).VALUE
                    }
                } 
                if ($vm -and (Get-ClusterGroup -Name $group.Name).Priority -gt 1000 -and $OSPlatformId -ne 2) {
                    $group
                }
            }
            if ($nonWindowsGroups) {
                Write-ToHost "Non-Windows VMs with repeated migration / failback failures detected" -Level 2 -Checkmark 2

                foreach ($vm in $nonWindowsGroups) {
                    Write-Host "Non-Windows VM '$($vm.Name)' failed $($vm.Count) times"
                }
                return $nonWindowsGroups
            }
            else {
                Write-ToHost "No Non-Windows VMs exceeded failure threshold (>200% of average) in last 7 days" -Level 1 -Checkmark 1
            }
        }
        return $null
    }
    Function Test-AzureLocalNodeServices {
        Write-Host "Checking per node services vital to Azure local..."
        $FailedServices=Invoke-Command -ComputerName (Get-ClusterNode).Name -ScriptBlock {
            param($ServiceList)
            $FailedServices=@()
            # Run Get-Service once for the entire list
            $Status = Get-Service -Name $ServiceList -ErrorAction SilentlyContinue
            # Check any that aren't running
            $FailedServices+=$Status | Where-Object { $_.Status -ne "Running" }
            $FailedServices
        } -ArgumentList ($AzureLocalServices)
        If ($FailedServices) {
            Write-ToHost "Azure local required all node services $(($FailedServices.Name | Sort -Unique) -join ',') are NOT running on ALL nodes" -Level 3 -Checkmark 3
        } else {
            Write-ToHost "All Azure local required all node services are running" -Level 1 -Checkmark 1
        }
        return $FailedServices
    }
    Function Test-DiskLatencyOutlier {
        If ($ErrorOnlyCheck -eq $false) {
            Write-Host "Looking at physical disk latency in the past week..."
            try {
                #Sample 2: Fire, fire, latency outlier
                #Ref: https://learn.microsoft.com/en-us/windows-server/storage/storage-spaces/performance-history-scripting#sample-2-fire-fire-latency-outlier
                $Cluster = Get-cluster
                $ClusterNodes = Get-ClusterNode -Cluster $Cluster -ErrorAction SilentlyContinue
                $TotalProblemDrives=@()
                $TotalProblemDrives += Invoke-Command $ClusterNodes.Name {
                    Function Format-Latency {
                    Param (
                    $RawValue
                    )
                    $i = 0 ; $Labels = ("s", "ms", "$([char]956)s", "ns") # Petabits, just in case!
                    Do { $RawValue *= 1000 ; $i++ } While ( $RawValue -Lt 1 )
                    # Return
                    [String][Math]::Round($RawValue, 2) + " " + $Labels[$i]
                    }

                    Function Format-StandardDeviation {
                    Param (
                    $RawValue
                    )
                    If ($RawValue -Gt 0) {
                        $Sign = "+"
                    } Else {
                        $Sign = "-"
                    }
                        # Return
                        $Sign + [String][Math]::Round([Math]::Abs($RawValue), 2)
                    }

                    $HDD = Get-StorageNode | ?{$ENV:COMPUTERNAME -imatch ($_.name -split '\.')[0]} | Get-PhysicalDisk  -PhysicallyConnected
                    $Output = $HDD | ForEach-Object {
                        $Iops = $_ | Get-ClusterPerf -PhysicalDiskSeriesName "PhysicalDisk.Iops.Total" -TimeFrame "LastWeek"
                        $AvgIops = ($Iops | Measure-Object -Property Value -Average).Average
                        If ($AvgIops -Gt 1) { # Exclude idle or nearly idle drives
                            $Latency = $_ | Get-ClusterPerf -PhysicalDiskSeriesName "PhysicalDisk.Latency.Average" -TimeFrame "LastWeek" 
                            $AvgLatency = ($Latency | Measure-Object -Property Value -Average).Average
                            [PsCustomObject]@{
                                "FriendlyName"  = $_.FriendlyName
                                "SerialNumber"  = $_.SerialNumber
                                "MediaType"     = $_.MediaType
                                "AvgLatencyPopulation" = $null # Set below
                                "AvgLatencyThisHDD"    = Format-Latency $AvgLatency
                                "RawAvgLatencyThisHDD" = $AvgLatency
                                "Deviation"            = $null # Set below
                                "RawDeviation"         = $null # Set below
                            }
                        }
                    }

                    If ($Output.Length -Ge 3) { # Minimum population requirement

                        # Find mean u and standard deviation o
                        $u = ($Output | Measure-Object -Property RawAvgLatencyThisHDD -Average).Average
                        $d = $Output | ForEach-Object { ($_.RawAvgLatencyThisHDD - $u) * ($_.RawAvgLatencyThisHDD - $u) }
                        $o = [Math]::Sqrt(($d | Measure-Object -Sum).Sum / $Output.Length)

                        $FoundOutlier = $False
                        $ProblemDrives=@()
                        $ProblemDrives+=$Output | ForEach-Object {
                            $Deviation = ($_.RawAvgLatencyThisHDD - $u) / $o
                            $_.AvgLatencyPopulation = Format-Latency $u
                            $_.Deviation = Format-StandardDeviation $Deviation
                            $_.RawDeviation = $Deviation
                            # If distribution is Normal, expect >99% within 3 deviations
                            If ($Deviation -Gt 3) {
                                $FoundOutlier = $True
                                [PSCustomerObject] @{
                                    "SerialNumber"   = $_.SerialNumber
                                    "MediaType"      = $_.MediaType
                                    "PSComputerName" = "$env:COMPUTERNAME"
                                    "Deviation"       = $Deviation
                                }
                            }
                        }
                    }

                    $ProblemDrives
                }
                $TotalProblemDrives = $TotalProblemDrives | Sort PSComputerName
                if ($TotalProblemDrives) {
                    Foreach ($disk in $TotalProblemDrives) {
                        Write-ToHost "Node $($disk.PSComputerName) with SN $($disk.SerialNumber) with deviation of $($disk.Deviation) may need to be reseated" -Level 2 -Checkmark 2
                    }
                    return $true
                } else {
                    Write-ToHost "All physical disks passed"
                    return $false
                }
                } catch { Show-Warning "Unable to get latency outlier Data.  `nError="+$_.Exception.Message
                }
            }
    }
    function Test-AzLocalClusterDiskEndurance {
        [CmdletBinding()]
        param()

        $allResults = @()
        Write-Host "Checking disk endurance and media failures"

        foreach ($node in $nodes) {
            $nodeName = $node.Name

            $results = Invoke-Command -ComputerName $nodeName -ScriptBlock {
                $disks = Get-PhysicalDisk
                $reliability = $disks | Get-StorageReliabilityCounter

                foreach ($disk in $disks) {
                    $rel = $reliability | Where-Object { $_.DeviceId -eq $disk.DeviceId }

                    $percentageUsed = $rel.PercentageUsed
                    $mediaErrors    = $rel.MediaErrors
                    $predictFail    = $rel.PredictFailure

                    # --- ACTION LOGIC ---

                    # 1. SMART failure indicators → Reseat
                    if ($mediaErrors -gt 10 -or $predictFail -eq $true) {
                        [PSCustomObject]@{
                            Node     = $env:COMPUTERNAME
                            Action   = "Reseat"
                            Disk     = $disk.FriendlyName
                            Serial   = $disk.SerialNumber
                            Details  = "SMART failure indicators detected"
                        }
                        continue
                    }

                    # 2. Endurance nearing end-of-life (≥98%) → Replace
                    if ($percentageUsed -ge 98) {
                        [PSCustomObject]@{
                            Node     = $env:COMPUTERNAME
                            Action   = "Purchase"
                            Disk     = $disk.FriendlyName
                            Serial   = $disk.SerialNumber
                            Details  = "Endurance used: $percentageUsed%"
                        }
                        continue
                    }
                }
            }

            $allResults += $results
        }
        if ($allResults) {
            Foreach ($badDisks in ($allResults | ? Action -eq "Purchase")) {
                Write-ToHost "Disk(s) with SN $($badDisks.SerialNumber) and $($badDsisks.Details) have reached end of life and need(s) to be purchased and replaced" -Level 3 -Checkmark 3
            }
            Foreach ($badDisks in ($allResults | ? Action -eq "Reseat")) {
                Write-ToHost "Disk(s) with SN $($badDisks.SerialNumber) may need to be reseated and/or the host rebooted" -Level 2 -Checkmark 2
            }
        } else {
            Write-ToHost "All physical disks are operating normally"
        }

        return $allResults
    }
    function Test-CauErrorAudit {
        [CmdletBinding()]
        param(
            [string]$ReportPath = "C:\Windows\Cluster\Reports"
        )
        if ((Get-SolutionUpdate).State -match "InstallationFailed") { 
            Write-Host "Testing recent failures in CAU reports over the last 12 hours since last update attempt..."
            $AllReports = Invoke-Command -Computername $nodes {Get-ChildItem -Path "$using:ReportPath" -Filter "CauReport*.xml"}
            $AllReports = $AllReports | Group-Object -Property Name | %{$_.Group | sort LastWriteTime,PSComputerName -Descending | Select -First 1} | Sort LastWriteTime -Descending
            $LatestFile = $AllReports[0]
            $TimeCutoff = $LatestFile.LastWriteTime.AddHours(-12)
            $TargetFiles = $AllReports | Where-Object { $_.LastWriteTime -ge $TimeCutoff }
            Write-Host "Auditing reports from: $($TimeCutoff.ToString()) to $($LatestFile.LastWriteTime.ToString())"
            $ErrorReport=@()
            $ErrorReport += foreach ($File in $TargetFiles) {
                try {
                    [xml]$xml = Invoke-Command -ComputerName $File.PSComputerName {Get-Content -Path $using:File.FullName -Raw -ErrorAction Stop}
                    # Select all NodeResult elements
                    $nodeResults = $Xml.GetElementsByTagName("NodeResult")

                    foreach ($node in $nodeResults) {
                        $status = $node.Status
    
                        # Only process failed or partially failed nodes
                        if ($status -and $status -ne 'Succeeded') {
        
                            # The NodeName might be buried in the InstallResults if z:Ref is used in the main Node element
                            $nodeName = $node.InstallResults.UpdateInstallResult.NodeName
                            if ($nodeName.InnerText) { $nodeName = $nodeName.InnerText }
        
                            $errorData = $node.ErrorRecordData
                            $errorId = $errorData.FullyQualifiedErrorId
                            if ($errorId.InnerText) { $errorId = $errorId.InnerText }
        
                            $exceptionData = $errorData.ExceptionData
                            $message = $exceptionData.Message
                            if ($message.InnerText) { $message = $message.InnerText }

                            [PSCustomObject]@{
                                NodeName = $nodeName
                                Status   = $status
                                ErrorID  = $errorId
                                Message  = $message
                            }
                        }
                    }
                } catch {
                    Write-Warning "Could not parse $($File.Name): $($_.Exception.Message)"
                }
                If ($xml.CauReport.ClusterResult.ErrorRecordData.ExceptionData.Message) {
                    [PSCustomObject]@{
                        NodeName = (Get-Cluster).Name
                        Status   = $xml.CauReport.ClusterResult.Status
                        ErrorID  = $xml.CauReport.ClusterResult.ErrorRecordData.ExceptionData.FullyQualifiedErrorId
                        Message  = $xml.CauReport.ClusterResult.ErrorRecordData.ExceptionData.Message
                    }
                }
            }
            $ErrorReport=$ErrorReport | Sort Message -Unique | Sort-Object FileDate -Descending
            if ($ErrorReport.count -eq 0) {
                Write-ToHost "No errors found in the last 12 hours of reports since last update attempt."
                return $null
            } else {
                Write-ToHost "$($ErrorReport.Message -join '`r`n')" -Level 3 -Checkmark 3
                return $ErrorReport
            }
        }
        return $null
    }
    function Test-GetHealthFault {
        try {
            Write-Host "Testing that Get-HealthFault command works"
            Get-HealthFault 2>$null
            Write-ToHost "Get-HealthFault command succeeded"
            return $false
        } catch {
            Write-ToHost "Get-HealthFault command failed" -Level 3 -Checkmark 3
            return $true
        }
    }
    function Test-MismatchedPSModules {
        Write-Host "Testing for mismatched PS module errors"
        $HealthCheckTime=[TimeZoneInfo]::ConvertTimeFromUtc((Get-SolutionUpdateEnvironment).HealthCheckDate,[TimeZoneInfo]::Local)
        try {
            $startTime = $HealthCheckTime.AddHours(-1)
            $endTime = $HealthCheckTime.AddHours(1)
        } catch {
            $startTime = (Get-WinEvent -LogName 'AzStackHciEnvironmentChecker' -MaxEvents 1).TimeCreated.AddHours(-1)
            $endTime = (Get-Date)
        }
        $events=@()
        $events += Invoke-Command -ComputerName $nodes -ScriptBlock {
            Get-WinEvent -ErrorAction SilentlyContinue -FilterHashtable @{
                LogName   = 'AzStackHciEnvironmentChecker'
                Id        = '17203'
                StartTime = $using:startTime
                EndTime   = $using:endTime
            } | Select-Object TimeCreated,MachineName,Id,@{L="Message";E={$_.Properties.Value}}
        }
        $badModules=@()
        Foreach ($event in $events) {
            if ($event.Message -like "Checking version of PS module*") {
                if ($event.Message -match "'([^']+)'.*?'([^']+)'.*?'([^']+)'.*?'([^']+)'") {
                    if ((((Get-InstalledModule -Name $matches[1] -AllVersions).Version | %{[version]$_}) -gt [version]$matches[4])) {
                        $badModules += [PSCustomObject]@{
                            ModuleName      = $matches[1]
                            NodeName        = $matches[2]
                            InstalledVersion = [version]$matches[3]
                            RequiredVersion  = [version]$matches[4]
                        }
                    }
                }
            }
        }
        $badModules=$badModules | Group-Object -Property NodeName,ModuleName | %{$_.Group | sort ModuleName | Select -First 1} | sort ModuleName -Descending
        if ($badModules.count) {
            Foreach ($badModule in $badModules) {
                Write-Host "On Node $($badModule.NodeName), module $($badModule.ModuleName) needs to be version $($badModule.RequiredVersion) but has version $($badModule.InstalledVersion) installed"
            }
            Write-ToHost "Mismatched PS modules found" -Level 3 -Checkmark 3
        } else {
            Write-ToHost "No mismatched PS modules found"
        }
        return $badModules
    }
    function Test-ClusterControlPlaneHealth {
        [CmdletBinding()]
        param(
            [int]$NodeTimeoutSec  = 8,
            [int]$ProbeTimeoutSec = 3,
            [int]$ThrottleLimit   = 10,
	    [string[]] $nodes=(Get-ClusterNode).name
        )
	Write-Host "Testing WMI, VMMS and Cluster service"
        # ----------------------------
        # Node-level execution (runs in parallel across cluster)
        # ----------------------------
        $scriptBlock = {
            param($ProbeTimeoutSec)

            function Run-Probe {
                param(
                    [string]$Name,
                    [int]$TimeoutSec,
                    [scriptblock]$Command
                )

                $job = Start-Job -ScriptBlock $Command

                # ----------------------------
                # TIMEOUT handling
                # ----------------------------
                if (-not (Wait-Job $job -Timeout $TimeoutSec)) {
                    Stop-Job $job -Force | Out-Null
                    Remove-Job $job -Force -ErrorAction SilentlyContinue

                    return [pscustomobject]@{
                        Name  = $Name
                        State = "TIMEOUT"
                    }
                }

                # ----------------------------
                # JOB STATE is authoritative
                # ----------------------------
                $state = $job.State

                try {
                    Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
                }
                finally {
                    Remove-Job $job -Force -ErrorAction SilentlyContinue
                }

                switch ($state) {
                    "Failed" {
                        return [pscustomobject]@{
                            Name  = $Name
                            State = "FAILED"
                        }
                    }

                    "Stopped" {
                        return [pscustomobject]@{
                            Name  = $Name
                            State = "FAILED"
                        }
                    }

                    default {
                        return [pscustomobject]@{
                            Name  = $Name
                            State = "OK"
                        }
                    }
                }
            }

            # ----------------------------
            # WMI (root control plane dependency)
            # ----------------------------
            $wmi = Run-Probe -Name "WMI" -TimeoutSec $ProbeTimeoutSec -Command {
                Get-CimInstance Win32_OperatingSystem | Out-Null
            }

            # ----------------------------
            # VMMS provider layer
            # ----------------------------
            $vmms = Run-Probe -Name "VMMS" -TimeoutSec $ProbeTimeoutSec -Command {
                Get-CimInstance -Namespace root\virtualization\v2 -Class Msvm_ComputerSystem | Out-Null
            }

            # ----------------------------
            # Hyper-V orchestration layer
            # ----------------------------
            $vm = Run-Probe -Name "GetVM" -TimeoutSec $ProbeTimeoutSec -Command {
                Get-VM | Out-Null
            }

            # ----------------------------
            # Cluster service layer
            # ----------------------------
            $cluster = Run-Probe -Name "Cluster" -TimeoutSec $ProbeTimeoutSec -Command {
                if (Get-Command Get-ClusterNode -ErrorAction SilentlyContinue) {
                    Get-ClusterNode | Out-Null
                }
            }

            # ----------------------------
            # Fault domain classification
            # ----------------------------
            $fault =
                if ($wmi.State -eq "TIMEOUT") {
                    "WMI / CONTROL PLANE TIMEOUT"
                }
                elseif ($wmi.State -eq "FAILED") {
                    "WMI / WINMGMT FAILED"
                }
                elseif ($vmms.State -eq "FAILED" -or $vm.State -eq "FAILED") {
                    "VMMS / HYPER-V FAILED"
                }
                elseif ($vmms.State -eq "TIMEOUT" -or $vm.State -eq "TIMEOUT") {
                    "VMMS / HYPER-V TIMEOUT"
                }
                elseif ($cluster.State -eq "FAILED") {
                    "CLUSTER / CLUSSVC FAILED"
                }
                elseif ($cluster.State -eq "TIMEOUT") {
                    "CLUSTER / CLUSSVC TIMEOUT"
                }
                else {
                    "HEALTHY"
                }

            [pscustomobject]@{
                Node        = $env:COMPUTERNAME
                WMI         = $wmi.State
                VMMS        = $vmms.State
                GetVM       = $vm.State
                Cluster     = $cluster.State
                FaultDomain = $fault
            }
        }

        # ----------------------------
        # TRUE PARALLEL EXECUTION ACROSS NODES
        # ----------------------------
        $jobs = Invoke-Command -ComputerName $nodes `
            -ScriptBlock $scriptBlock `
            -ArgumentList $ProbeTimeoutSec `
            -ThrottleLimit $ThrottleLimit `
            -AsJob

        # ----------------------------
        # Node-level timeout window
        # ----------------------------
        Wait-Job $jobs -Timeout $NodeTimeoutSec | Out-Null

        $timedOutJobs = Get-Job $jobs -ErrorAction SilentlyContinue | Where-Object State -eq "Running"

        foreach ($j in $timedOutJobs) {
            Stop-Job $j -Force | Out-Null
        }

        # ----------------------------
        # Collect results
        # ----------------------------
        $results = Receive-Job $jobs -ErrorAction SilentlyContinue

        Remove-Job $jobs -Force

        # ----------------------------
        # Inject node-level TIMEOUT classification
        # ----------------------------
        foreach ($j in $timedOutJobs) {
            $results += [pscustomobject]@{
                Node        = $j.Location
                WMI         = "TIMEOUT"
                VMMS        = "UNKNOWN"
                GetVM       = "UNKNOWN"
                Cluster     = "UNKNOWN"
                FaultDomain = "WMI / CONTROL PLANE TIMEOUT"
            }
        }
	    $badnodes=@()
	    $badNodes+=$results | ? FaultDomain -notmatch "HEALTHY"
	    If ($badnodes.count) {
		    If ($badNodes.FaultDomain -notmatch "WMI / CONTROL PLANE TIMEOUT") {
			    Write-ToHost "Nodes $($badNodes.Node -join ',') have unhealthy WMI, VMMS or ClusSvc services!" -Level 3 -CheckMark 3
		    } else {
		    Write-ToHost "Nodes $(($badNodes | ? FaultDomain -notmatch "WMI / CONTROL PLANE TIMEOUT").Node -join ',') have a problem with WMI" -Level 3 -CheckMark 3
		    }
	    } else {
		    Write-ToHost "All nodes WMI, VMMS and Cluster services check out"
	    }
        return $badNodes
    }
    Function Test-ControlPlaneVMNetwork {
        Write-Host "Testing Control Plane VM network..."
        $arcHciConfig = Get-ArcHciConfig
        $controlPlaneIp = $arcHciConfig.controlPlaneIp
        #$CPIPs=[ipaddress[]](get-vm -ComputerName $nodes "*-control-plan*" | Get-VMNetworkAdapter).IPAddresses | ? isIPv6LinkLocal -eq $false
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ConnectAsync($controlPlaneIp,6443).Wait(500) | Out-Null
        $pingablecount=0
        #Foreach ($IP in $CPIPs.IPAddressToString) {
            If ((ping -n 2 $controlPlaneIp | Select-String "Reply from.*TTL.*").count) {$pingablecount++}
        #}
        $result=($pingablecount -eq 0 -and !($tcpClient.Connected))
        if ($result) {
            Write-ToHost "Azure Control Plane VM with IP $controlPlaneIp is not healthy!" -Checkmark 3 -Level 3
        } else {
            Write-ToHost "Control Plane VM network checks out"
        }
        return $result
    }
    Function Test-AksArcIssues {
        $failedAksArcIssues=@()
        Write-Host "Testing Arks Arc Known Issues..."
        $iPolicy=(Get-PSRepository "PSGallery").InstallationPolicy
        Get-PSRepository "PSGallery" | Set-PSRepository -InstallationPolicy Trusted
        if (!(gcm *SupportAksArcKnownIssues)) {
            Install-Module -Name Support.AksArc -AllowClobber -Force -ErrorAction SilentlyContinue
        }
        #Remove-Module -Name Support.AksArc -Force -ErrorAction SilentlyContinue
        Update-Module -Name Support.AksArc -Force -ErrorAction SilentlyContinue
        Import-Module -Name Support.AksArc -Force
        if (gcm *SupportAksArcKnownIssues) {
            $testErr=$null
            $Tests=Test-SupportAksArcKnownIssues -ErrorVariable testErr
            try {$testErr=$testErr | ? {$_.Trim() -ne "System error."}} catch {}
            Get-PSRepository "PSGallery" | Set-PSRepository -InstallationPolicy $iPolicy
            $failedTests=$Tests | ? Status -eq "Failed"
            $failedTests | ft -AutoSize
            if ($failedTests) {
                $failedTests | ft -AutoSize
                Write-ToHost "Some Aks Arc tests failed" -Level 3 -Checkmark 3
                return $failedTests
            } elseif ($testErr -eq $null -or $testErr.count -eq 0) {
                Write-ToHost "All Aks Arc Issues tests passed"
                return $failedTests
            } else {
                Write-ToHost "Some tests failed" -Level 3 -Checkmark 3
                return "Aks Arc test failed hard"
            }
        } else {
            Write-ToHost "Could not install Aks Arc Issues module" -Level 2 -Checkmark 2
            return $null
        }
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
    Write-Host "Logging Telemetry Information..."

    function Add-TableData {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            [string]$TaliTableName,

            [Parameter(Mandatory=$true)]
            [string]$PartitionKey,

            [Parameter(Mandatory=$false)]
            [string]$RowKey,

            [Parameter(Mandatory=$false)]
            [string]$SasToken,
            
            [Parameter(Mandatory=$true)]
            $Data
        )

        try {$Data=[HashTable]$Data

        $RowKey = [guid]::NewGuid().Guid
        $uriText = @'
        https://gsetools.table.core.windows.net/TaliTelemetryData?sv=2019-02-02&spr=https&st=2026-06-10T20%3A46%3A31Z&se=2028-06-11T20%3A46%3A00Z&sp=a&sig=bBHChotKhHj8kTOByiTjLjQydWpCU2O7dXf6Ts%2B3E34%3D&tn=TaliTelemetryData
'@.Trim()

         
        $uri = [System.Uri]$uriText

        $headers = @{
            "Accept"       = "application/json;odata=nometadata"
            "Content-Type" = "application/json"
            "x-ms-version" = "2019-02-02"
            "DataServiceVersion"    = "3.0"
            "MaxDataServiceVersion" = "3.0"
        }

        $Data["PartitionKey"] = $PartitionKey
        $Data["RowKey"]       = $RowKey

        $body = $Data | ConvertTo-Json -Depth 5

        $maxRetries = 3
        $attempt = 0
        $success = $false
        } catch {return}
        while (-not $success -and $attempt -lt $maxRetries) {

            try {
                Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body | Out-Null
                $success = $true
                Write-Indent "Telemetry recorded successfully" 1 Green
            }
            catch {
                $attempt++

                if ($attempt -lt $maxRetries) {
                    Write-Indent "Retrying telemetry upload ($attempt/$maxRetries)..." 1 Yellow
                    Start-Sleep -Seconds 2
                }
                else {
                    Write-Indent "Telemetry upload failed after $maxRetries attempts" 1 Yellow
                }
            }
        }
    }

    function Write-Indent {
        param(
            [string]$Message,
            [int]$Level = 1,
            [string]$Color = "Gray"
        )

        $prefix = "  " * $Level
        Write-Host "$prefix$Message" -ForegroundColor $Color
    }

    # Unique report id
    $CReportID = [guid]::NewGuid().Guid


    Write-Indent "Resolving Geo Location..."

    try {
        if (-not $global:GeoCache) {
            $global:GeoCache = Invoke-RestMethod "https://ipwho.is/" -TimeoutSec 5
        }

        $response = $global:GeoCache

        if ($response.success -eq $true) {

            $country     = $response.country
            $countryCode = $response.country_code
            $region      = $response.region
            $city        = $response.city
            $latitude    = $response.latitude
            $longitude   = $response.longitude
            $timezone    = $response.timezone.id

            Write-Indent "Country: $country" 2
            Write-Indent "Region : $region" 2
        }
    }
    catch {
        Write-Indent "WARN: ipwho lookup failed" 2 Yellow
    }

    $data = @{
        Region       = $region
        Version      = $ver
        ReportID     = $CReportID
        country      = $country
        countryCode  = $countryCode
        geoRegion    = $region
        city         = $city
        lat          = $latitude
        lon          = $longitude
        timezone     = $timezone
        Timestamp = (Get-Date).ToUniversalTime().ToString("o")
        HostOS = [System.Environment]::OSVersion.VersionString
        PSVersion = $PSVersionTable.PSVersion.ToString()
    }

    # We use tool name for this value
    $PartitionKey = "Tali"

    Add-TableData `
        -TaliTableName "TaliTelemetryData" `
        -PartitionKey $PartitionKey `
        -Data $data 

<#
    $scriptBlock = $MyInvocation.MyCommand.ScriptBlock

    $TestFunctions = $scriptBlock.Ast.FindAll({
        param($n)

        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $n.Name -like 'Test-*'
    }, $true).Name


    $Tests = foreach ($name in $TestFunctions) {
        [pscustomobject]@{
            Name        = $name
            ScriptBlock = $scriptBlock.Ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $n.Name -eq $name
            }, $true).ScriptBlock
        }
    } #>


    If ($FixErrors -or $FixWarningsAlso) {Write-Warning "Fix commands are in beta and SHOULD NOT be used without proper guidance";sleep 5}
    If (($FixErrors -or $FixWarningsAlso) -and $ApproveAllFixesAutomatically) {Write-Warning "ApproveAllFixesAutomatically selected. All fixes will be applied!";sleep 10}
    $nodes=(Get-ClusterNode).Name
    Write-Host "Checking for running action plans"
    $MasUpdateNotRunning=(!((Get-ActionPlanInstances | ? Status -eq Running | ? ActionPlanName -like "MAS Update*").count))
    If (!($MasUpdateNotRunning) -and ($FixErrors -or $FixWarningsAlso)) {
        Write-Warning "Solution Update is running. Some fixes will be disabled"
    }

<#    $MaxJobs = 20
    $Jobs = @()

    foreach ($test in $Tests) {

        while ((Get-Job -State Running).Count -ge $MaxJobs) {
            Start-Sleep -Milliseconds 200
        }

        $Jobs += Start-Job -Name $test.Name -ArgumentList $test.Name, $test.ScriptBlock -ScriptBlock {

            param($FunctionName, $FunctionScriptBlock)
            $nodes=$using:nodes
            try {
                $GetNetAdapterAll=$using:GetNetAdapterAll
                $GetNetIntent=$using:GetNetIntent
                $GetNetIntentStatus=$using:GetNetIntentStatus
                $GetNetIntentGlobalStatus=$using:GetNetIntentGlobalStatus
            } catch {}
            Set-Item -Path "Function:\$FunctionName" -Value $FunctionScriptBlock

            try {
                $output = & $FunctionName

                # Contract:
                # $false = success
                # $true  = failure
                # anything else = failure payload
                if ($output -is [bool]) {
                    $success = -not $output
                    $failedItems = $null
                }
                elseif ($null -eq $output) {
                    $success = $true
                    $failedItems = $null
                }
                else {
                    $success = $false
                    $failedItems = @($output)
                }

                [pscustomobject]@{
                    TestName    = $FunctionName
                    Success     = $success
                    FailedItems = $failedItems
                    RawResult   = $output
                }
            }
            catch {
                [pscustomobject]@{
                    TestName    = $FunctionName
                    Success     = $false
                    FailedItems = $null
                    RawResult   = $null
                    Error       = $_.Exception.Message
                }
            }
        }
    }

    $allJobs=$Jobs
    $StartTime = Get-Date
    $LastReport = Get-Date
    $SeenCompleted = @{}
    do {

        $now = Get-Date

        # -----------------------------
        # 30-second running snapshot
        # -----------------------------
        if (($now - $LastReport).TotalSeconds -ge 30) {

            Write-Host "`n=== Running Jobs (Snapshot) ===" -ForegroundColor Cyan

            $running = Get-Job -State Running | Sort-Object Name

            foreach ($job in $running) {

                $start = $job.PSBeginTime
                $duration = if ($start) { $now - $start } else { $null }

                "{0,-25} Start: {1}  Duration: {2}" -f `
                    $job.Name,
                    $start,
                    $duration
            }

            $LastReport = $now
        }

        # -----------------------------
        # completion handling (print once, then remove)
        # -----------------------------
        $completed = Get-Job | ? State -ne Running

        foreach ($job in $completed) {

            if (-not $SeenCompleted.ContainsKey($job.Id)) {

                #$result = Receive-Job -Job $job -ErrorAction SilentlyContinue
                $duration = (Get-Date) - $StartTime

                [pscustomobject]@{
                    JobName  = $job.Name
                    Start    = $StartTime
                    Duration = $duration
                    Failed  = ($job.state -ne "Completed")
                }

                $SeenCompleted[$job.Id] = $true
                #Remove-Job -Job $job
            }
        }

        Start-Sleep -Seconds 1

    } while ((Get-Job).Count -gt 0)
    $dResults=Get-Job | Receive-Job -Wait #>

    Write-Host ""
    $testPass=0
    $badNodes=Test-ClusterControlPlaneHealth
    If ($badNodes.count) {
        Write-Host "Recommendation: Restart node(s) $($badNodes.Node -join ',') to resolve service issue"
        $testPass=2
    } 
    $testReport+= [PSCustomObject] @{TestName="Test-ClusterControlPlaneHealth";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    If ((Get-Job -Name "SUJob" -ErrorAction SilentlyContinue).count) {
        Write-Host "Waiting for prevoius Get Solution Update command to timeout..."
        Get-Job -Name "SUJob" -ErrorAction SilentlyContinue | Remove-Job -Force
    }
    if (Test-SolutionUpdateCommand) {
        If (($FixErrors -or $FixWarningsAlso) -and $MasUpdateNotRunning) {
            Write-Host "Fixing Get Solution Update command. Est Time is less than five minutes" -ForegroundColor Cyan
            Get-ClusterGroup "Azure Stack HCI Download Service Cluster Group","Azure Stack HCI Health Service Cluster Group","Azure Stack HCI Orchestrator Service Cluster Group","Azure Stack HCI Update Service Cluster Group" | Stop-ClusterGroup | Start-ClusterGroup
            Write-Host "Restarting cluster groups finished."
	        Write-Host "Waiting for Get Solution Update command to time out"
            While ((Get-Job "SUJob").State -eq "Running") {Write-Host "." -NoNewline;sleep 5}
            Write-Host "."
            Get-Job -Name "SUJob" -ErrorAction SilentlyContinue | Remove-Job -Force
            If (Test-SolutionUpdateCommand) {Write-ToHost "Fix Get Solution Update command FAILED!!!" -Level 4 -Checkmark 4;$testPass=2}
        } else {
            Write-Host "Recommendation: Restart the Azure Stack HCI cluster groups and make sure they are Online"
            $testPass=2
        }
    }
    $testReport+= [PSCustomObject] @{TestName="Test-SolutionUpdateCommand";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    $GetNetAdapterAll=Invoke-Command -ComputerName $nodes -ScriptBlock {Get-NetAdapter}
    $GetNetIntent=Get-NetIntent
    $GetNetIntentStatus=Get-NetIntentStatus
    $GetNetIntentGlobalStatus=Get-NetIntentStatus -GlobalOverrides
    $failedNetIntent=Test-NetIntents
    If ($failedNetIntent)  {
        If ($FixErrors -or $FixWarningsAlso) {
            Write-Host "Fixing Net Intents. Est Time is less than $($failedNetIntent.count+1) minutes" -ForegroundColor Cyan
            Get-service -ComputerName (($failedNetIntent).host | sort -Unique) "NetworkAtc" | Stop-Service
            Get-service -ComputerName (($failedNetIntent).host | sort -Unique) "NetworkAtc" | Start-Service -Verbose
            Foreach ($dNetAdapter in ($GetNetAdapterAll | ? {($GetNetIntent.NetAdapterNamesAsList) -match $_.name -and !($_.status -eq "Up" -or $_.ifOperStatus -eq "Up")})) {
                  Invoke-Command -ComputerName "$(($dNetAdapter).PSComputerName)" -ScriptBlock {Enable-NetAdapter -ifAlias "$($using:dNetAdapter.Name)" -Verbose}
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
                     try {Set-NetIntentRetryState -NodeName "$($failedIntent.Host)" -GlobalOverrides -Wait} catch {}
                } else {
                     try {Set-NetIntentRetryState -NodeName "$($failedIntent.Host)" -Name "$($failedIntent.IntentName)" -Wait} catch {}
                }
            }
            do {
                Start-Sleep 10
                $ready = Get-NetIntentStatus | Where-Object { $_.LastSuccess }
            } until ($ready)
            $GetNetIntentStatus=Get-NetIntentStatus
            $GetNetIntentGlobalStatus=Get-NetIntentStatus -GlobalOverrides
            $failedNetIntent=Test-NetIntents
            If ($failedNetIntent) {Write-ToHost "Fix Net Intents FAILED!!!" -Level 4 -Checkmark 4;$testPass=2}
        } else {
            $testPass=2
            $dnetAdapter=($GetNetAdapterAll | ? {($GetNetIntent.NetAdapterNamesAsList) -match $_.name -and !($_.status -eq "Up" -or $_.ifOperStatus -eq "Up")})
            if ($dnetAdapter) {
                Write-Host "Recommendation: Plug in and enable network adapters used in Net Intents and Retry the failed Net Intents"
            } else {
                Write-Host "Recommendation: Retry the failed Net Intents"
            }
        }
    }
    $testReport+= [PSCustomObject] @{TestName="Test-NetIntents";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
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
                While ((Get-NetAdapter -ifdesc *NDIS*| Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue).AddressState -ne "Preferred") {Write-Host "." -NoNewline;sleep 1}
            }
            Write-Host ""
            Sleep 10
            $failediDracDHCP=Test-iDracHostNicDHCP
            If ($failediDracDHCP) {Write-ToHost "Fix iDrac Host Nic DHCP FAILED!!!" -Level 4 -Checkmark 4;$testPass=2}
        } else {
            $testPass=2
            Write-Host "Recommendation: Enable DHCP on the iDrac host network adapter for all nodes"
        }
    }
    $testReport+= [PSCustomObject] @{TestName="Test-iDracHostNicDHCP";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    <# New-NetFirewallRule -DisplayName "Block-Idrac-Https-a897gt98gydf" -Direction Outbound -Action Block -RemoteAddress 169.254.0.0/16 -Protocol TCP -RemotePort 443 -Enabled True #>
    $failediDracRedfish=@()
    $failediDracRedfish+=Test-iDracRedfish
    if ($failediDracRedfish) {
        If (($FixErrors -or $FixWarningsAlso) -and $MasUpdateNotRunning) {
            Write-Host "Fixing iDrac Redfish. Est Time is five minutes" -ForegroundColor Cyan
            Write-Host "Please Enter IDrac Credentials for Host $($failediDracRedfish[0].PSComputerName)"
            Invoke-Command -ComputerName $nodes -ScriptBlock {Get-NetFirewallRule -DisplayName "Block-Idrac-Https-a897gt98gydf" -ErrorAction SilentlyContinue | Set-NetFirewallRule -Enabled False}
            Do {
                $credential=Get-Credential -Message "Please enter the iDrac creds for host $($failediDracRedfish[0].PSComputerName)" -UserName root;$cred2=Get-Credential -Message "Confirm iDRAC Password" -UserName $credential.GetNetworkCredential().UserName
            } while (($credential.GetNetworkCredential().Password -ne $cred2.GetNetworkCredential().Password) -or ($credential.GetNetworkCredential().UserName -ne $cred2.GetNetworkCredential().UserName))
            $IdracReboots=@()
            $IdracReboots+=$failediDracRedfish.PSComputerName | %{Invoke-Command -ComputerName $_ -ScriptBlock {
                add-type "using System.Net;using System.Security.Cryptography.X509Certificates;public class T : ICertificatePolicy {public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate,WebRequest request, int certificateProblem) {return true;}}";[System.Net.ServicePointManager]::CertificatePolicy = New-Object T
                $iDracIP=(Get-CimInstance win32_networkadapterconfiguration | ? Description -like "*NDIS*" -ErrorAction SilentlyContinue).DHCPServer
                if ($IDracIP -le "") {$iDracIP=(Get-PcsvDevice).IPv4Address}
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
            if ($IdracReboots.Contains($true)) {Invoke-Command -ComputerName $failediDracRedfish[$IdracReboots.IndexOf($true)].PSComputerName -ScriptBlock {
               $iDracIP=(Get-CimInstance win32_networkadapterconfiguration | ? Description -like "*NDIS*" -ErrorAction SilentlyContinue).DHCPServer
               if ($IDracIP -le "") {$iDracIP=(Get-PcsvDevice).IPv4Address}
               Write-Host "Waiting for iDrac with ip $iDracIP to shutdown"
               $dtime=0
               While ($dtime -lt 30 -and (((Test-NetConnection -ComputerName $iDracIP -WarningAction SilentlyContinue).PingSucceeded) -or ((Test-NetConnection -ComputerName $iDracIP -WarningAction SilentlyContinue).PingSucceeded))) {Write-Host -NoNewline ".";sleep 10;$dtime++}
               Write-Host "."
               $dtime=0
               Write-Host "Waiting for iDrac with ip $iDracIP to boot"
               While ($dtime -lt 50 -and !((Test-NetConnection -ComputerName $iDracIP -WarningAction SilentlyContinue).PingSucceeded)) {Write-Host -NoNewline ".";sleep 10;$dtime++}
               Write-Host "."
               Write-Host "Waiting 30 seconds for iDrac services to come up"
               (1..3) | %{Write-Host "." -NoNewline;sleep 10}
               Write-Host "."
            }}
            $failediDracRedfish=Test-iDracRedfish
            If ($failediDracRedfish) {Write-ToHost "Fix iDrac redfish FAILED! May need to drain flea power on host" -Level 4 -Checkmark 4;$testPass=2}
        } else {
            $testPass=2
            Write-Host "Recommendation: Reboot iDrac on failing nodes and/or enable redfish on those iDracs"
        }
    }
    $testReport+= [PSCustomObject] @{TestName="Test-iDracRedfish";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    If ((Test-OsBootTimeOver99Days)){
        $testPass=1
        Write-host "Recommendation: Manually Pause/Drain, Reboot and Resume with failback these node(s) to avoid update issues"
    }
    $testReport+= [PSCustomObject] @{TestName="Test-OsBootTimeOver99Days";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
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
            If ($nonCompliant) {Write-ToHost "Fix HWTimeout registry key failed!!!" -Level 4 -Checkmark 4;$testPass=2}
        } else {
             $testPass=2
             Write-Host "Recommendation: Set HWTimeout registry key to at least 10000 on all nodes"
        }
    }
    $testReport+= [PSCustomObject] @{TestName="Test-HWTimeoutKey";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    $disksInMaint= Test-NodesUpDisksinMaintMode
    If ($disksInMaint)  {
        If (($FixErrors -or $FixWarningsAlso) -and $MasUpdateNotRunning) {
            Write-Host "Taking disks out of maintenance mode. Est Time is less than five minutes" -ForegroundColor Cyan
            Repair-ClusterS2D -DisableStorageMaintenenceMode -Verbose
            $disksFixed=foreach ($disk in $disksInMaint) {
                try {
                    if (($disk | Get-PhysicalDisk).OperationalStatus -ne "OK") {
                        $node=($disk | Get-PhysicalDisk | Get-StorageNode -PhysicallyConnected).Name
                        If ($node) {
                            Invoke-Command -ComputerName $node -ScriptBlock {$using:disk | Get-PhysicalDisk | Disable-StorageMaintenanceMode} -ErrorAction Stop
                        } else {
                            $disk | Get-PhysicalDisk | Disable-StorageMaintenanceMode -ErrorAction Stop
                        }
                        
                    }
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
                $testPass=2
            } else {
                $disksInMaint = Test-NodesUpDisksinMaintMode
                If ($disksInMaint) {Write-ToHost "Fix take disks out of maintenance mode failed!!!" -Level 4 -Checkmark 4;$testPass=2}
            }
        } else {
            $testPass=2
            Write-Host "Recommendation: Take disks out of maintenance mode if all nodes are up"
        }
    }
    $testReport+= [PSCustomObject] @{TestName="Test-NodesUpDisksinMaintMode";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    $nonCompliant=Test-TimeZone
    If ($nonCompliant)  {
        If ($FixErrors -or $FixWarningsAlso) {
            Write-Host "Fixing tome zone consistency. Est Time is less than one minute" -ForegroundColor Cyan
            $tz=$global:dTimeZone
            Invoke-Command -ComputerName $nonCompliant.Node -ScriptBlock {Set-TimeZone -Id $using:tz}
            $nonCompliant=Test-TimeZone
            If ($nonCompliant) {Write-ToHost "Fix time zone failed!!!" -Level 4 -Checkmark 4;$testPass=2}
        } else {
            $testPass=2
            Write-Host "Recommendation: Set all nodes to the same time zone"
        }
    }
    $testReport+= [PSCustomObject] @{TestName="Test-TimeZone";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    If (Test-ClusterShutdownTime) {
        if ($FixErrors -or $FixWarningsAlso) {
            Write-Host "Fixing cluster shutdown timeout. Est Time is less than one minute" -ForegroundColor Cyan
            (Get-Cluster).ShutdownTimeoutInMinutes=1440
            If (Test-ClusterShutdownTime) {Write-ToHost "Fix setting cluster shutdown timeout to 1440 minutes failed!!!" -Level 4 -Checkmark 4;$testPass=2}
        } else {
            $testPass=2
            Write-Host "Recommendation: Set cluster shutdown timeout to 1440"
        }
    }
    $testReport+= [PSCustomObject] @{TestName="Test-ClusterShutdownTime";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    If (Test-InvalidCAUReports) {
        if ($FixErrors -or $FixWarningsAlso) {
            Write-Host "Removing invalid CAU reports. Est Time is less than one minute" -ForegroundColor Cyan
            Invoke-Command -ComputerName $nodes -ScriptBlock {Remove-Item C:\Windows\Cluster\Reports\CauReport-00000101000000.xml -ErrorAction SilentlyContinue -Force}
            If (Test-InvalidCAUReports) {Write-ToHost "Fix removing invalid CAU reports failed!!!" -Level 4 -Checkmark 4;$testPass=2}
        } else {
            $testPass=2
            Write-Host "Recommendation: Remove invalid CAU Reports named CauReport-00000101000000.xml"
        }
    }
    $testReport+= [PSCustomObject] @{TestName="Test-InvalidCAUReports";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    $FailedComputeIntents=Test-NetworkDirectOnComputeIntents
    If ($FailedComputeIntents) {
        if ($FixErrors -or $FixWarningsAlso) {
            Write-Host "Fixing Invalid compute intent settings. Est Time is less than one minute" -ForegroundColor Cyan
            Foreach ($FailedComIntent in $FailedComputeIntents) {
                $AdapOver=(Get-NetIntent -Name "$($FailedComIntent.IntentName)").AdapterAdvancedParametersOverride
                $AdapOver.NetworkDirect=0
                Set-NetIntent -Name "$($FailedComIntent.IntentName)" -AdapterPropertyOverrides $AdapOver
            }
            $FailedComputeIntents=Test-NetworkDirectOnComputeIntents
            If ($FailedComputeIntents) {Write-ToHost "Fix invalid Net Intent Network Direct configuration failed!!!" -Level 4 -Checkmark 4;$testPass=2}
        } else {
            $testPass=2
            Write-Host "Recommendation: Remove Network Direct setting on compute intents"
        }
    }
    $testReport+= [PSCustomObject] @{TestName="Test-NetworkDirectOnComputeIntents";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    $FailedStorageIntents=Test-NetworkDirectOnStorageIntents
    If ($FailedStorageIntents) {
        if ($FixErrors -or $FixWarningsAlso) {
            Write-Host "Fixing Invalid storage intent settings. Est Time is less than one minute" -ForegroundColor Cyan
            Foreach ($FailedStrIntent in $FailedStorageIntents) {
                $dnetAdapter=@()
                $dnetAdapter+=($GetNetAdapterAll | ? {($FailedStrIntent.NetAdapterNamesAsList) -match $_.name})
                $NDTech=($dnetAdapter | Get-NetAdapterAdvancedProperty  -DisplayName "NetworkDirect Technology").RegistryValue | sort -Unique | Select -First 1
                if ($NDTech -le "") {$NDTech=4}
                $AdapOver=(Get-NetIntent -Name "$($FailedStrIntent.IntentName)").AdapterAdvancedParametersOverride
                $AdapOver.NetworkDirectTechnology=$NDTech
                Set-NetIntent -Name "$($FailedStrIntent.IntentName)" -AdapterPropertyOverrides $AdapOver
            }
            $FailedStorageIntents=Test-NetworkDirectOnStorageIntents
            If ($FailedStorageIntents) {Write-ToHost "Fix invalid Net Intent Network Direct Technology configuration failed!!!" -Level 4 -Checkmark 4;$testPass=2}
        } else {
            $testPass=2
            Write-Host "Recommendation: Define Network Direct Technology setting on storage intents"
        }
    }
    $testReport+= [PSCustomObject] @{TestName="Test-NetworkDirectOnStorageIntents";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    $nonWindowsGroups = Test-AzLocalVmMigrationFailures
    if ($nonWindowsGroups) {
        If ($FixErrors -or $FixWarningsAlso) {
            # 6. Show candidates
            Write-Host "`nNon-Windows cluster groups eligible for Low (1000) priority:" -ForegroundColor Yellow
            $nonWindowsGroups | Select-Object Name, State | Format-Table
            # 7. Confirm action
            If ($ApproveAllFixesAutomatically) {
                $confirm="Y"
            } else {
                $confirm = Read-Host "Set these cluster groups to priority 1000 (Low)? (Y/N)"
            } 
            if ($confirm -notmatch '^(Y|y)') {
                Write-Host "No changes applied." -ForegroundColor Yellow
            } else {
                Write-Host "Setting cluster groups '$($nonWindowsGroups.Name -join ',')' to priority 1000..." -ForegroundColor Cyan
                # 8. Apply fix
                foreach ($group in $nonWindowsGroups) {
                    (Get-ClusterGroup -Name $group.Name).Priority = 1000
                }
            }
            $nonWindowsGroups = Test-AzLocalVmMigrationFailures
            if ($nonWindowsGroups) {Write-ToHost "Fix change high failure non-Windows VM migration priority to 1000 failed!!!" -Level 4 -Checkmark 4;$testPass=1}
        }
        $testPass=1
        Write-Host "Recommendation: Some non-Windows VMs such as $($nonWindowsGroups.Name -join ',') may need to have their priority set to 1000 (Low) to avoid migration issues. This will have those VMs use Quick Migrate instead"        
    }
    $testReport+= [PSCustomObject] @{TestName="Test-AzLocalVmMigrationFailures";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    $AzureLocalServices = @(
        "himds", 
        "WssdService", 
        "MocHostAgent", 
        "GCArcService", 
        "ExtensionService", 
        "KeyVaultLocalAgent", 
        "NetworkControllerHostAgent", 
        "SymptomManager"
    )
    $FailedServices=Test-AzureLocalNodeServices
    If ($FailedServices) {
        if (($FixErrors -or $FixWarningsAlso) -and $MasUpdateNotRunning) {
            Write-Host "Fixing stopped required services for Azure Local that run on all nodes. Est Time is less than two minutes" -ForegroundColor Cyan
            Foreach ($FailedService in $FailedServices) {
                Invoke-Command -ComputerName $FailedService.PSComputerName -ScriptBlock {
                    $using:FailedService | Start-Service
                }
            }
            $FailedServices=Test-AzureLocalNodeServices
            If ($FailedServices) {Write-ToHost "Fix starting stopped required services for Azure Local that run on all nodes failed!!!" -Level 4 -Checkmark 4;$testPass=2}
        } else {
            $testPass=2
            Write-Host "Recommendation: Start $(($FailedServices.Name | Sort -Unique) -join ',') on ALL nodes"
        }
    }
    $testReport+= [PSCustomObject] @{TestName="Test-AzureLocalNodeServices";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    If (Test-AzLocalOverProvisionedVirtualDisks) {
        $testPass=1
        Write-Host "Recommendation: Make sure Storage Pool space does not run below best practice levels"
    }
    $testReport+= [PSCustomObject] @{TestName="Test-AzLocalOverProvisionedVirtualDisks";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    $failed=Test-AzLocalThinProvisioningUtilization
    if ($failed.CurrentPercent -lt 99) {$failed.CurrentPercent=$failed.CurrentPercent+1}
    if ($failed.MaxPercent -lt 99) {$failed.MaxPercent=$failed.MaxPercent+1}
    If ($failed.CurrentPercent -gt $failed.Threshold -or $failed.MaxPercent -gt $failed.Threshold) {
        $changed=$false
        $testPass=2
        If ($FixErrors -and $failed.CurrentPercent -lt 100 -and $failed.CurrentPercent -gt $failed.Threshold) {
            Write-Host "Setting Thin Provisioning Alert Threshold to $($failed.CurrentPercent). Est Time is less than one minute" -ForegroundColor Cyan
            Get-StoragePool | ? IsPrimordial -eq $false | Set-StoragePool -ThinProvisioningAlertThresholds $failed.CurrentPercent -Verbose
            $changed=$true
        }
        If ($FixWarningsAlso -and $failed.MaxPercent -lt 100 -and !($ErrorOnlyCheck) -and $failed.MaxPercent -gt $failed.Threshold) {

            Write-Host "Setting Thin Provisioning Alert Threshold to $($failed.MaxPercent). Est Time is less than one minute" -ForegroundColor Cyan
            Get-StoragePool | ? IsPrimordial -eq $false | Set-StoragePool -ThinProvisioningAlertThresholds $failed.MaxPercent -Verbose
            $changed=$true
        }
        if ($changed) {
            If (Test-AzLocalThinProvisioningUtilization) {Write-ToHost "Fix setting Thin Provisioning Alert Threshold failed!!!" -Level 4 -Checkmark 4;$testPass=2}
        } else {
            If ($failed.CurrentPercent -gt $failed.Threshold) {
                $testPass=2
                Write-Host "Recommendation: Set Thin Provision Threshold to at least $($failed.CurrentPercent)"
            } elseif ($failed.MaxPercent -gt $failed.Threshold) {
                $testPass=1
                if ($failed.MaxPercent -lt 100) {
                    Write-Host "Recommendation: Set Thin Provision Threshold to $($failed.MaxPercent)"
                } else {
                    Write-Host "Recommendation: Make sure Vdisk usage does not exceed $($failed.Threshold)%"
                }
            }
        }        
    }
    $testReport+= [PSCustomObject] @{TestName="Test-AzLocalThinProvisioningUtilization";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    If (Test-AzLocalMemoryNMinusOne) {
        $testPass=2
        Write-Host "Recommendation: Lower total VM assigned memory to avoid node pause/drain issues"
    }
    $testReport+= [PSCustomObject] @{TestName="Test-AzLocalMemoryNMinusOne";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    If (Test-AzLocalCpuNMinusOneOvercommit) {
        $testPass=1
        Write-Host "Recommendation: Lower total vCPU assignment to avoid node pause/drain issues"
    }
    $testReport+= [PSCustomObject] @{TestName="Test-AzLocalCpuNumMinusOne";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    $ProblemDrives=Test-DiskLatencyOutlier
    If ($ProblemDrives) {
        $testPass=1
        Write-Host "Recommendation: Reboot nodes with the disks. Reseat disks. Re-test after 48 hours"
    }
    $testReport+= [PSCustomObject] @{TestName="Test-DiskLatencyOutlier";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    If ((Test-GetHealthFault) -eq $true) {
        if (($FixErrors -or $FixWarningsAlso) -and $MasUpdateNotRunning) {
            Write-Host "Fixing failed Get-HealthFault command. Est Time is less than two minutes" -ForegroundColor Cyan
            Invoke-Command -ComputerName $nodes -ScriptBlock {
                Restart-Service Winmgmt -Force
            }
            Sleep 5
            If ((Test-GetHealthFault) -eq $true) {Write-ToHost "Fix restarting Winmgmt that run on all nodes failed to fix Get-HealthFault command!!!" -Level 4 -Checkmark 4;$testPass=2}
        } else {
            $testPass=2
            Write-Host "Recommendation: Restart Winmgmt service on ALL nodes"
        }
    }
    $testReport+= [PSCustomObject] @{TestName="Test-GetHealthFault";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    $badModules=Test-MismatchedPSModules
    If ($badModules.count) {
        if (($FixErrors -or $FixWarningsAlso) -and $MasUpdateNotRunning) {
            Write-Host "Fixing mismatched PS modules...Est time less than $($badModules.count+1) Minutes..."
            $solutionState=(Get-SolutionUpdate).State
            if ($solutionState -eq "Installing" -or $solutionState -eq "InstallationFailed") {
                Write-ToHost "Cannot fix modules while a solution update is in process. Please complete the solution update" -Level 4 -Checkmark 4
            } else {
                Invoke-Command -ComputerName $nodes -ScriptBlock {
                    Remove-Module -Name AzStackHci.EnvironmentChecker -Force -ErrorAction SilentlyContinue
                    if ((Get-Module -ListAvailable -Name AzStackHci.EnvironmentChecker).count) {
                        Write-Host "On Node $($env:COMPUTERNAME), uninstalling AzStackHci.EnvironmentChecker module"
                        Uninstall-Module -Name AzStackHci.EnvironmentChecker -AllVersions -ErrorAction SilentlyContinue -Force
                    }
                }
                if ($badModules.ModuleName -match "Az.Accounts") {
                    $azAccountsVer=($badModules | ? ModuleName -eq "Az.Accounts" | Select -first 1).RequiredVersion
                } else {
                    $azAccountsVer=[version]((Get-InstalledModule -Name Az.Accounts).Version)
                }
                Foreach ($badModule in $badModules) {    
                    Invoke-Command -ComputerName $badModule.NodeName -ScriptBlock {
                        $badModule=$using:badModule
                        #$badModule
                        if (-not (((Get-InstalledModule -Name $badModule.ModuleName -AllVersions).Version | Foreach {[version]$_}) -match $badModule.RequiredVersion)) {
                                Install-Module -Name $badModule.ModuleName -RequiredVersion $badModule.RequiredVersion -Force -Verbose
                        }

                    } -AsJob -JobName "InstallModules-$($badmodule.ModuleName)" | Out-Null
                }
                #Get-Job
                Get-Job -Name "InstallModules*" | Receive-Job -Wait
                Get-Job -Name "InstallModules*" | Remove-Job
            
                Foreach ($badModule in $badModules) {
                    Invoke-Command -ComputerName $badModule.NodeName -ScriptBlock {
                        Get-InstalledModule -Name $using:badModule.ModuleName -AllVersions | Where-Object { [version]$_.Version -ne $using:badModule.RequiredVersion } | ForEach-Object { Uninstall-Module -Name $using:badModule.ModuleName -RequiredVersion $_.Version -Force -Verbose }
                    }
                }
                Invoke-Command -ComputerName $nodes -ScriptBlock {
                    Get-InstalledModule -Name Az.Accounts -AllVersions | Where-Object { [version]$_.Version -ne $using:azAccountsVer } | ForEach-Object { Uninstall-Module -Name Az.Accounts -RequiredVersion $_.Version -Force -Verbose }
                }
                if (Test-MismatchedPSModules) {Write-ToHost "Fix mismatched PS modules failed !!!" -Checkmark 4 -Level 4;$testPass=2
                } else {
                    $testPass=2
                    Write-Host "Recommendation: Install proper PS modules for solution version"
                }
            }
        }
    }
    $testReport+= [PSCustomObject] @{TestName="Test-MismatchedPSModules";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    $ErrorReport=Test-CauErrorAudit
    If ($ErrorReport) {
        $testPass=2
        Write-Host "Recommendation: Repair issue causing the CAU failure"
        Write-Host ""
    }
    $testReport+= [PSCustomObject] @{TestName="Test-CauReportError";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0 
    If ($ErrorReport -ne $null) {Write-Host ""}
    $controlPlaneVMDown=Test-ControlPlaneVMNetwork
    If ($controlPlaneVMDown -eq $true) {
        If (($FixErrors -or $FixWarningsAlso) -and $MasUpdateNotRunning) {
            Write-Host "Rebooting Control Plane VM to fix it's network" -ForegroundColor Cyan
            $CPVM="*-control-plan*"
            $arcHciConfig = Get-ArcHciConfig
            $controlPlaneIp = $arcHciConfig.controlPlaneIp
            Get-VM $CPVM -ComputerName $nodes | Restart-VM -Force -Confirm:$false -Verbose
            $dtime=0
            Write-Host "Waiting for VM to come up"
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $tcpClient.ConnectAsync($controlPlaneIp,6443).Wait(500) | Out-Null
            while(($tcpClient.Connected) -eq $false -and $dtime -lt 500) {Write-Host "." -NoNewline;sleep 1;$dtime++}
            Write-Host ""
            $controlPlaneVMDown=Test-ControlPlaneVMNetwork
            if ($controlPlaneVMDown) {Write-ToHost "Rebooting Control Plane VM did not resolve the issue!!!" -Checkmark 4 -Level 4;$testPass=2
            } else {
                $testPass=2
                Write-Host "Recommendation: Reboot the Control Plane VM"
            } 
        }
    }
    $testReport+= [PSCustomObject] @{TestName="Test-ControlPlaneVMNetwork";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    Write-Host ""
    $FailedArcIssues=Test-AksArcIssues
    If ($FailedArcIssues) {
       <# if (($FixErrors -or $FixWarningsAlso) -and $MasUpdateNotRunning) {
            Write-Host "Fixing failed Get-HealthFault command. Est Time is less than two minutes" -ForegroundColor Cyan
            Invoke-Command -ComputerName $nodes -ScriptBlock {
                Restart-Service Winmgmt -Force
            }
            Sleep 5
            If ((Test-GetHealthFault) -eq $true) {Write-ToHost "Fix restarting Winmgmt that run on all nodes failed to fix Get-HealthFault command!!!" -Level 4 -Checkmark 4}
        } else {#>
            $testPass=2
            Write-Host "Recommendation: Please run Invoke-SupportAksArcRemediation to resolve the problem"
        #}
    }
    $testReport+= [PSCustomObject] @{TestName="Test-AksArcIssues";TestResult=@("Passed","Warning","Error")[$testPass]};$testPass=0
    #Write-Host "Waiting for Get Solution Update command to time out"
    #While ((Get-Job "SUJob").State -eq "Running") {Write-Host "." -NoNewline;sleep 5}
    #Write-Host "."
    return $testReport
    Stop-Transcript -ErrorAction SilentlyContinue
}

