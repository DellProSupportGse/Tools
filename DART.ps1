    <#
    .Synopsis
    .DESCRIPTION
       This script will install Windows updates and Dell Drivers and Firmware on a single node
    .EXAMPLES
       Install Windows Updates, Drivers and Firmware:
            Invoke-DART -WindowsUpdates:$True -DriverandFirmware:$True
       Install Driver and Firmware Only:
            Invoke-DART -WindowsUpdates:$False -DriverandFirmware:$True
       Install Windows Updates Only:
            Invoke-DART -WindowsUpdates:$True -DriverandFirmware:$False
       Fully Automated
            Invoke-DART -WindowsUpdates:$True -DriverandFirmware:$True -Confirm:$false
    #>
    
Function Invoke-DART {

    param(
    [Parameter(Mandatory=$False, Position=1)]
    [bool] $IgnoreChecks,
    $param)

$DateTime=Get-Date -Format yyyyMMdd_HHmmss
Start-Transcript -NoClobber -Path "C:\programdata\Dell\DART\DART_$DateTime.log"

Function EndScript{ 
    Stop-Transcript
    break
}

$text=@"
v1.1
 __        __  ___ 
|  \  /\  |__)  |  
|__/ /~~\ |  \  |  
"@
# Run Menu
Function ShowMenu{
    do
     {
         $selection=""
         Clear-Host
         Write-Host $text
         Write-Host ""
<<<<<<< HEAD
         Write-Host "================== Please make a selection ==================="
         Write-Host ""
         Write-Host "Press '1' to Install Windows Updates"
         Write-Host "Press '2' to Install Dell Drivers and Firmware"
         Write-Host "Press '3' to Install Windows Updates and Dell Drv&Fw"
         Write-Host "Press 'H' to Display Help"
         Write-Host "Press 'Q' to Quit"
         Write-Host ""
         $selection = Read-Host "Please make a selection"
     }
    until ($selection -match '[1-4,qQ,hH]')
=======
         Write-Host "This code is provided as-is and is not supported by Dell Technologies"
         Write-Host ""
         Write-Host "==================== Please make a selection ====================="
         Write-Host ""
         Write-Host "Press '1' to Install Windows Updates"
         Write-Host "Press '2' to Install Dell Drivers and Firmware"
         Write-Host "Press '3' to Install Windows Updates and Dell Drivers and Firmware"
         Write-Host "Press 'H' to Display Help"
         Write-Host "Press 'Q' to Quit"
         Write-Host ""
         $selection = Read-Host "Please make a selection"
     }
    until ($selection -match '[1-3,qQ,hH]')
    $Global:WindowsUpdates=$False
    $Global:DriverandFirmware=$False
    $Global:Confirm=$False
>>>>>>> 948bcffa311ab3dd907e7b7e705ee27756e5dac8
    IF($selection -imatch 'h'){
        Clear-Host
        Write-Host ""
        Write-Host "What's New in"$Ver":"
        Write-Host $WhatsNew 
        Write-Host ""
        Write-Host "Useage:"
        Write-Host "    Make a select by entering a comma delimited string of numbers from the menu."
        Write-Host ""
        Write-Host "        Example: 1 will Install Windows Updates."
        Write-Host ""
<<<<<<< HEAD
        Write-Host "        Example: 1,3 will Install Windows Updates and Install CPLD"
=======
        Write-Host "        Example: 2 will Install Dell Drivers and Firmware"
>>>>>>> 948bcffa311ab3dd907e7b7e705ee27756e5dac8
        Write-Host ""
        Pause
        ShowMenu
    }
    IF($selection -match 1){
        Write-Host "Installing Windows Updates..."
<<<<<<< HEAD
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="DART";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/DART.ps1'));Invoke-DART -WindowsUpdates:$True -DriverandFirmware:$False -Confirm:$false
    }

    IF($selection -match 2){
        Write-Host "Installing Dell Drivers and Firmware..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="DART";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/DART.ps1'));Invoke-DART -WindowsUpdates:$False -DriverandFirmware:$True -Confirm:$false
    }
    IF($selection -match 3){
        Write-Host "Installing Windows Updates and Dell Drivers and Firmware..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="DART";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/DART.ps1'));Invoke-DART -WindowsUpdates:$True -DriverandFirmware:$True -Confirm:$false
    }
    ElseIF($selection -eq 4){
        Write-Host "Installing CPLD..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="DART";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/DART.ps1'));Invoke-DART -CPLD:$True -Confirm:$false

    }
    IF($selection -imatch 'q'){
        Write-Host "Bye Bye..."
        EndScript
    }
}#End of ShowMenu
ShowMenu
if ($PSCmdlet.ShouldProcess($param)) { 
=======
        $Global:WindowsUpdates=$True
        $Global:DriverandFirmware=$False
        $Global:Confirm=$false
    }
