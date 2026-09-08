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

Function Invoke-AzHCIUrlChecker {
    $Ver = "1.13"
    Clear-Host

    $text = @"
v$Ver
    _       _  _  ___ ___ _   _     _  ___ _           _           
   /_\   __| || |/ __|_ _| | | |_ _| |/ __| |_  ___ __| |_____ _ _ 
  / _ \ |_ / __ | (__ | || |_| | '_| | (__| ' \/ -_) _| / / -_) '_|
 /_/ \_\/__|_||_|\___|___|\___/|_| |_|\___|_||_\___\__|_\_\___|_|  
                               
                                                      by: Jim Gandy 
"@

    Clear-Host
    Write-Host $text
    Write-Host ""
    Write-Host "This script checks the URLs for Azure Stack HCI/Azure Local"
    Write-Host ""

    # Step 1: Download the main GitHub HTML page
    $mainUrl = 'https://github.com/MicrosoftDocs/azure-stack-docs/blob/main/azure-local/concepts/firewall-requirements.md#required-firewall-urls-for-azure-local-deployments'

    Write-Host "Gathering Regions from"
    Write-Host "    $mainUrl"
    Write-Host ""

    $mainPage = Invoke-WebRequest -Uri $mainUrl -UseBasicParsing -UserAgent "Mozilla/5.0"

    if ($mainPage.StatusCode -eq 200) {
        $urlPattern = "https?://[^""']+\-hci-endpoints.md"
        $FwUrls = [regex]::Matches($mainPage.Content, $urlPattern) |
            ForEach-Object { $_.Value } |
            Select-Object -Unique
    }
    else {
        Write-Host "ERROR: Webpage status code $($mainPage.StatusCode)" -ForegroundColor Red
        return
    }

    # Step 2: Extract region names from URLs
    $regionPattern = "/([a-z,A-Z]+(?:[a-z,A-Z]*))-hci-endpoints\.md"
    $regions = [regex]::Matches(($FwUrls -join "`n"), $regionPattern) |
        ForEach-Object { $_.Groups[1].Value }

    # Step 3: User menu
    Write-Host "============ Please make a selection ==================="
    Write-Host ""

    for ($i = 0; $i -lt $regions.Count; $i++) {
        Write-Host "$($i + 1)): $($regions[$i])"
    }

    Write-Host ""
    $choice = Read-Host "Enter the number of the region you want to check"
    $index = [int]$choice - 1

    if ($index -lt 0 -or $index -ge $regions.Count) {
        Write-Host "Invalid selection." -ForegroundColor Red
        return
    }

    $selectedRegion = $regions[$index]
    $FWEndPointLink = ($FwUrls -imatch "$selectedRegion-hci-endpoints\.md")[-1]

    # Step 4: Get the rendered page containing the rawBlobUrl
    Write-Host ""
    Write-Host "Gathering the Endpoint Url..."

    $endpointPage = Invoke-WebRequest -Uri $FWEndPointLink -UseBasicParsing -UserAgent "Mozilla/5.0"
    $html = $endpointPage.Content

    if ($html -match "rawBlobUrl[`"`']?\s*:\s*[`"`']([^`"`']+)") {
        $rawBlobUrl = $matches[1]
        Write-Host "    Found: $rawBlobUrl"
    }
    else {
        Write-Host "    ERROR: Not found." -ForegroundColor Red
        return
    }

    # Step 5: Fetch raw Markdown content
    $mdPage = Invoke-WebRequest -Uri $rawBlobUrl -UseBasicParsing -UserAgent "Mozilla/5.0"
    $markdown = $mdPage.Content

    # Step 6: Extract and clean table
    $tableBlock = ($markdown -split "`n") -match '^\|\s*\d+\s*\|'
    $tableHeader = ($markdown -split "`n") -match '^\|\s*Id\s*\|'

    $fullTable = $tableHeader + $tableBlock
    $cleanTable = $fullTable | Where-Object { $_ -notmatch '^\|\s*-+\s*\|' }

    # Step 7/8: Parse table and expand rows with multiple ports
    $columns = ($cleanTable[0] -split '\|') |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }

    $endpointObjects = @()

    foreach ($line in $cleanTable[1..($cleanTable.Count - 1)]) {
        if ($line -match '^\s*\|(.*)\|\s*$') {
            $rowValues = $matches[1] -split '\|'
            $rowValues = $rowValues | ForEach-Object { $_.Trim() }

            if ($rowValues.Count -ne $columns.Count) {
                Write-Warning "Skipping malformed row: $line"
                continue
            }

            $originalId = $rowValues[0]
            $portField = $rowValues[3]
            $ports = ($portField -split '[,/ ]+') | Where-Object { $_ -match '^\d+$' }

            if ($ports.Count -le 1) {
                $newObj = [PSCustomObject]@{}

                for ($i = 0; $i -lt $columns.Count; $i++) {
                    $newObj | Add-Member -NotePropertyName $columns[$i] -NotePropertyValue $rowValues[$i]
                }

                $endpointObjects += $newObj
            }
            else {
                for ($j = 0; $j -lt $ports.Count; $j++) {
                    $newObj = [PSCustomObject]@{}

                    for ($i = 0; $i -lt $columns.Count; $i++) {
                        $colName = $columns[$i]
                        $value = $rowValues[$i]

                        if ($colName -eq 'Id') {
                            $value = if ($j -eq 0) { $originalId } else { "$originalId.$j" }
                        }
                        elseif ($colName -eq 'Port') {
                            $value = $ports[$j]
                        }

                        $newObj | Add-Member -NotePropertyName $colName -NotePropertyValue $value
                    }

                    $endpointObjects += $newObj
                }
            }
        }
    }

    # Step 9: Split into groups based on wildcard Endpoint URL
    $testedendpoints = @()

    $wildcardEndpoints = $endpointObjects | Where-Object {
        $_.'Endpoint URL' -like '*`**' -or $_.'Endpoint URL' -like 'your*'
    }

    $testableEndpoints = $endpointObjects | Where-Object {
        $_.'Endpoint URL' -notlike '*`**' -and $_.'Endpoint URL' -notlike 'your*'
    }

    Write-Host ""
    Write-Host "===== Untestable Endpoints Need Manual Handling =====" -ForegroundColor Yellow
    $wildcardEndpoints | Format-Table Id, 'Endpoint URL', Port, Notes -AutoSize

    # Add Dell endpoints
    $staticEndpoints = @(
        @{ Id = '401'; 'Azure Local Component' = 'Dell APEX Cloud Platform Manager'; 'Endpoint URL' = 'downloads.dell.com'; Port = 443; Accessible = $null; Notes = 'Used to download updates from Dell'; 'Arc gateway support' = 'Unknown'; 'Required for' = 'Deployment' },
        @{ Id = '402'; 'Azure Local Component' = 'Dell APEX Cloud Platform Manager'; 'Endpoint URL' = 'dl.dell.com'; Port = 443; Accessible = $null; Notes = 'Used to download updates from Dell'; 'Arc gateway support' = 'Unknown'; 'Required for' = 'Deployment' },
        @{ Id = '403'; 'Azure Local Component' = 'Dell APEX Cloud Platform Manager'; 'Endpoint URL' = 'esrs3-core.emc.com'; Port = 443; Accessible = $null; Notes = 'Used for Dell APEX Cloud Platform Manager extension support access'; 'Arc gateway support' = 'Unknown'; 'Required for' = 'Deployment' },
        @{ Id = '404'; 'Azure Local Component' = 'Dell APEX Cloud Platform Manager'; 'Endpoint URL' = 'esrs3-coredr.emc.com'; Port = 443; Accessible = $null; Notes = 'Used for Dell APEX Cloud Platform Manager extension support access'; 'Arc gateway support' = 'Unknown'; 'Required for' = 'Deployment' },
        @{ Id = '405'; 'Azure Local Component' = 'Dell APEX Cloud Platform Manager'; 'Endpoint URL' = 'esrs3-core.emc.com'; Port = 8443; Accessible = $null; Notes = 'Used for Dell APEX Cloud Platform Manager extension support access'; 'Arc gateway support' = 'Unknown'; 'Required for' = 'Deployment' },
        @{ Id = '406'; 'Azure Local Component' = 'Dell APEX Cloud Platform Manager'; 'Endpoint URL' = 'esrs3-coredr.emc.com'; Port = 8443; Accessible = $null; Notes = 'Used for Dell APEX Cloud Platform Manager extension support access'; 'Arc gateway support' = 'Unknown'; 'Required for' = 'Deployment' }
    )

    foreach ($entry in $staticEndpoints) {
        $testableEndpoints += [PSCustomObject]$entry
    }

    # Step 10: Test endpoint access using curl.exe
    function Test-NtpTimeServer {
        param (
            [string]$ComputerName
        )

        try {
            $server = $ComputerName -replace '^https?://', ''
            $server = $server -replace ':123$', ''

            $output = & w32tm /stripchart /computer:$server /samples:1 /dataonly 2>&1
            $exitCode = $LASTEXITCODE

            $outputText = if ($output -is [array]) {
                $output -join '; '
            }
            else {
                "$output"
            }

            $success = ($exitCode -eq 0 -and $outputText -match '\d{1,2}:\d{2}:\d{2}')

            return [PSCustomObject]@{
                Accessible   = $success
                CurlExitCode = $exitCode
                CurlResponse = $outputText.Trim()
                TestUrl      = "ntp://$server`:123"
            }
        }
        catch {
            return [PSCustomObject]@{
                Accessible   = $false
                CurlExitCode = -1
                CurlResponse = $_.Exception.Message
                TestUrl      = "ntp://$ComputerName`:123"
            }
        }
    }

    $total = $testableEndpoints.Count
    $counter = 0
    $testedendpoints = @()

    foreach ($endpoint in $testableEndpoints) {
        $counter++

        $ep2test = $endpoint.'Endpoint URL'.Trim()
        $port = [int]$endpoint.Port

        Write-Progress `
            -Activity "Testing Endpoints" `
            -Status "$counter of $($total): $($ep2test):$($port)" `
            -PercentComplete (($counter / $total) * 100)

    if ($port -eq 123) {
        $timeResult = Test-NtpTimeServer -ComputerName $ep2test

        $testUrl = $timeResult.TestUrl
        $curlExitCode = $timeResult.CurlExitCode
        $curlOutput = $timeResult.CurlResponse
        $isUp = $timeResult.Accessible
    }
    else {
        try {
            $cleanEndpoint = $ep2test -replace '^https?://', ''

            $testUrl = if ($port -eq 443) {
                "https://$cleanEndpoint"
            }
            elseif ($port -eq 80) {
                "http://$cleanEndpoint"
            }
            else {
                "https://$cleanEndpoint`:$port"
            }

            $curlOutput = & curl.exe -k -I -sS --connect-timeout 15 -m 18 $testUrl 2>&1
            $curlExitCode = $LASTEXITCODE

            if ($curlOutput -is [array]) {
                $curlOutput = $curlOutput -join '; '
            }

            $curlOutput = "$curlOutput".Trim()
            $isUp = ($curlExitCode -eq 0)
        }
        catch {
            $testUrl = $ep2test
            $curlExitCode = -1
            $curlOutput = $_.Exception.Message
            $isUp = $false
        }
    }

        $obj = $endpoint.PSObject.Copy()

        $obj | Add-Member -NotePropertyName 'TestUrl' -NotePropertyValue $testUrl -Force
        $obj | Add-Member -NotePropertyName 'Accessible' -NotePropertyValue $isUp -Force
        $obj | Add-Member -NotePropertyName 'CurlExitCode' -NotePropertyValue $curlExitCode -Force
        $obj | Add-Member -NotePropertyName 'CurlResponse' -NotePropertyValue $curlOutput -Force

        $testedendpoints += $obj
    }

    Write-Progress -Activity "Testing Endpoints" -Completed

    # Step 11: Output the parsed endpoint table
    Write-Host "`n===== Testable Endpoints =====" -ForegroundColor Green

    $testedendpoints = $testedendpoints | Sort-Object 'Accessible', Id -Descending

    # Step 12: Format output
    $testedendpoints | ForEach-Object {
        $_ | Add-Member -NotePropertyName "SortId" -NotePropertyValue ([double]$_.'Id') -Force
    }

    $sortedEndpoints = $testedendpoints |
        Sort-Object -Property `
            @{ Expression = 'Accessible'; Descending = $true },
            @{ Expression = 'SortId'; Ascending = $true }

    $table = $sortedEndpoints |
        Select-Object Id,
            @{ Name = 'Component'; Expression = { $_.'Azure Local Component' } },
            @{ Name = 'Endpoint'; Expression = { $_.'Endpoint URL' } },
            Port,
            Accessible,
            CurlExitCode,
            Notes |
        Format-Table -AutoSize |
        Out-String -Stream

    if ($table.Count -ge 2) {
        $header = $table[0]
        $separator = $table[1]

        Write-Host $header
        Write-Host $separator

        foreach ($line in $table[2..($table.Count - 1)]) {
            if ($line -match '\bTrue\b') {
                Write-Host $line
            }
            elseif ($line -match '\bFalse\b') {
                Write-Host $line -ForegroundColor Red
            }
            else {
                Write-Host $line
            }
        }
    }

    # Step 13: Show failed endpoint details
    Write-Host ""
    Write-Host "===== Failed Endpoint Details =====" -ForegroundColor Yellow

    $failedEndpoints = $sortedEndpoints | Where-Object { -not $_.Accessible }

    if ($failedEndpoints.Count -eq 0) {
        Write-Host "No failed endpoints found." -ForegroundColor Green
    }
    else {
        $failedEndpoints |
            Select-Object Id,
                @{ Name = 'Endpoint'; Expression = { $_.'Endpoint URL' } },
                Port,
                TestUrl,
                CurlExitCode,
                CurlResponse |
            Format-List
    }
}