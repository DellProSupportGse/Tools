Function Test-DellAzureLocalIssues {

param(
    [switch]$FixErrors,
    [switch]$FixWarningsAlso,
    [switch]$ErrorOnlyCheck,
    [switch]$ApproveAllFixesAutomatically
)
    $ver="0.33"
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
        $failedNetIntentGlobal=@()
        Write-Host "Checking Net Intents..."
        $failedNetIntent+=$GetNetIntentStatus | ? {$_.LastSuccess -lt (Get-Date).AddMinutes(-40)}
        $failedNetIntentGlobal+=$GetNetIntentGlobalStatus | ? {$_.LastSuccess -lt (Get-Date).AddMinutes(-40)}
        $failedNetIntent=$failedNetIntent | ? {$_.Progress -gt ""}
        $failedNetIntentGlobal=$failedNetIntentGlobal | ? {$_.Progress -gt ""}
        If ($failedNetIntent) {
           Foreach ($failedIntent in $failedNetIntent) {
               Write-ToHost "Net Intent $($failedIntent.Name) on Node $($failedIntent.Host) FAILED" -Checkmark 3 -Level 3
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
        $OSBootTimeOver99Days=@()
        $OSBootTimeOver99Days+=Get-CimInstance -ComputerName $nodes Win32_OperatingSystem | %{[PSCustomObject]@{"CsName"=$_.CsName;"OSBootOver99Days"=(((Get-Date).AddDays(-99)-$_.LastBootUpTime) -gt 0)}}
        $failedOSBootTimeOver99Days=$OSBootTimeOver99Days | ? OSBootOver99Days -eq $true
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
            $nonCompliant+=$nodeResources | ? {$_.mem -ge 1tb} 
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
            }
            else {
                Get-StoragePool | Where-Object IsPrimordial -eq $false | Select-Object -First 1
            }

            if (-not $pool) {
                throw "No storage pool found."
            }

            $poolName = $pool.FriendlyName

            # Single-pass data collection
            $physicalDisks = Get-PhysicalDisk -StoragePoolFriendlyName $poolName
            $vDisks        = Get-VirtualDisk -StoragePoolFriendlyName $poolName
            $nodeCount     = (Get-ClusterNode).Count

            # Core metrics
            $largestDisk     = ($physicalDisks | Measure-Object Size -Maximum).Maximum
            $totalAllocatedMax = ($vDisks | Measure-Object Size -Sum).Sum
            $totalDiskCount   = $physicalDisks.Count
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
            # Failure reserve rule
            $failureReserve = if ($totalDiskCount -lt 11) {
                $largestDisk
            }
            else {
                $largestDisk * $nodeCount
            }

            # Survivable capacity
            $usableCapacity = $pool.Size - $pool.Reserved - $failureReserve

            return ($totalAllocatedMax -gt $usableCapacity)
        }
        catch {
            Write-ToHost "Could not determine Over Provisioned Virtual Disks on Storage Pool" -Checkmark 2 -Level 2
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
            }
            else {
                Get-StoragePool | Where-Object IsPrimordial -eq $false | Select-Object -First 1
            }

            # Default threshold always defined
            $threshold = 70

            if ($pool) {
                $poolName = $pool.FriendlyName

                if ($pool.ThinProvisioningAlertThreshold) {
                    $threshold = $pool.ThinProvisioningAlertThreshold
                }

                $vDisks = Get-VirtualDisk -StoragePoolFriendlyName $poolName

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
                    $currentPercent = ($currentFootprint / $usableCapacity) * 100
                    $maxPercent     = ($maxFootprint / $usableCapacity) * 100
                }
                else {
                    $currentPercent = 101	
                    $maxPercent = $null
                }

                if ($currentPercent -gt $threshold) {
                    Write-ToHost (
                        "CURRENT thin provisioning exceeds threshold: $currentPercent% (Threshold: $threshold%)"
                    ) -Level 3 -Checkmark 3
                } 
                if ($maxPercent -gt $threshold) {
                     Write-ToHost (
                         "WARNING: MAX thin provisioning exceeds threshold: $maxPercent% (Threshold: $threshold%)"
                     ) -Level 2 -Checkmark 2
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
        $vmTotal = (Get-VM -ComputerName $clusterNodes |
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
            Write-ToHost "Cluster is N-1 SAFE (headroom: $delta bytes)" -Level 1 -Checkmark 1
            return $false   # PASS
        }
        else {
            Write-ToHost "Cluster is NOT N-1 SAFE (shortfall: $([math]::Abs($delta)) bytes)" -Level 3 -Checkmark 3
            return $true    # FAIL
        }
    }
    function Test-AzLocalCpuNMinusOneOvercommit {
        [CmdletBinding()]
        param()

        Write-Host "Testing cluster CPU vCPU overcommit risk (N-1 model, 200% threshold)..."

        $clusterNodes = (Get-ClusterNode).Name

        # Total VM vCPU demand (cluster-wide)
        $vmVcpus = (Get-VM -ComputerName $clusterNodes |
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
    function Test-AzLocalVmMigrationFailures {
        [CmdletBinding()]
        param()

        Write-Host "Analyzing non-Windows VM live migration / failback failures (last 7 days across all nodes)..."

        $startTime = (Get-Date).AddDays(-7)
        $eventIds = 21502, 21503, 21504, 1069, 1205
        $events = Invoke-Command -ComputerName $nodes -ScriptBlock {
            param($startTime, $eventIds)

            Get-WinEvent -FilterHashtable @{
                LogName   = 'Microsoft-Windows-FailoverClustering/Operational'
                Id        = $eventIds
                StartTime = $startTime
            } | Select-Object TimeCreated, Id, Message, MachineName

        } -ArgumentList $startTime, $eventIds

        if (-not $events) {
            Write-ToHost "No migration or failback failures detected in last 7 days" -Level 1 -Checkmark 1
            return
        }

        # Extract VM names
        $vmFailures = foreach ($event in $events) {
            if ($event.Message -match "Virtual Machine\s+'([^']+)'") {
                [PSCustomObject]@{
                    VMName = $matches[1]
                    Node   = $event.MachineName
                }
            }
        }

        if (-not $vmFailures) {
            Write-ToHost "No VM-specific failures identified in event logs" -Level 1 -Checkmark 1
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
                Write-ToHost "Non-Windows VM '$($vm.Name)' failed $($vm.Count) times" -Level 2
            }

            return $nonWindowsGroups
        }
        else {
            Write-ToHost "No Non-Windows VMs exceeded failure threshold (>200% of average) in last 7 days" -Level 1 -Checkmark 1
            return
        }
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
                        # If distribution is Normal, expect >99% within 3 devations
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
                    Write-ToHost "Node $($disk.PSComputerName) with SN $($disk.SerialNumber) with Deviation of $($disk.Deviation) may need to be reseated" -Level 2 -Checkmark 2
                }
                return $true
            } else {
                Write-ToHost "All physical disks passed"
                return $false
            }
            } catch { Show-Warning "Unable to get latency outlier Data.  `nError="+$_.Exception.Message
            }
    }
    function Test-AzLocalClusterDiskEndurance {
        [CmdletBinding()]
        param()

        $nodes = Get-ClusterNode
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
                    if ($mediaErrors -gt 0 -or $predictFail -eq $true) {
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
    If (($FixErrors -or $FixWarningsAlso) -and $ApproveAllFixesAutomatically) {Write-Warning "ApproveAllFixesAutomatically selected. All fixes will be applied!";sleep 10}
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
            Write-Host "Fixing Net Intents. Est Time is less than $($failedNetIntent.count+1) minutes" -ForegroundColor Cyan
            Get-service -ComputerName $nodes "NetworkAtc" | Stop-Service
            Get-service -ComputerName $nodes "NetworkAtc" | Start-Service -Verbose
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
                     Set-NetIntentRetryState -NodeName "$($failedIntent.Host)" -GlobalOverrides -Wait
                } else {
                     Set-NetIntentRetryState -NodeName "$($failedIntent.Host)" -Name "$($failedIntent.IntentName)" -Wait
                }
            }
            do {
                Start-Sleep 5
                $ready = Get-NetIntentStatus | Where-Object { $_.LastSuccess }
            } until ($ready)
            $GetNetIntentStatus=Get-NetIntentStatus
            $GetNetIntentGlobalStatus=Get-NetIntentStatus -GlobalOverrides
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
        Write-host "Recommendation: Manually Pause/Drain, Reboot and Resume with failback these node(s) to avoid update issues"
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
            Write-Host "Taking disks out of maintenance mode. Est Time is less than five minutes" -ForegroundColor Cyan
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
            Write-Host "Fixing cluster shutdown timeout. Est Time is less than one minute" -ForegroundColor Cyan
            (Get-Cluster).ShutdownTimeoutInMinutes=1440
            If (Test-ClusterShutdownTime) {Write-ToHost "Fix setting cluster shutdown timeout to 1440 minutes failed!!!" -Level 4 -Checkmark 4}
        } else {
            Write-Host "Recommendation: Set cluster shutdown timeout to 1440"
        }
    }
    Write-Host ""
    If (Test-InvalidCAUReports) {
        if ($FixErrors -or $FixWarningsAlso) {
            Write-Host "Removing invalid CAU reports. Est Time is less than one minute" -ForegroundColor Cyan
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
            Write-Host "Fixing Invalid compute intent settings. Est Time is less than one minute" -ForegroundColor Cyan
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
    Write-Host ""
    #$nonWindowsGroups = Test-AzLocalVmMigrationFailures
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
            if ($nonWindowsGroups) {Write-ToHost "Fix change high failure non-Windows VM migration priority to 1000 failed!!!" -Level 4 -Checkmark 4}
        }
        Write-Host "Recommendation: Some non-Windows VMs such as $($nonWindowsGroups.Name -join ',') may need to have their priority set to 1000 (Low) to avoid migration issues. This will have those VMs use Quick Migrate instead"        
    }
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
        if ($FixErrors -or $FixWarningsAlso) {
            Write-Host "Fixing stopped required services for Azure Local that run on all nodes. Est Time is less than two minutes" -ForegroundColor Cyan
            Foreach ($FailedService in $FailedServices) {
                Invoke-Command -ComputerName $FailedService.PSComputerName -ScriptBlock {
                    $using:FailedService | Start-Service
                }
            }
            $FailedServices=Test-AzureLocalNodeServices
            If ($FailedServices) {Write-ToHost "Fix starting stopped required services for Azure Local that run on all nodes failed!!!" -Level 4 -Checkmark 4}
        } else {
            Write-Host "Recommendation: Start $(($FailedServices.Name | Sort -Unique) -join ',') on ALL nodes"
        }
    }
    Write-Host ""
    If (Test-AzLocalOverProvisionedVirtualDisks) {
        Write-Host "Recommendation: Make sure Storage Pool space does not run below best practice levels"
    }
    Write-Host ""
    $failed=Test-AzLocalThinProvisioningUtilization
    if ($failed.CurrentPercent -lt 99) {$failed.CurrentPercent=$failed.CurrentPercent+1}
    if ($failed.MaxPercent -lt 99) {$failed.MaxPercent=$failed.MaxPercent+1}
    If ($failed.CurrentPercent -gt $failed.Threshold -or $failed.MaxPercent -gt $failed.Threshold) {
        if ($FixErrors -or $FixWarningsAlso) {
            If ($FixWarningsAlso -and !($FixErrors) -and $failed.MaxPercent -lt 100) {
                Write-Host "Setting Thin Provisioning Alert Threshold to $($failed.CurrentPercent). Est Time is less than one minute" -ForegroundColor Cyan
                Get-StoragePool | ? IsPrimordial -eq $false | Set-StoragePool -ThinProvisioningAlertThresholds $failed.CurrentPercent -Verbose
            }
            If ($FixErrors) {
                Write-Host "Setting Thin Provisioning Alert Threshold to $($failed.MaxPercent). Est Time is less than one minute" -ForegroundColor Cyan
                Get-StoragePool | ? IsPrimordial -eq $false | Set-StoragePool -ThinProvisioningAlertThresholds $failed.MaxPercent -Verbose
            }
            If (Test-AzLocalThinProvisioningUtilization) {Write-ToHost "Fix setting Thin Provisioning Alert Threshold failed!!!" -Level 4 -Checkmark 4}
        } else {
            Write-Host "Recommendation: Set Thin Provision Threshold to at least $($failed.CurrentPercent)"
        }
    }
    Write-Host ""
    If (Test-Test-AzLocalMemoryNMinusOne) {
        Write-Host "Recommendation: Lower total VM assigned memory to avoid node pause/drain issues"
    }
    Write-Host ""
    If (Test-Test-AzLocalCpuNMinusOneOvercommit) {
        Write-Host "Recommendation: Lower total vCPU assignment to avoid node pause/drain issues"
    }
    Write-Host ""
    $ProblemDrives=Test-DiskLatencyOutlier
    If ($ProblemDrives) {
        Write-Host "Recommendation: Reboot nodes with the disks. Reseat disks. Re-test after 48 hours"
    }
    Write-Host ""
    Stop-Transcript -ErrorAction SilentlyContinue
}

