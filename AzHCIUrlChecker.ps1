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

Function Invoke-AzHCIUrlChecker{
$Ver="1.7"
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
         Write-Host "This script checks the URLs for Azure Stack HCI/Azure Local "
         Write-Host ""

# Step 1: Download the main GitHub HTML page
    $mainUrl = 'https://github.com/MicrosoftDocs/azure-stack-docs/blob/main/azure-local/concepts/firewall-requirements.md#required-firewall-urls-for-azure-local-deployments'
    Write-host "Gathering Regions..."
    Write-host ""
    $mainPage = Invoke-WebRequest -Uri $mainUrl -UseBasicParsing -UserAgent "Mozilla/5.0"

    if ($mainPage.StatusCode -eq 200) {
        # Safer regex pattern in PowerShell double-quoted string
        $urlPattern = "https?://[^""']+\.md"
        $FwUrls = [regex]::Matches($mainPage.Content, $urlPattern) | ForEach-Object { $_.Value }
    } else {
        Write-Host "ERROR: Webpage status code $($mainPage.StatusCode)" -ForegroundColor Red
        return
    }

# Step 2: Extract region names from URLs
    $regionPattern = "/([a-z]+(?:[a-z]*))-hci-endpoints\.md"
    $regions = [regex]::Matches(($FwUrls -join "`n"), $regionPattern) | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique


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

    # Extract rawBlobUrl
    if ($html -match "rawBlobUrl[`"`']?\s*:\s*[`"`']([^`"`']+)") {
        $rawBlobUrl = $matches[1]
        Write-Host "    Found: $rawBlobUrl"
    } else {
        Write-Host "    ERROR: Not found." -ForegroundColor Red
        return
    }

# Step 5: Fetch raw Markdown content
    $mdPage = Invoke-WebRequest -Uri $rawBlobUrl -UseBasicParsing -UserAgent "Mozilla/5.0"
    $markdown = $mdPage.Content

# Step 6: Extract and clean table
    # Extract the table block using regex (starts with | Id | and includes all | lines)
    $tableBlock = ($markdown -split "`n") -match '^\|\s*\d+\s*\|'  # Match rows like | 1 |
    $tableHeader = ($markdown -split "`n") -match '^\|\s*Id\s*\|'   # Match header line

    # Combine header + table lines
    $fullTable = $tableHeader + $tableBlock

    # Remove separators like |----|
    $cleanTable = $fullTable | Where-Object { $_ -notmatch '^\|\s*-+\s*\|' }

# Step 7: Parse table into PowerShell objects
    # Extract column names
    $columns = ($cleanTable[0] -split '\|') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

    # Parse each row into a custom object
    $endpointObjects = @()
    foreach ($line in $cleanTable[1..($cleanTable.Count - 1)]) {
        $cells = ($line -split '\|') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        $obj = [PSCustomObject]@{}
        for ($i = 0; $i -lt $columns.Count; $i++) {
            $obj | Add-Member -NotePropertyName $columns[$i] -NotePropertyValue $cells[$i]
        }
        $endpointObjects += $obj
    }

# Step 8: Check for more than one port and add a .x row in properation for testing connections in the next steps
    # Extract column names
    $columns = ($cleanTable[0] -split '\|') | ForEach-Object { $_.Trim() } | Where-Object { $_ }

    # Parse each row into objects, expand multiple ports into multiple rows
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
                # Just one port → create a single object
                $newObj = [PSCustomObject]@{}
                for ($i = 0; $i -lt $columns.Count; $i++) {
                    $value = $rowValues[$i]
                    $newObj | Add-Member -NotePropertyName $columns[$i] -NotePropertyValue $value
                }
                $endpointObjects += $newObj
            }
            else {
                # Multiple ports → make multiple objects with incremented Ids
                for ($j = 0; $j -lt $ports.Count; $j++) {
                    $newObj = [PSCustomObject]@{}
                    for ($i = 0; $i -lt $columns.Count; $i++) {
                        $colName = $columns[$i]
                        $value = $rowValues[$i]

                        if ($colName -eq 'Id') {
                            $value = if ($j -eq 0) { $originalId } else { "$originalId.$j" }
                        } elseif ($colName -eq 'Port') {
                            $value = $ports[$j]
                        }

                        $newObj | Add-Member -NotePropertyName $colName -NotePropertyValue $value
                    }
                    $endpointObjects += $newObj
                }
            }
        }
    }

