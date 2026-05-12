<#
    .Synopsis
       GetHyperVBottlenecks.ps1
    .DESCRIPTION
       Detects bottlenecks in a Hyper-V environment
    .EXAMPLES
       Invoke-GetHyperVBottlenecks
    .Author
       Jim Gandy
#>
function Invoke-GetHyperVBottlenecks {

    param(
        [string]$ClusterName = $env:COMPUTERNAME
    )

$ver="1.2"
$text = @"
v$Ver
   ___     _     _  _                      __   __  ___      _   _   _                 _       
  / __|___| |_  | || |_  _ _ __  ___ _ _   \ \ / / | _ ) ___| |_| |_| |___ _ _  ___ __| |__ ___
 | (_ / -_)  _| | __ | || | '_ \/ -_) '_| __\ V /  | _ \/ _ \  _|  _| / -_) ' \/ -_) _| / /(_-<
  \___\___|\__| |_||_|\_, | .__/\___|_|      \_/   |___/\___/\__|\__|_\___|_||_\___\__|_\_\/__/
                      |__/|_|                                                                  
                                                                By: Jim Gandy
    Simple Hyper-V Perf Bottleneck Detector
"@

$RequestedCounters = @(
    '\Hyper-V Hypervisor Logical Processor(_Total)\% Total Run Time'
    '\Hyper-V Hypervisor Virtual Processor(*)\% Total Run Time'
    '\Hyper-V Hypervisor Root Virtual Processor(*)\% Total Run Time'
    '\Processor(*)\% Interrupt Time'
    '\Processor(*)\% DPC Time'
    '\Memory\Available MBytes'
    '\Network Interface(*)\Bytes/sec'
    '\Hyper-V Virtual Network Adapter(*)\Bytes/sec'
    '\PhysicalDisk(*)\Avg. Disk sec/Read'
    '\PhysicalDisk(*)\Avg. Disk sec/Write'
)

