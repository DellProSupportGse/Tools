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
$text=@()
Function EndScript{  
    break
}
$Ver="v2.0"
$text = @"
$Ver 
 ________  _____       ______  __               
|_   __  ||_   _|    .' ___  |[  |  _           
  | |_ \_|  | |     / .'   \_| | | / ]  _ .--.  
  |  _|     | |   _ | |        | '' <  [ '/''\] 
 _| |_     _| |__/ |\ '.___.'\ | |'\ \  | |     
|_____|   |________| '.____ .'[__|  \_][___]    
                             by: Jim Gandy 
"@
Write-Host $text
    Write-host " "
    Write-host "Welcome to FLCkr"
    Write-host " "
    Write-host "    This tool lookups up filter drivers"
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
    $OpenFileDialog.ShowDialog() | Out-Null
    $OpenFileDialog.filenames
}

Function Get-FLTMCFromFile($InputFile){
    Write-Host "    Reading from file..."
    $filters=@()
    $lines = Get-Content -Path $InputFile
    foreach($line in $lines){
        $line = $line.Trim() -split "\s{2,}"
        if ($line.Length -ge 4 -and $line[0] -notmatch '^-+$' -and $line[0] -ne "Filter Name") {
            $filters += [PSCustomObject]@{
                FilterName    = $line[0]
                NumInstances  = $line[1]
                Altitude      = $line[2]
                Frame         = $line[3]
                WindowsDriver = $line[0] + ".sys"  # Assume the driver file matches FilterName
            }
        }
    }
    Parse-FiltersWeb $filters
}

Function Parse-FiltersWeb ($filters){
    $URL="https://raw.githubusercontent.com/MicrosoftDocs/windows-driver-docs/staging/windows-driver-docs-pr/ifs/allocated-altitudes.md"
    Write-Host "    Adding Company info from $URL..."
    # use the credentials of the current user to authenticate on the proxy server
    $Wcl = new-object System.Net.WebClient
    $Wcl.Headers.Add("user-agent","PowerShell Script")
    $Wcl.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials 
    # gets the the list or known file system minifilter drivers
    $KnownFltrs=Invoke-WebRequest -Uri $URL -UseBasicParsing | Select-Object RawContent
    $RawKnownFltrs=$KnownFltrs.RawContent.split("`n") 
    # Filter and parse lines
    $KnownFltrs = $RawKnownFltrs | ForEach-Object {
        # Trim whitespace and check for lines starting with "|"
        if ($_ -match '^\|\s*(\S+)\s*\|\s*(\d+\.?\d*)\s*\|\s*(.+?)\s*\|$') {
            [PSCustomObject]@{
                Minifilter = $Matches[1]
                Altitude   = $Matches[2]
                Company    = $Matches[3]
            }
        }
    }
    # Find matches in $KnownFltrs
    $matches = foreach ($filter in $filters) {
        $match = $KnownFltrs | Where-Object {
            $_.Minifilter -eq $filter.WindowsDriver -and $_.Altitude -eq $filter.Altitude
        }

        if ($match) {
            # If match is found, construct the object
            foreach ($m in $match) {
                [PSCustomObject]@{
                    FilterName    = $filter.FilterName
                    NumInstances  = $filter.NumInstances
                    Altitude      = $filter.Altitude
                    Frame         = $filter.Frame
                    WindowsDriver = $filter.WindowsDriver
                    Company       = $m.Company
                }
            }
        } else {
            # If no match is found, add "UNKNOWN" as the Company
            [PSCustomObject]@{
                FilterName    = $filter.FilterName
                NumInstances  = $filter.NumInstances
                Altitude      = $filter.Altitude
                Frame         = $filter.Frame
                WindowsDriver = $filter.WindowsDriver
                Company       = "NOT FOUND"
            }
        }
    }
    Write-Host "Filter Driver Lookup Results"
    $matches | Format-Table
}

Function Get-FLTMCLocally {
    # Run fltmc to get filter driver info
    Write-Host "    Gathering FLTMC..."
    $filters=@()
    $filters = fltmc | ForEach-Object {
        $line = $_.Trim() -split "\s{2,}"
        if ($line.Length -ge 4 -and $line[0] -notmatch '^-+$' -and $line[0] -ne "Filter Name") {
            [PSCustomObject]@{
                FilterName    = $line[0]
                NumInstances  = $line[1]
                Altitude      = $line[2]
                Frame         = $line[3]
                WindowsDriver = $line[0] + ".sys"  # Assume the driver file matches FilterName
            }
        }
    }
     Parse-FiltersLocally $filters
}

Function Parse-FiltersLocally ($filters) {
    Write-Host "    Adding Company/Description info from driver properties..."
    # Add Company/Description information by checking driver properties
	$filters | ForEach-Object {
	    $driverPath = "C:\Windows\System32\drivers\$($_.WindowsDriver)"
	    if (Test-Path $driverPath) {
	        $_ | Add-Member -MemberType NoteProperty -Name Company -Value (Get-ItemProperty $driverPath).VersionInfo.CompanyName
            $_ | Add-Member -MemberType NoteProperty -Name Description -Value (Get-ItemProperty $driverPath).VersionInfo.FileDescription
	    } else {
	        $_ | Add-Member -MemberType NoteProperty -Name Company -Value "Unable to find driver file locally"
	    }
	}
    Write-Host "Filter Driver Lookup Results"
    $filters | Format-Table
}

$Loc = Read-Host "Run FLTMC Locally? [y/n]"

    If($loc -ne ""){
        If($loc -ieq "n"){
            $InputFile=Get-FileName("C:")
            if(!$Input){EndScript}
            Get-FLTMCFromFile ($InputFile) 
        }Else{Get-FLTMCLocally("Run it locally")}
    }Else{Endscript}


$Run=Read-Host "Would you like to process another? [y/n]"
If($Run -notmatch "y"){EndScript}
}While($Run -eq "y")
}
