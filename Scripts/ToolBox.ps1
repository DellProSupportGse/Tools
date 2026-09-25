<#
    .Synopsis
       ToolBox.ps1
    .DESCRIPTION
       This script is a menu to the other tools
    .EXAMPLES
       Invoke-ToolBox
       Invoke-ToolBox -NoTelemetry
       Invoke-ToolBox -DebugTelemetry
    .Created
        By: Jim Gandy
#>

function EndScript {
    return
}

# =====================================================
# ToolBox Telemetry
# =====================================================
$script:ToolBoxTelemetryReportID    = [guid]::NewGuid().Guid
$script:ToolBoxTelemetryGeoResolved = $false
$script:ToolBoxTelemetryGeoData     = @{}

function Get-ToolBoxTelemetryMachineHash {
    try {
        $raw = "$env:USERDOMAIN\$env:USERNAME@$env:COMPUTERNAME"
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
            $hash = $sha.ComputeHash($bytes)
            return ([BitConverter]::ToString($hash)).Replace('-', '').Substring(0, 24)
        }
        finally {
            if ($sha) { $sha.Dispose() }
        }
    }
    catch {
        return ''
    }
}

function Resolve-ToolBoxTelemetryGeo {
    try {
        if ($script:ToolBoxTelemetryGeoResolved) { return }

        if (-not $global:GeoCache) {
            $global:GeoCache = Invoke-RestMethod -Uri 'https://ipwho.is/' -TimeoutSec 5 -ErrorAction Stop
        }

        $response = $global:GeoCache
        if ($response.success -eq $true) {
            $script:ToolBoxTelemetryGeoData = @{
                country     = [string]$response.country
                countryCode = [string]$response.country_code
                region      = [string]$response.region
                city        = [string]$response.city
                latitude    = [string]$response.latitude
                longitude   = [string]$response.longitude
                timezone    = [string]$response.timezone.id
            }
        }
        else {
            throw 'Geo lookup did not return success.'
        }
    }
    catch {
        try {
            $localRegion = [System.Globalization.RegionInfo]::CurrentRegion
            $script:ToolBoxTelemetryGeoData = @{
                country     = [string]$localRegion.EnglishName
                countryCode = [string]$localRegion.TwoLetterISORegionName
                region      = $null
                city        = $null
                latitude    = $null
                longitude   = $null
                timezone    = [string](Get-TimeZone).Id
            }
        }
        catch {
            $script:ToolBoxTelemetryGeoData = @{}
        }
    }
    finally {
        $script:ToolBoxTelemetryGeoResolved = $true
    }
}

function Send-ToolBoxTelemetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Module,

        [Parameter(Mandatory)]
        [string]$Version,

        [switch]$DebugTelemetry
    )

    # Module is intentionally derived from Tool.Name, not the menu number or
    # the registry's launcher Module value. This keeps telemetry stable when
    # tools are added/reordered. Example: 'Make ISO' -> 'MakeISO'.
    $telemetryModule = ($Module -replace '\s+', '')

    try {
        Resolve-ToolBoxTelemetryGeo

        $data = [ordered]@{
            PartitionKey = 'ToolBox'
            RowKey       = [guid]::NewGuid().Guid
            PSVersion    = $PSVersionTable.PSVersion.ToString()
            Region       = $script:ToolBoxTelemetryGeoData.region
            countryCode  = $script:ToolBoxTelemetryGeoData.countryCode
            lon          = $script:ToolBoxTelemetryGeoData.longitude
            MachineHash  = Get-ToolBoxTelemetryMachineHash
            geoRegion    = $script:ToolBoxTelemetryGeoData.region
            lat          = $script:ToolBoxTelemetryGeoData.latitude
            Version      = $Version
            timezone     = $script:ToolBoxTelemetryGeoData.timezone
            ReportID     = $script:ToolBoxTelemetryReportID
            city         = $script:ToolBoxTelemetryGeoData.city
            country      = $script:ToolBoxTelemetryGeoData.country
            Module       = $telemetryModule
        }

        $payload = @{
            TelemetryName = 'ToolBoxTelemetryData'
            TableName     = 'ToolBoxTelemetryData'
            Data          = $data
        }

        $body = $payload | ConvertTo-Json -Depth 10

        if ($DebugTelemetry) {
            Write-Host ''
            Write-Host 'ToolBox Telemetry Request:' -ForegroundColor Cyan
            Write-Host $body
        }

        $response = Invoke-RestMethod `
            -Method Post `
            -Uri 'https://gsetools-bufhdqefb8e6ecc6.centralus-01.azurewebsites.net/api/PostTelemetryData' `
            -ContentType 'application/json' `
            -Body $body `
            -TimeoutSec 15 `
            -ErrorAction Stop

        if ($DebugTelemetry) {
            Write-Host 'ToolBox Telemetry Response:' -ForegroundColor Green
            $response | ConvertTo-Json -Depth 10 | Write-Host
        }
    }
    catch {
        # Telemetry must never prevent ToolBox or a selected tool from running.
        if ($DebugTelemetry) {
            Write-Warning "ToolBox telemetry failed: $($_.Exception.Message)"
            if ($_.ErrorDetails.Message) {
                Write-Warning $_.ErrorDetails.Message
            }
        }
    }
}

