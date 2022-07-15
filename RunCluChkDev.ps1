# Run CluChk Dev
# Created By: Jim Gandy
# v1.4
Function Invoke-RunCluChkDev{
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host "Downloading latest version..."
$url = 'https://gsetools.blob.core.windows.net/cluchk/CluChkDEV.ps1.remove?SECRET REMOVED'
$start_time = Get-Date
Try{Invoke-WebRequest -Uri $url -UseDefaultCredentials
    Write-Output "Time taken: $((Get-Date).Subtract($start_time).Seconds) second(s)"
   }
Catch{Write-Host "	ERROR: Source location NOT accessible. Please try again later"-foregroundcolor Red
    Pause
    }
Finally{
    $wc = New-Object System.Net.WebClient
    $wc.UseDefaultCredentials = $true
    iex ($wc.DownloadString($url))
    }
#Variable Cleanup
Remove-Variable * -ErrorAction SilentlyContinue
}
