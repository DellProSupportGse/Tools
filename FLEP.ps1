<#
.Synopsis
   Filter Event Logs in Parrallel
.DESCRIPTION
    Script to filter event logs more quickly
.CREATEDBY
    Jim Gandy
#>
Function Invoke-FLEP{
$FLEPVer="1.3"
Clear-Host
$text = @"
v$FLEPVer
  ___ _    ___ ___ 
 | __| |  | __| _ \
 | _|| |__| _||  _/
 |_| |____|___|_|  
                     
         by: Jim Gandy 
"@
$Oops=@"
Oops... Something went wrong. Please try again.
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
         Write-Host "Press '1' to Export System Event logs"
         Write-Host "Press '2' to Filter for 505 Events"
         Write-Host "Press '3' to Filter System Event logs for Usual Suspects"
         Write-Host "Press 'H' to Display Help"
         Write-Host "Press 'Q' to Quit"
         Write-Host ""
         $selection = Read-Host "Please make a selection"
     }
    until ($selection -match '[1-3,qQ,hH]')
    $Global:FilterSystem  = "N"
    $Global:Filter505 = "N"
    IF($selection -imatch 'h'){
        Clear-Host
        Write-Host ""
        Write-Host "What's New in"$CluChkVer":"
        Write-Host "    v1.3"
        Write-host "        1. New Feature: Added Export System Event logs to export the whole log" 
        Write-host "        2. New Feature: Added UTC Time Created to output" 
        Write-Host ""
        Write-Host "Usage:"
        Write-Host "    Make a selection by entering a comma delimited string of numbers from the menu."
        Write-Host ""
        Write-Host "        Example: 1 will filter system event logs for"
        Write-Host "                 EventID=13,20,28,41,57,129,153,134,301,1001,1017,1018,1135,5120,6003-6009"
        Write-Host "                 and output them in a CSV file in the folder where the log exists."
        Write-Host ""
        Write-Host "        Example: 2 will filter Microsoft-Windows-Storage-Storport/Operational event logs for"
        Write-Host "                 EventID=505"
        Write-Host "                 and output them in a CSV file in the folder where the log exists."
        Write-Host ""
        Pause
        ShowMenu
    }

    IF($selection -match 1){
        Write-Host "Export System Event logs..."
        $Global:ExportSystem  = "Y"
    }

    IF($selection -match 2){
        Write-Host "Filter for 505 Events for the last 7 days..."
        $Global:Filter505  = "Y"
    }
    
    IF($selection -match 3){
        Write-Host "Filter System Event logs for Usual Suspects (13, 20, 28, 41, 57, 129, 153, 134, 301, 1001, 1017, 1018, 1135, 5120, 6003 - 6009)..."
        $Global:FilterSystem = "Y"
    }
    
    IF($selection -imatch 'q'){
        Write-Host "Bye Bye..."
        break script
    }
}#End of ShowMenu