function Test-CounterPath {
    param(
        [string]$ComputerName,
        [string]$CounterPath
    )

    try {
        Get-Counter `
            -ComputerName $ComputerName `
            -Counter $CounterPath `
            -MaxSamples 1 `
            -ErrorAction Stop | Out-Null

        [pscustomobject]@{
            Status = 'FOUND'
            Reason = 'Counter returned data'
        }
    }
    catch {
        $CounterSetName = ($CounterPath -split '\\')[1]

        try {
            $ListSet = Get-Counter `
                -ComputerName $ComputerName `
                -ListSet $CounterSetName `
                -ErrorAction Stop

            if ($ListSet.Paths -contains $CounterPath) {
                [pscustomobject]@{
                    Status = 'FOUND-NOINSTANCE'
                    Reason = 'Counter exists, but no active instance returned data'
                }
            }
            else {
                [pscustomobject]@{
                    Status = 'MISSING'
                    Reason = $_.Exception.Message
                }
            }
        }
        catch {
            [pscustomobject]@{
                Status = 'MISSING'
                Reason = $_.Exception.Message
            }
        }
    }
}

try {
    Import-Module FailoverClusters -ErrorAction Stop

    $ClusterNodes = Get-ClusterNode -Cluster $ClusterName |
        Where-Object { $_.State -eq 'Up' } |
        Select-Object -ExpandProperty Name
}
catch {
    Write-Host "Could not get cluster nodes. Falling back to local computer." -ForegroundColor Yellow
    $ClusterNodes = @($env:COMPUTERNAME)
}

$AllResults = @()
$MissingCounters = @()
$ExistingNoInstanceCounters = @()

foreach ($ComputerName in $ClusterNodes) {

    Write-Host ""
    Write-Host "Checking $ComputerName..." -ForegroundColor Cyan

    $ValidCounters = @()

    foreach ($Counter in $RequestedCounters) {
        $Result = Test-CounterPath -ComputerName $ComputerName -CounterPath $Counter

        switch ($Result.Status) {
            'FOUND' {
                $ValidCounters += $Counter
            }

            'FOUND-NOINSTANCE' {
                $ValidCounters += $Counter

                $ExistingNoInstanceCounters += [pscustomobject]@{
                    Node    = $ComputerName
                    Counter = $Counter
                    Status  = 'Exists, no active instance'
                    Reason  = $Result.Reason
                }
            }

            'MISSING' {
                $MissingCounters += [pscustomobject]@{
                    Node    = $ComputerName
                    Counter = $Counter
                    Reason  = $Result.Reason
                }
            }
        }
    }

    if (-not $ValidCounters) {
        $AllResults += [pscustomobject]@{
            Node              = $ComputerName
            HostCPUPercent    = $null
            AvailableMemoryGB = $null
            MaxVmNetMBps      = $null
            MaxReadLatencyMs  = $null
            MaxWriteLatencyMs = $null
            MaxInterruptPct   = $null
            MaxDpcPct         = $null
            Error             = 'No valid counters found'
        }

        continue
    }

    try {
        $Data = Get-Counter `
            -ComputerName $ComputerName `
            -Counter $ValidCounters `
            -SampleInterval 1 `
            -MaxSamples 1 `
            -ErrorAction Stop

        $Samples = $Data.CounterSamples

        $HostCPU = $Samples |
            Where-Object { $_.Path -match 'hyper-v hypervisor logical processor\(_total\).*% total run time' } |
            Select-Object -First 1

        $AvailMem = $Samples |
            Where-Object { $_.Path -match 'memory\\available mbytes' } |
            Select-Object -First 1

        $MaxReadLatency = $Samples |
            Where-Object { $_.Path -match 'physicaldisk.*avg\. disk sec/read' } |
            Measure-Object CookedValue -Maximum

        $MaxWriteLatency = $Samples |
            Where-Object { $_.Path -match 'physicaldisk.*avg\. disk sec/write' } |
            Measure-Object CookedValue -Maximum

        $MaxVmNet = $Samples |
            Where-Object { $_.Path -match 'hyper-v virtual network adapter.*bytes/sec' } |
            Measure-Object CookedValue -Maximum

        $MaxInterrupt = $Samples |
            Where-Object { $_.Path -match '% interrupt time' } |
            Measure-Object CookedValue -Maximum

        $MaxDpc = $Samples |
            Where-Object { $_.Path -match '% dpc time' } |
            Measure-Object CookedValue -Maximum

        $AllResults += [pscustomobject]@{
            Node              = $ComputerName
            HostCPUPercent    = if ($HostCPU) { [math]::Round($HostCPU.CookedValue, 1) } else { $null }
            AvailableMemoryGB = if ($AvailMem) { [math]::Round(($AvailMem.CookedValue / 1024), 1) } else { $null }
            MaxVmNetMBps      = if ($MaxVmNet.Count -gt 0) { [math]::Round(($MaxVmNet.Maximum / 1MB), 2) } else { $null }
            MaxReadLatencyMs  = if ($MaxReadLatency.Count -gt 0) { [math]::Round(($MaxReadLatency.Maximum * 1000), 2) } else { $null }
            MaxWriteLatencyMs = if ($MaxWriteLatency.Count -gt 0) { [math]::Round(($MaxWriteLatency.Maximum * 1000), 2) } else { $null }
            MaxInterruptPct   = if ($MaxInterrupt.Count -gt 0) { [math]::Round($MaxInterrupt.Maximum, 2) } else { $null }
            MaxDpcPct         = if ($MaxDpc.Count -gt 0) { [math]::Round($MaxDpc.Maximum, 2) } else { $null }
            Error             = $null
        }
    }
    catch {
        $AllResults += [pscustomobject]@{
            Node              = $ComputerName
            HostCPUPercent    = $null
            AvailableMemoryGB = $null
            MaxVmNetMBps      = $null
            MaxReadLatencyMs  = $null
            MaxWriteLatencyMs = $null
            MaxInterruptPct   = $null
            MaxDpcPct         = $null
            Error             = $_.Exception.Message
        }
    }
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " CLUSTER BOTTLENECK SUMMARY" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

$AllResults |
    Sort-Object Node |
    Format-Table `
        Node,
        HostCPUPercent,
        AvailableMemoryGB,
        MaxVmNetMBps,
        MaxReadLatencyMs,
        MaxWriteLatencyMs,
        MaxInterruptPct,
        MaxDpcPct,
        Error `
        -AutoSize

Write-Host ""
Write-Host "POTENTIAL ISSUES" -ForegroundColor Yellow
Write-Host "----------------"

$Issues = foreach ($Item in $AllResults) {

    if ($null -ne $Item.HostCPUPercent -and $Item.HostCPUPercent -ge 90) {
        [pscustomobject]@{
            Node  = $Item.Node
            Area  = 'CPU'
            Value = "$($Item.HostCPUPercent)%"
            Issue = 'Host CPU is above 90%'
        }
    }

    if ($null -ne $Item.AvailableMemoryGB -and $Item.AvailableMemoryGB -lt 2) {
        [pscustomobject]@{
            Node  = $Item.Node
            Area  = 'Memory'
            Value = "$($Item.AvailableMemoryGB) GB"
            Issue = 'Available memory below 2 GB'
        }
    }

    if ($null -ne $Item.MaxVmNetMBps -and $Item.MaxVmNetMBps -ge 250) {
        [pscustomobject]@{
            Node  = $Item.Node
            Area  = 'Network'
            Value = "$($Item.MaxVmNetMBps) MBps"
            Issue = 'VM network adapter above 250 MBps'
        }
    }

    if ($null -ne $Item.MaxReadLatencyMs -and $Item.MaxReadLatencyMs -gt 50) {
        [pscustomobject]@{
            Node  = $Item.Node
            Area  = 'Storage'
            Value = "$($Item.MaxReadLatencyMs) ms"
            Issue = 'Read latency above 50 ms'
        }
    }

    if ($null -ne $Item.MaxWriteLatencyMs -and $Item.MaxWriteLatencyMs -gt 50) {
        [pscustomobject]@{
            Node  = $Item.Node
            Area  = 'Storage'
            Value = "$($Item.MaxWriteLatencyMs) ms"
            Issue = 'Write latency above 50 ms'
        }
    }

    if ($null -ne $Item.MaxInterruptPct -and $Item.MaxInterruptPct -gt 20) {
        [pscustomobject]@{
            Node  = $Item.Node
            Area  = 'Interrupts'
            Value = "$($Item.MaxInterruptPct)%"
            Issue = 'High interrupt time'
        }
    }

    if ($null -ne $Item.MaxDpcPct -and $Item.MaxDpcPct -gt 20) {
        [pscustomobject]@{
            Node  = $Item.Node
            Area  = 'DPC'
            Value = "$($Item.MaxDpcPct)%"
            Issue = 'High DPC time'
        }
    }

    if ($Item.Error) {
        [pscustomobject]@{
            Node  = $Item.Node
            Area  = 'Collection'
            Value = 'Error'
            Issue = $Item.Error
        }
    }
}

if ($Issues) {
    $Issues | Format-Table Node, Area, Value, Issue -AutoSize -Wrap
}
else {
    Write-Host "No threshold-based issues detected." -ForegroundColor Green
}

if ($ExistingNoInstanceCounters) {
    Write-Host ""
    Write-Host "COUNTERS THAT EXIST BUT RETURNED NO ACTIVE INSTANCE" -ForegroundColor Yellow
    Write-Host "---------------------------------------------------"

    $ExistingNoInstanceCounters |
        Sort-Object Node, Counter |
        Format-Table Node, Counter, Status -Wrap -AutoSize
}

if ($MissingCounters) {
    Write-Host ""
    Write-Host "MISSING COUNTERS" -ForegroundColor Yellow
    Write-Host "----------------"

    $MissingCounters |
        Sort-Object Node, Counter |
        Format-Table Node, Counter, Reason -Wrap -AutoSize
}

Write-host "Ref: https://learn.microsoft.com/en-us/windows-server/administration/performance-tuning/role/hyper-v-server/detecting-virtualized-environment-bottlenecks"

}
