# Run Drift
# Created By: Jim Gandy
# v1.3
Function Invoke-RunDriFT{
Write-Host "Set ExecutionPolicy Bypass..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
Write-Host "    ExecutionPolicy:"$env:PSExecutionPolicyPreference
Write-Host "Start Drift..."
$output =""

# Remove downloaded source code
Function Run-Cleanup{
    Param($output)
    Write-Host "Clean up..."
    $output="$ENV:TEMP\DriFT.ps1"
    if (Test-Path $output -PathType Leaf){Remove-Item $output -Recurse -Force | Out-Null}
}

Function Run-Drift{
    Param($Tsr2Run)
    Write-Host "    Processing TSR:" $Tsr2Run
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $CurrentLoc=$ENV:TEMP
    Write-Host "    Downloading latest version..."
    #$url = 'https://bit.ly/3gCNm7A'
    $url = 'https://drift.gse.support/'
    $output = "$CurrentLoc\DriFT.ps1"
#    $global:output = $output
    $start_time = Get-Date
    Try{Invoke-WebRequest -Uri $url -OutFile $output -UseDefaultCredentials
	    Write-Output "    Time taken: $((Get-Date).Subtract($start_time).Seconds) second(s)"}
    Catch{Write-Host "    ERROR: Source location NOT accessible. Please try again later"-foregroundcolor Red
    Pause}
    Finally{
        #& $output @Tsr2Run
        Start-Process -FilePath "C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $output
    }
}

    Write-Host "    Checking for argument(s)..."
    IF($args){
        Write-Host "    Found:" $args
        $params=""
        $pattern = '([a-zA-Z]:\\(((?![<>:"/\\|?*]).)+((?<![ .])\\)?)*)(\s|$)'
        Select-String "$pattern" -input "$args" -AllMatches | Foreach {$_.matches} | ForEach-Object { 
            $params=@("$($_.Groups.Groups[1].Value)")
            Run-Drift $params
            Sleep 5
            Run-Cleanup
	    clear-host 
        }
    }
    #Run drift if no argument(s)
    If(!($args)){
        Write-Host "    None found."
        Run-Drift
        Sleep 5
        Run-Cleanup
	clear-host 
    }
   
}
