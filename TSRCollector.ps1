 <#
    .Synopsis
       Invoke-TSRCollector
    .DESCRIPTION
       This tool is used to collect TSRs from all nodes in a cluster and bring them back to a single share
    .EXAMPLE
       Invoke-TSRCollector
    #>
Function Invoke-TSRCollector{
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High')]
        param(
            $param,
    [Parameter(Mandatory=$False, Position=1)]
            [string] $CaseNumber,
    [Parameter(Mandatory=$False, Position=2)]
            [System.Management.Automation.PSCredential]
            [System.Management.Automation.Credential()]
            $credential = [System.Management.Automation.PSCredential]::Empty)
## Gather Tech Support Report Collector for all nodes in a cluster
    CLS
Function EndScript{  
    break
}
    Function Get-iDRACIPaddresses{
        $iDIPs=Read-Host "Please enter comma delimited list of iDRAC IP addresse(s)"
        $i=0
        IF($iDIPs -imatch ','){$iDIPs=$iDIPs -split ','}
        While(($iDIPs.count -eq ($iDIPs | %{[IPAddress]$_.Trim()}).count) -eq $False){
            $i++
            Write-Host "WARNING: Not a valid IP. Please try again." -ForegroundColor Yellow
            $iDIPs=Read-Host "Please enter comma delimited list of switch IP addresses"
            IF($iDIPs -imatch ','){$iDIPs=$iDIPs -split ','}
            IF($i -ge 2){
                Write-Host "ERROR: Too many attempts. Exiting..." -ForegroundColor Red
                break script
            }
        }
        #$iDRACIPs=$iDIPs
        return $iDIPs
    }

$DateTime=Get-Date -Format yyyyMMdd_HHmmss
#Start-Transcript -NoClobber -Path "C:\programdata\Dell\TSRCollector\TSRCollector_$DateTime.log"
write-host "$(Start-Transcript -NoClobber -Path "C:\programdata\Dell\TSRCollector\TSRCollector_$DateTime.log")"
$text=@"
v1.92
  _____ ___ ___    ___     _ _        _           
 |_   _/ __| _ \  / __|___| | |___ __| |_ ___ _ _ 
   | | \__ \   / | (__/ _ \ | / -_) _|  _/ _ \ '_|
   |_| |___/_|_\  \___\___/_|_\___\__|\__\___/_|  
                                                  
                                    by: Jim Gandy
"@
Write-Host $text
$Title=@()
    #$Title+="Welcome to Tech Support Report Collector"
    Write-host $Title
#    Write-host " "
    Write-host "   This tool is used to collect TSRs from"
    Write-host "   all nodes in a cluster into a single zip file"
    Write-host " "
    if ($PSCmdlet.ShouldProcess($param)) {
# Fix 8.3 temp paths
    $MyTemp=(Get-Item $env:temp).fullname
    
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
if (-not ($Casenumber)) {$dowait=$true;$CaseNumber = Read-Host -Prompt "Please Provide the case number TSR's are being collected for"} else {$dowait=$false}
$user = "root"
$pass= "calvin"
$secpasswd = ConvertTo-SecureString $pass -AsPlainText -Force
if ($credential.username -eq $null) {
    Do {
       $credential=Get-Credential -Message "Please enter the iDRAC Administrator credentials" -UserName root;$cred2=Get-Credential -Message "Confirm iDRAC Password" -UserName $credential.GetNetworkCredential().UserName
    } while (($credential.GetNetworkCredential().Password -ne $cred2.GetNetworkCredential().Password) -or ($credential.GetNetworkCredential().UserName -ne $cred2.GetNetworkCredential().UserName))
}
# Gathers the iDRAC IP addresses from all nodes
If(Get-Service clussvc -ErrorAction SilentlyContinue){
    Write-Host "Gathering the iDRAC IP Addresses from cluster nodes..."
    $iDRACIPs=Invoke-Command -ComputerName (Get-ClusterNode -Cluster (Get-Cluster).Name) -ScriptBlock {
    (Get-PcsvDevice).IPv4Address
    }
}Else{
    #$dowait=$true
    # Get iDRAC IP addresses
    $iDRACIPs = Get-iDRACIPaddresses
}
Do{
    Write-Host "    iDRAC IP Address(s):"
    Write-host "        $iDRACIPs"
    $iDRACIPCheck = Read-Host "    Is the list above the correct list of iDRAC IP Addresses? (Y/N)"
}
until ($iDRACIPCheck -match '[yY,nN]')
IF($iDRACIPCheck -imatch "n"){
    #$dowait=$true
    $iDRACIPs = Get-iDRACIPaddresses
    Do{
    Write-Host "    iDRAC IP Address(s):"
    Write-host "        $iDRACIPs"
    $iDRACIPCheck = Read-Host "    Is the list above the correct list of iDRAC IP Addresses? (Y/N)"
}
until ($iDRACIPCheck -match '[yY,nN]')
}
IF($iDRACIPCheck -imatch "n"){Write-Host "Too many tries. Rerun script";Stop-Transcript;Break}

$iDracIPs = $iDracIPs | %{[PSCustomObject]@{"iDracIP"=$_;"Credential"=$credential}}

$debugCheck = (Read-Host "Collect Debug logs also (Y/[N]) ").ToUpper()
if ($debugCheck -eq "Y") {
    $DataSelector =  @("HWData","TTYLogs","OSAppData","DebugLogs")
} else {
    $DataSelector =  @("HWData","TTYLogs","OSAppData")
}
$draccreds=@{}
$token = $null
$session = $null
# Run TechSupportReport on each node
    ForEach($IP in $iDRACIPs){
        $credfail=$null
        $result=@()
        Write-Host "Starting TSR collection from: $IP..."
        $idrac_ip=$IP.iDracIP
        $token=$null      
        try {
            # 1. Create a session and get X-auth token
            $loginUri = "https://$idrac_ip/redfish/v1/SessionService/Sessions"
 
            $body = @{
                UserName = $credential.UserName
                Password = $credential.GetNetworkCredential().Password
            } | ConvertTo-Json
            $session=$null
            $RespErr=$null
            $session = Invoke-WebRequest -Uri $loginUri -Method Post -Body $body -ContentType "application/json" -UseBasicParsing -ErrorVariable RespErr 
 
            # Token is returned in the X-Auth-Token response header
            $token = $token = $session.Headers['X-Auth-Token'].Trim()
            $sessionUrl = $session.Headers['Location']
 
            # Location is usually relative, e.g. /redfish/v1/SessionService/Sessions/1
            if ($sessionUrl -and -not $sessionUrl.StartsWith('http')) {
                $sessionUrl = "https://$idrac_ip$sessionUrl"
            }
        } catch {
            Try {if ($RespErr) {$RespErrMessage=($RespErr.message| ConvertFrom-Json).error.'@Message.ExtendedInfo'.message}} catch {}
            IF($RespErrMessage -match 'The authentication credentials included with this request are missing or invalid.' -or $RespErr.Message -eq "The remote server returned an error: (401) Unauthorized."){
                $iDRACIPs[$iDRACIPs.IndexOf($idrac_ip)]="!$idrac_ip"
                $credfail="!"
                $dowait=$true
                $newcredential=Get-Credential -Message "Please enter the iDRAC Administrator credentials for $idrac_ip"
                
                # 1. Create a session and get X-auth token
                $loginUri = "https://$idrac_ip/redfish/v1/SessionService/Sessions"
 
                $body = @{
                    UserName = $newcredential.UserName
                    Password = $newcredential.GetNetworkCredential().Password
                } | ConvertTo-Json
                $session = $null
                $session = Invoke-WebRequest -Uri $loginUri -Method Post -Body $body -ContentType "application/json" -UseBasicParsing -ErrorVariable RespErr 
 
                # Token is returned in the X-Auth-Token response header
                $token=$null
                $token = $session.Headers['X-Auth-Token'].Trim()
                If ($token) {
                    $draccreds.add("!$idrac_ip",$newcredential)
                    $sessionUrl = $session.Headers['Location']
                    $IP.Credential=$newcredential
                }
 
                # Location is usually relative, e.g. /redfish/v1/SessionService/Sessions/1
                if ($sessionUrl -and -not $sessionUrl.StartsWith('http')) {
                    $sessionUrl = "https://$idrac_ip$sessionUrl"
                }
            }
        }
        $session=$null
        $iDRACIPs[$iDRACIPs.IndexOf($idrac_ip)]="$credfail$idrac_ip"
        # 2. Use the token for a GET request
      <#  $uri = "https://$idracIP/api/Systems(1)"
        $response = Invoke-WebRequest -Uri $uri -Method Get -Headers $headers -UseBasicParsing

        $response.Content | ConvertFrom-Json#>
        $Body = @{"ShareType"="Local";"DataSelectorArrayIn"=''}
        $Body["DataSelectorArrayIn"] = $DataSelector
        $Body = $Body | ConvertTo-Json -Compress
        $headers = @{
            'Content-Type' = 'application/json'
            'X-Auth-Token' = $token
        }
        $uri = "https://$idrac_ip/redfish/v1/Dell/Managers/iDRAC.Embedded.1/DellLCService/Actions/DellLCService.SupportAssistCollection"
        Try{
            $RespErr =""
            #$result=Invoke-WebRequest -UseBasicParsing -Uri $URI -Credential $credential -Method POST -Headers @{'content-type'='application/json';'Accept'='application/json'} -Body $body -ErrorVariable RespErr 
            $result=Invoke-WebRequest -UseBasicParsing -Uri $URI -Method POST -Headers $headers -Body $body -ErrorVariable RespErr 
            Write-Host "$(($result.Content| ConvertFrom-Json).'@Message.ExtendedInfo')"
        } Catch{
            $RespErrMessage=$null
            $credfail=""
            Try {$RespErrMessage=($RespErr.message| ConvertFrom-Json).error.'@Message.ExtendedInfo'.message} catch {}
            IF($RespErrMessage -match 'already running'){
                Write-Host "    ERROR: A SupportAssist job is already running on the server. Please try again later." -ForegroundColor Red
            }
        }
    IF($RespErrMessage -match "Unable to run the method because the requested HTTP method is not allowed.") {
        Write-Warning "Idrac8 Detected. Using racadm"
        try {
            $tag=(racadm -r $idrac_ip -u "$($credential.UserName)" -p "$($credential.GetNetworkCredential().Password)" getsysinfo | findstr Service).substring(26)
            racadm -r $idrac_ip -u "$($credential.UserName)" -p "$($credential.GetNetworkCredential().Password)" techsupreport export -f "$Mytemp\logs\TSRCollector\TSR$(get-date -Format 'yyyyMMddHHmmss')_$tag.zip"
            $result = @([pscustomobject]@{statuscode=202})
        } catch {Write-host -ForegroundColor Red "ERROR: Racadm failed. racadm may be missing"}
    }
    if ($sessionUrl -and $token) {
    try {
        Invoke-WebRequest -Uri $sessionUrl -Method Delete -Headers @{'X-Auth-Token' = $token} -UseBasicParsing -ErrorAction SilentlyContinue | Out-Null
    } catch {}
    }
    IF($result.StatusCode -eq 202){Write-Host "    StatusCode:"$result.StatusCode "Successfully scheduled TSR" }
    Else{
        $iDRACIPs[$iDRACIPs.IndexOf("$credfail$idrac_ip")]="#$idrac_ip"
        Write-Host "    ERROR: StatusCode:" $result.StatusCode "Failed to scheduled TSR" -ForegroundColor Red
        }
    }


    Write-Host "Please wait while TSRs are collected. Usually this takes 2-5 minutes per node." -ForegroundColor Green
    Write-Host "TSRs will be saved at $MyTemp\logs" -ForegroundColor Green
} #End ShouldProcess
if ($dowait) {
    New-Item "$MyTemp\logs\TSRCollector" -ItemType "directory" -ErrorAction SilentlyContinue | Out-Null
    do {
        $idracCount=$iDRACIPs.count
        $token = $null
        $session = $null
        foreach ($IP in $iDRACIPs) {
           $idrac_ip=$IP.iDracIP
           #$drac_Cred=($idrac_ip.split("_"))[-1].trim()
           #if ($idrac_ip.contains("!") -and -not $idrac_ip.Contains("#")) {$drac_Cred=$draccreds[$idrac_ip]}
           if (!($idrac_ip.Contains("#"))) {
               $drac_Cred=$IP.Credential
               #if ($idrac_ip.contains("!") -and -not $idrac_ip.Contains("#")) {$drac_Cred=$draccreds[$idrac_ip]}
               $idrac_ip=$idrac_ip.replace("!","")
                $body = @{
                    UserName = $drac_Cred.UserName
                    Password = $drac_Cred.GetNetworkCredential().Password
                } | ConvertTo-Json
                $session=$null
                $RespErr=$null
                $loginUri = "https://$idrac_ip/redfish/v1/SessionService/Sessions"
                $session = Invoke-WebRequest -Uri $loginUri -Method Post -Body $body -ContentType "application/json" -UseBasicParsing -ErrorVariable RespErr 
 
                # Token is returned in the X-Auth-Token response header
                $token = $session.Headers['X-Auth-Token'].Trim()
                $sessionUrl = $session.Headers['Location']
 
                # Location is usually relative, e.g. /redfish/v1/SessionService/Sessions/1
                if ($sessionUrl -and -not $sessionUrl.StartsWith('http')) {
                    $sessionUrl = "https://$idrac_ip$sessionUrl"
                }
                $headers = @{
                  'Content-Type' = 'application/json'
                  'X-Auth-Token' = $token
               }
               #Write-Host "Checking $idrac_ip with token $token"
           }
           if (!($idrac_ip.Contains("#"))) {
                $uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1"
                $result = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers $headers
                $servicetag = ($result.Content | ConvertFrom-Json).Oem.Dell.DellSystem.ChassisServiceTag
                if (!(test-path "$MyTemp\logs\TSRCollector\TSR*_$($servicetag).zip")) {
                    try {$result=Invoke-WebRequest -UseBasicParsing -Uri "https://$idrac_ip/redfish/v1/Dell/sacollect.zip" -Headers $headers -Method GET -OutFile "$MyTemp\logs\TSRCollector\TSR$(get-date -Format "yyyyMMddHHmmss")_$($servicetag).zip" -ErrorAction SilentlyContinue -ErrorVariable RespErr} catch {}
                } 
           } else {$idracCount--}
           if ($sessionUrl -and $token) {
                try {
                    Invoke-WebRequest -Uri $sessionUrl -Method Delete -Headers @{'X-Auth-Token' = $token} -UseBasicParsing -ErrorAction SilentlyContinue | Out-Null
                } catch {}
           }

        }
    $TSRsCollected = (Get-ChildItem -Path $MyTemp\logs -Filter "TSR??????????????_*.zip" -Recurse)
    $totalTSRsCollected = $TSRsCollected.Count
    $i++
    Write-Host "$totalTSRsCollected / $($idracCount) TSR's collected so far, and waited $i / 20 minutes"
    if ($totalTSRsCollected -lt $idracCount) {Sleep -Seconds 60}
    }
    while ($totalTSRsCollected -lt $idracCount -and $i -le 20)
    Get-ChildItem -Path $MyTemp\logs -Filter "TSR??????????????_*.zip" -Recurse | Compress-Archive -DestinationPath "$MyTemp\logs\TSRReports_$(get-date -Format "yyyyMMdd-HHmm")_$($CaseNumber)"
    foreach ($idrac_ip in $iDRACIPs) {if (($idrac_ip -match "#")) {Write-Host "ERROR: Failed to capture TSR from $idrac_ip" -ForegroundColor Red}}
    $iDRACIPs=""
}
return $iDRACIPs
Stop-Transcript
}# End Invoke-TSRCollector
