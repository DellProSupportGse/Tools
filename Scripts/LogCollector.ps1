    <#
    .Synopsis
       Invoke-LogCollector
    .DESCRIPTION
       This tool is used to collect logs from nodes or all nodes in a cluster and bring them back to a single location
    .EXAMPLE
       Invoke-LogCollector -DellTSR
    .EXAMPLE
       Invoke-LogCollector
    #>
Function Invoke-LogCollector{
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High')]
        param(
            [switch]$DellTSR,
            $param
        )
# Version
$Ver="1.27"
#region Telemetry Information
Write-Host "Logging Telemetry Information..."
# =====================================================
#region Telemetry Information
# =====================================================
$script:TelemetryReportID    = [guid]::NewGuid().Guid
$script:TelemetryGeoResolved = $false
$script:TelemetryGeoData     = @{}
$script:TelemetryStartupSent = $false
$script:uploadToAzure        = $true
function Write-Indent {
    param(
        [string]$Message,
        [int]$Level = 1,
        [string]$Color = "Gray"
    )
    try {
        $prefix = "  " * $Level
        Write-Host "$prefix$Message" -ForegroundColor $Color
    }
    catch {}
}
function Get-TelemetryMachineHash {
    try {
        $raw = "$env:USERDOMAIN\$env:USERNAME@$env:COMPUTERNAME"
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash)).Replace("-","").Substring(0,24)
    }
    catch {
        return ""
    }
}
function Resolve-TelemetryGeo {
    try {
        if ($script:TelemetryGeoResolved) { return }
        Write-Indent "Resolving Geo Location..."
        try {
            # Prefer local Windows settings
            $LocalRegionInfo = [System.Globalization.RegionInfo]::CurrentRegion
            if (-not $LocalRegionInfo.TwoLetterISORegionName) {
                throw "Unable to determine local region."
            }
            $script:TelemetryGeoData = @{
                country     = [string]$LocalRegionInfo.EnglishName
                countryCode = [string]$LocalRegionInfo.TwoLetterISORegionName
                timezone    = [string](Get-TimeZone).Id
            }
            Write-Indent "Country: $($script:TelemetryGeoData.country)" 2
            Write-Indent "Source : Windows Regional Settings" 2
        }
        catch {
            # Fallback to external IP geolocation
            Write-Indent "WARN: Local region lookup failed - trying ipwho.is" 2 Yellow
            if (-not $script:GeoCache) {
                $script:GeoCache = Invoke-RestMethod "https://ipwho.is/" -TimeoutSec 5
            }
            $response = $script:GeoCache
            if ($response.success -ne $true) {
                throw "ipwho.is did not return a valid response."
            }
            $script:TelemetryGeoData = @{
                country     = [string]$response.country
                countryCode = [string]$response.country_code
                timezone    = [string]$response.timezone.id
            }
            Write-Indent "Country: $($script:TelemetryGeoData.country)" 2
            Write-Indent "Source : ipwho.is fallback" 2
        }
    }
    catch {
        Write-Indent "WARN: Unable to determine geographic information" 2 Yellow
        # Always leave a valid object behind
        $script:TelemetryGeoData = @{
            country     = $null
            countryCode = $null
            timezone    = try { [string](Get-TimeZone).Id } catch { $null }
        }
    }
    finally {
        $script:TelemetryGeoResolved = $true
    }
}
function Send-ToolTelemetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TelemetryName,
        [Parameter(Mandatory=$true)]
        [string]$EventName,
        [Parameter(Mandatory=$true)]
        [string]$Version,
        [Parameter(Mandatory=$true)]
        [string]$Endpoint,
        [int]$ServerCount = 0,
        [int]$GroupCount = 0,
        [switch]$NoGeo,
        [switch]$DebugTelemetry
    )
    if (-not $script:uploadToAzure) { return }
    if ($EventName -match '^(Startup|Launch|AppStart|ToolStart|TelemetryStartup)$') {
        if ($script:TelemetryStartupSent) { return }
        $script:TelemetryStartupSent = $true
    }
    try {
        if (-not $NoGeo) {
            Resolve-TelemetryGeo
        }
        $rowKey = [guid]::NewGuid().Guid
        $partitionKey = $TelemetryName -replace 'TelemetryData$',''
        # ONLY requested table columns are placed in Data.
        $data = [ordered]@{
            PartitionKey = $partitionKey
            RowKey        = $rowKey
            PSVersion     = $PSVersionTable.PSVersion.ToString()
            countryCode   = $script:TelemetryGeoData.countryCode
            MachineHash   = Get-TelemetryMachineHash
            Version       = $Version
            timezone      = $script:TelemetryGeoData.timezone
            ReportID      = $script:TelemetryReportID
            country       = $script:TelemetryGeoData.country
        }
        # Envelope for the Function only. The Function should write Data only.
        $payload = @{
            TelemetryName = $TelemetryName
            TableName     = $TelemetryName
            Data          = $data
        }
        $body = $payload | ConvertTo-Json -Depth 10
        if ($DebugTelemetry) {
            Write-Host "Telemetry Request:" -ForegroundColor Cyan
            Write-Host $body
        }
        $response = Invoke-RestMethod `
            -Method Post `
            -Uri $Endpoint `
            -ContentType "application/json" `
            -Body $body `
            -TimeoutSec 15
        if ($DebugTelemetry) {
            Write-Host "Telemetry Response:" -ForegroundColor Green
            $response | ConvertTo-Json -Depth 10
        }
        else {
            Write-Indent "Telemetry recorded successfully" 1 Green
        }
    }
    catch {
        if ($DebugTelemetry) {
            Write-Warning "Telemetry failed: $($_.Exception.Message)"
            if ($_.ErrorDetails.Message) {
                Write-Warning $_.ErrorDetails.Message
            }
        }
        return
    }
}
 $telemetryParams = @{
     TelemetryName  = "LogCollectorTelemetryData"
     EventName      = "Startup"
     Version        = $Ver
     Endpoint       = "https://gsetools-bufhdqefb8e6ecc6.centralus-01.azurewebsites.net/api/PostTelemetryData"
     DebugTelemetry = $false
 }
 Send-ToolTelemetry @telemetryParams
#endregion
    
Function EndScript{  
    break
}
Function Upload-FileToCase{
param (
    [string]$FilePath = '',
    [string]$ServiceTag = '',
    [string]$CaseNumber = '',
    [string]$PreferredName = '',
    [string]$Email = ''
)
$dfilename=Split-Path -Leaf $FilePath
If (!($Global:CaseSrId)) {$Global:CaseSrId= (Invoke-RestMethod -Uri "https://tdm.dell.com/tdm-file-upload/public/v2/cases-by-generic-id/$CaseNumber").cases.id}
$filesize=(Get-Item $FilePath).length
#$body = @{"customerEmail"="$Email";"fileName"="$dfilename";"fileSize"="20";"lightningCaseId"="$($Global:CaseSrId)";"preferredName"="$PreferredName";"serviceRequestNb"="$CaseNumber"} | ConvertTo-Json
$body = @{"companyName"="";"customerEmail"="$Email";"dellContactEmail"="";"fileName"="$dfilename";"fileSize"="$filesize";"preferredName"="$PreferredName";"serviceRequestNb"="$CaseNumber"} | ConvertTo-Json
$header = @{
 "Accept"="application/json"
 "Content-Type"="application/json"
} 
$StartUpload=Invoke-RestMethod -Headers $header -Body $body -Uri  "https://tdm.dell.com/tdm-file-upload/public/v2/initiate-upload" -Method Post -SessionVariable session
# Define the input file and chunk size
$tempdir=$env:TEMP+"\"+(New-Guid)
New-Item -Path $tempdir -ItemType Directory | Out-Null
$chunkSize = 20000000
$bufferSize = 8192 # Size of the buffer to read/write data
$outputStream=$null
Write-Host "Preparing file for upload"
# Open the input file in binary mode
$inputStream = [System.IO.File]::OpenRead($FilePath)
try {
    $chunkIndex = 1
    Do {
        $chunkFile = Join-Path $tempdir "$(Split-Path -Leaf ($FilePath.substring(0,$FilePath.length-4)))-$chunkIndex"
        $totalBytesRead = 0
        $buffer = New-Object byte[] $bufferSize
        Do {
            $bytesRead = $inputStream.Read($buffer, 0, [Math]::Min($bufferSize, $chunkSize - $totalBytesRead))
            if ($bytesRead -ne 0) { 
                if (!($outputStream)) { $outputStream = [System.IO.File]::OpenWrite($chunkFile)}
                $outputStream.Write($buffer, 0, $bytesRead)
                $totalBytesRead += $bytesRead
            }
        } while ($totalBytesRead -lt $chunkSize -and $bytesRead -gt 0)
        $outputStream.Close()
        $outputStream = $null
        $chunkIndex++
    } while ($totalBytesRead -ge $chunkSize)
} finally {$inputStream.Close()}
$percChunk=100/($chunkIndex-1)
Add-Type -AssemblyName 'System.Net.Http'
$httpClient = New-Object System.Net.Http.Httpclient
Write-Host -NoNewLine "Uploading file."
Foreach ($chunkFile in (gci $tempdir -File | Sort LastWriteTime)) {
    try {$packageFileStream.close()} catch {}
    $packageFileStream = New-Object System.IO.FileStream @($chunkFile.FullName, [System.IO.FileMode]::Open)
    [int]$chunkNumber=$chunkFile.Name.Substring($chunkFile.Name.LastIndexOf("-")).substring(1)
    $contentDispositionHeaderValue = New-Object System.Net.Http.Headers.ContentDispositionHeaderValue "form-data"
    $contentDispositionHeaderValue.Name = "file"
    $contentDispositionHeaderValue.FileName = ("blob")
    $streamContent = New-Object System.Net.Http.StreamContent $packageFileStream
    $streamContent.Headers.ContentDisposition = $contentDispositionHeaderValue
    try {$streamContent.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue $ContentType} catch {}
    $content = New-Object System.Net.Http.MultipartFormDataContent
    $content.add((New-Object System.Net.Http.StringContent $email),'customerEmail')
    $content.add((New-Object System.Net.Http.StringContent $StartUpload.fileId),'fileId')
    $content.add((New-Object System.Net.Http.StringContent $StartUpload.uploadId),'uploadId')
    $content.add((New-Object System.Net.Http.StringContent "$chunkNumber"),'chunkNumber')
    $content.Add($streamContent)
    $httpClient = New-Object System.Net.Http.Httpclient
    $response=$httpClient.PostAsync("https://tdm.dell.com/tdm-file-upload/public/v3/upload-chunk", $content).Result
    if ($response.StatusCode -ne "204") {Write-Warning "Chunk $chunkNumber upload failed!!";$response;$packageFileStream.close();return 1}
    $packageFileStream.close()
    Write-Host -NoNewLine "$([int]($chunkNumber*$percChunk))%."
    $chunkNumber++
} 
Write-Host "."
$body=@{customerEmail="$email";fileId=$($StartUpload.fileId);uploadId=$($StartUpload.uploadId)} | ConvertTo-Json
$response=Invoke-RestMethod -Uri "https://tdm.dell.com/tdm-file-upload/public/v2/upload-complete" -Body $body -Headers @{"Accept"="application/json, text/plain, */*";"Accept-Encoding"="gzip, deflate, br, zstd";"Accept-Language"="en-US,en;q=0.9"} -Method Post -WebSession $session #?uploadId=$($StartUpload.uploadId)&fileId=$($StartUpload.fileId)&chunkNumber=1&customerEmail=$email
$body=@{emailId="$email";fileId=$($StartUpload.fileId);serviceTag=$Stag;language="en_US"} | ConvertTo-Json
$response=Invoke-RestMethod -Uri "https://tdm.dell.com/tdm-file-upload/public/v2/file-status"-Body $body -Headers @{"Accept"="application/json, text/plain, */*";"Accept-Encoding"="gzip, deflate, br, zstd";"Accept-Language"="en-US,en;q=0.9"} -Method Post -WebSession $session
If ($response.uploadCompleted -eq $true) {
    Write-Host "Upload Completed..."
    Remove-Item $tempdir -Force -Recurse
    return 0
} else {
    Write-Warning "Upload Failed!!!"
    return 1
}
}
Clear-Host
# Logs
$DateTime=Get-Date -Format yyyyMMdd_HHmmss
New-Item -ItemType Directory -Force -Path "C:\ProgramData\Dell\LogCollector" -ErrorAction SilentlyContinue | Out-Null
Start-Transcript -NoClobber -Path "C:\ProgramData\Dell\LogCollector\LogCollector_$DateTime.log"
$global:defaultOption=$null
If ((Get-Command Get-StampInformation -ErrorAction SilentlyContinue)) {$global:defaultOption="15"} else {
if ((Get-Service clussvc).StartUpType -ne 'Disabled') {$global:defaultOption="1"} else {
$global:defaultOption="4"}
}
Write-Host "" 
$MyTemp=(Get-Item $env:temp).fullname
$Logs = $MyTemp + "\Logs\"
# Clean up old temporary logs before making a fresh directory
IF(Test-Path -Path $Logs){ Remove-Item $Logs -Recurse -Confirm:$false -Force -ErrorAction SilentlyContinue}
New-Item -ItemType Directory -Force -Path $Logs -ErrorAction SilentlyContinue | Out-Null
try {Start-Job -Name "Telemetry" -ScriptBlock {
} | Out-Null} catch {}
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
Write-Host "To assist with troubleshooting, this tool will collect environment"
Write-Host "information (such as hostnames, IP addresses, and diagnostic logs)"
Write-Host "and attach it to your support case."
Write-Host ""
Write-Host "This data helps support engineers diagnose issues faster."
Write-Host ""
# =====================================================
Write-Host "Do you allow this information to be collected and attached?"
$consent = (Read-Host "(Y/[N]) ").ToUpper()
if ($consent -eq "Y") {
# Collect data to improve customer experience
 Write-Host "Thank you for participating in our program. Your input is valuable to us!"
 $x=0
 $Email=$null
 Do {
    try {$Email = [mailaddress] (Read-Host -Prompt "`r`nPlease enter your email address")} catch {Write-Warning "Email address invalid. Please correct"}
    $x++
 } while ($x -lt 4 -and !($Email))
 If ($x -eq 4) {
    Write-Host "    ERROR: Too many tries. Exiting..." -ForegroundColor Red
    EndScript
 }
  
} else {
  $consent = "N"
 # Do not collect data
 Write-Host "We respect your decision. Your privacy is important to us."
 Write-Host "Logs will be only stored locally."
}
#only collect personal data when $consent eq 'Y'
Write-Host ""
$MyTemp=(Get-Item $env:temp).fullname
$Global:CaseNumber =$null
$Global:CaseSrId=$null
$x=0
 Do {
    If ($consent -eq "Y") {
        try {$Global:CaseNumber = [long] (Read-Host -Prompt "Please enter the relevant technical support case number")} catch {}
        $x++
        try {$Global:CaseSrId= (Invoke-RestMethod -ErrorAction SilentlyContinue -Uri "https://tdm.dell.com/tdm-file-upload/public/v2/cases-by-generic-id/$($Global:CaseNumber)").cases} catch {}
        If (!($Global:CaseSrId.Id) -or $Global:CaseSrId.status -eq "Closed") {Write-Host "Invalid Case Number or Case is Closed. Please try again" -ForegroundColor Yellow;$Global:CaseSrId=$null}
    } else {try {$Global:CaseNumber = [long] (Read-Host -Prompt "Please enter the relevant technical support case number")} catch {}
    If (!($Global:CaseNumber)) {$Global:CaseNumber="99999999999"}}
 } while ($x -lt 4 -and !($Global:CaseSrId) -and $consent -eq "Y")
 If ($x -eq 4) {
    Write-Host "    ERROR: Too many tries. Exiting..." -ForegroundColor Red
    EndScript
 }
# Local collection uses Dell iSM and never asks for iDRAC credentials.
# Uses the published Get-DellTSR-Local.ps1, with optional local override.
Function Invoke-LocalDellTSR {
    $script:TSRFiles = @()
    $tsrOutput = Join-Path ([Environment]::GetFolderPath('CommonDocuments')) ("DellTSR\LogCollector_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + "_" + [guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Path $tsrOutput -Force -ErrorAction Stop | Out-Null
    $scriptNames = @('Get-DellTSR-Local.ps1')
    $candidatePaths = @()
    if ($PSScriptRoot) { $candidatePaths += (Join-Path $PSScriptRoot $scriptNames[0]) }
    $candidatePaths += (Join-Path (Get-Location).Path $scriptNames[0])
    $candidatePaths += (Join-Path 'C:\Dell' $scriptNames[0])
    $tsrScript = $candidatePaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $tsrScript) {
        # Same repository as LogCollector. HTTPS only, and downloaded code is not run when download fails.
        $url = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/refs/heads/main/Scripts/Get-DellTSR-Local.ps1'
        $tsrScript = Join-Path $env:TEMP ("Get-DellTSR-Local_" + [guid]::NewGuid().ToString('N') + '.ps1')
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $tsrScript -UseBasicParsing -ErrorAction Stop
            if ((Get-Item -LiteralPath $tsrScript).Length -lt 100) { throw 'Downloaded script is unexpectedly small.' }
        } catch {
            Write-Warning "Unable to get Get-DellTSR-Local.ps1: $($_.Exception.Message)"
            Write-Host 'Place Get-DellTSR-Local.ps1 next to LogCollector.ps1 or publish it to the Tools repository.' -ForegroundColor Yellow
            Remove-Item -LiteralPath $tsrScript -Force -ErrorAction SilentlyContinue
            return
        }
        $downloadedScript = $tsrScript
    }
    try {
        Write-Host "Running $tsrScript" -ForegroundColor Cyan
        Write-Host "TSR output: $tsrOutput" -ForegroundColor Cyan
        # The standalone script checks / prompts / installs iSM as necessary.
        & $tsrScript -OutputDirectory $tsrOutput
        $script:TSRFiles = @(Get-ChildItem -LiteralPath $tsrOutput -File -Filter '*.zip' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        if (-not $script:TSRFiles.Count) {
            Write-Warning "No TSR ZIP was produced. Check the collection output above; directory: $tsrOutput"
        } else {
            Write-Host "Collected $($script:TSRFiles.Count) TSR ZIP file(s)." -ForegroundColor Green
        }
    } catch {
        Write-Warning "Local TSR collection failed: $($_.Exception.Message)"
    } finally {
        if ($downloadedScript) { Remove-Item -LiteralPath $downloadedScript -Force -ErrorAction SilentlyContinue }
    }
}
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
         Write-Host "0)  APEX Logs (ACP/ECE)"
         Write-Host "1)  Azure Local/HCI/S2D logs (SDDC)"
         Write-Host "2)  PowerEdge logs (TSR)"
         Write-Host "3)  Switch logs (Show Tech)"
         Write-Host "4)  Windows Failover Clustering, Hyper-v and Standalone Server (TSS)"
         Write-Host "5)  Test Dell Azure Local Issues (TALI)"
         Write-Host "6)  Deprecated - Use old method to collect Azure Local/HCI/S2D logs"
         Write-Host "Q to Quit"
         Write-Host ""
         Write-Host "NOTE: Initial logs for ALL Azure Local (not S2D) cases should at minimum type 15 for both an SDDC and TALI logs." -ForegroundColor Yellow
         Write-Host "      If TSRs are also needed then put in 125" -ForegroundColor Yellow
         Write-Host ""
         Write-Host "Default option is $($global:defaultOption). To select this just hit enter" -ForegroundColor Cyan
         Write-Host ""
         $selection = Read-Host "Type a number(s) (ex. 15) and press [Enter] [$($global:defaultOption)]"
     }
    until ($selection -match '[0-6,qQ,hH]|^$')
    $Global:CollectACPECE  = "N"
    $Global:CollectSTS     = "N"
    $Global:CollectSDDC    = "N"
    $Global:CollectTSR     = "N"
    $Global:CollectTSS     = "N"
    $Global:CollectTALI    = "N"
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
    If($selection -eq "") {$selection=$global:defaultOption}
    If($selection -eq 5) {
        $GetSDDCAlso=Read-Host "It's recommended to run TALI with the SDDC to gather a full set of usable logs. Would you like to include the SDDC? ([Y]/n)"
        If ($GetSDDCAlso -ine "n") {$selection = 15}
    }
    IF($selection -match 0){
        Write-Host "Gathering APEX Logs (ACP/ECE)..."
        $Global:CollectACPECE = "Y"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="RunAcpLogCollector";$repo="PowershellScripts";'+(new-object System.net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/Scripts/run_acp_log_collect.ps1'))
        $ACPLogPath = Invoke-RunAPEXlogsCollector -confirm:$False
    }
    IF($selection -match 3){
        Write-Host "Gathering Switch logs (Show Tech)..."
        $Global:CollectSTS = "Y"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="GetShowTech";$repo="PowershellScripts"'+(new-object System.net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/Scripts/GetShowTech.ps1'))
        Invoke-GetShowTech -confirm:$False -CaseNumber $Casenumber
    }
     IF($selection -match 2){
         Write-Host "Collecting PowerEdge logs (TSR) locally (no iDRAC credentials)..." -ForegroundColor Cyan
         $Global:CollectTSR = "Y"
         Invoke-LocalDellTSR
     }
    $SignalFile = $null
    IF($selection -match 5){
        if ($PSSenderInfo) {Write-Host -ForegroundColor Yellow "This module is not supported using a remote powershell session. Please run locally";EndScript}
        If ((invoke-command -scriptblock {try {get-cluster -ErrorAction SilentlyContinue} catch {}}).Name -eq $null) {Write-Host -ForegroundColor DarkYellow "This module MUST be run locally on a cluster node. Waiting 10 seconds.";sleep 10}
        Write-Host "Collecting Test Dell Azure Local Issues script (TALI)..."
        $Global:CollectTALI = "Y"
        If ($selection -notmatch "0|1|2|3|4|6|7|8|9") {
            Echo TALI;[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="TALI";$repo="PowershellScripts"; '+(new-object net.webclient).DownloadString('http'+'s://raw.g'+'ithubusercontent.com/DellProSupportGse/Tools/main/Scripts/TALI.ps1'))
            Test-DellAzureLocalIssues
        } else {
            $SignalFile = Join-Path $env:TEMP "TALI_Signal_$([Guid]::NewGuid().Guid).tmp"
            # Ensure the file does not exist beforehand
            if (Test-Path $SignalFile) { Remove-Item $SignalFile -Force }
            $Payload = '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression(''$module=''''TALI'''';$repo=''''PowershellScripts''''; ''+(new-object net.webclient).DownloadString(''http''+''s://raw.g''+''ithubusercontent.com/DellProSupportGse/Tools/main/Scripts/TALI.ps1''));Test-DellAzureLocalIssues'
            $CommandToRun = "$Payload; New-Item -Path '$SignalFile' -ItemType File -Force | Out-Null"
            Start-Process powershell -ArgumentList '-NoExit', '-Command', $CommandToRun
        }
    }
    IF($selection -match 1){
        if ($PSSenderInfo) {Write-Host -ForegroundColor Yellow "This module is not supported using a remote powershell session. Please run locally";EndScript}
        If ((invoke-command -scriptblock {try {get-cluster -ErrorAction SilentlyContinue} catch {}}).Name -eq $null) {Write-Host -ForegroundColor DarkYellow "This module MUST be run locally on a cluster node. Waiting 10 seconds.";sleep 10}
        Write-Host "Collecting Azure Local/HCI/S2D logs (SDDC)..."
        $Global:CollectSDDC = "Y"
        [int]$TimeoutSeconds = 20
        [int]$HoursOfEvents = 168
        [string]$DefaultValue = "6"
        [string]$Prompt = "How many days to collect? [$DefaultValue]: "
        [int]$DaysOfLogs = $DefaultValue
        $finalInput=$null
        # Verify Console is available (fails in ISE, works in standard console/terminal/VS Code)
        if ($Host.Name -eq "Visual Studio Code Host" -or $null -eq [Console]::KeyAvailable) {
            # Fallback if Console API is unavailable
            Write-Warning "Console API not fully supported in this host. Using default value of $DefaultValue days."
        } else {
            Write-Host $Prompt -NoNewline
            $inputBuffer = New-Object System.Text.StringBuilder
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $timeoutMilliseconds = $TimeoutSeconds * 1000
            while ($stopwatch.ElapsedMilliseconds -lt $timeoutMilliseconds -and $finalInput -eq $null -and $HoursOfEvents -eq 168) {
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    # Case 1: User pressed Enter
                    if ($key.Key -eq [ConsoleKey]::Enter) {
                        Write-Host "" # Move to next line
                        $finalInput = $inputBuffer.ToString()
                        if (!([string]::IsNullOrEmpty($finalInput))) { $DaysOfLogs=$finalInput }
                    }
                    # Case 2: User pressed Backspace
                    elseif ($key.Key -eq [ConsoleKey]::Backspace) {
                        if ($inputBuffer.Length -gt 0) {
                            $inputBuffer.Remove($inputBuffer.Length - 1, 1) | Out-Null
                            # Erase character visually from console
                            Write-Host "`b `b" -NoNewline
                        }
                    }
                    # Case 3: Enforce numeric input only
                    elseif ($key.KeyChar -match '[0-9]') {
                        $inputBuffer.Append($key.KeyChar) | Out-Null
                        Write-Host $key.KeyChar -NoNewline
                    }
                }
                else {
                    Start-Sleep -Milliseconds 50 # Prevent high CPU utilization
                }
            }
            Write-Host "" # Move to next line
            If ($finalInput -eq $null) { Write-Host "Timeout reached. Proceeding with default: $DefaultValue"}
        }
        If ($HoursOfEvents -eq 168) {$HoursOfEvents=($DaysOfLogs+1)*24}
        If (gcm Get-Cluster) {$ClusterName=(Get-Cluster).Name} else {$ClusterName=$env:COMPUTERNAME}
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="GetDellSDDC";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/source/refs/heads/main/GetDellSDDC.ps1'))
        Invoke-GetDellSDDC -IncludeReliabilityCounters -HoursOfEvents $HoursOfEvents -PerfSamples 30 -RunCluChk
        $HealthZip = Get-ChildItem "$($env:USERPROFILE)\HealthTest-$ClusterName-*.zip" | sort lastwritetime | select -last 1
        $HealthZipNew = $HealthZip.BaseName + "-" + $CaseNumber + ".zip"
        Rename-Item -Path $HealthZip -NewName $HealthZipNew -Verbose
    }
    IF($selection -match 6){
        if ($PSSenderInfo) {Write-Host -ForegroundColor Yellow "This module is not supported using a remote powershell session. Please run locally";EndScript}
        If ((invoke-command -scriptblock {try {get-cluster -ErrorAction SilentlyContinue} catch {}}).Name -eq $null) {Write-Host -ForegroundColor DarkYellow "This module MUST be run locally on a cluster node. Waiting 10 seconds.";sleep 10}
        Write-Host "Collecting Azure Local/HCI/S2D logs (SDDC)..."
        $Global:CollectSDDC = "Y"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="SDDC";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/Scripts/RunSDDC.ps1'))
        Invoke-RunSDDC -confirm:$False -CaseNumber $CaseNumber
    }
    IF($selection -match 4){
        if ($PSSenderInfo) {Write-Host -ForegroundColor Yellow "This module is not supported using a remote powershell session. Please run locally";EndScript}
        Write-Host "Collecting Windows Server (TSS)..."
        $Global:CollectTSS = "Y"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="TSSCollect"; $repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/TommyPaulkDell/TSS/main/TSSCollect.ps1'))
        Invoke-TSSCollect -confirm:$False -CaseNumber $CaseNumber
    }
    IF($selection -imatch 'q'){
        Write-Host "Bye Bye..."
        EndScript
    }
    If ($SignalFile -ne $null) {
        If (-not (Test-Path $SignalFile -ErrorAction SilentlyContinue)) {Write-Host "Waiting for TALI remote window to finish execution..."}
        while (-not (Test-Path $SignalFile -ErrorAction SilentlyContinue)) {
            Start-Sleep -Milliseconds 250
        }
        # 5. Cleanup the signal file and resume execution
        Remove-Item $SignalFile -Force -ErrorAction SilentlyContinue
    }
    UploadLogs
}#End of ShowMenu
Function ZipNClean{
    # Zip up
        Write-Host "Compressing Logs..."
        $MyTemp=(Get-Item $env:temp).fullname
        $DT=Get-Date -Format "yyyyMMddHHmm"
        IF(Test-Path -Path "$MyTemp\logs"){
            Compress-Archive -Path "$MyTemp\logs\*.*" -DestinationPath "c:\dell\LogCollector_$($DT).zip"
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
    $MyTemp=(Get-Item $env:temp).fullname
    if ($consent -eq "Y") {Write-Host "Uploading files. Please wait...." -ForegroundColor Cyan} else {Write-Host "Please upload the following logs using https://tdm.dell.com/file-upload" -ForegroundColor Cyan}
    $consent
    # Upload ACPECE logs
        IF($ACPLogPath){
            Write-Host "ACP log path $ACPLogPath" -ForegroundColor Cyan
            If ($consent -eq "Y") {
                $s=Upload-FileToCase -FilePath $ACPLogPath -CaseNumber $CaseNumber -Email $email.Address -PreferredName $email.User -ServiceTag "$(Get-WmiObject Win32_BIOS | Select-Object -ExpandProperty SerialNumber)"
                if ($s -eq 0) {Write-Host "ACP/ECE logs uploaded to case $CaseNumber" -ForegroundColor Green}
                    else {Write-Host "ACP/ECE logs upload FAILED!!. Please upload $($ACPLogPath) using " -NoNewline -ForegroundColor DarkYellow;Write-Host "https://tdm.dell.com/file-upload" -ForegroundColor Cyan}
                }
            }
    #Upload SDDC
    IF(Test-Path -Path "$($env:USERPROFILE)\Healthtest*$CaseNumber*"){
        $HealthZip = Get-ChildItem "$($env:USERPROFILE)\Healthtest*$CaseNumber*" | sort lastwritetime | select -last 1 
        Write-Host "SDDC log path $($HealthZip.Fullname)" -ForegroundColor Cyan
        If ($consent -eq "Y") {
            $s=Upload-FileToCase -FilePath $HealthZip.Fullname -CaseNumber $CaseNumber -Email $email.Address -PreferredName $email.User -ServiceTag "$(Get-WmiObject Win32_BIOS | Select-Object -ExpandProperty SerialNumber)"
        
            #Upload File...
            #$resp=Invoke-RestMethod -Uri "$uri" -Method Put -Headers $headers -InFile $HealthZip -ErrorAction Continue -Verbose 4>&1
            if ($s -eq 0) {Write-Host "SDDC uploaded to case $CaseNumber" -ForegroundColor Green}
            else {Write-Host "SDDC upload FAILED!!. Please upload $($HealthZip.Fullname) using "-NoNewline -ForegroundColor DarkYellow;Write-Host "https://tdm.dell.com/file-upload" -ForegroundColor Cyan}
        }
    }
    #Upload ShowTech
    IF(Test-Path -Path "$MyTemp\logs\ShowTechs_$CaseNumber*"){
        $ZipPath=Get-ChildItem $MyTemp\logs\ShowTechs_$CaseNumber* | sort lastwritetime | select -Last 1
        Write-Host "ShowTech log path $($ZipPath.Fullname)" -ForegroundColor Cyan
        if ($consent -eq "Y") {
            Expand-Archive -Path $ZipPath.Fullname -DestinationPath ($env:temp+"\$($ZipPath.BaseName)")
            $content= Get-Content (Get-ChildItem ($env:temp + "\$($ZipPath.BaseName)") -File | Select -First 1).Fullname
            Remove-Item ($env:temp + "\$($ZipPath.BaseName)") -Recurse -Force
            $parsed=($content | Select-String -context 0,2 -SimpleMatch "Svc Tag").ToString()
            $servicetag=(($parsed.split("`r")[2]) -split "  ")[-2]
            $s=Upload-FileToCase -FilePath $ZipPath.Fullname -CaseNumber $CaseNumber -Email $email.Address -PreferredName $email.User -ServiceTag "$(Get-WmiObject Win32_BIOS | Select-Object -ExpandProperty SerialNumber)"
            #Upload File...
            #$resp2=Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -InFile $ZipPath -ErrorAction Continue -Verbose 4>&1
            if ($s -eq 0) {Write-Host "Showtech uploaded to case $CaseNumber" -ForegroundColor Green}
            else {Write-Host "Showtech upload FAILED!!. Please upload $($ZipPath.Fullname) using " -NoNewline -ForegroundColor DarkYellow ;Write-Host "https://tdm.dell.com/file-upload" -ForegroundColor Cyan}
        }
    }
    #Upload TSS
    IF((Get-ChildItem -Path "C:\Dell\Logs" -Filter "$($CaseNumber).zip" -Recurse).count){
        $ZipPath=Get-ChildItem -Path "C:\Dell\Logs" -Filter "$($CaseNumber).zip" -Recurse | sort lastwritetime | select -last 1
        $ZipPath=Rename-Item $ZipPath.FullName "TSS-$($ZipPath.Name)" -PassThru
        Write-Host "TSS log path $($ZipPath.Fullname)" -ForegroundColor Cyan
        if ($consent -eq "Y") {
            #Upload File...
            $s=Upload-FileToCase -FilePath $ZipPath.Fullname -CaseNumber $CaseNumber -Email $email.Address -PreferredName $email.User -ServiceTag "$(Get-WmiObject Win32_BIOS | Select-Object -ExpandProperty SerialNumber)"
            if ($s -eq 0) {Write-Host "TSS uploaded on case $CaseNumber" -ForegroundColor Green}
            else {Write-Host "TSS upload FAILED!!. Please upload $($ZipPath.Fullname) using " -NoNewline -ForegroundColor DarkYellow ;Write-Host "https://tdm.dell.com/file-upload" -ForegroundColor Cyan}
        }
    }
    # Upload only the TSR ZIP files generated by this invocation (not old files).
    foreach ($ZipPath in @($script:TSRFiles)) {
        if (-not $ZipPath -or -not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) { continue }
        Write-Host "TSR log path $ZipPath" -ForegroundColor Cyan
        if ($consent -eq "Y") {
            try {
                $s = Upload-FileToCase -FilePath $ZipPath -CaseNumber $CaseNumber `
                    -Email $email.Address -PreferredName $email.User `
                    -ServiceTag (Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue).SerialNumber
                if ($s -eq 0) { Write-Host "TSR uploaded to case $CaseNumber" -ForegroundColor Green }
                else { throw "Upload service returned failure code $s" }
            } catch {
                Write-Warning "TSR upload FAILED: $($_.Exception.Message)"
                Write-Host "Manually upload $ZipPath at https://tdm.dell.com/file-upload" -ForegroundColor Yellow
            }
        } else {
            Write-Host "TSR saved locally: $ZipPath (upload not authorized)" -ForegroundColor Yellow
        }
    }
    IF($Global:CollectTALI -eq "Y" -and  (Get-ChildItem -Path "C:\ProgramData\Dell\Test-DellAzureLocalIssues-*").count){
        $TALI=Get-ChildItem "C:\ProgramData\Dell\Test-DellAzureLocalIssues-*" | sort lastwritetime | select -last 1 
        Write-Host "TALI log path $($TALI.Fullname)" -ForegroundColor Cyan
        if ($consent -eq "Y") {
            #Upload File...
            $s=Upload-FileToCase -FilePath $TALI.Fullname -CaseNumber $CaseNumber -Email $email.Address -PreferredName $email.User -ServiceTag "$(Get-WmiObject Win32_BIOS | Select-Object -ExpandProperty SerialNumber)"
            if ($s -eq 0) {Write-Host "TALI uploaded on case $CaseNumber" -ForegroundColor Green}
            else {Write-Host "TALI upload FAILED!!. Please upload $($TALI.Fullname) using " -NoNewline -ForegroundColor DarkYellow ;Write-Host "https://tdm.dell.com/file-upload" -ForegroundColor Cyan}
        }
    }
}
if ($DellTSR) {
    Write-Host "-DellTSR mode: collecting only the local PowerEdge TSR." -ForegroundColor Cyan
    $Global:CollectTSR = "Y"
    Invoke-LocalDellTSR
    UploadLogs
} else {
    ShowMenu
}
Stop-Transcript
}# End invoke-LogCollector