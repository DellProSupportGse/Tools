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
$Ver="1.1"
Clear-Host
$text = @"
v$Ver
    _       _  _  ___ ___ _   _     _  ___ _           _           
   /_\   __| || |/ __|_ _| | | |_ _| |/ __| |_  ___ __| |_____ _ _ 
  / _ \ |_ / __ | (__ | || |_| | '_| | (__| ' \/ -_) _| / / -_) '_|
 /_/ \_\/__|_||_|\___|___|\___/|_| |_|\___|_||_\___\__|_\_\___|_|  
                               
                                                      by: Jim Gandy 
"@
Write-Host $text
Write-Host ""
Write-Host "This script checks the URLs that the Azure Stack HCI "
Write-Host "operating system may need to access as per Microsoft"
Write-Host "Doc: https://docs.microsoft.com/en-us/azure-stack/hci/concepts/firewall-requirements"
Write-Host ""
# Scrape MS KB from URLs
    $URL='https://raw.githubusercontent.com/MicrosoftDocs/azure-stack-docs/main/azure-stack/includes/required-urls-table.md'
    $Webpage=Invoke-WebRequest -Uri $URL -UseBasicParsing -Method Get -ContentType 'charset=utf-8'
    if ($Webpage.statuscode -eq '200') {
        $Webpage.RawContent|Out-File $env:TEMP\temp1.txt -encoding utf8 -Force
        $readfile=Get-Content $env:TEMP\temp1.txt
        Remove-Item $env:TEMP\temp1.txt -Force
        $UrlList=@()
        $URLs2Check=@()
        $Add=""
        $resultObject=@()
        foreach($Line in $readfile){
            $URL=""
            $Port=""
            $Notes=""
            IF($Line -imatch '\|   \:---\|'){$Add=$true;continue}
            #IF($Line -imatch '----'){$Add=$false}
            IF($Add -eq $true){
                #$URLs+=$Line -replace [char]8220,'"' -replace [char]8221,'"' -replace '`' -replace 'json' -replace 'http\:\/\/' -replace 'https\:\/\/' -replace '\/' -replace'\*\.' -replace '\[\{','{' -replace '\}\]','},' -replace '\}\s\]','}'
                $URLs+=$Line -split '\|'
                $resultObject = [PSCustomObject] @{
                    Service = ($Line -split '\|')[1] -replace '[^\x20-\x7F]','' -replace '^\s+',''
                    URL     = ($Line -split '\|')[2] -replace '[^\x20-\x7F]','' -replace '^\s+','' -replace '\s','' -replace '\*\.',''
                    Port    = ($Line -split '\|')[3] -replace '[^\x20-\x7F]','' -replace '^\s+',''
                    Notes   = ($Line -split '\|')[4] -replace '[^\x20-\x7F]','' -replace '^\s+',''
                }
                #Pause
                $UrlList+=$resultObject
            }
        }
    }Else{Write-Host "ERROR: Failed to get URL list from: $URL" -ForegroundColor Red }
$URLs2Check= $UrlList | sort URL -Unique
    
# Check for running on cluster
IF(Get-Command Get-ClusterNode -ErrorAction SilentlyContinue -WarningAction SilentlyContinue){
    $ServerList = (Get-ClusterNode -ErrorAction SilentlyContinue -WarningAction SilentlyContinue).Name
}
IF(-not($ServerList)){
    $ServerList=$env:COMPUTERNAME
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
        Write-Host "Checking $($Url.URL)..."
        Invoke-Command -ComputerName $ServerList -WarningAction SilentlyContinue -ScriptBlock {
            $Result = Test-NetConnection -ComputerName ($Using:Url.URL) -Port ($Using:Url.Port) -ErrorAction SilentlyContinue
            If($Result.TcpTestSucceeded -eq $true) {Write-Host "PASSED: From $($env:COMPUTERNAME) to $($Using:Url.URL)" -ForegroundColor Green}
            If($Result.TcpTestSucceeded -eq $false) {Write-Host "FAILED: From $($env:COMPUTERNAME) to $($Using:Url.URL) INFO:$($Using:Url.Notes)" -ForegroundColor Red}
        }
    }
}
