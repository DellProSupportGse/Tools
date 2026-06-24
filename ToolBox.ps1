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

    $Ver = '1.3'

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
            Name        = 'KeyRelay'
            Description = 'Finds Windows Update Errors'
            Internal    = $false
            SortOrder   = 10
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/KeyRelay.ps1'
            Module      = 'KeyRelay'
            Command     = 'Invoke-KeyRelay'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'iDRACMan'
            Description = 'Finds Windows Update Errors'
            Internal    = $false
            SortOrder   = 10
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/refs/heads/main/iDRACCMan/iDRAC-ConnectionManager.ps1'
            Module      = 'iDRACMan'
            Command     = ''
            Encoding    = 'UTF8'
        }
        [pscustomobject]@{
            Name        = 'BOILER'
            Description = 'Finds Windows Update Errors'
            Internal    = $false
            SortOrder   = 10
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/BOILER.ps1'
            Module      = 'BOILER'
            Command     = 'Invoke-BOILER'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'DART'
            Description = 'Installs Dell/MS Updates'
            Internal    = $false
            SortOrder   = 20
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/DART.ps1'
            Module      = 'DART'
            Command     = 'Invoke-DART'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'FLEP'
            Description = 'Filters Event Logs'
            Internal    = $false
            SortOrder   = 30
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/FLEP.ps1'
            Module      = 'FLEP'
            Command     = 'Invoke-FLEP'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'FLCkr'
            Description = 'Looks up Mini Filter Drivers'
            Internal    = $false
            SortOrder   = 40
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/FLCkr.ps1'
            Module      = 'FLCkr'
            Command     = 'Invoke-FLCkr'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'LogCollector'
            Description = 'Make log collection easier'
            Internal    = $false
            SortOrder   = 50
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/main/LogCollector.ps1'
            Module      = 'LogCollector'
            Command     = 'Invoke-LogCollector'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'CluChk'
            Description = 'Cluster Checker'
            Internal    = $true
            SortOrder   = 60
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/source/main/cluchk.ps1'
            Module      = 'RunCluChk'
            Command     = 'Invoke-RunCluChk'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'DriFT'
            Description = 'Driver and Firmware Tool'
            Internal    = $true
            SortOrder   = 70
            Url         = 'https://raw.githubusercontent.com/DellProSupportGse/source/main/drift.ps1'
            Module      = 'RunDriFT'
            Command     = 'Invoke-RunDriFT'
            Encoding    = 'Default'
        }
        [pscustomobject]@{
            Name        = 'SLIC'
            Description = 'Switch Log InspeCtor'
            Internal    = $true
            SortOrder   = 80
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

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        if ($Tool.Encoding -eq 'UTF8') {
            $webClient = New-Object Net.WebClient
            $webClient.Encoding = [System.Text.Encoding]::UTF8
        }
        else {
            $webClient = New-Object Net.WebClient
        }

        $code = '$module="{0}";$repo="PowershellScripts"' -f $Tool.Module
        $code += $webClient.DownloadString($Tool.Url)

        Invoke-Expression $code

        if (Get-Command $Tool.Command -ErrorAction SilentlyContinue) {
            & $Tool.Command
        }
        else {
            Write-Host ""
            Write-Host "ERROR: Command not found after loading tool: $($Tool.Command)" -ForegroundColor Red
            Pause
        }
    }

    function ShowMenu {
        do {
            Clear-Host

            $tools = $script:ToolBoxTools | Sort-Object SortOrder, Name

            Write-Host $text
            Write-Host ""
            Write-Host "This code is under the MIT License. See Repository for Licensing/Support details."
            Write-Host ""
            Write-Host "==================== Please make a selection ====================="
            Write-Host ""

            for ($i = 0; $i -lt $tools.Count; $i++) {
                $tool = $tools[$i]
                $internalText = if ($tool.Internal) { ' ***INTERNAL ONLY***' } else { '' }

                Write-Host ("{0})  {1,-12} - {2}{3}" -f ($i + 1), $tool.Name, $tool.Description, $internalText)
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
                Write-Host "  - Tools can be sorted with SortOrder."
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

            if ($selection -match '^\d+$') {
                $index = [int]$selection - 1

                if ($index -ge 0 -and $index -lt $tools.Count) {
                    $Global:WindowsUpdates     = $false
                    $Global:DriverandFirmware  = $false
                    $Global:Confirm            = $false

                    Invoke-ToolBoxDownload -Tool $tools[$index]
                    Pause
                }
            }

        } while ($true)
    }

    ShowMenu
}
