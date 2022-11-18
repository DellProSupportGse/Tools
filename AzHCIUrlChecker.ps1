<#
    .Synopsis
       AzHCIUrlChecker.ps1
    .DESCRIPTION
       This script checks the URLs that the Azure Stack HCI operating system may need to access
    .EXAMPLES
       Invoke-AzHCIUrlChecker
    .Author
       Jim Gandy
#>

Function Invoke-AzHCIUrlChecker{
$Ver="1.6"
Clear-Host
$text = @"
v$Ver
    _       _  _  ___ ___ _   _     _  ___ _           _           
   /_\   __| || |/ __|_ _| | | |_ _| |/ __| |_  ___ __| |_____ _ _ 
  / _ \ |_ / __ | (__ | || |_| | '_| | (__| ' \/ -_) _| / / -_) '_|
 /_/ \_\/__|_||_|\___|___|\___/|_| |_|\___|_||_\___\__|_\_\___|_|  
                               
                                                      by: Jim Gandy 
"@

# Run Menu
Function ShowMenu{
    do
     {
         $selection=""
         Clear-Host
         Write-Host $text
         Write-Host ""
         Write-Host "This script checks the URLs that the Azure Stack HCI "
         Write-Host "operating system may need to access as per Microsoft"
         Write-Host "Doc: https://docs.microsoft.com/en-us/azure-stack/hci/concepts/firewall-requirements"
         Write-Host ""
         Write-Host "============ Please make a selection ==================="
         Write-Host ""
         Write-Host "Press '1' to Check Azure Stack HCI"
         Write-Host "Press '2' to Check Arc For Servers"
         Write-Host "Press '3' to Check Arc Resource Bridge"
         Write-Host "Press '4' to Check Recommended Urls"
         Write-Host "Press '5' to Check All the above"
         Write-Host "Press 'H' to Display Help"
         Write-Host "Press 'Q' to Quit"
         Write-Host ""
		 $selection = Read-Host "Please make a selection"
     }
    until ($selection -match '[1-5,qQ,hH]')
    $Global:AzureStackHCI  = "N"
    $Global:ArcForServers  = "N"
    $Global:ArcResourceBridge  = "N"
    $Global:recommendedurls = "N"
    $Global:CheckALL = "N"
    IF($selection -imatch 'h'){
        Clear-Host
        Write-Host ""
        Write-Host "What's New in AzHCIUrlChecker:"
        Write-Host $WhatsNew 
        Write-Host ""
        Write-Host "Usage:"
        Write-Host "    Make a selection by entering a comma delimited string of numbers from the menu."
        Write-Host ""
        Write-Host "        Example: 1 will Check Azure Stack HCI ."
        Write-Host ""
        Write-Host "        Example: 1,3 will check Azure Stack HCI and "
        Write-Host "                 Arc Resource Bridge"
        Write-Host ""
        Pause
        ShowMenu
    }
    IF($selection -match 1){
        Write-Host "Checking Azure Stack HCI..."
        $Global:AzureStackHCI = "Y"
    }

    IF($selection -match 2){
        Write-Host "Checking Arc For Servers..."
        $Global:ArcForServers  = "Y"
    }
    IF($selection -match 3){
        Write-Host "Checking Arc Resource Bridge..."
        $Global:ArcResourceBridge = "Y"
    }
    IF($selection -match 4){
        Write-Host "Checking Recommended Urls..."
        $Global:recommendedurls = "Y"
    }
    ElseIF($selection -eq 5){
        Write-Host "Checking all..."
        $Global:recommendedurls = "Y"
        $Global:CheckALL = "Y"
    }
    IF($selection -imatch 'q'){
        Write-Host "Bye Bye..."
        EndScript
    }
}#End of ShowMenu
#endregion
ShowMenu
# Scrape MS KB from URLs
    $URL='https://raw.githubusercontent.com/MicrosoftDocs/azure-stack-docs/main/azure-stack/includes/hci-required-urls-table.md'
    $Webpage=Invoke-WebRequest -Uri $URL -UseBasicParsing -Method Get -ContentType 'charset=utf-8'
    if ($Webpage.statuscode -eq '200') {
        $Webpage.RawContent|Out-File $env:TEMP\temp1.txt -encoding utf8 -Force
        $readfile=Get-Content $env:TEMP\temp1.txt
        Remove-Item $env:TEMP\temp1.txt -Force
        $UrlList=@()
        $URLs2Check=@()
        $Add=""
        $resultObject=@()
        # Make webtable into PS Object
        foreach($Line in $readfile){
            $URL=""
            $Port=""
            $Notes=""

            IF($Line -imatch '\|\s+\:---\|'){$Add=$true;continue}
            IF($Add -eq $true){
                $URLs+=$Line -split '\|'
                $resultObject = [PSCustomObject] @{
                    Service = ($Line -split '\|')[1] -replace '[^\x20-\x7F]','' -replace '^\s+',''
                    URL     = ($Line -split '\|')[2] -replace '[^\x20-\x7F]','' -replace '^\s+','' -replace '\s','' -replace 'www\\','www'
                    Port    = ($Line -split '\|')[3] -replace '[^\x20-\x7F]','' -replace '^\s+',''
                    Notes   = ($Line -split '\|')[4] -replace '[^\x20-\x7F]','' -replace '^\s+',''
                }
                $UrlList+=$resultObject
            }
        }
    }Else{Write-Host "ERROR: Failed to get URL list from: $URL" -ForegroundColor Red }

