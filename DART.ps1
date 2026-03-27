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
    
    param(
    [Parameter(Mandatory=$False, Position=1)]
    [bool] $IgnoreChecks=$False,[bool] $IgnoreVersion=$False)

Function Invoke-DART {

    param(
    [Parameter(Mandatory=$False, Position=1)]
    [bool] $IgnoreChecks=$False,[bool] $IgnoreVersion=$False,
    $param)

    $ver="1.65"

$DateTime=Get-Date -Format yyyyMMdd_HHmmss
Start-Transcript -NoClobber -Path "C:\programdata\Dell\DART\DART_$DateTime.log"
$Global:IgnoreChecks=$IgnoreChecks
$Global:IgnoreVersion=$IgnoreVersion
# =====================================================
#region Telemetry Information
# =====================================================
$uploadToAzure=$True
IF($uploadToAzure){

    Write-Host "Logging Telemetry Information..."

    function Add-TableData {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            [string]$TableName,

            [Parameter(Mandatory=$true)]
            [string]$PartitionKey,

            [Parameter(Mandatory=$true)]
            [hashtable]$Data
        )

        if (-not $uploadToAzure) { return }

        $RowKey = [guid]::NewGuid().Guid
        
        $TableSvcSasUrl = 'https://gsetools.table.core.windows.net/DARTTelemetryData?sv=2019-02-02&spr=https&st=2026-03-27T18%3A02%3A49Z&se=2028-03-28T18%3A02%3A00Z&sp=a&sig=JO4zo4jRLM11IrnZFPuFNXYhUQJywKfSX6E47Bdtp%2Bg%3D&tn=DARTTelemetryData'

        $uri = "https://gsetools.table.core.windows.net/$TableName$($TableSvcSasUrl.Substring($TableSvcSasUrl.IndexOf('?')))"

        $headers = @{
            "Accept"       = "application/json;odata=nometadata"
            "Content-Type" = "application/json"
            "x-ms-version" = "2019-02-02"
        }

        $Data["PartitionKey"] = $PartitionKey
        $Data["RowKey"]       = $RowKey

        $body = $Data | ConvertTo-Json -Depth 5

        $maxRetries = 3
        $attempt = 0
        $success = $false

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
        Version      = $Ver
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
    $PartitionKey = "Boiler"

    Add-TableData `
        -TableName "BOILERTelemetryData" `
        -PartitionKey $PartitionKey `
        -Data $data 

}
#endregion
    

Function EndScript{ 
    Stop-Transcript
    break
}

$addtablefunction=${function:add-TableData1}
Start-Job -Name "Telemetry" -ScriptBlock {
${function:add-TableData1} = $using:addtablefunction
# Generating a unique report id to link telemetry data to report data
    $CReportID=""
    $CReportID=(new-guid).guid
    
# Define the API endpoint URL
    $geourl = "http://ip-api.com/json"

# Invoke the API to determine Geolocation
    $response = Invoke-RestMethod $geourl

$data = @{
    Region=$env:UserDomain
    Version=$Ver
    ReportID=$CReportID  
    country=$response.country
    counrtyCode=$response.countryCode
    georegion=$response.region
    regionName=$response.regionName
    city=$response.city
    zip=$response.zip
    lat=$response.lat
    lon=$response.lon
    timezone=$response.timezone
}
$RowKey=(new-guid).guid
$PartitionKey="DART"
add-TableData1 -TableName "DARTTelemetryData" -PartitionKey $PartitionKey -RowKey $RowKey -data $data
#endregion End of Telemetry data
} | Out-Null
$Global:SolutionUpdates=(gcm Get-StampInformation -ErrorAction SilentlyContinue).count
$Global:EnforcedMode=$false
$Global:EnforcedMode=if((Get-Command Get-ASWDACPolicyMode -ErrorAction SilentlyContinue).count) {if((Get-ASWDACPolicyMode | ? NodeName -eq (hostname)).policymode -ne "Audit"){$True}}

$text=@"
$ver
 __        __  ___ 
|  \  /\  |__)  |  
|__/ /~~\ |  \  |  
"@
# Run Menu
$OSInfo = Get-WmiObject -Class Win32_OperatingSystem
#$Global:pre23h2=!($OSInfo.caption -imatch "Azure Stack HCI" -and $OSInfo.BuildNumber -ge "25398")
if ($Global:SolutionUpdates) {$sel='[1,qQ,hH]'} else {$sel='[1-2,qQ,hH]'}
Function ShowMenu{
    do
     {
         $selection=""
         Clear-Host
         Write-Host $text
         Write-Host ""
         #Check for ignore checks
         If($Global:IgnoreChecks -eq $True){Write-Host "IgnoreChecks:True" -ForegroundColor Yellow}
         If($Global:IgnoreVersion -eq $True){Write-Host "IgnoreVersion:True" -ForegroundColor Yellow}
         if($Global:EnforcedMode -eq $true){Write-Host "ASWDAC is not in Audit mode. Updates may fail." -ForegroundColor DarkYellow}

         Write-Host "This code is under the MIT License. See Repository for Licensing/Support details."
         Write-Host ""
         Write-Host "==================== Please make a selection ====================="
         Write-Host ""
         Write-Host "Press '1' to Install Dell Drivers and Firmware"
         IF(-not $Global:SolutionUpdates) {Write-Host "Press '2' to Install Windows Updates"}
         IF(-not $Global:SolutionUpdates) {Write-Host "Press '12' to Install both Dell Drivers and Firmware as well as Windows Updates"}
         #Write-Host "Press '3' to Install Windows Updates and Dell Drivers and Firmware"
         Write-Host "Press 'H' to Display Help"
         Write-Host "Press 'Q' to Quit"
         Write-Host ""
         $selection = Read-Host "Please make a selection"
     }
    until ($selection -match $sel)
    $Global:WindowsUpdates=$False
    $Global:DriverandFirmware=$False
    $Global:Confirm=$False
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
        Write-Host "        Example: 2 will Install Dell Drivers and Firmware"
        Write-Host ""
        Pause
        ShowMenu
    }
    IF($selection -match 2 -and -not $Global:SolutionUpdates){
        Write-Host "Installing Windows Updates..."
        $Global:WindowsUpdates=$True
        #$Global:DriverandFirmware=$False
        $Global:Confirm=$false
    }

    IF($selection -match 1){
        Write-Host "Installing Dell Drivers and Firmware..."
        #$Global:WindowsUpdates=$False
        $Global:DriverandFirmware=$True
        $Global:Confirm=$false
    }
    <#IF($selection -match 3){
        Write-Host "Installing Windows Updates and Dell Drivers and Firmware..."
        $Global:WindowsUpdates=$True
        $Global:DriverandFirmware=$True
        $Global:Confirm=$false
    }#>

    IF($selection -imatch 'q'){
        Write-Host "Bye Bye..."
        EndScript
    }
}#End of ShowMenu


IF(!($Global:IgnoreChecks -eq $True) -and !($Global:IgnoreVersion -eq $True)){
    #Added for SBE Update of HCI 23H2 so we do no harm
    IF($Global:SolutionUpdates){
    CLS
    Write-Host 
    Write-Host "WARNING: At this time DART does not support updating $($OSInfo.caption) 23H2+ with MS Solution Updates." -ForegroundColor Yellow
    Write-Host "    For more information and detailed instructions for updating $($OSInfo.caption) 23H2+, please refer to the release notes available here:"  -ForegroundColor Yellow
    Write-Host "        'https://www.dell.com/support/kbdoc/en-us/000224407/dell-for-microsoft-azure-stack-hci-ax-hardware-updates-release-notes'" -ForegroundColor Yellow
    Write-Host 
    EndScript
    }
}

ShowMenu

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
            Try{$webClient = [System.Net.WebClient]::new()
                # Set the User-Agent header to mimic Chrome
                $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")
                $webClient.DownloadFile($URL, $OutFile)}
            Catch{
                Try {Invoke-WebRequest $URL -OutFile $OutFile -UserAgent::Chrome} Catch {
                Write-Host "        ERROR: Downloading $URL" -ForegroundColor Red
                EndScript
            }}
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
            Write-Host "Executing S2D/Azure Stack HCI Pre-Checks..."
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
                    IF($Maint.count -eq 0){$Maint="Success"}
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
$DSUReboot=$False
            # CD to DSU dir

                cd $((Get-ChildItem -Path "C:\Program Files\Dell\" -Filter DSU.EXE -Recurse | Sort LastWriteTime | Select -Last 1).FullName -replace 'dsu.exe')

            # Check if HCI and run DSU install needed updates
#Out-File -FilePath c:\ansd.txt -InputObject @('a','c')
                IF($ASHCI -eq "YES" ){
./DSU.exe --catalog-location="$MyTemp\ASHCI-Catalog.xml" /u /q | Out-Default
                }Else{
./DSU.exe /u /q | Out-Default
                }
                Do {  
                    $ProcessesFound = Get-Process -Name DSU -ErrorAction SilentlyContinue
                    If ($ProcessesFound) {
                        Write-Host "    Still running: $($ProcessesFound)"
                        Start-Sleep 10
                    }
                } Until (!$ProcessesFound)
            # Check Status

                $DupsStatus=(Get-Content $((Get-ChildItem -Path "C:\ProgramData\Dell\" -Filter DSU_STATUS.JSON -Recurse | Sort LastWriteTIme | Select -Last 1).FullName)) | ConvertFrom-Json | select -ExpandProperty SystemUpdateStatus 

                Switch($DupsStatus){
                    {$DupsStatus.InvokerInfo.exitStatus -eq 34}{
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
                            $DupsStatus | FL *
                            Switch($DupsStatus){
                                {$DupsStatus | Where-Object{$_.updateStatus -ne "SUCCESS"}}
                                    {
                                        Write-Host "ERROR: Some updates failed to install. Please review logs for further information. C:\ProgramData\Dell\UpdatePackage\log" -ForegroundColor Red
                                        EndScript
                                    }
                                {$DupsStatus | Where-Object{$_.rebootRequired -eq "True"}}
                               {
$DSUReboot=$True
}
                            }
                    }
                }
Return $DSUReboot

        }
        $IsDSUInstalled="NO"
        IF(-not ($IsDSUInstalled -eq "YES")){
            Write-Host "Downloading Dell System Update(DSU)..."
            $LatestDSU = 'https://dl.dell.com/FOLDER12418375M/1/Systems-Management_Application_03GC8_WN64_2.1.1.0_A00.EXE'
            $DSUInstallerLocation=Download-File $LatestDSU
            Write-Host "Installing DSU..."
            Start-Process $DSUInstallerLocation -ArgumentList '/s' -NoNewWindow -Wait
            $DSUInstallStatus=$DSUInstallerLocation.Split('\\')[-1] -replace ".exe",""
            IF(((Get-Content "C:\ProgramData\Dell\UpdatePackage\log\$DSUInstallStatus.txt" | select-string -Pattern 'Exit code ' -SimpleMatch | Select-Object -Last 1) -split "= ")[-1] -eq 1 -or (Get-ChildItem -Path "C:\Program Files\Dell\" -Filter DSU.EXE -Recurse).count -eq 0){
                Write-Host "    ERROR: Failed to install DSU." -ForegroundColor Red
                EndScript
            }Else{Write-Host "    SUCCESS: DSU Installed Successfully." -ForegroundColor Green }
        }
        Write-Host "Gather Server Model Info..."
        # Find Storage Spaces Direct RN or AX info
            $Model=(Get-WmiObject -Class Win32_ComputerSystem).model
$IsS2d=$False;try {$IsS2d=(Get-ClusterStorageSpacesDirect).state -eq "Enabled"} catch {}
            IF($Model -imatch 'Storage Spaces Direct' -or $Model -imatch 'AX'){
                $ASHCI="YES"
                $URL="https://downloads.dell.com/catalog/ASHCI-Catalog.xml.gz"
                $InFile="$MyTemp\ASHCI-Catalog.xml.gz"
                IF ([System.Environment]::OSVersion.OSVersion -match "10.0.14393") {
                   Write-Host "Windows Server 2016 detected" -ForegroundColor Yellow
                   Write-Host "Windows 2016 Ready Nodes can no longer be supported by DART or DSU."
                   Write-Host "Please visit the following url for information on supported bios, driver and firmware versions:"
                   Write-Host "https://dell.github.io/azurestack-docs/docs/hci/supportmatrix/archive/ws2016/"
                   EndScript
                   #$URL="https://dl.dell.com/FOLDER09682297M/1/ASHCI-Catalog.xml.gz"
                   #$URL="https://dl.dell.com/FOLDER07774224M/1/ASHCI-Catalog.xml.gz"
                }
            }Else{
                $ASHCI="NO"
                # Check if node is a Cluster memeber
                IF(Get-Service clussvc -ErrorAction SilentlyContinue){$IsClusterMember = "YES"}Else{$IsClusterMember = "NO"}
                $URL="https://downloads.dell.com/catalog/Catalog.xml.gz"
                $InFile="$MyTemp\Catalog.xml.gz"
                If($IsClusterMember -eq "NO"){
                    # Added to patch none cluster power edge server 
                    $Global:IgnoreChecks = $True
                }
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
            If($Global:IgnoreChecks -ne $True){
                Run-ASHCIPre
                $NoClusterPre=$True
            }
        }
        IF($NoClusterPre -ne $True){
            If($Global:IgnoreChecks -ne $True){
If ($IsS2d) {Run-ASHCIPre} else {Run-ClusterPre}
            }
        }
        If($Global:IgnoreChecks -eq $True){Write-Host "Ignoring ASHCI/Cluster Prechecks" -ForegroundColor Yellow}
        # Check if Windows
$WinReboot=$False
        IF([System.Environment]::OSVersion.VersionString -imatch 'Windows'){
            IF($WindowsUpdates -eq $True){ 
                Write-Host "    Executing Windows Updates..."
                (new-object -Comobject Microsoft.Update.AutoUpdate).detectnow()
                #((New-Object -ComObject Microsoft.Update.Searcher).Search("IsInstalled=0 and Type='Software' and isHidden=0").Updates | ? Title -match '2022-10 Update for Azure Stack HCI, version 22H2').IsHidden=1
                $Updates=(New-Object -ComObject Microsoft.Update.Searcher).Search("IsInstalled=0 and Type='Software' and isHidden=0").Updates
                if($Updates.count -ge 1){
                    Write-Host "The following updates have been found"
                    $Updates | % {Write-Host "$($_.IsDownloaded) $($_.Title)"}
                    Write-Host "Downloading Updates"
                    $djob=Start-Job -Name "djob" -scriptblock {
                        $UpdateDownloader=New-Object -ComObject Microsoft.Update.Downloader
                        $UpdateDownloader.Updates=(New-Object -ComObject Microsoft.Update.Searcher).Search("IsInstalled=0 and Type='Software' and isHidden=0").Updates
                        $UpdateDownloader.Download()
                        } 
                    Do {sleep 9;$e=get-EventLog -LogName System -After ((Get-Date).addseconds(-10)) | ? Source -match "update" | sort timegenerated;if ($e) {Write-Host "$($e.timegenerated) $($e.message)"}} while(!$djob.PSEndTime)
                    Receive-Job -Job $djob
                    write-host "Installing $($Updates.count) Updates"
                    $ujob=Start-Job -Name "ujob" -scriptblock {
                        $UpdateInstaller=New-Object -ComObject Microsoft.Update.Installer
                        $UpdateInstaller.Updates=(New-Object -ComObject Microsoft.Update.Searcher).Search("IsInstalled=0 and Type='Software' and isHidden=0").Updates
                        $UpdateInstaller.Install().RebootRequired
                        }
                    Do {sleep 59;$e=get-EventLog -LogName System -After ((Get-Date).addminutes(-1)) | ? Source -match "update" | sort timegenerated;if ($e) {Write-Host "$($e.timegenerated) $($e.message)"}} while(!$ujob.PSEndTime)
                    $WinReboot=Receive-Job -Job $ujob
if ($WinReboot -ne $True) {
$WinReboot
$WinReboot=$False
}
                } else { write-host "No updates detected" }
}ElseIF($WindowsUpdates -eq $False){Write-Host "    Skipping Windows Updates" -ForegroundColor Yellow}
        }
$DSUReboot=$False
        IF($DriverandFirmware -eq $True){
            Write-Host "    Executing DSU..."
            $DSUReboot=Run-DSU
        }ElseIF($DriverandFirmware -eq $False){Write-Host "    Skipped Dell Drivers and Firmware" -ForegroundColor Yellow}
If ($DSUReboot -eq $True -or $WinReboot -eq $True) {
    Write-Host "Please reboot to complete installation" -ForegroundColor Yellow
    Write-Host "Will create Exit Maintenance Mode Scheduled Task to run at next logon or five minutes after finishing OS boot...." -ForegroundColor Yellow
            try {$Host.UI.RawUI.FlushInputBuffer() } catch {while ($Host.UI.RawUI.KeyAvailable) {
                    $Host.UI.RawUI.ReadKey() | Out-Null
                }}
            try {$Reboot = (Read-Host "Ready to reboot? [y/n]").ToLower()} catch {}
            Switch ($Reboot){
                "y"{
                    $Script='CLS;$DateTime=Get-Date -Format yyyyMMdd_HHmmss;Start-Transcript -NoClobber -Path "C:\programdata\Dell\DART\DART_$DateTime.log";Write-Host "Resuming Cluster Node $ENV:COMPUTERNAME...";Resume-ClusterNode -Name $Env:COMPUTERNAME -Failback Immediate -ErrorAction SilentlyContinue;Get-ClusterNode;Write-Host "Exiting Storage Maintenance Mode...";Get-StorageScaleUnit -FriendlyName "$($Env:ComputerName)" | Disable-StorageMaintenanceMode -ErrorAction SilentlyContinue;Get-PhysicalDisk|Sort DeviceID;Unregister-ScheduledTask -TaskName "Exit Maintenance Mode" -Confirm:$false;Remove-Item -Path c:\dell\exit-maintenancemode.ps1 -Force;stop-Transcript'
                    IF(-not(Test-Path c:\dell)){
                        New-Item -Path "c:\" -Name "Dell" -ItemType "directory"
                    }
                    $Script | Out-File -FilePath c:\dell\exit-maintenancemode.ps1 -Force
                    $trigger=@()
                    $trigger+=New-ScheduledTaskTrigger -AtStartup
                    $trigger[0].Delay='PT5M'
                    $trigger+=New-ScheduledTaskTrigger -AtLogon
                    Register-ScheduledTask -User "system" -TaskName "Exit Maintenance Mode" -Trigger $trigger -Action (New-ScheduledTaskAction -Execute "${Env:WinDir}\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-WindowStyle Hidden -Command `"& 'c:\dell\exit-maintenancemode.ps1'`"") -RunLevel Highest -Settings (New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew) -Force;
                    Restart-Computer -Force
                    EndScript
                    }
                Default {
                    EndScript
                    }
                }
                EndScript
}
        IF($Global:IgnoreChecks -ne $True){
            try {$Host.UI.RawUI.FlushInputBuffer() } catch {while ($Host.UI.RawUI.KeyAvailable) {
                    $Host.UI.RawUI.ReadKey() | Out-Null
                }}
            try {$ExitSMM = (Read-Host "Ready to Resume Cluster Node and exit Storage Maintenance Mode? [y/n]").ToLower()} catch {}
            Switch ($ExitSMM){
                  "y"{
                        # Resume Cluster
                        IF($Global:IgnoreChecks -ne $True){
                            IF(($IsClusterMemeber -eq "YES") -or ($ASHCI -eq "YES")){
                                Write-Host "Resuming Cluster Node $ENV:COMPUTERNAME..."
                                Resume-ClusterNode -Name $Env:COMPUTERNAME -Failback Immediate -ErrorAction SilentlyContinue >$null
                            }
                        }

                        # Disable Storage Maintenance Mode
                        IF($Global:IgnoreChecks -ne $True){
                            IF($ASHCI -eq "YES" -or $isS2d){
                                Write-Host "Exiting Storage Maintenance Mode..."
                                Get-StorageFaultDomain -type StorageScaleUnit | Where-Object {$_.FriendlyName -eq "$($Env:ComputerName)"} | Disable-StorageMaintenanceMode -ErrorAction SilentlyContinue
                            }

                         }
                    }
                Default {
                        $Script='CLS;$DateTime=Get-Date -Format yyyyMMdd_HHmmss;Start-Transcript -NoClobber -Path "C:\programdata\Dell\DART\DART_$DateTime.log";Write-Host "Resuming Cluster Node $ENV:COMPUTERNAME...";Resume-ClusterNode -Name $Env:COMPUTERNAME -Failback Immediate -ErrorAction SilentlyContinue;Get-ClusterNode;Write-Host "Exiting Storage Maintenance Mode...";Get-StorageFaultDomain -type StorageScaleUnit | Where-Object {$_.FriendlyName -eq "$($Env:ComputerName)"} | Disable-StorageMaintenanceMode -ErrorAction SilentlyContinue;Get-PhysicalDisk|Sort DeviceID;Unregister-ScheduledTask -TaskName "Exit Maintenance Mode" -Confirm:$false;Remove-Item -Path c:\dell\exit-maintenancemode.ps1 -Force;stop-Transcript'
                        IF(-not(Test-Path c:\dell)){
                            New-Item -Path "c:\" -Name "Dell" -ItemType "directory"
                        }
                        $Script | Out-File -FilePath c:\dell\exit-maintenancemode.ps1 -Force
                        Write-Host "Creating Exit Maintenance Mode Scheduled Task to run at next logon or five minutes after finishing OS boot...."
                        $trigger=@()
                        $trigger+=New-ScheduledTaskTrigger -AtStartup
                        $trigger[0].Delay='PT5M'
                        $trigger+=New-ScheduledTaskTrigger -AtLogon
                        Register-ScheduledTask -User "system" -TaskName "Exit Maintenance Mode" -Trigger $trigger -Action (New-ScheduledTaskAction -Execute "${Env:WinDir}\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-WindowStyle Hidden -Command `"& 'c:\dell\exit-maintenancemode.ps1'`"") -RunLevel Highest -Settings (New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew) -Force;
                    }
            }
        }
    }#$PSCmdlet.ShouldProcess($param)
}Else{Write-Host "ERROR: Non-Dell Server Detected!" -ForegroundColor Red}# Dell Server Check
Stop-Transcript
}               
               Invoke-DART -IgnoreChecks $IgnoreChecks -IgnoreVersion $IgnoreVersion
