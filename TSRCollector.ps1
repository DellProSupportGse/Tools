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
            [Parameter(Mandatory=$False, Position=1)]
            [bool] $LeaveShare,
            $param,
	    [Parameter(Mandatory=$False, Position=2)]
         [string] $CaseNumber)
## Gather Tech Support Report Collector for all nodes in a cluster
    CLS
Function EndScript{  
    break
}
$DateTime=Get-Date -Format yyyyMMdd_HHmmss
Start-Transcript -NoClobber -Path "C:\programdata\Dell\TSRCollector\TSRCollector_$DateTime.log"
$text=@"
v1.71
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
if (-not ($Casenumber)) {$CaseNumber = Read-Host -Prompt "Please Provide the case number TSR's are being collected for"}
$user = "root"
$pass= "calvin"
$secpasswd = ConvertTo-SecureString $pass -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($user, $secpasswd)
# IP address of the machine sharing
    Write-Host "Gathering Host IP Address..."
    $NSLookupOut=cmd /c "nslookup $env:COMPUTERNAME"
    ForEach($item in $NSLookupOut){
        $NSLookupAll+=$item
    }
    $ShareIP=(($NSLookupAll -split 'Name:    ')[-1] -split 'Address:  ')[-1]
    IF($ShareIP -notmatch "^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)(\.(?!$)|$)){4}$") {
        $ShareIP=(($NSLookupAll -split 'Name:    ')[-1] -split 'Addresses:  ')[-1]
        $ShareIP=($ShareIP -split "	  ")[-1]
    }
    Write-Host "    Host IP: $ShareIP"
# Create a new folder and shares it
    Write-Host "Creating a new shared folder to save the TSRs..."
    $ShareName = "Logs"
    $ShareFolder=$MyTemp+"\"+$ShareName+"\TSRCollector\"
   IF(Test-Path $ShareFolder){Remove-Item -Path $ShareFolder -Force}
    New-Item -ItemType Directory -Force -Path $ShareFolder  >$null 2>&1
    New-SmbShare -Name "Logs" -Path "$ShareFolder" -Temporary -FullAccess (([System.Security.Principal.SecurityIdentifier]("S-1-1-0")).Translate([System.Security.Principal.NTAccount])) >$null 2>&1
    Write-Host "    Share location is $ShareFolder"
# Gets the logged on creds
    Write-Host "Gathering the credentials to access the share..."
    $sus = $env:UserName
    #$sdom = (Get-WmiObject win32_computersystem).Domain
    $sdom = cmd /c "whoami"
    $sdom = ($sdom -split "\\")[0]
    $ShareCreds=Get-Credential -Message "Enter credentials to access the share name to copy the TSR to the share." -UserName $sus
# Test SBM share
    Write-Host "Checking SMB share exists..."
    IF(Get-SmbShare | Where-Object{$_.Name -imatch 'Logs'}){
        Write-Host "    SUCCESS: SMB share found." -ForegroundColor Green
        Write-Host "Connecting to SMB share with provdied creds..."
        Remove-PSDrive -Name logs >$null 2>&1
        sleep 3
        $s=0
        New-PSDrive -Credential $ShareCreds1 -Name Logs -Root "\\$ShareIP\$ShareName" -PSProvider FileSystem  >$null 2>&1
        While(-not(Get-PSDrive -Name Logs)){
            $s++
            Write-Host "    WARNING: Failed to access share with provided creds. Please try again." -ForegroundColor Yellow
            Sleep 3
            $ShareCreds=Get-Credential -Message "Enter credentials to access the share name to copy the TSR to the share." -UserName $sus
            IF($s -ge 3){
                Write-Host "    ERROR: Failed too many time. Exiting..." -ForegroundColor Red
                Break script
            }
            New-PSDrive -Credential $ShareCreds1 -Name Logs -Root "\\$ShareIP\$ShareName" -PSProvider FileSystem
        }Write-Host "    SUCCESS: Able to access SMB share with provided creds." -ForegroundColor Green
    Remove-PSDrive -Name logs >$null 2>&1
    }Else{
        Write-Host "    ERROR: File share not created. Exiting." -ForegroundColor Red
        Break script
    }
# Gathers the iDRAC IP addresses from all nodes
If(Get-Service clussvc -ErrorAction SilentlyContinue){
    Write-Host "Gathering the iDRAC IP Addresses from cluster nodes..."
    $iDRACIPs=Invoke-Command -ComputerName (Get-ClusterNode -Cluster (Get-Cluster).Name) -ScriptBlock {
    (Get-PcsvDevice).IPv4Address
    }
}Else{
    # Get iDRAC IP addresses
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
    $iDRACIPs = Get-iDRACIPaddresses
}
Do{
    Write-Host "    iDRAC IP Address(s):"
    Write-host "        $iDRACIPs"
    $iDRACIPCheck = Read-Host "    Is the list above the correct list of iDRAC IP Addresses? (Y/N)"
}
until ($iDRACIPCheck -match '[yY,nN]')
IF($iDRACIPCheck -imatch "n"){
    $iDRACIPs = Get-iDRACIPaddresses
}