# Step 9: Split into groups based on wildcard Endpoint URL (*)
    $wildcardEndpoints = $endpointObjects | Where-Object { $_.'Endpoint URL' -like '*`**' -or $_.'Endpoint URL' -like 'your*' }
    $testableEndpoints = $endpointObjects | Where-Object { $_.'Endpoint URL' -notlike '*`**' -and $_.'Endpoint URL' -notlike 'your*' }
    
    Write-Host ""
    Write-Host "===== ⚠️ Untestable Endpoints (Need Manual Handling) =====" -ForegroundColor Yellow
    $wildcardEndpoints | Format-Table Id, 'Endpoint URL', Port, Notes -AutoSize

    
    #$testableEndpoints | Format-Table Id, 'Endpoint URL', Port, Notes -AutoSize

    #Test-PortFast $testableEndpoints



function Test-PortFast {
    param (
        [string]$ComputerName,
        [int]$Port,
        [int]$TimeoutMs = 2000
    )

    try {
        $ComputerName=$ComputerName -replace "http://" -replace "https://"
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect($ComputerName, $Port, $null, $null)
        $wait = $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)

        if ($wait -and $client.Connected) {
            $client.Close()
            return $true
        } else {
            $client.Close()
            return $false
        }
    } catch {
        return $false
    }
}

$total = $testableEndpoints.Count
$counter = 0
$testedendpoints = @()

foreach ($endpoint in $testableEndpoints) {
    $counter++
    $ep2test = $endpoint.'Endpoint URL'.Trim()
    $port = [int]$endpoint.Port

    Write-Progress -Activity "Testing Endpoints" -Status "$counter of $($total):$($ep2test):$($port)" -PercentComplete (($counter / $total) * 100)

    $isUp = Test-PortFast -ComputerName $ep2test -Port $port

    # Clone the object to make sure it’s not shared reference
    $obj = $endpoint.PSObject.Copy()
    $obj | Add-Member -NotePropertyName 'Accessible' -NotePropertyValue $isUp -Force

    $testedendpoints += $obj
}





# Step 9: Output the parsed endpoint table
    Write-Host "`n===== ✅ Testable Endpoints =====" -ForegroundColor Green
    $testedendpoints = $testedendpoints | sort 'Accessible',Id -Descending 
    #$testedendpoints | select Id,'Azure Local',Component,'Endpoint URL',Port,'Accessible', Notes |ft 

# Convert ID to float for proper sorting (handles 24.1, 24.2, etc.)
$testedendpoints | ForEach-Object {
    $_ | Add-Member -NotePropertyName "SortId" -NotePropertyValue ([double]$_.'Id') -Force
}

# Sort by Accessible (True first), then numeric ID
$sortedEndpoints = $testedendpoints |
    Sort-Object -Property @{Expression = 'Accessible'; Descending = $true}, @{Expression = 'SortId'; Ascending = $true}

# Format table and output with aligned columns and color
$table = $sortedEndpoints |
    Select-Object Id, @{Name='Component'; Expression={$_.'Azure Local Component'}},
                  @{Name='Endpoint';  Expression={$_.'Endpoint URL'}},
                  Port, Accessible, Notes |
    Format-Table -AutoSize | Out-String -Stream

# Extract and print header
$header = $table[0]
$separator = $table[1]
Write-Host $header
Write-Host $separator

# Print rows with color based on accessibility
foreach ($line in $table[2..($table.Count - 1)]) {
    if ($line -match '\bTrue\b') {
        Write-Host $line
    } elseif ($line -match '\bFalse\b') {
        Write-Host $line -ForegroundColor Red
    } else {
        Write-Host $line
    }
}

}
