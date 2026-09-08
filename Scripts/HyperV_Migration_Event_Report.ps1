<#
.SYNOPSIS
    Creates a dual-host Hyper-V migration event HTML report.

.DESCRIPTION
    Pulls Warning, Error, and Critical events from all enabled event logs
    on a source and destination Hyper-V host for the last X minutes.

    Report includes:
      - Source/Destination host column
      - Errors/Critical in red
      - Warnings in yellow
      - Hyper-V / VMMS / WMI / WinRM / Cluster events highlighted
      - Search/filter box
      - Host filter
      - Level filter
      - Sortable columns
      - Full rendered message data

.EXAMPLE
    .\HyperV_Migration_Event_Report.ps1

.EXAMPLE
    .\HyperV_Migration_Event_Report.ps1 -Minutes 5

.EXAMPLE
    .\HyperV_Migration_Event_Report.ps1 -SourceHost WIN-1LL61BEGCHE -DestinationHost WIN-1CJ52FKUOIQ -Minutes 15

.Author
    Jim Gandy
#>

param(
    [int]$Minutes = 1,

    [string]$SourceHost = "WIN-1LL61BEGCHE",

    [string]$DestinationHost = "WIN-1CJ52FKUOIQ",

    [string]$OutFile = "C:\Dell\HyperV_Migration_Event_Report.html",

    [switch]$IncludeInformation
)

$ErrorActionPreference = "Continue"

$OutFolder = Split-Path -Path $OutFile -Parent

if (-not (Test-Path $OutFolder)) {
    New-Item -Path $OutFolder -ItemType Directory -Force | Out-Null
}

try {
    Add-Type -AssemblyName System.Web -ErrorAction Stop
}
catch {
    Write-Warning "Could not load System.Web. HTML encoding will use basic replacement."
}

function ConvertTo-SafeHtml {
    param(
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return "[No rendered message available]"
    }

    if ("System.Web.HttpUtility" -as [type]) {
        return ([System.Web.HttpUtility]::HtmlEncode($Text) `
            -replace "`r`n", "<br>" `
            -replace "`n", "<br>" `
            -replace "`r", "<br>")
    }
    else {
        return ($Text `
            -replace '&', '&amp;' `
            -replace '<', '&lt;' `
            -replace '>', '&gt;' `
            -replace '"', '&quot;' `
            -replace "'", '&#39;' `
            -replace "`r`n", "<br>" `
            -replace "`n", "<br>" `
            -replace "`r", "<br>")
    }
}

function Get-RemoteRecentEvents {
    param(
        [string]$ComputerName,
        [int]$Minutes,
        [bool]$IncludeInformation
    )

    $ScriptBlock = {
        param(
            [int]$Minutes,
            [bool]$IncludeInformation
        )

        $StartTime = (Get-Date).AddMinutes(-$Minutes)

        if ($IncludeInformation) {
            $Levels = @(1, 2, 3, 4)
        }
        else {
            $Levels = @(1, 2, 3)
        }

        Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IsEnabled -and $_.RecordCount -gt 0
        } |
        ForEach-Object {
            $LogName = $_.LogName

            try {
                Get-WinEvent -FilterHashtable @{
                    LogName   = $LogName
                    StartTime = $StartTime
                    Level     = $Levels
                } -ErrorAction Stop
            }
            catch {
                # Some logs are listed but not readable, or have provider issues.
            }
        } |
        ForEach-Object {
            [pscustomobject]@{
                HostName         = $env:COMPUTERNAME
                TimeCreated      = $_.TimeCreated
                LogName          = $_.LogName
                Id               = $_.Id
                LevelDisplayName = $_.LevelDisplayName
                Level            = $_.Level
                ProviderName     = $_.ProviderName
                MachineName      = $_.MachineName
                UserId           = if ($_.UserId) { $_.UserId.Value } else { "" }
                ProcessId        = $_.ProcessId
                ThreadId         = $_.ThreadId
                Message          = $_.Message
            }
        }
    }

    try {
        Invoke-Command -ComputerName $ComputerName -ScriptBlock $ScriptBlock -ArgumentList $Minutes, $IncludeInformation -ErrorAction Stop
    }
    catch {
        [pscustomobject]@{
            HostName         = $ComputerName
            TimeCreated      = Get-Date
            LogName          = "Collection"
            Id               = 0
            LevelDisplayName = "Error"
            Level            = 2
            ProviderName     = "Script"
            MachineName      = $ComputerName
            UserId           = ""
            ProcessId        = ""
            ThreadId         = ""
            Message          = "Failed to collect events from $ComputerName. $($_.Exception.Message)"
        }
    }
}

$Hosts = @($SourceHost, $DestinationHost)

