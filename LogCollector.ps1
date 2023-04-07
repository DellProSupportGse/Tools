    <#
    .Synopsis
       Invoke-LogCollector
    .DESCRIPTION
       This tool is used to collect logs from nodes or all nodes in a cluster and bring them back to a single location
    .EXAMPLE
       Invoke-GetLogs
    #>
Function Invoke-LogCollector{
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High')]
        param($param)

#region Telemetry Information
Write-Host "Logging Telemetry Information..."
function add-TableData1 {
    [CmdletBinding()] 
        param(
            [Parameter(Mandatory = $true)]
            [string] $tableName,

            [Parameter(Mandatory = $true)]
            [string] $PartitionKey,

            [Parameter(Mandatory = $true)]
            [string] $RowKey,

            [Parameter(Mandatory = $true)]
            [array] $data,
            
            [Parameter(Mandatory = $false)]
            [array] $SasToken
        )
        $storageAccount = "gsetools"

        # Allow only add and update access via the "Update" Access Policy on the CluChkTelemetryData table
        # Ref: az storage table generate-sas --connection-string 'USE YOUR KEY' -n "CluChkTelemetryData" --policy-name "Update" 
        If(-not($SasToken)){
            $sasWriteToken = "?sv=2019-02-02&si=LogCollectorUpdate&sig=Jj%2FImBN5rknIuc3TnLf6141lZvHPMvlzJhHAS7CsWOU%3D&tn=LogCollectorTelemetryData"
        }Else{$sasWriteToken=$SasToken}

        $resource = "$tableName(PartitionKey='$PartitionKey',RowKey='$Rowkey')"

        # should use $resource, not $tableNmae
        $tableUri = "https://$storageAccount.table.core.windows.net/$resource$sasWriteToken"
       # Write-Host   $tableUri 

        # should be headers, because you use headers in Invoke-RestMethod
        $headers = @{
            Accept = 'application/json;odata=nometadata'
        }

        $body = $data | ConvertTo-Json
        #This will write to the table
        #write-host "Invoke-RestMethod -Method PUT -Uri $tableUri -Headers $headers -Body $body -ContentType application/json"
		try {
			$item = Invoke-RestMethod -Method PUT -Uri $tableUri -Headers $headers -Body $body -ContentType application/json
		} catch {
			#write-warning ("table $tableUri")
			#write-warning ("headers $headers")
		}
		
}# End function add-TableData
    

Function EndScript{  
    break
}
Clear-Host
# Logs
$DateTime=Get-Date -Format yyyyMMdd_HHmmss
Start-Transcript -NoClobber -Path "C:\programdata\Dell\LogCollector\LogCollector_$DateTime.log"
# Clean up
IF(Test-Path -Path "$((Get-Item $env:temp).fullname)\logs"){ Remove-Item "$((Get-Item $env:temp).fullname)\logs" -Recurse -Confirm:$false -Force}
$Ver="1.25"
# Generating a unique report id to link telemetry data to report data
    $CReportID=""
    $CReportID=(new-guid).guid
# Get the internet connection IP address by querying a public API
    $internetIp = Invoke-RestMethod -Uri "https://api.ipify.org?format=json" | Select-Object -ExpandProperty ip

# Define the API endpoint URL
    $geourl = "http://ip-api.com/json/$internetIp"

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
$PartitionKey="LogCollector"
add-TableData1 -TableName "LogCollectorTelemetryData" -PartitionKey $PartitionKey -RowKey $RowKey -data $data
#endregion End of Telemetry data

$text = @"
v$Ver
  _                 ___     _ _        _           
 | |   ___  __ _   / __|___| | |___ __| |_ ___ _ _ 
 | |__/ _ \/ _' | | (__/ _ \ | / -_) _|  _/ _ \ '_|
 |____\___/\__, |  \___\___/_|_\___\__|\__\___/_|  
           |___/                                   
"@
Write-Host $text
Write-Host ""
Write-Host "We are committed to providing the best possible customer"
Write-Host "experience. To do so, we would like to collect some "
Write-Host "information about your usage of our service."
Write-Host ""
Write-Host "Do you consent to provide environment information "
Write-Host "(such as hostnames, IP Addresses, etc.) to improve the "
Write-Host "customer experience?"
$consent = (Read-Host "(Y/[N]) ").ToUpper()
if ($consent -eq "Y") {
  # Collect data to improve customer experience
  Write-Host "Thank you for participating in our program. Your input is valuable to us!"
  
} else {
  $consent = "N"
  # Do not collect data
  Write-Host "We respect your decision. Your privacy is important to us."
}
#only collect personal data when $consent eq 'Y'
Write-Host ""
$CaseNumber =""
$CaseNumber = Read-Host -Prompt "Please enter the relevant technical support case number"
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
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="GetShowTech";$repo="PowershellScripts"'+(new-object System.net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/GetShowTech.ps1'));Invoke-GetShowTech -confirm:$False -CaseNumber $Casenumber

    }

    IF($selection -match 2){
        Write-Host "Collect Support Assist Collection(s)..."
        $Global:CollectTSR  = "Y"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="TSRCollector";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/TSRCollector.ps1'));Invoke-TSRCollector -confirm:$False -CaseNumber $CaseNumber

    }
    IF($selection -match 3){
        Write-Host "Collect PrivateCloud.DiagnosticInfo (SDDC)..."
        $Global:CollectSDDC = "Y"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="SDDC";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/RunSDDC.ps1'));Invoke-RunSDDC -confirm:$False -CaseNumber $CaseNumber

    }
    ElseIF($selection -eq 4){
        IF(Test-Path -Path "$((Get-Item $env:temp).fullname)\logs"){ Remove-Item "$((Get-Item $env:temp).fullname)\logs" -Recurse -Confirm:$false -Force}
        Write-Host "Collect Show Tech-Support(s) + Support Assist Collection(s) + PrivateCloud.DiagnosticInfo (SDDC)..."
        $Global:CollectSTS  = "Y"
        $Global:CollectSDDC = "Y"
        $Global:CollectTSR  = "Y"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="GetShowTech";$repo="PowershellScripts"'+(new-object System.net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/GetShowTech.ps1'));Invoke-GetShowTech -confirm:$False -CaseNumber $Casenumber
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="TSRCollector";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/TSRCollector.ps1'));Invoke-TSRCollector -LeaveShare:$True -confirm:$False -CaseNumber $Casenumber
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="SDDC";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/RunSDDC.ps1'));Invoke-RunSDDC -confirm:$False -CaseNumber $Casenumber
        # Remove share
            Write-Host "Removing SMB share called Logs..."
            Remove-SmbShare -Name "Logs" -Force
        ZipNClean
    }
    IF($consent -eq "Y") {UploadLogs}
    IF($selection -imatch 'q'){
        Write-Host "Bye Bye..."
        EndScript
    }
}#End of ShowMenu
Function ZipNClean{
    # Zip up
        Write-Host "Compressing Logs..."
        $MyTemp=(Get-Item $env:temp).fullname
        $DT=Get-Date -Format "yyyyMMddHHmm"
        IF(Test-Path -Path "$MyTemp\logs"){
            Compress-Archive -Path "$MyTemp\logs\*.*" -DestinationPath "c:\dell\LogCollector_$($DT)"
            Sleep 60            
            IF(Test-Path -Path "c:\dell\LogCollector_$($DT).zip"){
                Write-Host "Logs can be found here: C:Dell\LogCollector_$($DT).zip"
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
Function UploadLogs {
    #Upload SDDC
    IF(Test-Path -Path "$MyTemp\logs\Healthtest*$CaseNumber*"){
        $HealthZip = Get-ChildItem $MyTemp\logs\Healthtest*$CaseNumber* | sort lastwritetime | select -last 1 
        #Get the File-Name without path
        $name = (Get-Item $HealthZip).Name

        #The target URL wit SAS Token
        $uri = "https://gsetools.blob.core.windows.net/sddcdata/$($name)?sp=acw&st=2022-06-28T17:26:35Z&se=2032-06-29T01:26:35Z&spr=https&sv=2021-06-08&sr=c&sig=4gtvKkicwS%2BcD6BSBgapTziNrfar11CL%2B6hsVHWzJXI%3D"

        #Define required Headers
        $headers = @{
            'x-ms-blob-type' = 'BlockBlob'
                }

        #Upload File...
        Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -InFile $HealthZip -ErrorAction Continue
    }
    #Upload ShowTech
    IF(Test-Path -Path "$MyTemp\logs\ShowTechs_$CaseNumber*"){
        $ZipPath=Get-ChildItem $MyTemp\logs\ShowTechs_$CaseNumber* | sort lastwritetime | select -last 1 
        #Get the File-Name without path
        $name = (Get-Item $ZipPath).Name

        #The target URL wit SAS Token
        $uri = "https://gsetools.blob.core.windows.net/showtech/$($name)?sp=acw&st=2022-08-14T20:19:23Z&se=2032-08-15T04:19:23Z&spr=https&sv=2021-06-08&sr=c&sig=XfWDMd2y4sQrXm1gxA6up6VRGV5XPrwPkxEINpKTKCs%3D"

        #Define required Headers
        $headers = @{
            'x-ms-blob-type' = 'BlockBlob'
            }

        #Upload File...
        Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -InFile $ZipPath -ErrorAction Continue
    }
    #Upload TSR
    IF(Test-Path -Path $MyTemp\logs -Filter TSRReports_$CaseNumber*){
        $ZipPath=Get-ChildItem -Path $MyTemp\logs -Filter TSRReports_$CaseNumber* -Recurse | sort lastwritetime | select -last 1 
        #Get the File-Name without path
        $name = (Get-Item $ZipPath).Name

        #The target URL wit SAS Token
        $uri = "https://gsetools.blob.core.windows.net/tsrcollect/$($name)?sp=acw&st=2022-08-14T21:28:03Z&se=2032-08-15T05:28:03Z&spr=https&sv=2021-06-08&sr=c&sig=dhqj1OR7bWRkRp4D3HXwnLT%2Ba%2Br4J6ANF80LhKcafAw%3D"

        #Define required Headers
        $headers = @{
            'x-ms-blob-type' = 'BlockBlob'
            }

        #Upload File...
        Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -InFile $ZipPath -ErrorAction Continue
    }
}
ShowMenu
Stop-Transcript
}# End invoke-LogCollector
