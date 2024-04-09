# Run Drift
# Created By: Jim Gandy
# v1.5
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
    $url = 'https://raw.githubusercontent.com/DellProSupportGse/source/main/drift.ps1'
    $output = "$CurrentLoc\DriFT.ps1"
    $start_time = Get-Date
    Try{
        Invoke-WebRequest -Method GET -Uri $url -OutFile $output
    Write-Output "    Time taken: $((Get-Date).Subtract($start_time).Seconds) second(s)"}
    Catch{Write-Host "    ERROR: Source location NOT accessible. Please try again later"-foregroundcolor Red
    Pause}
    Finally{
        #& $output @Tsr2Run
        Start-Process -FilePath "C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $output -Wait -NoNewWindow
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
            Run-Cleanup       
        }
    }
    #Run drift if no argument(s)
    If(!($args)){
        Write-Host "    None found."
        Run-Drift
        Run-Cleanup    
    }
}