>>>>>>> 948bcffa311ab3dd907e7b7e705ee27756e5dac8

    IF($selection -match 2){
        Write-Host "Installing Dell Drivers and Firmware..."
        $Global:WindowsUpdates=$False
        $Global:DriverandFirmware=$True
        $Global:Confirm=$false
    }
    IF($selection -match 3){
        Write-Host "Installing Windows Updates and Dell Drivers and Firmware..."
        $Global:WindowsUpdates=$True
        $Global:DriverandFirmware=$True
        $Global:Confirm=$false
    }

    IF($selection -imatch 'q'){
        Write-Host "Bye Bye..."
        EndScript
    }
}#End of ShowMenu
ShowMenu

#Check for ignore checks
If($IgnoreChecks -eq $True){Write-Host "IgnoreChecks:True" -ForegroundColor Yellow}

# Dell Server Check
IF((Get-WmiObject -Class Win32_ComputerSystem).Manufacturer -imatch "Dell" -and (Get-WmiObject -Class Win32_ComputerSystem).PCSystemType -imatch "4"){
    # Fix 8.3 temp paths
        $MyTemp=(Get-Item $env:temp).fullname
if ($PSCmdlet.ShouldProcess($param)) { 

        Function Download-File{
            Param($URL)
            $DLFileName=$URL.Split('\/')[-1]
            Write-Host "    Downloading $URL..."
            $OutFile=$MyTemp+"\"+$DLFileName
            # Use TLS 1.2
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            # Download file
            #Try{Invoke-WebRequest $URL -OutFile $OutFile -UseDefaultCredentials}
            Try{Invoke-WebRequest $URL -OutFile $OutFile}
            Catch{
                Write-Host "        ERROR: Downloading $URL" -ForegroundColor Red
                EndScript
            }
            #Finally{
                IF([System.IO.File]::Exists($OutFile)){
                    Write-Host "        SUCCESS: File downloaded successfully" -ForegroundColor Green
                }
            #}
            Return $OutFile
        }

        Function Expand-Gz{
            Param($InFile)
            $outFile = $infile.Substring(0, $infile.LastIndexOfAny('.'))
            $input = New-Object System.IO.FileStream $inFile, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::Read)
            $output = New-Object System.IO.FileStream $outFile, ([IO.FileMode]::Create), ([IO.FileAccess]::Write), ([IO.FileShare]::None)
            $gzipStream = New-Object System.IO.Compression.GzipStream $input, ([IO.Compression.CompressionMode]::Decompress)
            $buffer = New-Object byte[](1024)
                While($true){
                    $read = $gzipstream.Read($buffer, 0, 1024)
                    if ($read -le 0){break}
                        $output.Write($buffer, 0, $read)
                }
            $gzipStream.Close()
            $output.Close()
            $input.Close()
        }

        Function Run-ASHCIPre{
            # Check for any outstanding Storage Jobs
            Write-Host "Executing Azure Stack HCI Pre-Checks..."
            IF(Get-VirtualDisk | Where-Object{$_.OperationalStatus -ine "OK"}){
                Write-Host "    ERROR: Virtual Disk(s) UnHealth Please remediate before continuing" -ForegroundColor Red
                EndScript}
            Write-Host "    Checking for Running storage jobs..."
            do {
                $SJobs=((Get-StorageJob | Where-Object {$_.Name -imatch 'Repair' -and ($_.JobState -eq 'Running')}) | Measure-Object).Count
                IF($SJobs -gt 1){
                    Start-Sleep 5
                    Write-Host "        Found Running storage jobs. Next check in 5 seconds..."
                }
            }until(
                ## Running Repair Jobs are less than 1
                    $SJobs -lt 1
            )

            # Suspend Cluster Host to prevent chicken-egg scenario
                Write-Host "    Suspending $env:COMPUTERNAME..."
                    Suspend-ClusterNode -Name $env:COMPUTERNAME -Drain -ForceDrain -Wait -ErrorAction Inquire >$null
                IF($ClusPreERR){
                    Write-Host "        ERROR: Failed to suspend cluster node. Exiting..." -ForegroundColor Red
                    EndScript
                    }
                IF((Get-ClusterNode -Name $env:COMPUTERNAME).State -eq "Paused"){
                    Write-Host "        SUCCESS: Cluster node is suspended" -ForegroundColor Green
                }

            # Enter Storage Maintenance Mode
                Write-Host "    Enabling Storage Maintenance Mode on $env:COMPUTERNAME..."
                try {
                    $Maint=$Null
                    Get-StorageFaultDomain -type StorageScaleUnit | Where-Object {$_.FriendlyName -eq "$($Env:ComputerName)"} | Enable-StorageMaintenanceMode -ErrorAction Stop -ErrorVariable Maint
                    IF($Maint -eq $Null){$Maint="Success"}
                }
                catch {
                    Write-Host "        ERROR: Failed to enter storage maintenance mode." -ForegroundColor Red
                    Write-Host "$Maint" -ForegroundColor Red
                    Write-Host "    Resuming Node..."
                    Resume-ClusterNode -Name $Env:COMPUTERNAME -Failback Immediate
                    $Maint="Failed"
                    EndScript
                }
                IF($Maint -eq "Success"){
                    Write-Host "        SUCCESS: Storage Scale Unit entered Storage Maintenance Mode" -ForegroundColor Green
                
                }
        }

    Function Run-ClusterPre{
        Write-Host "Executing Cluster Pre-Checks..."
        IF(Get-VirtualDisk | Where-Object{$_.OperationalStatus -ine "OK"}){
            Write-Host "    ERROR: Virtual Disk(s) UnHealth Please remediate before continuing" -ForegroundColor Red
            EndScript}
        Try{
            # Suspend Cluster Host to prevent chicken-egg scenario
                Write-Host "    Suspending $env:COMPUTERNAME..."
                Suspend-ClusterNode -Name $env:COMPUTERNAME -Drain -ForceDrain -Wait -ErrorAction Inquire
        }Catch{
            Write-Host "    ERROR: Failed to suspend cluster node. Exiting..." -ForegroundColor Red
            EndScript
            }
            IF(-not $ClusPreERR){
                Write-Host "    SUCCESS: Cluster node suspended." -ForegroundColor Green
            }
    }

        Function Run-DSU{
            # CD to DSU dir
                cd 'C:\Program Files\Dell\DELL EMC System Update'
            # Check if HCI and run DSU install needed updates
                IF($ASHCI -eq "YES"){
                    # We create an ans.txt with a and c on seperate lines to answer DSU (a - Select All, c to Commit) and then pipe into dsu.exe the ans.txt when it runs
                        cmd /c "echo a>c:\ansd.txt&&echo c>>c:\ansd.txt&&DSU.exe --catalog-location=$MyTemp\ASHCI-Catalog.xml --apply-upgrades <c:\ansd.txt&&del c:\ansd.txt"
                }Else{
                    # We create an ans.txt with a and c on seperate lines to answer DSU (a - Select All, c to Commit) and then pipe into dsu.exe the ans.txt when it runs
                        cmd /c "echo a>c:\ansd.txt&&echo c>>c:\ansd.txt&&DSU.exe --apply-upgrades <c:\ansd.txt&&del c:\ansd.txt"
                }
                Do {  
                    $ProcessesFound = Get-Process -Name DSU -ErrorAction SilentlyContinue
                    If ($ProcessesFound) {
                        Write-Host "    Still running: $($ProcessesFound)"
                        Start-Sleep 10
                    }
                } Until (!$ProcessesFound)
            # Check Status
                $DupsStatus=Get-Content 'C:\ProgramData\Dell\DELL EMC System Update\dell_dup\DSU_STATUS.json'| ConvertFrom-Json | select -ExpandProperty SystemUpdateStatus 
                Switch($DupsStatus){
                    {$DupsStatus.InvokerInfo.statusMessage -imatch 'No Applicable Update'}{
                        Write-Host "`n`n"
                        Write-Host "Installation Report"
                        "-"*100
                        $DupsStatus.InvokerInfo | FL *
                        }
                    {$DupsStatus.UpdateableComponent}{$DupsStatus = $DupsStatus.UpdateableComponent
                        # Check reboot required
                            Write-Host "`n`n"
                            Write-Host "Installation Report"
                            "-"*100
                            Switch($DupsStatus){
                                {$DupsStatus | Where-Object{$_.updateStatus -ne "SUCCESS"}}
                                    {
                                        $DupsStatus | FL *
                                        Write-Host "ERROR: Some updates failed to install. Please review logs for further information. C:\ProgramData\Dell\UpdatePackage\log" -ForegroundColor Red
                                        EndScript
                                    }
                                {$DupsStatus | Where-Object{$_.rebootRequired -eq "True"}}
                                                                                                                                                                                                                                                                                    {
                            $DupsStatus | FL *
                            Write-Host "Please reboot to complete installation" -ForegroundColor Yellow
                            $Reboot = Read-Host "Ready to reboot? [y/n]"
                            Switch ($Reboot){
                                "y"{
                                    $Script='CLS;$DateTime=Get-Date -Format yyyyMMdd_HHmmss;Start-Transcript -NoClobber -Path "C:\programdata\Dell\DART\DART_$DateTime.log";Write-Host "Resuming Cluster Node $ENV:COMPUTERNAME...";Resume-ClusterNode -Name $Env:COMPUTERNAME -Failback Immediate -ErrorAction SilentlyContinue;Get-ClusterNode;Write-Host "Exiting Storage Maintenance Mode...";Get-StorageScaleUnit -FriendlyName "$($Env:ComputerName)" | Disable-StorageMaintenanceMode -ErrorAction SilentlyContinue;Get-PhysicalDisk|Sort DeviceID;Unregister-ScheduledTask -TaskName "Exit Maintenance Mode" -Confirm:$false;Remove-Item -Path c:\dell\exit-maintenancemode.ps1 -Force;stop-Transcript'
                                    IF(-not(Test-Path c:\dell)){
                                        New-Item -Path "c:\" -Name "Dell" -ItemType "directory"
                                    }
                                    $Script | Out-File -FilePath c:\dell\exit-maintenancemode.ps1 -Force
                                    Register-ScheduledTask -TaskName "Exit Maintenance Mode" -Trigger (New-ScheduledTaskTrigger -AtLogon) -Action (New-ScheduledTaskAction -Execute "${Env:WinDir}\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-WindowStyle Hidden -Command `"& 'c:\dell\exit-maintenancemode.ps1'`"") -RunLevel Highest -Force;
                                    Restart-Computer -Force
                                    EndScript
                                    }
                                "n"{
                                    EndScript
                                    }
                            }
                            EndScript
                        }
                                Default{
                                    Write-Host "No reboot required"
                                    $DupsStatus | FL *
                                    EndScript
                                }
                            }
                    }
                }

        }
   # Find latest DSU version on downloads.dell.com
       Try{
           # Use TLS 1.2
           [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
           Write-Host "Finding Latest Dell EMC System Update(DSU) version..."
           $URL="https://downloads.dell.com/omimswac/dsu/"
           #$Results=Invoke-WebRequest $URL -UseDefaultCredentials
           $Results=Invoke-WebRequest $URL -UseBasicParsing
           ## Parse the href tag to find the links on the page
           $LatestDSU=@()
           $results.Links.href | Where-Object {$_ -match "\d"} | ForEach-Object {
                ## build an object showing the link and version
                $LatestDSU+=[PSCustomObject]@{
                    Link = "https://downloads.dell.com" + $_
                    Version = ((($_ -split "_A00.EXE") -split "WN64_") -match "\d")[1]
                }
           }
           $LatestDSU=$LatestDSU|sort Version | select -Last 1
           Write-Host "    Found: $($LatestDSU.Version) | $($LatestDSU.Link)" -ForegroundColor Green
       }
       Catch{
           Write-Host "    ERROR: Failed to find DSU version. Exiting..." -ForegroundColor Red
           EndScript
       }
   # Check if DSU is already installed
        Write-Host "Checking if DSU is installed..."
        Set-Location 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        $RegKeyPaths=Get-ChildItem | Select PSPath -ErrorAction SilentlyContinue 
        ForEach($Key in $RegKeyPaths){
            IF(Get-ItemProperty -Path $Key.PSPath | ?{$_.DisplayName -imatch 'DELL EMC System Update'}){
                $DSUVer=(Get-ItemProperty -Path $Key.PSPath).DisplayVersion
                IF(Get-ItemProperty -Path $Key.PSPath | ?{[version]$_.DisplayVersion -ge [version]$LatestDSU.Version}){
                    Write-Host "    FOUND: DSU $DSUVer already installed" -ForegroundColor Green
                    $IsDSUInstalled="YES"
                    Set-Location c:\
                }
            }
        }
        IF(-not ($IsDSUInstalled -eq "YES")){
            Write-Host "Downloading Dell EMC System Update(DSU)..."
            $DSUInstallerLocation=Download-File $LatestDSU.Link
            Write-Host "Installing DSU..."
            Start-Process $DSUInstallerLocation -ArgumentList '/s' -NoNewWindow -Wait
            $DSUInstallStatus=$DSUInstallerLocation.Split('\\')[-1] -replace ".exe",""
            IF(((Get-Content "C:\ProgramData\Dell\UpdatePackage\log\$DSUInstallStatus.txt" | select-string -Pattern 'Exit code ' -SimpleMatch | Select-Object -Last 1) -split "= ")[-1] -eq 1){
                Write-Host "    ERROR: Failed to install DSU." -ForegroundColor Red
                EndScript
            }Else{Write-Host "    SUCCESS: DSU Installed Successfully." -ForegroundColor Green }
        }
        Write-Host "Gather Server Model Info..."
        # Find Storage Spaces Direct RN or AX info
            $Model=(Get-WmiObject -Class Win32_ComputerSystem).model
            IF($Model -imatch 'Storage Spaces Direct' -or $Model -imatch 'AX'){
                $ASHCI="YES"
                $URL="https://downloads.dell.com/catalog/ASHCI-Catalog.xml.gz"
                $InFile="$MyTemp\ASHCI-Catalog.xml.gz"
            }Else{
                $ASHCI="NO"
                # Check if node is a Cluster memeber
                IF(Get-Service clussvc -ErrorAction SilentlyContinue){$IsClusterMember = "YES"}Else{$IsClusterMember = "NO"}
                $URL="https://downloads.dell.com/catalog/Catalog.xml.gz"
                $InFile="$MyTemp\Catalog.xml.gz"
            }
        Write-Host "    SUCCESS: $Model" -ForegroundColor Green
        IF($ASHCI -eq "YES"){
            Write-Host "Downloading Catalog..."
            $CatalogLocation=Download-File $URL
            Write-Host "Expanding Catalog for use..."
            Try{Expand-Gz $InFile}
            Catch{Write-Host "    ERROR: Failed to expand catalog" -ForegroundColor Red}
            Finally{
                IF([System.IO.File]::Exists(($InFile -replace ".gz",""))){
                    Write-Host "    SUCCESS: Catalog expanded" -ForegroundColor Green
                }
            }
            If($IgnoreChecks -ne $True){
                Run-ASHCIPre
                $NoClusterPre=$True
            }
        }
        IF($NoClusterPre -ne $True){
            If($IgnoreChecks -ne $True){
                Run-ClusterPre
            }
        }
        If($IgnoreChecks -eq $True){Write-Host "Ignoring ASHCI/Cluster Prechecks" -ForegroundColor Yellow}
        # Check if Windows
        IF([System.Environment]::OSVersion.VersionString -imatch 'Windows'){
            IF($WindowsUpdates -eq $True){ 
                Write-Host "    Executing Windows Updates..."
                #cmd /c "echo A>c:\ans.txt&&echo A>>c:\ans.txt&&cscript C:\Windows\System32\en-US\WUA_SearchDownloadInstall.vbs <c:\ans.txt&&del c:\ans.txt"
                Start-Process -WindowStyle Normal -FilePath "$env:comspec" -ArgumentList '/C echo A>c:\ans.txt&&echo A>>c:\ans.txt&&cscript C:\Windows\System32\en-US\WUA_SearchDownloadInstall.vbs <c:\ans.txt&&del c:\ans.txt'
            }ElseIF($WindowsUpdates -eq $False){Write-Host "    Skipping Windows Updates" -ForegroundColor Yellow}
        }
        IF($DriverandFirmware -eq $True){
            Write-Host "    Executing DSU..."
            Run-DSU
        }ElseIF($DriverandFirmware -eq $False){Write-Host "    Skipped Dell Drivers and Firmware" -ForegroundColor Yellow}
        $ExitSMM = Read-Host "Ready to Resume Cluster Node and exit Storage Maintenance Mode? [y/n]"
            Switch ($ExitSMM){
                "y"{
                        # Resume Cluster
                        IF($IgnoreChecks -ne $True){
                            IF(($IsClusterMemeber -eq "YES") -or ($ASHCI -eq "YES")){
                                Write-Host "Resuming Cluster Node $ENV:COMPUTERNAME..."
                                Resume-ClusterNode -Name $Env:COMPUTERNAME -Failback Immediate -ErrorAction SilentlyContinue >$null
                            }
                        }

                        # Disable Storage Maintenance Mode
                        IF($IgnoreChecks -ne $True){
                            IF($ASHCI -eq "YES"){
                                Write-Host "Exiting Storage Maintenance Mode..."
                                Get-StorageFaultDomain -type StorageScaleUnit | Where-Object {$_.FriendlyName -eq "$($Env:ComputerName)"} | Disable-StorageMaintenanceMode -ErrorAction SilentlyContinue
                            }

                         }
                    }
                "n"{
                        $Script='CLS;$DateTime=Get-Date -Format yyyyMMdd_HHmmss;Start-Transcript -NoClobber -Path "C:\programdata\Dell\DART\DART_$DateTime.log";Write-Host "Resuming Cluster Node $ENV:COMPUTERNAME...";Resume-ClusterNode -Name $Env:COMPUTERNAME -Failback Immediate -ErrorAction SilentlyContinue;Get-ClusterNode;Write-Host "Exiting Storage Maintenance Mode...";Get-StorageScaleUnit -FriendlyName "$($Env:ComputerName)" | Disable-StorageMaintenanceMode -ErrorAction SilentlyContinue;Get-PhysicalDisk|Sort DeviceID;Unregister-ScheduledTask -TaskName "Exit Maintenance Mode" -Confirm:$false;Remove-Item -Path c:\dell\exit-maintenancemode.ps1 -Force;stop-Transcript'
                        IF(-not(Test-Path c:\dell)){
                            New-Item -Path "c:\" -Name "Dell" -ItemType "directory"
                        }
                        $Script | Out-File -FilePath c:\dell\exit-maintenancemode.ps1 -Force
                        Write-Host "Creating Exit Maintenance Mode Scheduled Task to run at next logon...."
                        Register-ScheduledTask -TaskName "Exit Maintenance Mode" -Trigger (New-ScheduledTaskTrigger -AtLogon) -Action (New-ScheduledTaskAction -Execute "${Env:WinDir}\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-WindowStyle Hidden -Command `"& 'c:\dell\exit-maintenancemode.ps1'`"") -RunLevel Highest -Force;
                    }
                }
    }#$PSCmdlet.ShouldProcess($param)
}Else{Write-Host "ERROR: Non-Dell Server Detected!" -ForegroundColor Red}# Dell Server Check
Stop-Transcript
}               
               
