# Run CluChk
# Created By: Jim Gandy
# v1.3
Function Invoke-RunCluChk{
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host "Downloading latest version..."
$url = 'https://gsetools.blob.core.windows.net/cluchk/CluChk.ps1.remove?sv=2020-10-02&si=ReadAccess&sr=b&sig=BpFR0jPXaQUNNATR7%2FqNj7CXjNw9bJH8jmeX0melJxM%3D'
$start_time = Get-Date
Try{Invoke-WebRequest -Uri $url -OutFile $output -UseDefaultCredentials
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