Write-Host "Collecting event logs..." -ForegroundColor Cyan
Write-Host "Source Host:      $SourceHost" -ForegroundColor Cyan
Write-Host "Destination Host: $DestinationHost" -ForegroundColor Cyan
Write-Host "Time Window:      Last $Minutes minutes" -ForegroundColor Cyan

$RawEvents = foreach ($HostName in $Hosts) {
    Write-Host "Querying $HostName ..." -ForegroundColor Yellow

    Get-RemoteRecentEvents `
        -ComputerName $HostName `
        -Minutes $Minutes `
        -IncludeInformation ([bool]$IncludeInformation)
}

$RawEvents = @($RawEvents)

$TotalEvents = $RawEvents.Count
$ErrorCount = @($RawEvents | Where-Object { $_.LevelDisplayName -eq "Error" }).Count
$CriticalCount = @($RawEvents | Where-Object { $_.LevelDisplayName -eq "Critical" }).Count
$WarningCount = @($RawEvents | Where-Object { $_.LevelDisplayName -eq "Warning" }).Count

Write-Host "Events collected: $TotalEvents" -ForegroundColor Green

$Rows = foreach ($Event in $RawEvents | Sort-Object TimeCreated -Descending) {

    $Classes = @()

    switch ($Event.LevelDisplayName) {
        "Critical" { $Classes += "critical" }
        "Error"    { $Classes += "error" }
        "Warning"  { $Classes += "warning" }
        default    { $Classes += "info" }
    }

    if (
        $Event.ProviderName -match "Hyper-V|VMMS|Failover|Cluster|WMI|WinRM|Virtualization" -or
        $Event.LogName -match "Hyper-V|VMMS|Failover|Cluster|WMI|WinRM|Virtualization"
    ) {
        $Classes += "hyperv"
    }

    $ClassText = $Classes -join " "

    $HostValue     = ConvertTo-SafeHtml ([string]$Event.HostName)
    $TimeValue     = ConvertTo-SafeHtml ([string]$Event.TimeCreated)
    $LevelValue    = ConvertTo-SafeHtml ([string]$Event.LevelDisplayName)
    $LogValue      = ConvertTo-SafeHtml ([string]$Event.LogName)
    $IdValue       = ConvertTo-SafeHtml ([string]$Event.Id)
    $ProviderValue = ConvertTo-SafeHtml ([string]$Event.ProviderName)
    $MachineValue  = ConvertTo-SafeHtml ([string]$Event.MachineName)
    $ProcessValue  = ConvertTo-SafeHtml ([string]$Event.ProcessId)
    $ThreadValue   = ConvertTo-SafeHtml ([string]$Event.ThreadId)
    $MessageValue  = ConvertTo-SafeHtml ([string]$Event.Message)

@"
<tr class="$ClassText">
<td>$HostValue</td>
<td>$TimeValue</td>
<td>$LevelValue</td>
<td>$LogValue</td>
<td>$IdValue</td>
<td>$ProviderValue</td>
<td>$MachineValue</td>
<td>$ProcessValue</td>
<td>$ThreadValue</td>
<td class="message">$MessageValue</td>
</tr>
"@
}

$Generated = Get-Date

$Html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Hyper-V Migration Event Report</title>
<style>
body {
    font-family: Segoe UI, Arial, sans-serif;
    margin: 20px;
    background: #f4f6f8;
    color: #222;
}
h1 {
    margin-bottom: 5px;
}
.summary {
    background: #ffffff;
    border: 1px solid #d0d7de;
    padding: 12px;
    margin-bottom: 14px;
    border-radius: 6px;
}
.controls {
    background: #ffffff;
    border: 1px solid #d0d7de;
    padding: 10px;
    margin-bottom: 14px;
    border-radius: 6px;
}
input, select, button {
    padding: 8px;
    margin-right: 8px;
    margin-bottom: 8px;
    font-size: 14px;
}
#filterInput {
    width: 520px;
}
table {
    border-collapse: collapse;
    width: 100%;
    background: #ffffff;
    font-size: 13px;
}
th {
    background: #2f3640;
    color: white;
    padding: 8px;
    cursor: pointer;
    position: sticky;
    top: 0;
    z-index: 2;
    text-align: left;
}
td {
    border: 1px solid #ddd;
    padding: 8px;
    vertical-align: top;
}
tr:nth-child(even) {
    background: #fafafa;
}
tr.critical {
    background: #ffb3b3 !important;
}
tr.error {
    background: #ffd6d6 !important;
}
tr.warning {
    background: #fff3bf !important;
}
tr.info {
    background: #ffffff;
}
tr.hyperv {
    border-left: 6px solid #0078D4;
}
.message {
    max-width: 1300px;
    word-break: break-word;
    white-space: normal;
}
.small {
    font-size: 12px;
    color: #555;
}
.badge {
    display: inline-block;
    padding: 2px 6px;
    border-radius: 4px;
    font-weight: 600;
    margin-right: 4px;
}
.badge-error {
    background: #ffd6d6;
}
.badge-warning {
    background: #fff3bf;
}
.badge-hyperv {
    background: #d7ebff;
}
.counts {
    margin-top: 8px;
}
</style>
</head>
<body>

<h1>Hyper-V Migration Event Report</h1>

<div class="summary">
<b>Source Host:</b> $SourceHost<br>
<b>Destination Host:</b> $DestinationHost<br>
<b>Time Window:</b> Last $Minutes minutes<br>
<b>Generated:</b> $Generated<br>

<div class="counts">
<b>Total Events:</b> $TotalEvents<br>
<b>Critical:</b> $CriticalCount<br>
<b>Errors:</b> $ErrorCount<br>
<b>Warnings:</b> $WarningCount<br>
</div>

<br>
<span class="small">
<span class="badge badge-error">Red</span> Error/Critical
<span class="badge badge-warning">Yellow</span> Warning
<span class="badge badge-hyperv">Blue border</span> Hyper-V / VMMS / WMI / WinRM / Cluster related
</span>
</div>

<div class="controls">
<input type="text" id="filterInput" onkeyup="filterTable()" placeholder="Search host, log, provider, ID, message, level...">

<select id="levelFilter" onchange="filterTable()">
    <option value="">All Levels</option>
    <option value="critical">Critical</option>
    <option value="error">Error</option>
    <option value="warning">Warning</option>
    <option value="information">Information</option>
    <option value="verbose">Verbose</option>
</select>

<select id="hostFilter" onchange="filterTable()">
    <option value="">All Hosts</option>
    <option value="$SourceHost">$SourceHost</option>
    <option value="$DestinationHost">$DestinationHost</option>
</select>

<button onclick="clearFilters()">Clear Filters</button>
</div>

<table id="eventTable">
<thead>
<tr>
<th onclick="sortTable(0)">Host</th>
<th onclick="sortTable(1)">TimeCreated</th>
<th onclick="sortTable(2)">Level</th>
<th onclick="sortTable(3)">LogName</th>
<th onclick="sortTable(4)">Event ID</th>
<th onclick="sortTable(5)">Provider</th>
<th onclick="sortTable(6)">Machine</th>
<th onclick="sortTable(7)">ProcessId</th>
<th onclick="sortTable(8)">ThreadId</th>
<th onclick="sortTable(9)">Message</th>
</tr>
</thead>
<tbody>
$Rows
</tbody>
</table>

<script>
function filterTable() {
    const textFilter = document.getElementById("filterInput").value.toLowerCase();
    const levelFilter = document.getElementById("levelFilter").value.toLowerCase();
    const hostFilter = document.getElementById("hostFilter").value.toLowerCase();

    const rows = document.getElementById("eventTable").tBodies[0].rows;

    for (let row of rows) {
        const rowText = row.innerText.toLowerCase();
        const host = row.cells[0].innerText.toLowerCase();
        const level = row.cells[2].innerText.toLowerCase();

        const textMatch = rowText.includes(textFilter);
        const levelMatch = levelFilter === "" || level === levelFilter;
        const hostMatch = hostFilter === "" || host === hostFilter;

        row.style.display = (textMatch && levelMatch && hostMatch) ? "" : "none";
    }
}

function clearFilters() {
    document.getElementById("filterInput").value = "";
    document.getElementById("levelFilter").value = "";
    document.getElementById("hostFilter").value = "";
    filterTable();
}

function sortTable(n) {
    const table = document.getElementById("eventTable");
    const tbody = table.tBodies[0];
    const rows = Array.from(tbody.rows);

    const asc = table.dataset.sortCol != n || table.dataset.sortDir === "desc";

    rows.sort(function(a, b) {
        let x = a.cells[n].innerText.trim();
        let y = b.cells[n].innerText.trim();

        if (n === 1) {
            x = new Date(x);
            y = new Date(y);
        }
        else if (n === 4 || n === 7 || n === 8) {
            x = parseInt(x) || 0;
            y = parseInt(y) || 0;
        }
        else {
            x = x.toLowerCase();
            y = y.toLowerCase();
        }

        if (x < y) return asc ? -1 : 1;
        if (x > y) return asc ? 1 : -1;
        return 0;
    });

    rows.forEach(function(row) {
        tbody.appendChild(row);
    });

    table.dataset.sortCol = n;
    table.dataset.sortDir = asc ? "asc" : "desc";
}
</script>

</body>
</html>
"@

$Html | Out-File $OutFile -Encoding UTF8

Write-Host "Report written to: $OutFile" -ForegroundColor Green

Start-Process $OutFile