ShowMenu
IF($FilterSystem -ieq "y" -or $Filter505 -ieq "y"-or $ExportSystem -ieq "y"){
    
    # Added to Select-Object the extracted SDDC
    Do{$Extracted = Read-Host "Do you already have the logs extracted? [y/n]"}
    until ($Extracted -match '[yY,nN]')
    IF($Extracted -ieq "y"){
        $LogsExtracted="YES"
        Write-Host "    Please Provide the path to the extracted logs"
        Write-Host "      Ex: c:\SRs\81449725\HealthTest-NL70U00CL02-20200928-1130"
        $LogsPath=Read-Host "    Path"
        $IR=1
        $LogsPathLoc=Split-Path -Path $LogsPath
        $ExtracLoc=(Split-Path -Path $LogsPath) +"\"+ (Split-Path -Path $LogsPath -Leaf).Split(".")[0]
    }

    If($Extracted -ieq "n"){
        Function Get-FileName($initialDirectory)
        {
            [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    
            $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog -Property @{MultiSelect = $true}
            $OpenFileDialog.Title = "Please Select SDDC File."
            $OpenFileDialog.initialDirectory = $initialDirectory
            $OpenFileDialog.filter = "ZIP (*.zip)| *.zip"
            $OpenFileDialog.ShowDialog() | Out-Null
            $OpenFileDialog.filenames
        }
          Write-Host "    Please Select-Object SDDC File to use..."
          $Log2Extract=Get-FileName("$env:USERPROFILE\Documents\SRs")

            if(!$Log2Extract){EndScript}


        #Extraction temp location
            $LogsPathLoc=Split-Path -Path $ExtracLoc
            $ExtracLoc=(Split-Path -Path $LogsPath) +"\"+ (Split-Path -Path $LogsPath -Leaf).Split(".")[0]
            Try{
                If (Test-Path $ExtracLoc -PathType Container){Remove-Item $ExtracLoc -Recurse -Force -ErrorAction Stop | Out-Null}
            }Catch{
                Write-Host $Oops
                Write-Host ""
                Write-Host "$Error" -ForegroundColor Red
                EndScript
            }
            if (!(Test-Path $ExtracLoc -PathType Container)) {New-Item -ItemType Directory -Force -Path $ExtracLoc | Out-Null }

        # unzip files
        function Unzip
        {
            param([string]$zipfile, [string]$outpath)
            Write-Host "    Expanding: "
            Write-Host "      $Log2Extract "
            Write-Host "    To:"
            Write-Host "      $ExtracLoc"
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
        }
        Unzip $Log2Extract $ExtracLoc
    }
}Else{break script}

Measure-Command{
# Filter SDDC system event logs for known IDs in parallel
#$lpath = "C:\Users\jim_gandy\OneDrive - Dell Technologies\Documents\SRs\122393915\EMC-825BFF5F1E\HealthTest-wtghostvmcl-20210916-1034\"
$lpath = $ExtracLoc
If($ExportSystem -ieq "y"){$logs = Get-ChildItem -Recurse -Path $lpath | Where-Object{$_.Name -like "system.EVTX"}}
If($FilterSystem -ieq "y"){$logs = Get-ChildItem -Recurse -Path $lpath | Where-Object{$_.Name -like "system.EVTX"}}
If($Filter505 -ieq "y"){
    $logs = Get-ChildItem -Recurse -Path $lpath | Where-Object{$_.Name -like "Microsoft-Windows-Storage-Storport-Operational.EVTX"}
    $MSCS=(Get-Date).ToFileTime() - (Get-Date).adddays(-7).ToFileTime()
}
ForEach($log in $logs){
    Write-Host "Processing log $(($log).fullname)"
    $FPath=$(($log).fullname)
    [System.Threading.Thread]::CurrentThread.CurrentCulture = New-Object "System.Globalization.CultureInfo" "en-US"
###########################
IF($FilterSystem -ieq "Y"){
    $EvntIDXML = @'
        <QueryList>
            <Query Id="0" Path="file://C:\">
                <Select Path="file://XXXXX">*[System[(EventID=13 or EventID=20 or EventID=28 or EventID=41 or EventID=57 or EventID=129 or EventID=153 or EventID=134 or EventID=301 or EventID=1001 or EventID=1017 or EventID=1018 or EventID=1135 or EventID=5120 or  (EventID &gt;= 6003 and EventID &lt;= 6009) )]]</Select>
            </Query>
        </QueryList>
'@
}

IF($Filter505 -ieq "Y"){
    $EvntIDXML = @'
        <QueryList>
            <Query Id="0" Path="file://C:\">
                <Select Path="file://XXXXX">*[System[(EventID=505) and TimeCreated[timediff(@SystemTime) &lt;= 43200000]]]</Select>
            </Query>
        </QueryList>
'@
}
IF($ExportSystem -ieq "Y"){
    $EvntIDXML = @'
        <QueryList>
            <Query Id="0" Path="file://C:\">
                <Select Path="file://XXXXX">*[System]</Select>
            </Query>
        </QueryList>
'@
}
$ScriptBlock={
    param($FPath,$EvntIDXML,$MSCS)

$NewXML = $EvntIDXML -Replace "XXXXX",$Fpath -replace "43200000",$MSCS

                      Get-WinEvent -FilterXML $NewXML -ErrorAction SilentlyContinue `
                      | Select-Object TimeCreated,@{L='UTCTimeCreated';E={$_.TimeCreated.ToUniversalTime()}},id,Logname,MachineName,ProviderName,Message,Properties `
                      | ForEach-Object -Process {New-Object -TypeName PSObject -Property `
                      ([Ordered]@{'UTCTimeCreated'=$_.UTCTimeCreated;'TimeCreated'=$_.TimeCreated;'Id'=$_.Id;'LogName'=$_.LogName;`
                      'ComputerName'=$_.MachineName;'ProviderName'=$_.ProviderName;'Message'=$_.Message;`
                      'EventData'=$_.properties.Value -Join ","})}
                      }
        Start-Job $ScriptBlock -ArgumentList $log.fullname,$EvntIDXML,$MSCS
}
While (Get-Job -State "Running")
{
  Start-Sleep 1
}
$DT="{0:yyyyMMddHHmmssfff}" -f (get-date)
Get-Job | Receive-Job | Export-Csv $lpath"\EventLog$DT.csv" -NoTypeInformation
Write-Host "Output file: $lpath\EventLog$DT.csv"
} 
}
 