function Invoke-ToolBox {
    [CmdletBinding()]
    param(
        [switch]$NoTelemetry,
        [switch]$DebugTelemetry
    )

    Clear-Host

    $Ver = '1.94'

    $text = @"
v$Ver
  _____         _   ___
 |_   _|__  ___| | | _ ) _____ __
   | |/ _ \/ _ \ | | _ \/ _ \ \ /
   |_|\___/\___/_| |___/\___/_\_\

                      by: Jim Gandy
"@

    # IE Fix
    try {
        Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Internet Explorer\Main' `
            -Name 'DisableFirstRunCustomize' -Value 2 -ErrorAction SilentlyContinue
    }
    catch {}

    # =====================================================
    # Tool Registry
    # Add new tools here only
    # =====================================================
    $script:ToolBoxTools = @(
        [pscustomobject]@{
            Name        = 'Convert-Etl2Pcap'
            Description = 'Convert ETL network traces to PCap.'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/Scripts/Convert-Etl2Pcap.ps1'
            Module      = 'ETL2PCAP'
            Command     = 'Invoke-ETL2PCAP'
            Encoding    = 'UTF8'
        }
        [pscustomobject]@{
            Name        = 'Make ISO'
            Description = 'Convert a folder to ISO.'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/Scripts/isomaker.ps1'
            Module      = 'MakeISO'
            Command     = 'Invoke-MakeISO'
            Encoding    = 'UTF8'
        }
        [pscustomobject]@{
            Name        = 'GetHyperVBottlenecks'
            Description = 'This is a tool to detect bottlenecks in a Hyper-V environment.'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/Scripts/GetHyperVBottlenecks.ps1'
            Module      = 'GetHyperVBottlenecks'
            Command     = 'Invoke-GetHyperVBottlenecks'
            Encoding    = 'UTF8'
        }
        [pscustomobject]@{
            Name        = 'KeyRelay'
            Description = 'GUI tool to send text to applications that do not allow pasting.'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/Scripts/KeyRelay.ps1'
            Module      = 'KeyRelay'
            Command     = 'Invoke-KeyRelay'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'AzHCIUrlChkr'
            Description = 'AzL Url Enpoint Checker'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/Scripts/AzHCIUrlChecker.ps1'
            Module      = 'AzHCIUrlChkr'
            Command     = 'Invoke-AzHCIUrlChecker'
            Encoding    = 'UTF8'
        }
        [pscustomobject]@{
            Name        = 'iDRACMan'
            Description = 'simplified iDRAC access'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/Scripts/iDRACCMan/iDRAC-ConnectionManager.ps1'
            Module      = 'iDRACMan'
            Command     = ''
            Encoding    = 'UTF8'
        }
        [pscustomobject]@{
            Name        = 'BOILER'
            Description = 'Finds Windows Update Errors'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/Scripts/BOILER.ps1'
            Module      = 'BOILER'
            Command     = 'Invoke-BOILER'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'DART'
            Description = 'Installs Dell/MS Updates'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/Scripts/DART.ps1'
            Module      = 'DART'
            Command     = 'Invoke-DART'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'FLEP'
            Description = 'Filters Event Logs'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/Scripts/FLEP.ps1'
            Module      = 'FLEP'
            Command     = 'Invoke-FLEP'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'FLCkr'
            Description = 'Looks up Mini Filter Drivers'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/Scripts/FLCkr.ps1'
            Module      = 'FLCkr'
            Command     = 'Invoke-FLCkr'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'LogCollector'
            Description = 'Make log collection easier'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/Scripts/LogCollector.ps1'
            Module      = 'LogCollector'
            Command     = 'Invoke-LogCollector'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'CluChk'
            Description = 'Cluster Checker'
            Internal    = $true
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/source/main/cluchk.ps1'
            Module      = 'RunCluChk'
            Command     = 'Invoke-RunCluChk'
            Encoding    = 'UTF8'
        }
        [pscustomobject]@{
            Name        = 'DriFT'
            Description = 'Driver and Firmware Tool'
            Internal    = $true
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/source/main/drift.ps1'
            Module      = 'RunDriFT'
            Command     = 'Invoke-RunDriFT'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'SLIC'
            Description = 'Switch Log InspeCtor'
            Internal    = $true
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/source/main/slic.ps1'
            Module      = 'RunSLIC'
            Command     = 'Invoke-SLIC'
            Encoding    = 'UTF8'
        }
    )

    function Invoke-ToolBoxDownload {
        param(
            [Parameter(Mandatory)]
            [pscustomobject]$Tool
        )

        $ps5 = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
        $safeToolName = $Tool.Name -replace '[^\w.-]', '_'
        $tempScript = Join-Path $env:TEMP (
            'ToolBox_{0}_{1}.ps1' -f $safeToolName, ([guid]::NewGuid().Guid)
        )

        if ($Tool.Name -eq 'CluChk' -or $Tool.Name -eq 'LogCollector') {
            $childCode = @"
`$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ('$($Tool.Encoding)' -eq 'UTF8') {
    `$webClient = New-Object Net.WebClient
    `$webClient.Encoding = [System.Text.Encoding]::UTF8
}
else {
    `$webClient = New-Object Net.WebClient
}

# Set variables separately so the downloaded script remains unchanged.
# This allows a script-level param() block to remain the first statement.
`$module = '$($Tool.Module)'
`$repo   = 'PowershellScripts'

`$code = `$webClient.DownloadString('$($Tool.Url)')
Invoke-Expression `$code

`$cmd = '$($Tool.Command)'
if (-not [string]::IsNullOrWhiteSpace(`$cmd)) {
    if (Get-Command `$cmd -ErrorAction SilentlyContinue) {
        & `$cmd
    }
    else {
        Write-Host ''
        Write-Host "ERROR: Command not found after loading tool: `$cmd" -ForegroundColor Red
    }
}

if (`$null -ne `$webClient) {
    try { `$webClient.Dispose() } catch {}
}

try {
    Remove-Item -LiteralPath '$tempScript' -Force -ErrorAction SilentlyContinue
}
catch {}

exit
"@
        }
        else {
            $childCode = @"
`$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    if ('$($Tool.Encoding)' -eq 'UTF8') {
        `$webClient = New-Object Net.WebClient
        `$webClient.Encoding = [System.Text.Encoding]::UTF8
    }
    else {
        `$webClient = New-Object Net.WebClient
    }

    # Set variables separately so the downloaded script remains unchanged.
    # This allows a script-level param() block to remain the first statement.
    `$module = '$($Tool.Module)'
    `$repo   = 'PowershellScripts'

    `$code = `$webClient.DownloadString('$($Tool.Url)')
    Invoke-Expression `$code

    `$cmd = '$($Tool.Command)'
    if (-not [string]::IsNullOrWhiteSpace(`$cmd)) {
        if (Get-Command `$cmd -ErrorAction SilentlyContinue) {
            & `$cmd
        }
        else {
            Write-Host ''
            Write-Host "ERROR: Command not found after loading tool: `$cmd" -ForegroundColor Red
        }
    }
}
catch {
    Write-Host ''
    Write-Host 'ERROR running $($Tool.Name):' -ForegroundColor Red
    Write-Host `$_.Exception.Message -ForegroundColor Red
    Start-Sleep -Seconds 4
}
finally {
    if (`$null -ne `$webClient) {
        try { `$webClient.Dispose() } catch {}
    }
    try {
        Remove-Item -LiteralPath '$tempScript' -Force -ErrorAction SilentlyContinue
    }
    catch {}

    exit
}
"@
        }

        try {
            Set-Content `
                -LiteralPath $tempScript `
                -Value $childCode `
                -Encoding UTF8 `
                -ErrorAction Stop

            Start-Process -FilePath $ps5 -ArgumentList @(
                '-NoProfile'
                '-ExecutionPolicy'
                'Bypass'
                '-File'
                "`"$tempScript`""
            ) -ErrorAction Stop

            # Record telemetry only after Windows successfully starts the child process.
            # IMPORTANT: derive Module from Name, not menu number and not Tool.Module.
            if (-not $NoTelemetry) {
                Send-ToolBoxTelemetry `
                    -Module $Tool.Name `
                    -Version $Ver `
                    -DebugTelemetry:$DebugTelemetry
            }
        }
        catch {
            Write-Host ''
            Write-Host "ERROR starting $($Tool.Name):" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
            try {
                Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
            }
            catch {}
        }
    }

    function ShowMenu {
        do {
            Clear-Host

            $tools = $script:ToolBoxTools | Sort-Object @{Expression = { $_.Name.ToUpper() }}
            Write-Host $text
            Write-Host ''
            Write-Host 'This code is under the MIT License. See Repository for Licensing/Support details.'
            Write-Host ''
            Write-Host '==================== Please make a selection ====================='
            Write-Host ''

            $numberWidth = ($tools.Count.ToString()).Length
            $nameWidth   = (($tools | ForEach-Object { $_.Name.Length }) | Measure-Object -Maximum).Maximum

            for ($i = 0; $i -lt $tools.Count; $i++) {
                $tool = $tools[$i]
                $internalText = if ($tool.Internal) { ' ***INTERNAL ONLY***' } else { '' }

                $menuNumber = ([string]($i + 1)).PadLeft($numberWidth)
                $menuName   = ([string]$tool.Name).PadRight($nameWidth)
                Write-Host ("{0})  {1} - {2}{3}" -f `
                    $menuNumber,
                    $menuName,
                    $tool.Description,
                    $internalText
                )
            }

            Write-Host ''
            Write-Host 'H)  Help'
            Write-Host 'Q)  Quit'
            Write-Host ''

            $selection = Read-Host 'Type a number and press [Enter]'

            if ($selection -imatch '^q$') {
                Write-Host 'Bye Bye...'
                return
            }

            if ($selection -imatch '^h$') {
                Clear-Host
                Write-Host ''
                Write-Host "What's New in v$Ver"
                Write-Host '  - Added ToolBox launch telemetry by stable tool/module name.'
                Write-Host '  - Telemetry Module is derived from the tool Name with spaces removed.'
                Write-Host '  - Menu remains auto-generated from the tool registry.'
                Write-Host ''
                Write-Host 'Usage:'
                Write-Host '  Make a selection by entering a number from the menu.'
                Write-Host ''
                Write-Host 'Example:'
                Write-Host '  1 will run the first sorted tool.'
                Write-Host ''
                Pause
                continue
            }

            # Number selection
            $selectedTool = $null

            if ($selection -match '^\d+$') {
                $index = [int]$selection - 1
                if ($index -ge 0 -and $index -lt $tools.Count) {
                    $selectedTool = $tools[$index]
                }
            }
            else {
                # Name selection
                $selectedTool = $tools | Where-Object {
                    $_.Name -ieq $selection
                } | Select-Object -First 1
            }

            if ($selectedTool) {
                $Global:WindowsUpdates    = $false
                $Global:DriverandFirmware = $false
                $Global:Confirm           = $false

                Invoke-ToolBoxDownload -Tool $selectedTool
                continue
            }
            else {
                Write-Host ''
                Write-Host "Invalid selection: $selection" -ForegroundColor Red
                Start-Sleep -Seconds 2
                continue
            }
        } while ($true)
    }

    ShowMenu
}