# Run TechSupportReport on each node
    ForEach($IP in $iDRACIPs){
        $result=@()
        Write-Host "Collecting TSR from: $IP..."
        $body = @{
            "IPAddress"= $ShareIP;
            "UserName"= $ShareCreds.UserName;
            "Password"= $ShareCreds.GetNetworkCredential().Password;
            "ShareName"= $ShareName;
            "ShareType"="CIFS";
            } | ConvertTo-Json
        $idrac_ip=$IP
        $URI="https://$idrac_ip/redfish/v1/Dell/Managers/iDRAC.Embedded.1/DellLCService/Actions/DellLCService.ExportTechSupportReport"
                           
        Try{
            $RespErr =""
            $result=Invoke-WebRequest -UseBasicParsing -Uri $URI -Credential $credential -Method POST -Headers @{'content-type'='application/json';'Accept'='application/json'} -Body $body -ErrorVariable RespErr 
            ($result.Content| ConvertFrom-Json).'@Message.ExtendedInfo'
        }
        Catch{
            $RespErrMessage=$null
            Try {$RespErrMessage=($RespErr.message| ConvertFrom-Json).error.'@Message.ExtendedInfo'.message} catch {}
            IF($RespErrMessage -match 'already running'){
                Write-Host "    ERROR: A SupportAssist job is already running on the server. Please try again later." -ForegroundColor Red
            } ElseIF($RespErrMessage -match 'The authentication credentials included with this request are missing or invalid.' -or $RespErr.Message -eq "The remote server returned an error: (401) Unauthorized."){
                $credential=Get-Credential -Message "Please enter the iDRAC Adminitrator credentials for $idrac_ip"
                $result= Invoke-WebRequest -UseBasicParsing -Uri $URI -Credential $credential -Method POST -Headers @{'content-type'='application/json';'Accept'='application/json'} -Body $body -ErrorVariable RespErr
                ($result.Content| ConvertFrom-Json).'@Message.ExtendedInfo'
            }
        }
    IF($RespErrMessage -match "Unable to run the method because the requested HTTP method is not allowed.") {
        Write-Warning "Idrac8 Detected. Using racadm"
        try {
            $tag=(racadm -r $idrac_ip -u "$($credential.UserName)" -p "$($credential.GetNetworkCredential().Password)" getsysinfo | findstr Service).substring(26)
            racadm -r $idrac_ip -u "$($credential.UserName)" -p "$($credential.GetNetworkCredential().Password)" techsupreport export -f "$ShareFolder\TSR$(get-date -Format 'yyyyMMddHHmmss')_$tag.zip"
            $result = @([pscustomobject]@{statuscode=202})
        } catch {Write-host -ForegroundColor Red "ERROR: Racadm failed. racadm may be missing"}
    }
    IF($result.StatusCode -eq 202){Write-Host "    StatusCode:"$result.StatusCode "Successfully scheduled TSR" }Else{Write-Host "    ERROR: StatusCode:" $result.StatusCode "Failed to scheduled TSR" -ForegroundColor Red}
    }
    Write-Host "Please wait while TSRs are collected. Usually this takes 2-5 minutes per node." -ForegroundColor Green
    Write-Host "TSRs will be saved at $ShareFolder" -ForegroundColor Green
    IF(!($LeaveShare -eq $True)){
        # Creating Scheduled Job to remove SMB share in 10 mins
            Write-Host "Creating Scheduled Job to remove SMB share in 15 mins..."
            $dateTime = (Get-Date).AddSeconds(900)
            $T = New-JobTrigger -Once -At "$($dateTime.ToString("MM/dd/yyyy HH:mm"))" 
            IF(Get-ScheduledJob | Where-Object{$_.Name -eq "TSRCollector"}){Unregister-ScheduledJob -Name "TSRCollector"}
            Register-ScheduledJob -Name "TSRCollector" -Trigger $T -ScriptBlock {
                # Remove share
                    Remove-SmbShare -Name "Logs" -Force
            }
        # Change directory to the shared folder were the TSRs will be put
			try {explorer "$ShareFolder" } catch {
			Start-Process -FilePath "cmd.exe" -ArgumentList("/K","cd","/d","$ShareFolder","&","echo TSRs will show up in this directory when finished") }
    }

} #End ShouldProcess
do {
$TSRsCollected = (Get-ChildItem -Path $ShareFolder)
$totalTSRsCollected = $TSRsCollected.Count
Sleep -Seconds 60
$i++
Write-Host "$totalTSRsCollected / $($idracIPs.count) TSR's collected so far, and waited $i / 15 minutes"
}
while ($totalTSRsCollected -lt $iDRACIPs.count -and $i -le 15)
 Compress-Archive -Path "$ShareFolder\*.*" -DestinationPath "$ShareFolder\TSRReports_$($CaseNumber)"
$ZipPath="$ShareFolder\TSRReports_$($CaseNumber).zip"
$ZipName=(Get-Item $ZipPath).Name
#The target URL wit SAS Token
$uri = "https://gsetools.blob.core.windows.net/tsrcollect/$($ZipName)?sp=acw&st=2022-08-14T21:28:03Z&se=2032-08-15T05:28:03Z&spr=https&sv=2021-06-08&sr=c&sig=dhqj1OR7bWRkRp4D3HXwnLT%2Ba%2Br4J6ANF80LhKcafAw%3D"

#Define required Headers
$headers = @{
    'x-ms-blob-type' = 'BlockBlob'
            }

#Upload File...
Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -InFile $ZipPath -ErrorAction Continue
Stop-Transcript
}# End Invoke-TSRCollector
