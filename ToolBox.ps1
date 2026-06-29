<#
    .Synopsis
       ToolBox.ps1
    .DESCRIPTION
       This script is a menu to the other tools 
    .EXAMPLES
       Invoke-ToolBox
    .Created 
        By: Jim Gandy
#>
function EndScript {
    return
}

function Invoke-ToolBox {
    Clear-Host

    $Ver = '1.9'

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
        Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Internet Explorer\Main" `
            -Name "DisableFirstRunCustomize" -Value 2 -ErrorAction SilentlyContinue
    } catch {}

    # =====================================================
    # Tool Registry
    # Add new tools here only
    # =====================================================
    $script:ToolBoxTools = @(
        [pscustomobject]@{
            Name        = 'Convert-Etl2Pcap'
            Description = 'Convert ETL network traces to PCap.'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/Convert-Etl2Pcap.ps1'
            Module      = 'ETL2PCAP'
            Command     = 'Invoke-ETL2PCAP'
            Encoding    = 'UTF8'
        }
        [pscustomobject]@{
            Name        = 'Make ISO'
            Description = 'Convert a folder to ISO.'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/isomaker.ps1'
            Module      = 'MakeISO'
            Command     = 'Invoke-MakeISO'
            Encoding    = 'UTF8'
        } 
        [pscustomobject]@{
            Name        = 'GetHyperVBottlenecks'
            Description = 'This is a tool to detect bottlenecks in a Hyper-V environment.'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/refs/heads/main/GetHyperVBottlenecks.ps1'
            Module      = 'GetHyperVBottlenecks'
            Command     = 'Invoke-GetHyperVBottlenecks'
            Encoding    = 'UTF8'
        }                        
        [pscustomobject]@{
            Name        = 'KeyRelay'
            Description = 'GUI tool to send text to applications that do not allow pasting.'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/KeyRelay.ps1'
            Module      = 'KeyRelay'
            Command     = 'Invoke-KeyRelay'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'AzHCIUrlChkr'
            Description = 'AzL Url Enpoint Checker'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/AzHCIUrlChecker.ps1'
            Module      = 'AzHCIUrlChkr'
            Command     = 'Invoke-AzHCIUrlChecker'
            Encoding    = 'UTF8'
        }            
        [pscustomobject]@{
            Name        = 'iDRACMan'
            Description = 'simplified iDRAC access'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/refs/heads/main/iDRACCMan/iDRAC-ConnectionManager.ps1'
            Module      = 'iDRACMan'
            Command     = ''
            Encoding    = 'UTF8'
        }
        [pscustomobject]@{
            Name        = 'BOILER'
            Description = 'Finds Windows Update Errors'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/BOILER.ps1'
            Module      = 'BOILER'
            Command     = 'Invoke-BOILER'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'DART'
            Description = 'Installs Dell/MS Updates'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/DART.ps1'
            Module      = 'DART'
            Command     = 'Invoke-DART'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'FLEP'
            Description = 'Filters Event Logs'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/FLEP.ps1'
            Module      = 'FLEP'
            Command     = 'Invoke-FLEP'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'FLCkr'
            Description = 'Looks up Mini Filter Drivers'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/FLCkr.ps1'
            Module      = 'FLCkr'
            Command     = 'Invoke-FLCkr'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'LogCollector'
            Description = 'Make log collection easier'
            Internal    = $false
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/LogCollector.ps1'
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
            Encoding    = 'Default'
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

    $tempScript = Join-Path $env:TEMP ("ToolBox_{0}_{1}.ps1" -f $Tool.Name, ([guid]::NewGuid().Guid))

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

    `$code = '`$module="$($Tool.Module)";`$repo="PowershellScripts";'
    `$code += `$webClient.DownloadString('$($Tool.Url)')

    Invoke-Expression `$code

    `$cmd = '$($Tool.Command)'

    if (-not [string]::IsNullOrWhiteSpace(`$cmd)) {
        if (Get-Command `$cmd -ErrorAction SilentlyContinue) {
            & `$cmd
        }
        else {
            Write-Host ""
            Write-Host "ERROR: Command not found after loading tool: `$cmd" -ForegroundColor Red
        }
    }
}
catch {
    Write-Host ""
    Write-Host "ERROR running $($Tool.Name):" -ForegroundColor Red
    Write-Host `$_.Exception.Message -ForegroundColor Red
    Start-Sleep -Seconds 4
}
finally {
    try { Remove-Item '$tempScript' -Force -ErrorAction SilentlyContinue } catch {}
    exit
}
"@

    Set-Content -Path $tempScript -Value $childCode -Encoding UTF8

    Start-Process -FilePath $ps5 -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$tempScript`""
    )
}

    function ShowMenu {
        do {
            Clear-Host

            $tools = $script:ToolBoxTools | Sort-Object @{Expression={$_.Name.ToUpper()}}

            Write-Host $text
            Write-Host ""
            Write-Host "This code is under the MIT License. See Repository for Licensing/Support details."
            Write-Host ""
            Write-Host "==================== Please make a selection ====================="
            Write-Host ""

            $numberWidth = ($tools.Count.ToString()).Length
            $nameWidth   = (($tools | ForEach-Object { $_.Name.Length }) | Measure-Object -Maximum).Maximum

            for ($i = 0; $i -lt $tools.Count; $i++) {
                $tool = $tools[$i]
                $internalText = if ($tool.Internal) { ' ***INTERNAL ONLY***' } else { '' }

                Write-Host ("{0,$numberWidth})  {1,-$nameWidth} - {2}{3}" -f `
                    ($i + 1),
                    $tool.Name,
                    $tool.Description,
                    $internalText
                )
            }

            Write-Host ""
            Write-Host "H)  Help"
            Write-Host "Q)  Quit"
            Write-Host ""

            $selection = Read-Host "Type a number and press [Enter]"

            if ($selection -imatch '^q$') {
                Write-Host "Bye Bye..."
                return
            }

            if ($selection -imatch '^h$') {
                Clear-Host
                Write-Host ""
                Write-Host "What's New in v$Ver"
                Write-Host "  - Menu is now auto-generated from a tool registry."
                Write-Host "  - Adding tools no longer requires adding new IF blocks."
                Write-Host ""
                Write-Host "Usage:"
                Write-Host "  Make a selection by entering a number from the menu."
                Write-Host ""
                Write-Host "Example:"
                Write-Host "  1 will run the first sorted tool."
                Write-Host ""
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
                $Global:WindowsUpdates     = $false
                $Global:DriverandFirmware  = $false
                $Global:Confirm            = $false

                Invoke-ToolBoxDownload -Tool $selectedTool
                continue
            }
            else {
                Write-Host ""
                Write-Host "Invalid selection: $selection" -ForegroundColor Red
                Start-Sleep -Seconds 2
                continue
            }

        } while ($true)
    }

    ShowMenu
}