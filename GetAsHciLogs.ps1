    <#
    .Synopsis
       Invoke-GetAsHciLogs
    .DESCRIPTION
       This tool is used to collect Azure Stack HCI logs from all nodes in a cluster and bring them back to a single location
    .EXAMPLE
       Invoke-GetAsHciLogs
    #>
Function Invoke-GetAsHciLogs{
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High')]
        param($param)

Function EndScript{  
    break
}
# Logs
$DateTime=Get-Date -Format yyyyMMdd_HHmmss
Start-Transcript -NoClobber -Path "C:\programdata\Dell\AsHciLogs\AsHciLogs_$DateTime.log"
$Ver="1.0"
Clear-Host
$text = @"
v$Ver
   ___     _       _   ___ _  _  ___ ___   _                  
  / __|___| |_    /_\ / __| || |/ __|_ _| | |   ___  __ _ ___ 
 | (_ / -_)  _|  / _ \\__ \ __ | (__ | |  | |__/ _ \/ _` (_-< 
  \___\___|\__| /_/ \_\___/_||_|\___|___| |____\___/\__, /__/ 
                                                    |___/     
"@
Write-Host $text
Write-Host ""
# Run Menu
Function ShowMenu{
    do
     {
         $selection=""
         Clear-Host
         Write-Host $text
         Write-Host ""
         Write-Host "============ Please make a selection ==================="
         Write-Host ""
         Write-Host "Press '1' to Collect Show Tech-Support(s)"
         Write-Host "Press '2' to Collect Support Assist Collection(s)"
         Write-Host "Press '3' to Collect PrivateCloud.DiagnosticInfo (SDDC)"
         Write-Host "Press '4' to Collect All"
         Write-Host "Press 'H' to Display Help"
         Write-Host "Press 'Q' to Quit"
         Write-Host ""
         $selection = Read-Host "Please make a selection"
     }
    until ($selection -match '[1-4,qQ,hH]')
    $Global:CollectSTS  = "N"
    $Global:CollectSDDC = "N"
    $Global:CollectTSR  = "N"
    IF($selection -imatch 'h'){
        Clear-Host
        Write-Host ""
        Write-Host "What's New in"$Ver":"
        Write-Host $WhatsNew 
        Write-Host ""
        Write-Host "Useage:"
        Write-Host "    Make a select by entering a comma delimited string of numbers from the menu."
        Write-Host ""
        Write-Host "        Example: 1 will Collect Show Tech-Support(s) only and create a report."
        Write-Host "                 Show Tech-Support is a log collection from a Dell switch."
        Write-Host ""
        Write-Host "        Example: 1,3 will Collect Show Tech-Support(s) and "
        Write-Host "                     PrivateCloud.DiagnosticInfo (SDDC) and create a report."
        Write-Host ""
        Pause
        ShowMenu
    }
    IF($selection -match 1){
        Write-Host "Gathering Show Tech-Support(s)..."
        $Global:CollectSTS = "Y"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="GetShowTech";$repo="PowershellScripts"'+(new-object System.net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/GetShowTech.ps1'));Invoke-GetShowTech -confirm:$False

    }

    IF($selection -match 2){
        Write-Host "Collect Support Assist Collection(s)..."
        $Global:CollectTSR  = "Y"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="TSRCollector";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/TSRCollector.ps1'));Invoke-TSRCollector -confirm:$False

    }
    IF($selection -match 3){
        Write-Host "Collect PrivateCloud.DiagnosticInfo (SDDC)..."
        $Global:CollectSDDC = "Y"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="SDDC";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/RunSDDC.ps1'));Invoke-RunSDDC -confirm:$False

    }
    ElseIF($selection -eq 4){
        IF(Test-Path -Path "$((Get-Item $env:temp).fullname)\logs"){ Remove-Item "$((Get-Item $env:temp).fullname)\logs" -Recurse -Confirm:$false -Force}
        Write-Host "Collect Show Tech-Support(s) + Support Assist Collection(s) + PrivateCloud.DiagnosticInfo (SDDC)..."
        $Global:CollectSTS  = "Y"
        $Global:CollectSDDC = "Y"
        $Global:CollectTSR  = "Y"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="TSRCollector";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/TSRCollector.ps1'));Invoke-TSRCollector -LeaveShare:$True -confirm:$False
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="GetShowTech";$repo="PowershellScripts"'+(new-object System.net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/GetShowTech.ps1'));Invoke-GetShowTech -confirm:$False
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="SDDC";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/RunSDDC.ps1'));Invoke-RunSDDC -confirm:$False
        # Remove share
            Write-Host "Removing SMB share called Logs..."
            Remove-SmbShare -Name "Logs" -Force
        ZipNClean
    }
    IF($selection -imatch 'q'){
        Write-Host "Bye Bye..."
        EndScript
    }
}#End of ShowMenu
Function ZipNClean{
    # Zip up
        Write-Host "Compressing Azure Stack HCI Logs..."
        $MyTemp=(Get-Item $env:temp).fullname
        $DT=Get-Date -Format "yyyyMMddHHmm"
        IF(Test-Path -Path "$MyTemp\logs"){
            Compress-Archive -Path "$MyTemp\logs\*.*" -DestinationPath "c:\dell\AzHciLogs_$($DT)"
            IF(Test-Path -Path "c:\dell\AzHciLogs_$($DT)"){
                Write-Host "Logs can be found here: C:Dell\AzHciLogs_$($DT).zip"
                # Clean up
                Write-Host "Clean up..."
                Remove-Item "$MyTemp\logs" -Recurse -Confirm:$false -Force
                cd c:\dell
                Invoke-Expression "explorer ."
            }Else{
                Write-Host "ERROR: Failed to compress $MyTemp\logs." -ForegroundColor Red
                cd "$MyTemp\logs"
                Invoke-Expression "explorer ."
            }

        }

}
ShowMenu
}# End invoke-GetAsHciLogs
