# Run CluChk Dev
# Created By: Jim Gandy
# v1.4
Function Invoke-RunCluChkDev{
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host "Downloading latest version..."
$url = 'https://gsetools.blob.core.windows.net/cluchk/CluChkDEV.ps1.remove?sv=2021-10-04&si=ReadAccess&sr=c&sig=FPrKWcg0IRxzIDZHuu4syLjMSuLn%2Fco3gH1OLkYnPIs%3D'
#sv=2020-10-02&st=2022-07-15T19%3A43%3A49Z&se=2025-07-16T19%3A43%3A00Z&sr=b&sp=r&sig=HjZEXdUzx8iT7P6BSZLsuIaRPX3ohBMjsAvH3jqXYmE%3D'

$start_time = Get-Date
Try{Invoke-WebRequest -Uri $url -UseDefaultCredentials
    Write-Output "Time taken: $((Get-Date).Subtract($start_time).Seconds) second(s)"
   }
Catch{Write-Host "ERROR: Source location NOT accessible. Please try again later"-foregroundcolor Red
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
