<#
.Synopsis
   FLTMC Checker
.DESCRIPTION
    Script to check the mini Filter Drivers aginst the known list
    Input file creation
    fltmc >%temp%\fltmc_out.txt && notepad %temp%\fltmc_out.txt
.CREATEDBY
    Jim Gandy
.UPDATES
    v1.0 - Initial release
#>
Function Invoke-FLCkr{
param($param)
Remove-Variable * -ErrorAction SilentlyContinue
CLS
$URL="https://raw.githubusercontent.com/MicrosoftDocs/windows-driver-docs/staging/windows-driver-docs-pr/ifs/allocated-altitudes.md"
$text=@()
Function EndScript{  
    break
}
$Ver="v1.0"
$text = @"
$Ver 
 ________  _____       ______  __               
|_   __  ||_   _|    .' ___  |[  |  _           
  | |_ \_|  | |     / .'   \_| | | / ]  _ .--.  
  |  _|     | |   _ | |        | '' <  [ `/'`\] 
 _| |_     _| |__/ |\ `.___.'\ | |`\ \  | |     
|_____|   |________| `.____ .'[__|  \_][___]    
                             by: Jim Gandy 
"@
Write-Host $text
    Write-host " "
    Write-host "Welcome to FLCkr"
    Write-host " "
    Write-host "This tool lookups up filter drivers"
    Write-host "in Microsoft's known good list"
    Write-host "URL: $URL"
    Write-host " "
    $Run = Read-Host "Ready to run? [y/n]"
    Write-host " "
    If (($run -ieq "n")-or ($run -ieq "")){EndScript}
Do{
$LocalFltmc=@()
Function Get-FileName($initialDirectory)
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog -Property @{Multiselect = $true}
    $OpenFileDialog.Title = "Please Select FLTMC Output File"
    $OpenFileDialog.initialDirectory = $initialDirectory
    #$OpenFileDialog.filter = "ZIP (*.zip)| *.zip"
    $OpenFileDialog.ShowDialog() | Out-Null
    $OpenFileDialog.filenames
}

Function Get-FLTMC($InputFile){
    $parts=@()
    $output=@()
    If($InputFile -match "Run it locally"){$output = FLTMC}
    Else{$output = Get-Content $InputFile}
    If($output -match "Filter Name"){
        $Found=($output|Select-String "Filter Name" -Context 0,1).LineNumber
        $output=$output[($Found+1)..($output.length)]
        }
    $output | foreach {$parts = $_ -split "\s+", 6
        New-Object -Type PSObject -Property @{
                FilterName = ($parts[0])
                NumInstances = $parts[1]
                Altitude = $parts[2]
                Frame = $parts[3]}
        }
}
$Loc = Read-Host "Run FLTMC Locally? [y/n]"

    If($loc -ne ""){
        If($loc -ieq "n"){
            $InputFile=Get-FileName("C:")
            if(!$Input){EndScript}
            $LocalFltmc=Get-FLTMC ($InputFile) | Select FilterName,NumInstances,Altitude,Frame
        }Else{$LocalFltmc=Get-FLTMC("Run it locally") | Select FilterName,NumInstances,Altitude,Frame}
    }Else{Endscript}

#use the credentials of the current user to authenticate on the proxy server
$Wcl = new-object System.Net.WebClient
$Wcl.Headers.Add("user-agent","PowerShell Script")
$Wcl.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials 
#gets the the list or known file system minifilter drivers
#$URL="https://raw.githubusercontent.com/MicrosoftDocs/windows-driver-docs/staging/windows-driver-docs-pr/ifs/allocated-altitudes.md"
$KnownFltrs=Invoke-WebRequest -Uri $URL | Select-Object RawContent
$RawKnownFltrs=$KnownFltrs.RawContent.split("`n") 
#Parse the output
$FltCheck=@()
$FltCheck="FilterName,NumInstances,Altitude,Frame,WindowsDriver,Company`r`n"
ForEach($Driver in $LocalFltmc){
    $Driver1=@()
    $Driver1=$Driver.FilterName.Trim()
    $FltCheck+=$Driver1+","+$Driver.NumInstances+","+$Driver.Altitude+","+$Driver.Frame+""
    ForEach($Line in $RawKnownFltrs){
        If($line -match $Driver1){
            $S= $Line -split "\s+" , 6
            $out=","+$S[1]+","+$S[5].Replace("|","")
            $FltCheck+=$out
        }
    }
    $FltCheck+=",N/A,N/A`r`n"
}
Write-Host "Filter Driver Lookup Results"
$FltCheck|convertfrom-csv | FT -AutoSize
<#$ScreenOut=$FltCheck|convertfrom-csv | FT -AutoSize
$item=@()
Write-PSObject -MatchMethod Exact -Column "Company" -Value "Microsoft" -ValueForeColor Yellow
ForEach($item in $ScreenOut){
    If($item -notmatch "Microsoft"){
        Write-Host $item -ForegroundColor Yellow
    }Else{Write-Host $item}
}
#>
Write-Host "Driver lookup source URL: $URL"
Write-Host ""
$Run=Read-Host "Would you like to process another? [y/n]"
If($Run -notmatch "y"){EndScript}
}While($Run -eq "y")
}
