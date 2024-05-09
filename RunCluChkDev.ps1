# Run CluChk Del
# Created By: Jim Gandy
# v1.5
Function Invoke-RunCluChk{
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host "Downloading latest version..."
$url = 'https://raw.githubusercontent.com/DellProSupportGse/source/main/cluchkdev.ps1'
$start_time = Get-Date
Try{Invoke-WebRequest -Uri $url -UseDefaultCredentials | Out-Null
    Write-Output "Time taken: $((Get-Date).Subtract($start_time).Seconds) second(s)"
   }
Catch{Write-Host "ERROR: Source location NOT accessible. Please try again later"-foregroundcolor Red
    Pause
    }
Finally{
Invoke-Expression('$module="RunCluChk";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString($url));Invoke-RunCluChk
    }
#Variable Cleanup
Remove-Variable * -ErrorAction SilentlyContinue
}
