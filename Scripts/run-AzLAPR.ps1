# AzLAPR launcher for ToolBox Invoke-Expression.
# No script-level param block: ToolBox can load this wrapper unchanged.
# The application is downloaded and executed in a separate STA Windows PowerShell
# process, entirely from memory. The main application retains -InstanceId support.
$azlaprUrl = 'https://raw.githubusercontent.com/DellProSupportGse/Tools/refs/heads/main/Scripts/AzL-ActionPlanReader.ps1'
$azlaprChild = @'
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$client = New-Object System.Net.WebClient
try {
    $client.Encoding = [System.Text.Encoding]::UTF8
    $code = $client.DownloadString('AZLAPR_URL_PLACEHOLDER')
} finally {
    $client.Dispose()
}
$module = 'AzLActionPlanReader'
$repo = 'PowershellScripts'
# Dot-source in the fresh child process so WinForms callbacks retain their scope.
. ([scriptblock]::Create($code))
'@.Replace('AZLAPR_URL_PLACEHOLDER', $azlaprUrl)
$azlaprEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($azlaprChild))
$azlaprExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$azlaprProcess = Start-Process -FilePath $azlaprExe -ArgumentList @(
    '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass',
    '-EncodedCommand', $azlaprEncoded
) -PassThru -Wait
if ($azlaprProcess.ExitCode -ne 0) {
    Write-Warning "AzLAPR exited with code $($azlaprProcess.ExitCode). Check the child PowerShell window for details."
}