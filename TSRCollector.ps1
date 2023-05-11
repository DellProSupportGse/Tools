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
<<<<<<< HEAD
#Start-Transcript -NoClobber -Path "C:\programdata\Dell\TSRCollector\TSRCollector_$DateTime.log"
write-host "$(Start-Transcript -NoClobber -Path "C:\programdata\Dell\TSRCollector\TSRCollector_$DateTime.log")"
=======
Start-Transcript -NoClobber -Path "C:\programdata\Dell\TSRCollector\TSRCollector_$DateTime.log"
>>>>>>> parent of 7947e33 (Update TSRCollector.ps1)
$text=@"
v1.80
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
    Write-host "   all nodes in a cluster into a single share"
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
if (-not ($credential)) {$credential = New-Object System.Management.Automation.PSCredential($user, $secpasswd)}
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

$debugCheck = (Read-Host "Collect Debug logs also (Y/[N]) ").ToUpper()
if ($debugCheck -eq "Y") {
    $DataSelector =  @("HWData","TTYLogs","OSAppData","DebugLogs")
} else {
    $DataSelector =  @("HWData","TTYLogs","OSAppData")
}
# Run TechSupportReport on each node
    ForEach($IP in $iDRACIPs){
        $result=@()
        Write-Host "Collecting TSR from: $IP..."
        $idrac_ip=$IP            
        $Body = @{"ShareType"="Local";"DataSelectorArrayIn"=''}
        $Body["DataSelectorArrayIn"] = $DataSelector
        $Body = $Body | ConvertTo-Json -Compress
        $uri = "https://$idrac_ip/redfish/v1/Dell/Managers/iDRAC.Embedded.1/DellLCService/Actions/DellLCService.SupportAssistCollection"
        Try{
            $RespErr =""
            $result=Invoke-WebRequest -UseBasicParsing -Uri $URI -Credential $credential -Method POST -Headers @{'content-type'='application/json';'Accept'='application/json'} -Body $body -ErrorVariable RespErr 
            Write-Host "$(($result.Content| ConvertFrom-Json).'@Message.ExtendedInfo')"
        }
        Catch{
            $RespErrMessage=$null
            Try {$RespErrMessage=($RespErr.message| ConvertFrom-Json).error.'@Message.ExtendedInfo'.message} catch {}
            IF($RespErrMessage -match 'already running'){
                Write-Host "    ERROR: A SupportAssist job is already running on the server. Please try again later." -ForegroundColor Red
            } ElseIF($RespErrMessage -match 'The authentication credentials included with this request are missing or invalid.' -or $RespErr.Message -eq "The remote server returned an error: (401) Unauthorized."){
                $credential=Get-Credential -Message "Please enter the iDRAC Adminitrator credentials for $idrac_ip"
                $result= Invoke-WebRequest -UseBasicParsing -Uri $URI -Credential $credential -Method POST -Headers @{'content-type'='application/json';'Accept'='application/json'} -Body $body -ErrorVariable RespErr
                Write-Host "$(($result.Content| ConvertFrom-Json).'@Message.ExtendedInfo')"
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
    IF($result.StatusCode -eq 202){Write-Host "    StatusCode:"$result.StatusCode "Successfully scheduled TSR" }Else{Write-Host "    ERROR: StatusCode:" $result.StatusCode "Failed to scheduled TSR" -ForegroundColor Red}
    }


    Write-Host "Please wait while TSRs are collected. Usually this takes 2-5 minutes per node." -ForegroundColor Green
    Write-Host "TSRs will be saved at $MyTemp\logs" -ForegroundColor Green
} #End ShouldProcess
if ($dowait) {
    do {
        foreach ($idrac_ip in $iDRACIPs) {
           $uri = "https://$idrac_ip/redfish/v1/Systems/System.Embedded.1"
           $result = Invoke-WebRequest -Uri $uri -Credential $credential -Method Get -UseBasicParsing -ErrorVariable RespErr -Headers @{"Accept"="application/json"}
           $servicetag = ($result.Content | ConvertFrom-Json).Oem.Dell.DellSystem.ChassisServiceTag
           if (!(test-path "$MyTemp\logs\TSRCollector\TSR*_$($servicetag).zip")) {
               try {$result=Invoke-WebRequest -UseBasicParsing -Uri "https://$idrac_ip/redfish/v1/Dell/sacollect.zip" -Credential $credential -Method GET -OutFile "$MyTemp\logs\TSRCollector\TSR$(get-date -Format "yyyyMMddHHmmss")_$($servicetag).zip" -ErrorAction SilentlyContinue -ErrorVariable RespErr } catch {}
           }
        }
    $TSRsCollected = (Get-ChildItem -Path $MyTemp\logs -Filter "TSR??????????????_*.zip" -Recurse)
    $totalTSRsCollected = $TSRsCollected.Count
    $i++
    Write-Host "$totalTSRsCollected / $($idracIPs.count) TSR's collected so far, and waited $i / 20 minutes"
    if ($totalTSRsCollected -lt $iDRACIPs.count) {Sleep -Seconds 60}
    }
    while ($totalTSRsCollected -lt $iDRACIPs.count -and $i -le 20)
    Get-ChildItem -Path $MyTemp\logs -Filter "TSR??????????????_*.zip" -Recurse | Compress-Archive -DestinationPath "$MyTemp\logs\TSRReports_$($CaseNumber)"

}
return $iDRACIPs
Stop-Transcript
}# End Invoke-TSRCollector