IF($AzureStackHCI -eq "Y"){
    $URLs2Check+= $UrlList | Where-Object{$_.Service -imatch 'Azure Stack HCI'} | sort URL -Unique
    $URLs2Check
    $CheckALL="N"
    }
IF($ArcForServers -eq "Y"){
    $URLs2Check+= $UrlList | Where-Object{$_.Service -imatch 'Arc For Servers'} | sort URL -Unique
    $AddMissing+= [PSCustomObject]@{
				Service = "Arc For Servers"
                URL     = "onegetcdn.azureedge.net"
                Port    = "443"
                Notes   = "Dell Added: ARC Agent installation needs to access this location for nuget packages"}
    $URLs2Check+=$AddMissing    
    $URLs2Check
    $CheckALL="N"
    }
IF($ArcResourceBridge -eq "Y"){
    $URLs2Check+= $UrlList | Where-Object{$_.Service -imatch 'Arc Resource Bridge'} | sort URL -Unique
    $URLs2Check
    $CheckALL="N"
    }
IF($recommendedurls -eq "Y"){
    $URL='https://raw.githubusercontent.com/MicrosoftDocs/azure-stack-docs/main/azure-stack/includes/hci-recommended-urls-table.md'
    $Webpage=Invoke-WebRequest -Uri $URL -UseBasicParsing -Method Get -ContentType 'charset=utf-8'
    if ($Webpage.statuscode -eq '200') {
        $Webpage.RawContent|Out-File $env:TEMP\temp1.txt -encoding utf8 -Force
        $readfile=Get-Content $env:TEMP\temp1.txt
        Remove-Item $env:TEMP\temp1.txt -Force
        $RecUrlList=@()
        $URLs2Check=@()
        $Add=""
        $resultObject=@()
        # Make webtable into PS Object
        foreach($Line in $readfile){
            $URL=""
            $Port=""
            $Notes=""
            IF($Line -imatch '\|   \:---\|'){$Add=$true;continue}
            IF($Add -eq $true){
#                $URLs+=$Line -split '\|'
                $resultObject = [PSCustomObject] @{
                    Service = ($Line -split '\|')[1] -replace '[^\x20-\x7F]','' -replace '^\s+',''
                    URL     = ($Line -split '\|')[2] -replace '[^\x20-\x7F]','' -replace '^\s+','' -replace '\s','' -replace 'www\\','www'
                    Port    = ($Line -split '\|')[3] -replace '[^\x20-\x7F]','' -replace '^\s+',''
                    Notes   = ($Line -split '\|')[4] -replace '[^\x20-\x7F]','' -replace '^\s+',''
                }
                $RecUrlList+=$resultObject
            }
        }
    }Else{Write-Host "ERROR: Failed to get URL list from: $URL" -ForegroundColor Red }
    $URLs2Check+= $RecUrlList | sort URL -Unique
    $URLs2Check
    $CheckALL="N"
    }

IF($CheckALL -eq "Y"){
    $URLs2Check+= $UrlList| sort URL -Unique | sort Service
    $URLs2Check
    }

Function Invoke-URLChecker{    
# Check for running on cluster
    IF(Get-Command Get-ClusterNode -ErrorAction SilentlyContinue -WarningAction SilentlyContinue){
        $ServerList = (Get-ClusterNode -ErrorAction SilentlyContinue -WarningAction SilentlyContinue).Name
    }
    IF(-not($ServerList)){
        Write-Host " Unable to discover cluster nodes." -ForegroundColor Yellow
        $ServerList=$env:COMPUTERNAME
        $ServerList = Read-Host " Please provide a list of servers to check in comma delimited form"
        $ServerList = $ServerList -split ',' -replace '\s+'
    }

#Change buffer width to make reader frindly
    $pshost = get-host
    $pswindow = $pshost.ui.rawui
    $newsize = $pswindow.buffersize
    $newsize.height = 3000
    $newsize.width = 1024
    $pswindow.buffersize = $newsize
    $newsize = $pswindow.windowsize

# Test connections
    foreach($Url in $URLs2Check) {
        IF($Url.URL -notmatch '\*\.'){
        Write-Host "Checking $($Url.URL)..."
        Invoke-Command -ComputerName $ServerList -WarningAction SilentlyContinue -ScriptBlock {
            $Result = Test-NetConnection -ComputerName ($Using:Url.URL) -Port ($Using:Url.Port) -ErrorAction SilentlyContinue
            If($Result.TcpTestSucceeded -eq $true) {Write-Host "PASSED: From $($env:COMPUTERNAME) to $($Using:Url.URL)" -ForegroundColor Green}
            If($Result.TcpTestSucceeded -eq $false) {Write-Host "FAILED: From $($env:COMPUTERNAME) to $($Using:Url.URL) INFO:$($Using:Url.Notes)" -ForegroundColor Red}
        }}
    }
}
Invoke-URLChecker
IF($URLs2Check -match '\*\.'){
Write-Host "Please Note that wildcard (*) Urls where not tested but should also be accessable." -ForegroundColor Yellow
}
}
