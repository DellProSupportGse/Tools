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
            $param)
## Gather Tech Support Report Collector for all nodes in a cluster
    CLS
Function EndScript{  
    break
}
$text=@"
v1.1
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
$user = "root"
$pass= "calvin"
$secpasswd = ConvertTo-SecureString $pass -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($user, $secpasswd)
$ShareIP=((Get-wmiObject Win32_networkAdapterConfiguration | ?{$_.IPEnabled}) | ?{$_.DefaultIPGateway.length -gt 0}).ipaddress[0]
# Create a new folder and shares it
    Write-Host "Creating a new shared folder to save the TSRs..."
    $ShareName = "Logs"
    $ShareFolder=$MyTemp+"\"+$ShareName
    New-Item -ItemType Directory -Force -Path $ShareFolder  >$null 2>&1
    New-SmbShare -Name "Logs" -Path "$ShareFolder" -Temporary -FullAccess Everyone  >$null 2>&1
    Write-Host "    Share location is $ShareFolder"
# Gets the logged on creds
    Write-Host "Gathering the credentials to access the share..."
    $sus = $env:UserName
    $sdom = (Get-WmiObject win32_computersystem).Domain
    $ShareCreds=Get-Credential -Message "Enter credentials to access the share name to copy the TSR to the share." -UserName $sus
# Gathers the iDRAC IP addresses from all nodes
    Write-Host "Gathering the iDRAC IP Addresses from cluster nodes..."
    $iDRACIPs=Invoke-Command -ComputerName (Get-ClusterNode -Cluster (Get-Cluster).Name) -ScriptBlock {
    (Get-PcsvDevice).IPv4Address
    }
    Write-Host "    FOUND:$iDRACIPs"
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
            IF($RespErr){
                $credential=Get-Credential -Message "Please enter the iDRAC Adminitrator credentials for $idrac_ip"
                $result= Invoke-WebRequest -UseBasicParsing -Uri $URI -Credential $credential -Method POST -Headers @{'content-type'='application/json';'Accept'='application/json'} -Body $body -ErrorVariable RespErr
            }
        }
    IF($result.StatusCode -eq 202){Write-Host "    StatusCode:"$result.StatusCode "Successfully scheduled TSR" -ForegroundColor Green }Else{Write-Host "    ERROR: StatusCode:" $result.StatusCode "Failed to scheduled TSR" -ForegroundColor Red}
    }
# Change directory to the shared folder were the TSRs will be put
    cd $ShareFolder
    Invoke-Expression "explorer ."
    Write-Host "Please wait while TSRs are collected. Ussually this takes 2-5 minutes per node."
    IF(!($LeaveShare -eq $True)){
        # Wait for TSRs to arrive
            $i=0
            While (!((Get-Item "$ShareFolder\TSR*.zip").count -eq $iDRACIPs.count)) { Start-Sleep 60;$i++;IF($i -ge 10){Write-Host "ERROR: Failed to return all TSRs in 10m. Please investigate." -ForegroundColor Red; Break Script}}
        # Remove share
            Write-Host "Removing SMB share called Logs..."
            Remove-SmbShare -Name "Logs" -Force
    }
}
}
