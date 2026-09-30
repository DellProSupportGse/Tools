<#
    .Synopsis
    .DESCRIPTION
       Azure Local: standalone predeployment preparation using model-filtered SBE
       presets. Downloads/verifies the bundle, applies manifest-listed driver INFs
       and applicable Dell firmware DUPs locally, then stages deployment files in
       C:\SBE. No solution-update commands, cluster maintenance, or DSU catalog.
       Raw drive firmware is audited for manual follow-up; no forced downgrades.
       Other Windows Server systems retain the original DART DSU workflow.
       Run from elevated Windows PowerShell: .\DART_SBE.ps1
    .EXAMPLES
       Install Windows Updates, Drivers and Firmware:
            Invoke-DART -WindowsUpdates:$True -DriverandFirmware:$True
       Install Driver and Firmware Only:
            Invoke-DART -WindowsUpdates:$False -DriverandFirmware:$True
       Install Windows Updates Only:
            Invoke-DART -WindowsUpdates:$True -DriverandFirmware:$False
       Fully Automated
            Invoke-DART -WindowsUpdates:$True -DriverandFirmware:$True -Confirm:$false
    #>
    
    param(
    [Parameter(Mandatory=$False, Position=1)]
    [bool] $IgnoreChecks=$False,[bool] $IgnoreVersion=$False)

# SBE release metadata is discovered live from Dell's public Azure Local SupportMatrix
# repository on every run. Download URL/SHA256 are resolved from Dell's live SBE
# download catalog. A last-known-good cache is used only if the live SupportMatrix
# lookup fails; no SBE release/model list is embedded in DART.
function ConvertFrom-DartHtmlCell {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    $text = $Value -replace '(?i)<br\s*/?>', "`n"
    $text = $text -replace '(?is)<[^>]+>', ''
    $text = [Net.WebUtility]::HtmlDecode($text)
    return $text.Trim()
}

function Resolve-DartSbeCatalogItem {
    param(
        [Parameter(Mandatory=$true)][xml]$Catalog,
        [Parameter(Mandatory=$true)][string]$Version
    )

    # Match URL and hash within the SAME SBE record; never across siblings.
    foreach ($node in $Catalog.SelectNodes('/Catalog/Family/SBE')) {
        if ($node.GetAttribute('Version') -ne $Version) { continue }
        $url = [string]$node.DownloadURL
        $sha = [string]$node.PackageHash
        if ($url -notmatch '^https://(downloads|dl)\.dell\.com/.+\.zip$' -or
            $sha -notmatch '^[0-9a-fA-F]{64}$') { continue }
        return [pscustomobject]@{
            Url=$url; SHA256=$sha.ToLowerInvariant(); Family=$node.ParentNode.GetAttribute('name')
        }
    }
    return $null
}

function Get-DartSbePreset {
    $supportMatrixIndex = 'https://dell.github.io/azurestack-docs/docs/hci/supportmatrix/'
    $rawBase = 'https://raw.githubusercontent.com/dell/azurestack-docs/main/content/en/docs/hci/SupportMatrix'
    $catalogUris = @(
        'https://aka.ms/DellAzureLocalSBEDownloadCatalog',
        'https://downloads.dell.com/filestore/Prod/SbeDownloadCatalog/AX_SBE_Download_Catalog.xml'
    )
    $cacheRoot = Join-Path $env:ProgramData 'Dell\DART\SBE'
    $cacheFile = Join-Path $cacheRoot 'SupportMatrixAllReleasesCache.json'
    $headers = @{ 'User-Agent' = 'Dell-DART-SBE' }

    try {
        Write-Host 'Checking all Dell SupportMatrix release notes and historical SBE download entries...'
        $tree = Invoke-RestMethod -Uri 'https://api.github.com/repos/dell/azurestack-docs/git/trees/main?recursive=1' -Headers $headers -ErrorAction Stop
        if ($tree.truncated) { throw 'GitHub returned an incomplete SupportMatrix tree.' }
        $notePaths = @($tree.tree | Where-Object { $_.path -match '^content/en/docs/hci/SupportMatrix/(?:Archive/)?[0-9]{4}/SBEReleaseNotes/_index\.md$' } | ForEach-Object { $_.path })
        if (-not $notePaths.Count) { throw 'No SBE release-note files were found in the SupportMatrix repository.' }

        $releaseRows = [Collections.Generic.List[object]]::new()
        foreach ($notePath in $notePaths) {
            $release = ($notePath -split '/')[-3]
            $notesUrl = "https://raw.githubusercontent.com/dell/azurestack-docs/main/$notePath"
            try {
                $markdown = (Invoke-WebRequest -Uri $notesUrl -Headers $headers -UseBasicParsing -ErrorAction Stop).Content
            }
            catch {
                # Not every SupportMatrix release necessarily contains SBE release notes.
                continue
            }

            $rowChunks = $markdown -split '(?i)<tr[^>]*>'
            foreach ($rowChunk in $rowChunks) {
                $cells = @([regex]::Matches($rowChunk, '(?is)<td[^>]*>(.*?)</td>') | ForEach-Object { $_.Groups[1].Value })
                if ($cells.Count -lt 6) { continue }
                $version = ConvertFrom-DartHtmlCell $cells[0]
                if ($version -notmatch '^\d+\.\d+\.\d+\.\d+$') { continue }

                $models = @((ConvertFrom-DartHtmlCell $cells[2]) -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                $solutionPatterns = @((ConvertFrom-DartHtmlCell $cells[5]) -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                if (-not $models.Count) { continue }

                $releaseRows.Add([pscustomobject]@{
                    Release          = $release
                    Version          = $version
                    OS               = ConvertFrom-DartHtmlCell $cells[4]
                    Models           = $models
                    SolutionPatterns = $solutionPatterns
                    Notes            = "https://dell.github.io/azurestack-docs/docs/hci/supportmatrix/$release/sbereleasenotes/"
                })
            }
        }
        if (-not $releaseRows.Count) { throw 'No SBE release rows could be parsed from Dell SupportMatrix.' }

        [xml]$catalog = $null
        $catalogError = $null
        foreach ($catalogUri in $catalogUris) {
            try {
                $catalogText = (Invoke-WebRequest -Uri $catalogUri -UseBasicParsing -ErrorAction Stop).Content
                $catalog = New-Object System.Xml.XmlDocument
                $catalog.XmlResolver = $null
                $catalog.LoadXml($catalogText)
                break
            }
            catch { $catalogError = $_ }
        }
        if ($null -eq $catalog) {
            throw "Dell SBE download catalog could not be downloaded: $($catalogError.Exception.Message)"
        }

        $presets = [Collections.Generic.List[object]]::new()
        foreach ($row in $releaseRows) {
            $download = Resolve-DartSbeCatalogItem -Catalog $catalog -Version $row.Version
            if ($null -eq $download) {
                Write-Warning "SupportMatrix lists SBE $($row.Version), but it was not found with URL/SHA256 in Dell's download catalog; skipping it."
                continue
            }
            $presets.Add([pscustomobject]@{
                Release          = $row.Release
                Version          = $row.Version
                Family           = if ($download.Family) { $download.Family } else { 'Dell-AzureLocal' }
                OS               = $row.OS
                Historical       = $false
                Models           = $row.Models
                SolutionPatterns = $row.SolutionPatterns
                Url              = $download.Url
                SHA256           = $download.SHA256
                Notes            = $row.Notes
            })
        }
        # Older bundles remain in Dell's download catalog after release-note pages
        # are removed. Use Dell AX product families, not newer PowerEdge aliases.
        $historicalModels = @{
            'AX-14G' = @('AX-640','AX-740xd')
            'AX-15G' = @('AX-650','AX-750','AX-6515','AX-7525')
            'AX-16G-45n0c' = @('AX-660','AX-760','AX-4510C','AX-4520C','APEX MC-660','APEX MC-760','APEX MC-4510C','APEX MC-4520C')
            'AX-17G' = @('AX-670','AX-770')
            '16G-45n0c-Intel' = @('AX-660','AX-760','AX-4510C','AX-4520C')
            '17G-Intel' = @('AX-670','AX-770')
        }
        foreach ($familyNode in $catalog.SelectNodes('/Catalog/Family')) {
            $family = $familyNode.GetAttribute('name')
            foreach ($item in $familyNode.SelectNodes('SBE')) {
                $version = $item.GetAttribute('Version')
                if ($version -notmatch '^\d+\.\d+\.\d{4}\.\d+$' -or @($presets | Where-Object Version -eq $version).Count) { continue }
                if (-not $historicalModels.ContainsKey($family)) {
                    Write-Warning "Unmapped SBE family '$family': $version cannot be filtered by model."
                    continue
                }
                $download = Resolve-DartSbeCatalogItem -Catalog $catalog -Version $version
                if ($null -eq $download) { Write-Warning "No valid Dell URL/hash for $version"; continue }
                $presets.Add([pscustomobject]@{
                    Release=($version -split '\.')[2]; Version=$version; Family=$family
                    Models=$historicalModels[$family]; OS='Verify in historical Dell release notes'
                    Historical=$true; SolutionPatterns=@('Not supplied by current SupportMatrix; verify before installing')
                    Url=$download.Url; SHA256=$download.SHA256
                    Notes=$supportMatrixIndex
                })
            }
        }
        if (-not $presets.Count) { throw 'No SupportMatrix SBE releases could be matched to Dell download catalog entries.' }

        New-Item -Path $cacheRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
        $presets | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $cacheFile -Encoding UTF8 -Force
        Write-Host ("Live SupportMatrix: {0} SBE release entries discovered." -f $presets.Count) -ForegroundColor Green
        foreach ($preset in $presets) { $preset }
        return
    }
    catch {
        Write-Warning "Live Dell SupportMatrix lookup failed: $($_.Exception.Message)"
        if (Test-Path -LiteralPath $cacheFile -PathType Leaf) {
            try {
                $cached = @(Get-Content -LiteralPath $cacheFile -Raw -ErrorAction Stop | ConvertFrom-Json)
                if ($cached.Count) {
                    Write-Warning "Using last-known-good dynamic SBE cache: $cacheFile"
                    foreach ($preset in $cached) { $preset }
                    return
                }
            }
            catch {
                Write-Warning "Cached SupportMatrix data could not be loaded: $($_.Exception.Message)"
            }
        }
        throw 'Unable to obtain Dell SBE release metadata from the live SupportMatrix and no usable dynamic cache exists.'
    }
}

function Get-DartPayloadPath {
    param([string]$Root, [string]$RelativePath)
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $path = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    if (-not $path.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) { throw 'Payload path escapes the extracted SBE directory.' }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing SBE payload file: $path" }
    return $path
}

function Assert-DartDellSignature {
    param([string]$Path)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Dell') {
        throw "Dell signature validation failed: $Path ($($signature.Status))"
    }
}

function Invoke-DartDup {
    param([string]$Path, [string]$LogDirectory, [switch]$CheckOnly)
    $phase = if ($CheckOnly) { 'check' } else { 'install' }
    $log = Join-Path $LogDirectory (([IO.Path]::GetFileNameWithoutExtension($Path)) + ".$phase.log")
    $arguments = '/s /l="' + $log + '"'
    if ($CheckOnly) { $arguments += ' /c' }
    # Never use /f (force downgrade) or /r (automatic reboot).
    $process = Start-Process -FilePath $Path -ArgumentList $arguments -Wait -PassThru -ErrorAction Stop
    return [int]$process.ExitCode
}

function Get-DartDriverResult {
    param([int]$ExitCode, [string]$OutputText)
    # 259 is accepted only with explicit no-change evidence from PnPUtil.
    # Unknown/localized 259 output remains a failure requiring log review.
    $upToDate = $ExitCode -eq 259 -and
        $OutputText -match '(?im)^\s*Driver package is up-to-date on device:' -and
        $OutputText -match '(?im)^\s*Added driver packages:\s*0\s*$' -and
        $OutputText -notmatch '(?im)^.*\b(failed|failure|error)\b'
    $status = switch ($ExitCode) {
        0 { 'Driver processed; inspect log for matched devices' }
        3010 { 'Driver processed; reboot required' }
        259 {
            if ($upToDate) { 'Already installed / up to date; no changes needed' }
            else { 'Unverified exit 259; inspect PnPUtil log' }
        }
        default { 'Failed' }
    }
    [pscustomobject]@{
        Continue = ($ExitCode -in @(0,3010) -or $upToDate)
        RebootRequired = ($ExitCode -eq 3010)
        Status = $status
    }
}

function Get-DartSbeArchive {
    param([Parameter(Mandatory=$true)]$Selected, [Parameter(Mandatory=$true)][string]$VersionRoot)
    if ($Selected.LocalArchive) {
        # Recheck immediately before extraction in case the file changed after selection.
        $localHash = (Get-FileHash -LiteralPath $Selected.LocalArchive -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($localHash -ne $Selected.SHA256) { throw 'Local SBE ZIP changed or failed SHA256 verification. Nothing installed.' }
        Write-Host 'Using verified local SBE ZIP; download skipped.' -ForegroundColor Green
        return $Selected.LocalArchive
    }
    $cache = Join-Path $VersionRoot 'Cache'
    New-Item -Path $cache -ItemType Directory -Force -ErrorAction Stop | Out-Null
    $archive = Join-Path $cache 'Bundle.zip'
    # Include bundles left in timestamped run directories by earlier DART versions.
    $candidates = @()
    if (Test-Path -LiteralPath $archive -PathType Leaf) { $candidates += Get-Item -LiteralPath $archive }
    $candidates += @(Get-ChildItem -LiteralPath $VersionRoot -Directory -ErrorAction Stop |
        Where-Object Name -ne 'Cache' | Sort-Object Name -Descending | ForEach-Object {
            $previous = Join-Path $_.FullName 'Bundle.zip'
            if (Test-Path -LiteralPath $previous -PathType Leaf) { Get-Item -LiteralPath $previous }
        })
    foreach ($candidate in $candidates) {
        Write-Host "Verifying existing SBE bundle: $($candidate.FullName)"
        try { $hash = (Get-FileHash -LiteralPath $candidate.FullName -Algorithm SHA256 -ErrorAction Stop).Hash }
        catch { Write-Warning "Cannot verify $($candidate.FullName); checking other copies."; continue }
        if ($hash -eq $Selected.SHA256) {
            Write-Host 'Using existing verified SBE bundle; download skipped.' -ForegroundColor Green
            return $candidate.FullName
        }
        Write-Warning "Hash mismatch: $($candidate.FullName). This copy will not be used."
    }
    $partial = Join-Path $cache ("Bundle.{0}.partial" -f [guid]::NewGuid().ToString('N'))
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    try {
        Write-Host "Downloading $($Selected.Url)"
        try { Start-BitsTransfer -Source $Selected.Url -Destination $partial -ErrorAction Stop }
        catch { Invoke-WebRequest -Uri $Selected.Url -OutFile $partial -UseBasicParsing -ErrorAction Stop }
        if ((Get-FileHash -LiteralPath $partial -Algorithm SHA256 -ErrorAction Stop).Hash -ne $Selected.SHA256) {
            throw 'SBE SHA256 mismatch; downloaded bundle rejected. Nothing installed.'
        }
        Move-Item -LiteralPath $partial -Destination $archive -Force -ErrorAction Stop
        return $archive
    } finally {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
    }
}

function Select-DartLocalSbe {
    param([object[]]$Choices, [string]$Model)
    while ($true) {
        Write-Host 'Enter the downloaded Dell Bundle SBE ZIP path (for example C:\SBE\Bundle_SBE_Dell_....zip).'
        $path = ([string](Read-Host 'ZIP path, or B to go back')).Trim().Trim('"').Trim("'")
        if ($path -eq 'B') { return }
        try {
            $file = Get-Item -LiteralPath $path -ErrorAction Stop
            if ($file.PSIsContainer -or $file.Extension -ne '.zip') { throw 'Select a ZIP file, not a folder.' }
            Write-Host 'Verifying local SBE bundle SHA-256...'
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
            $matches = @($Choices | Where-Object { $_.Models -contains $Model -and $_.SHA256 -eq $hash })
            if ($matches.Count -ne 1) {
                throw "This ZIP does not match a verified Dell SBE bundle for $Model in the current or cached release list. Select the original outer Bundle ZIP."
            }
            $selected = $matches[0].PSObject.Copy()
            $selected | Add-Member -NotePropertyName LocalArchive -NotePropertyValue $file.FullName -Force
            Write-Host ("Using local SBE {0}: {1}" -f $selected.Version, $file.FullName) -ForegroundColor Green
            return $selected
        } catch { Write-Warning $_.Exception.Message }
    }
}

function Select-DartSbeRelease {
    param([object[]]$Choices, [string]$Model)
    $current = @($Choices | Where-Object { -not $_.Historical } | Sort-Object { [version]$_.Version } -Descending)
    $historical = @($Choices | Where-Object { $_.Historical } | Sort-Object { [version]$_.Version } -Descending)
    $showHistorical = $false
    while ($true) {
        $menu = @($current)
        $title = 'Current'
        if ($showHistorical) { $menu = @($historical); $title = 'Historical' }
        Write-Host ''
        Write-Host "$title SBE releases for $Model" -ForegroundColor Cyan
        Write-Host ''
        if (-not $menu.Count) { Write-Host '  No releases available in this menu.' }
        for ($i = 0; $i -lt $menu.Count; $i++) {
            $entry = $menu[$i]
            Write-Host ("  {0}. SBE {1}" -f ($i + 1), $entry.Version) -ForegroundColor White
            Write-Host ("     Release: {0}" -f $entry.Release)
            Write-Host ("     HCI OS: {0}" -f $entry.OS)
            if ($entry.Historical) { Write-Host '     Historical bundle: model-family match; verify deployment compatibility.' -ForegroundColor Yellow }
            Write-Host ("     Target solution: {0}" -f ($entry.SolutionPatterns -join ', '))
            Write-Host ''
        }
        if ($showHistorical) { Write-Host '  B. Back to current releases' }
        elseif ($historical.Count) { Write-Host ("  H. Historical ({0} older releases)" -f $historical.Count) }
        Write-Host '  L. Local SBE ZIP (provide path)'
        Write-Host '  Q. Cancel'
        Write-Host ''
        $answer = ([string](Read-Host 'Select an option')).Trim()
        if ($answer -eq 'Q') { return }
        if ($answer -eq 'L') {
            $local = Select-DartLocalSbe -Choices $Choices -Model $Model
            if ($null -ne $local) { return $local }
            continue
        }
        if ($answer -eq 'B' -and $showHistorical) { $showHistorical = $false; continue }
        if ($answer -eq 'H' -and -not $showHistorical -and $historical.Count) { $showHistorical = $true; continue }
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $menu.Count) {
            return $menu[$number - 1]
        }
        Write-Host 'Invalid selection. Choose one of the displayed options.' -ForegroundColor Yellow
    }
}

function Invoke-DartSbe {
    [CmdletBinding()]
    param()
    $localSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ($localSystem.Manufacturer -notmatch 'Dell') { throw 'This server is not a Dell system.' }
    $model = ([string]$localSystem.Model).Trim()
    $choices = @(Get-DartSbePreset | Where-Object { $_.Models -contains $model } | Sort-Object { [version]$_.Version } -Descending -Unique)
    if (-not $choices.Count) { throw "No preset SBE lists server model '$model'." }
    Write-Host "Predeployment preparation - LOCAL SERVER ONLY: $env:COMPUTERNAME ($model)" -ForegroundColor Cyan
    $selected = Select-DartSbeRelease -Choices $choices -Model $model
    if ($null -eq $selected) { return }
    Write-Host "Selected SBE $($selected.Version). Release notes: $($selected.Notes)"
    Write-Host 'Choose a release suitable for your intended Azure Local deployment version. Historical bundles are not automatically certified for your intended OS/solution version.'
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ([int]$os.BuildNumber -lt 26100) { throw 'This standalone installation workflow requires HCI OS 24H2 or later. Install the appropriate OS image first.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run DART in elevated Windows PowerShell.' }
    # A configured cluster has this registry key even if ClusSvc is stopped.
    # Normal mode remains predeployment-only. -IgnoreChecks may be used for a
    # previously clustered node, but only after the Cluster Service is stopped.
    if (Test-Path 'HKLM:\Cluster') {
        if ($Global:IgnoreChecks -ne $True) {
            throw 'This SBE path is for standalone predeployment servers. Cluster membership was detected; use -IgnoreChecks only after stopping the cluster for intentional maintenance.'
        }

        $clusSvc = Get-Service -Name ClusSvc -ErrorAction SilentlyContinue
        if ($clusSvc -and $clusSvc.Status -ne 'Stopped') {
            throw '-IgnoreChecks was specified on a cluster member, but the Cluster Service is still running. Stop the cluster/service before starting SBE firmware updates.'
        }

        Write-Warning 'Cluster membership is present, but -IgnoreChecks is enabled and ClusSvc is stopped. Continuing with local SBE maintenance.'
    }
    $versionRoot = Join-Path $env:ProgramData ("Dell\DART\SBE\{0}" -f $selected.Version)
    $run = Join-Path $versionRoot (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
    $outer = Join-Path $run 'Bundle'
    $payload = Join-Path $run 'Payload'
    $logs = Join-Path $run 'Logs'
    New-Item -Path $outer,$payload,$logs -ItemType Directory -Force -ErrorAction Stop | Out-Null
    $archive = Get-DartSbeArchive -Selected $selected -VersionRoot $versionRoot
    Expand-Archive -LiteralPath $archive -DestinationPath $outer -ErrorAction Stop
    $manifests = @(Get-ChildItem $outer -Recurse -File -Filter 'SBE_*.xml' | Where-Object Name -ne 'SBE_Discovery_Dell.xml')
    $zips = @(Get-ChildItem $outer -Recurse -File -Filter 'SBE_*.zip')
    if ($manifests.Count -ne 1 -or $zips.Count -ne 1 -or $manifests[0].BaseName -ne $zips[0].BaseName -or $manifests[0].Name -notlike "*$($selected.Version)*") { throw 'Unexpected SBE bundle structure/version.' }
    Expand-Archive -LiteralPath $zips[0].FullName -DestinationPath $payload -ErrorAction Stop
    $driverManifest = Get-DartPayloadPath $payload 'CAUPlugins\01-Custom\DriverComponents.xml'
    $driverXml = New-Object System.Xml.XmlDocument
    $driverXml.XmlResolver = $null
    $driverXml.Load($driverManifest)
    $drivers = @($driverXml.PlatformComponent.Components.Component)
    if (-not $drivers.Count) { throw 'No driver components were found in the SBE manifest.' }
    # Use manifest targets, not every INF: a bundle can contain alternate versions.
    $driverPaths = foreach ($driver in $drivers) {
        $relative = ([string]$driver.TargetPath).Replace('%SBELocalPath%\','')
        if ($relative -notmatch '^DriversGE\\.*\.inf$') { throw "Unsupported driver target: $relative" }
        Get-DartPayloadPath $payload $relative
    }
    # Filter firmware by the SBE lifecycle manifest instead of trying every DUP in the bundle.
    # TargetPlatform identifies which server models a package is intended for. TargetComponent
    # is retained for reporting; the Dell DUP still performs the final device-level applicability check.
    $lcmManifest = Get-DartPayloadPath $payload 'Software\lcm-manifest.xml'
    $lcmXml = New-Object System.Xml.XmlDocument
    $lcmXml.XmlResolver = $null
    $lcmXml.Load($lcmManifest)
    $allFirmwarePackages = @($lcmXml.InstallManifest.Packages.Package)
    if (-not $allFirmwarePackages.Count) { throw 'No firmware packages were found in Software\lcm-manifest.xml.' }

    $modelKey = $model.Trim()
    $modelPackages = @($allFirmwarePackages | Where-Object {
        $targets = @($_.TargetPlatform.Model | ForEach-Object { ([string]$_).Trim() })
        $targets -contains $modelKey
    })
    if (-not $modelPackages.Count) { throw "lcm-manifest.xml contains no firmware packages for server model '$model'." }

    # The same DUP can appear in more than one manifest entry (for example, one executable can
    # service multiple adapter families). Queue each executable only once, using the lowest install order.
    $dupMap = [ordered]@{}
    foreach ($package in ($modelPackages | Sort-Object { [int]$_.InstallOrder })) {
        $relative = ([string]$package.File).Trim().Replace('/','\')
        if ([IO.Path]::GetExtension($relative) -ine '.exe') { continue }
        $fullPath = Get-DartPayloadPath $payload $relative
        $key = $fullPath.ToLowerInvariant()
        if (-not $dupMap.Contains($key)) {
            $components = @($package.TargetComponent.Model | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
            $dupMap[$key] = [pscustomobject]@{
                Name         = [IO.Path]::GetFileName($fullPath)
                FullName     = $fullPath
                DisplayName  = ([string]$package.DisplayName).Trim()
                Version      = ([string]$package.Version).Trim()
                ComponentType= ([string]$package.ComponentType).Trim()
                Components   = ($components -join ', ')
                InstallOrder = [int]$package.InstallOrder
            }
        }
    }
    $dups = @($dupMap.Values | Sort-Object InstallOrder, Name)
    if (-not $dups.Count) { throw "No executable firmware packages in lcm-manifest.xml apply to server model '$model'." }
    foreach ($dup in $dups) { Assert-DartDellSignature $dup.FullName }

    Write-Host "Payload: $($drivers.Count) manifest driver entries; $($dups.Count) model-matched firmware DUPs for $model."
    Write-Host "Firmware filtered by Software\lcm-manifest.xml TargetPlatform. Dell DUPs still perform final component/device applicability checks."
    Write-Host ''
    Write-Host "Firmware packages selected for ${model}:" -ForegroundColor Cyan
    $dups | Select-Object InstallOrder,DisplayName,Version,ComponentType,Components,Name | Format-Table -AutoSize | Out-Host
    Write-Host 'Raw drive-firmware binaries are audited separately, not flashed by this version.' -ForegroundColor Yellow
    Write-Host 'Network driver updates can interrupt remote sessions. No reboot is automatic.' -ForegroundColor Yellow
    if ((Read-Host "Type INSTALL to apply SBE $($selected.Version) payloads to this server") -cne 'INSTALL') { Write-Host "Downloaded/extracted only: $run"; return }
    $results = [Collections.Generic.List[object]]::new()
    $needsReboot = $false
    $report = Join-Path $run 'Results.csv'
    # Use the bundle's own certificate check when available; never bypass BIOS prerequisites.
    $biosReady = $selected.Release -eq '2512'
    $certificateCheck = Join-Path $payload 'Software\Scripts\Confirm-SecureBootCertificates.ps1'
    if (Test-Path -LiteralPath $certificateCheck) {
        Assert-DartDellSignature $certificateCheck
        $certificateResults = @(& $certificateCheck)
        $biosReady = $certificateResults.Count -gt 0 -and $certificateResults[-1] -is [bool] -and $certificateResults[-1]
    }
    try {
        for ($i=0; $i -lt $drivers.Count; $i++) {
            Write-Host "Driver: $($drivers[$i].FriendlyName)"
            $log = Join-Path $logs "Driver-$i.log"
            $driverOutput = @(& "$env:windir\System32\pnputil.exe" /add-driver $driverPaths[$i] /install 2>&1)
            $code = $LASTEXITCODE
            $driverOutput | Tee-Object -FilePath $log | Out-Host
            $driverResult = Get-DartDriverResult -ExitCode $code -OutputText ($driverOutput -join "`n")
            if ($driverResult.RebootRequired) { $needsReboot = $true }
            $results.Add([pscustomobject]@{Type='Driver';Package=$drivers[$i].FriendlyName;ExitCode=$code;Status=$driverResult.Status;Log=$log})
            $results | Export-Csv $report -NoTypeInformation
            Write-Host "    $($driverResult.Status)"
            if (-not $driverResult.Continue) { throw "Driver installation failed or needs review (exit $code). See $log" }
        }
        foreach ($dup in $dups) {
            Write-Host "Checking firmware: $($dup.Name)"
            if ($dup.Name -like 'BIOS_*' -and -not $biosReady) {
                $results.Add([pscustomobject]@{Type='Firmware';Package=$dup.Name;ExitCode='';Status='Blocked: Secure Boot 2023 certificate prerequisite not verified';Log=$logs})
                continue
            }
            $code = Invoke-DartDup -Path $dup.FullName -LogDirectory $logs -CheckOnly
            if ($code -eq 0) {
                Write-Host "Installing firmware: $($dup.Name)"
                $code = Invoke-DartDup -Path $dup.FullName -LogDirectory $logs
                $status = switch ($code) {
                    0 { 'Installed' }
                    2 { $needsReboot = $true; 'Installed; reboot required' }
                    default { 'Failed: inspect DUP log' }
                }
            } else {
                $status = switch ($code) {
                    3 { 'Not installed: same/newer version or soft dependency; review log' }
                    4 { 'Not installed: prerequisite missing or no supported device; review log' }
                    5 { 'Not installed: qualification check failed; review log' }
                    default { 'Failed: applicability check error' }
                }
            }
            $results.Add([pscustomobject]@{Type='Firmware';Package=$dup.Name;ExitCode=$code;Status=$status;Log=$logs})
            $results | Export-Csv $report -NoTypeInformation
            if ($status -like 'Failed*') {
                Write-Host "    FAILED: $($dup.Name) (exit $code). Continuing with remaining firmware packages." -ForegroundColor Red
                Write-Host "    Review DUP logs in: $logs" -ForegroundColor Yellow
            } else {
                Write-Host "    $status"
            }
        }
        # Audit raw drive firmware using the SBE's exact server/drive mapping.
        $diskManifest = Join-Path $payload 'Configuration\Disks\StorageDisks.xml'
        if (Test-Path $diskManifest) {
            [xml]$diskXml = Get-Content -LiteralPath $diskManifest -Raw
            $modelKey = $model -replace '[^a-zA-Z0-9]',''
            $groups = @($diskXml.StorageDisks.Components | Where-Object { ($_.Model -replace '[^a-zA-Z0-9]','') -eq $modelKey })
            $driveReport = foreach ($disk in @(Get-PhysicalDisk -ErrorAction Stop)) {
                $matches = @($groups.Disks.Disk | Where-Object { ([string]$_.Model).Trim() -eq ([string]$disk.Model).Trim() })
                $targets = @($matches | ForEach-Object { [string]$_.TargetFirmware.Version } | Sort-Object -Unique)
                $status = if ($targets.Count -eq 1 -and $targets[0] -eq ([string]$disk.FirmwareVersion).Trim()) { 'At target' } elseif ($targets.Count -eq 1) { 'Manual firmware review/update required' } else { 'No unique exact mapping; review manually' }
                [pscustomobject]@{DeviceId=$disk.DeviceId;SerialNumber=$disk.SerialNumber;Model=$disk.Model;Current=$disk.FirmwareVersion;Target=($targets -join ',');Status=$status;Binary=($matches.TargetFirmware.BinaryPath -join ';')}
            }
            $driveReport | Export-Csv (Join-Path $run 'DriveFirmwareReview.csv') -NoTypeInformation
            $driveReport | Format-Table -AutoSize | Out-Host
        }
        # Keep the three outer files for Azure Local deployment, separate from extracted payloads.
        $deploymentPath = 'C:\SBE'
        $discovery = Join-Path $outer 'SBE_Discovery_Dell.xml'
        Invoke-WebRequest -Uri 'https://aka.ms/AzureStackSBEUpdate/DellEMC' -OutFile $discovery -UseBasicParsing -ErrorAction Stop
        $xml = New-Object System.Xml.XmlDocument; $xml.XmlResolver = $null; $xml.Load($discovery)
        if ($xml.DocumentElement.LocalName -eq 'html') { throw 'Discovery download returned HTML.' }
        New-Item -Path $deploymentPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        $existing = @(Get-ChildItem $deploymentPath -File -Filter 'SBE_*' -ErrorAction Stop)
        if ($existing.Count) {
            $backup = Join-Path $run 'PreviousDeploymentSBE'
            New-Item $backup -ItemType Directory -ErrorAction Stop | Out-Null
            $existing | Move-Item -Destination $backup -ErrorAction Stop
        }
        Copy-Item -LiteralPath $manifests[0].FullName,$zips[0].FullName,$discovery -Destination $deploymentPath -ErrorAction Stop
        Write-Host "Selected SBE deployment files staged in $deploymentPath."
    } finally {
        $results | Export-Csv $report -NoTypeInformation
        $results | Format-Table Type,Package,ExitCode,Status -AutoSize | Out-Host
        Write-Host "Results and logs: $run"

        # Dell firmware updates can temporarily expose a USB-backed SECUPD service partition.
        # Remove the SECUPD access path only from partitions whose DiskPath identifies them as USB-backed.
        $secupdDeviceIds = @(
            Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue |
                Where-Object { $_.VolumeName -imatch 'SECUPD' } |
                Select-Object -ExpandProperty DeviceID
        )
        if ($secupdDeviceIds.Count) {
            $usbPartitions = @(Get-Partition -ErrorAction SilentlyContinue | Where-Object { $_.DiskPath -imatch 'usb' })
            foreach ($secupdDeviceId in $secupdDeviceIds) {
                try {
                    Write-Host "Removing temporary USB-backed SECUPD access path: $secupdDeviceId" -ForegroundColor Yellow
                    $usbPartitions | Remove-PartitionAccessPath -AccessPath $secupdDeviceId -ErrorAction Stop
                } catch {
                    Write-Warning "Unable to remove USB-backed SECUPD access path $secupdDeviceId : $($_.Exception.Message)"
                }
            }
        }

        if ($needsReboot) { Write-Host 'A reboot is required. Reboot this server, then rerun to check remaining updates.' -ForegroundColor Yellow }
    }
    Write-Host 'Payload processing finished. Review all skipped/blocked packages and DriveFirmwareReview.csv before deployment.' -ForegroundColor Yellow
    Write-Host 'This does not register an installed SBE version or certify full support-matrix compliance.'
    if ((Read-Host 'Reboot this standalone server now? [y/N]') -eq 'y') { Restart-Computer -Force }
}


Function Invoke-DART {

    param(
    [Parameter(Mandatory=$False, Position=1)]
    [bool] $IgnoreChecks=$False,[bool] $IgnoreVersion=$False,
    $param)

    $ver="1.10"

$DateTime=Get-Date -Format yyyyMMdd_HHmmss
New-Item -Path "C:\ProgramData\Dell\DART" -ItemType Directory -Force | Out-Null
Start-Transcript -NoClobber -Path "C:\programdata\Dell\DART\DART_$DateTime.log"
$Global:IgnoreChecks=$IgnoreChecks
$Global:IgnoreVersion=$IgnoreVersion

# =====================================================
#region Telemetry Information
# =====================================================

$script:TelemetryReportID    = [guid]::NewGuid().Guid
$script:TelemetryGeoResolved = $false
$script:TelemetryGeoData     = @{}
$script:TelemetryStartupSent = $false
$script:uploadToAzure        = $true

function Write-Indent {
    param(
        [string]$Message,
        [int]$Level = 1,
        [string]$Color = "Gray"
    )

    try {
        $prefix = "  " * $Level
        Write-Host "$prefix$Message" -ForegroundColor $Color
    }
    catch {}
}

function Get-TelemetryMachineHash {
    try {
        $raw = "$env:USERDOMAIN\$env:USERNAME@$env:COMPUTERNAME"
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash)).Replace("-","").Substring(0,24)
    }
    catch {
        return ""
    }
}

function Resolve-TelemetryGeo {
    try {
        if ($script:TelemetryGeoResolved) { return }

        Write-Indent "Resolving Geo Location..."

        try {
            # Prefer local Windows settings
            $LocalRegionInfo = [System.Globalization.RegionInfo]::CurrentRegion

            if (-not $LocalRegionInfo.TwoLetterISORegionName) {
                throw "Unable to determine local region."
            }

            $script:TelemetryGeoData = @{
                country     = [string]$LocalRegionInfo.EnglishName
                countryCode = [string]$LocalRegionInfo.TwoLetterISORegionName
                timezone    = [string](Get-TimeZone).Id
            }

            Write-Indent "Country: $($script:TelemetryGeoData.country)" 2
            Write-Indent "Source : Windows Regional Settings" 2
        }
        catch {
            # Fallback to external IP geolocation
            Write-Indent "WARN: Local region lookup failed - trying ipwho.is" 2 Yellow

            if (-not $script:GeoCache) {
                $script:GeoCache = Invoke-RestMethod "https://ipwho.is/" -TimeoutSec 5
            }

            $response = $script:GeoCache

            if ($response.success -ne $true) {
                throw "ipwho.is did not return a valid response."
            }

            $script:TelemetryGeoData = @{
                country     = [string]$response.country
                countryCode = [string]$response.country_code
                timezone    = [string]$response.timezone.id
            }

            Write-Indent "Country: $($script:TelemetryGeoData.country)" 2
            Write-Indent "Source : ipwho.is fallback" 2
        }
    }
    catch {
        Write-Indent "WARN: Unable to determine geographic information" 2 Yellow

        # Always leave a valid object behind
        $script:TelemetryGeoData = @{
            country     = $null
            countryCode = $null
            timezone    = try { [string](Get-TimeZone).Id } catch { $null }
        }
    }
    finally {
        $script:TelemetryGeoResolved = $true
    }
}

function Send-ToolTelemetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TelemetryName,

        [Parameter(Mandatory=$true)]
        [string]$EventName,

        [Parameter(Mandatory=$true)]
        [string]$Version,

        [Parameter(Mandatory=$true)]
        [string]$Endpoint,

        [int]$ServerCount = 0,

        [int]$GroupCount = 0,

        [switch]$NoGeo,

        [switch]$DebugTelemetry
    )

    if (-not $script:uploadToAzure) { return }

    if ($EventName -match '^(Startup|Launch|AppStart|ToolStart|TelemetryStartup)$') {
        if ($script:TelemetryStartupSent) { return }
        $script:TelemetryStartupSent = $true
    }

    try {
        if (-not $NoGeo) {
            Resolve-TelemetryGeo
        }

        $rowKey = [guid]::NewGuid().Guid
        $partitionKey = $TelemetryName -replace 'TelemetryData$',''

        # ONLY requested table columns are placed in Data.
        $data = [ordered]@{
            PartitionKey = $partitionKey
            RowKey        = $rowKey
            PSVersion     = $PSVersionTable.PSVersion.ToString()
            countryCode   = $script:TelemetryGeoData.countryCode
            MachineHash   = Get-TelemetryMachineHash
            Version       = $Version
            timezone      = $script:TelemetryGeoData.timezone
            ReportID      = $script:TelemetryReportID
            country       = $script:TelemetryGeoData.country
        }

        # Envelope for the Function only. The Function should write Data only.
        $payload = @{
            TelemetryName = $TelemetryName
            TableName     = $TelemetryName
            Data          = $data
        }

        $body = $payload | ConvertTo-Json -Depth 10

        if ($DebugTelemetry) {
            Write-Host "Telemetry Request:" -ForegroundColor Cyan
            Write-Host $body
        }

        $response = Invoke-RestMethod `
            -Method Post `
            -Uri $Endpoint `
            -ContentType "application/json" `
            -Body $body `
            -TimeoutSec 15

        if ($DebugTelemetry) {
            Write-Host "Telemetry Response:" -ForegroundColor Green
            $response | ConvertTo-Json -Depth 10
        }
        else {
            Write-Indent "Telemetry recorded successfully" 1 Green
        }

    }
    catch {
        if ($DebugTelemetry) {
            Write-Warning "Telemetry failed: $($_.Exception.Message)"
            if ($_.ErrorDetails.Message) {
                Write-Warning $_.ErrorDetails.Message
            }
        }
        return
    }
}

 $telemetryParams = @{
     TelemetryName  = "DARTTelemetryData"
     EventName      = "Startup"
     Version        = $Ver
     Endpoint       = "https://gsetools-bufhdqefb8e6ecc6.centralus-01.azurewebsites.net/api/PostTelemetryData"
     DebugTelemetry = $false
 }

 Send-ToolTelemetry @telemetryParams

#endregion

Function EndScript{ 
    Stop-Transcript
    break
}

$addtablefunction=${function:add-TableData1}
Start-Job -Name "Telemetry" -ScriptBlock {
${function:add-TableData1} = $using:addtablefunction
# Generating a unique report id to link telemetry data to report data
    $CReportID=""
    $CReportID=(new-guid).guid
    
# Define the API endpoint URL
    $geourl = "http://ip-api.com/json"

# Invoke the API to determine Geolocation
    $response = Invoke-RestMethod $geourl

$data = @{
    Region=$env:UserDomain
    Version=$Ver
    ReportID=$CReportID  
    country=$response.country
    counrtyCode=$response.countryCode
    georegion=$response.region
    regionName=$response.regionName
    city=$response.city
    zip=$response.zip
    lat=$response.lat
    lon=$response.lon
    timezone=$response.timezone
}
$RowKey=(new-guid).guid
$PartitionKey="DART"
add-TableData1 -TableName "DARTTelemetryData" -PartitionKey $PartitionKey -RowKey $RowKey -data $data
#endregion End of Telemetry data
} | Out-Null
$Global:SolutionUpdates=(gcm Get-StampInformation -ErrorAction SilentlyContinue).count
$Global:EnforcedMode=$false
# Get-ASWDACPolicyMode calls Get-Cluster internally on Azure Local. If the cluster
# service was intentionally stopped for an SBE maintenance run, skip this check
# when -IgnoreChecks is in use so DART can continue without requiring ClusSvc.
if ($Global:IgnoreChecks -ne $True) {
    try {
        if ((Get-Command Get-ASWDACPolicyMode -ErrorAction SilentlyContinue).Count) {
            $wdacMode = Get-ASWDACPolicyMode -ErrorAction Stop | Where-Object { $_.NodeName -eq (hostname) }
            if ($wdacMode -and $wdacMode.PolicyMode -ne 'Audit') {
                $Global:EnforcedMode = $true
            }
        }
    }
    catch {
        Write-Warning "Unable to query ASWDAC policy mode: $($_.Exception.Message)"
    }
}
else {
    Write-Host 'Skipping ASWDAC policy mode check because -IgnoreChecks is enabled.' -ForegroundColor Yellow
}

$text=@"
$ver
 __        __  ___ 
|  \  /\  |__)  |  
|__/ /~~\ |  \  |  
"@
# Run Menu
$OSInfo = Get-WmiObject -Class Win32_OperatingSystem
#$Global:pre23h2=!($OSInfo.caption -imatch "Azure Stack HCI" -and $OSInfo.BuildNumber -ge "25398")
if ($Global:SolutionUpdates) {$sel='[1,qQ,hH]'} else {$sel='[1-2,qQ,hH]'}
Function ShowMenu{
    do
     {
         $selection=""
         Clear-Host
         Write-Host $text
         Write-Host ""
         #Check for ignore checks
         If($Global:IgnoreChecks -eq $True){Write-Host "IgnoreChecks:True" -ForegroundColor Yellow}
         If($Global:IgnoreVersion -eq $True){Write-Host "IgnoreVersion:True" -ForegroundColor Yellow}
         if($Global:EnforcedMode -eq $true){Write-Host "ASWDAC is not in Audit mode. Updates may fail." -ForegroundColor DarkYellow}

         Write-Host "This code is under the MIT License. See Repository for Licensing/Support details."
         Write-Host ""
         Write-Host "==================== Please make a selection ====================="
         Write-Host ""
         Write-Host "Press '1' to Install Dell Drivers and Firmware"
         IF(-not $Global:SolutionUpdates) {Write-Host "Press '2' to Install Windows Updates"}
         IF(-not $Global:SolutionUpdates) {Write-Host "Press '12' to Install both Dell Drivers and Firmware as well as Windows Updates"}
         #Write-Host "Press '3' to Install Windows Updates and Dell Drivers and Firmware"
         Write-Host "Press 'H' to Display Help"
         Write-Host "Press 'Q' to Quit"
         Write-Host ""
         $selection = Read-Host "Please make a selection"
     }
    until ($selection -match $sel)
    $Global:WindowsUpdates=$False
    $Global:DriverandFirmware=$False
    $Global:Confirm=$False
    IF($selection -imatch 'h'){
        Clear-Host
        Write-Host ""
        Write-Host "What's New in"$Ver":"
        Write-Host $WhatsNew 
        Write-Host ""
        Write-Host "Useage:"
        Write-Host "    Make a select by entering a comma delimited string of numbers from the menu."
        Write-Host ""
        Write-Host "        Example: 1 will Install Windows Updates."
        Write-Host ""
        Write-Host "        Example: 2 will Install Dell Drivers and Firmware"
        Write-Host ""
        Pause
        ShowMenu
    }
    IF($selection -match 2 -and -not $Global:SolutionUpdates){
        Write-Host "Installing Windows Updates..."
        $Global:WindowsUpdates=$True
        #$Global:DriverandFirmware=$False
        $Global:Confirm=$false
    }

    IF($selection -match 1){
        Write-Host "Installing Dell Drivers and Firmware..."
        #$Global:WindowsUpdates=$False
        $Global:DriverandFirmware=$True
        $Global:Confirm=$false
    }
    <#IF($selection -match 3){
        Write-Host "Installing Windows Updates and Dell Drivers and Firmware..."
        $Global:WindowsUpdates=$True
        $Global:DriverandFirmware=$True
        $Global:Confirm=$false
    }#>

    IF($selection -imatch 'q'){
        Write-Host "Bye Bye..."
        EndScript
    }
}#End of ShowMenu


# Route Azure Local to standalone SBE preparation before legacy DSU/cluster handling.
$IsAzureLocal = $OSInfo.Caption -match 'Azure (Stack HCI|Local)' -or [bool]$Global:SolutionUpdates
if ($IsAzureLocal) {
    try { Invoke-DartSbe }
    catch { Write-Error "SBE workflow stopped: $($_.Exception.Message)" }
    finally { Stop-Transcript }
    return
}

ShowMenu

# Dell Server Check
IF((Get-WmiObject -Class Win32_ComputerSystem).Manufacturer -imatch "Dell" -and (Get-WmiObject -Class Win32_ComputerSystem).PCSystemType -imatch "4"){
    # Fix 8.3 temp paths
        $MyTemp=(Get-Item $env:temp).fullname
if ($PSCmdlet.ShouldProcess($param)) { 

        Function Download-File{
            Param($URL)
            $DLFileName=$URL.Split('\/')[-1]
            Write-Host "    Downloading $URL..."
            $OutFile=$MyTemp+"\"+$DLFileName
            # Use TLS 1.2
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            # Download file
            Try{$webClient = [System.Net.WebClient]::new()
                # Set the User-Agent header to mimic Chrome
                $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")
                $webClient.DownloadFile($URL, $OutFile)}
            Catch{
                Try {Invoke-WebRequest $URL -OutFile $OutFile -UserAgent::Chrome} Catch {
                Write-Host "        ERROR: Downloading $URL" -ForegroundColor Red
                EndScript
            }}
            #Finally{
                IF([System.IO.File]::Exists($OutFile)){
                    Write-Host "        SUCCESS: File downloaded successfully" -ForegroundColor Green
                }
            #}
            Return $OutFile
        }

        Function Expand-Gz{
            Param($InFile)
            $outFile = $infile.Substring(0, $infile.LastIndexOfAny('.'))
            $input = New-Object System.IO.FileStream $inFile, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::Read)
            $output = New-Object System.IO.FileStream $outFile, ([IO.FileMode]::Create), ([IO.FileAccess]::Write), ([IO.FileShare]::None)
            $gzipStream = New-Object System.IO.Compression.GzipStream $input, ([IO.Compression.CompressionMode]::Decompress)
            $buffer = New-Object byte[](1024)
                While($true){
                    $read = $gzipstream.Read($buffer, 0, 1024)
                    if ($read -le 0){break}
                        $output.Write($buffer, 0, $read)
                }
            $gzipStream.Close()
            $output.Close()
            $input.Close()
        }

        Function Run-ASHCIPre{
            # Check for any outstanding Storage Jobs
            Write-Host "Executing S2D/Azure Stack HCI Pre-Checks..."
            IF(Get-VirtualDisk | Where-Object{$_.OperationalStatus -ine "OK"}){
                Write-Host "    ERROR: Virtual Disk(s) UnHealth Please remediate before continuing" -ForegroundColor Red
                EndScript}
            Write-Host "    Checking for Running storage jobs..."
            do {
                $SJobs=((Get-StorageJob | Where-Object {$_.Name -imatch 'Repair' -and ($_.JobState -eq 'Running')}) | Measure-Object).Count
                IF($SJobs -gt 1){
                    Start-Sleep 5
                    Write-Host "        Found Running storage jobs. Next check in 5 seconds..."
                }
            }until(
                ## Running Repair Jobs are less than 1
                    $SJobs -lt 1
            )

            # Suspend Cluster Host to prevent chicken-egg scenario
                Write-Host "    Suspending $env:COMPUTERNAME..."
                    Suspend-ClusterNode -Name $env:COMPUTERNAME -Drain -ForceDrain -Wait -ErrorAction Inquire >$null
                IF($ClusPreERR){
                    Write-Host "        ERROR: Failed to suspend cluster node. Exiting..." -ForegroundColor Red
                    EndScript
                    }
                IF((Get-ClusterNode -Name $env:COMPUTERNAME).State -eq "Paused"){
                    Write-Host "        SUCCESS: Cluster node is suspended" -ForegroundColor Green
                }

            # Enter Storage Maintenance Mode
                Write-Host "    Enabling Storage Maintenance Mode on $env:COMPUTERNAME..."
                try {
                    $Maint=$Null
                    Get-StorageFaultDomain -type StorageScaleUnit | Where-Object {$_.FriendlyName -eq "$($Env:ComputerName)"} | Enable-StorageMaintenanceMode -ErrorAction Stop -ErrorVariable Maint
                    IF($Maint.count -eq 0){$Maint="Success"}
                }
                catch {
                    Write-Host "        ERROR: Failed to enter storage maintenance mode." -ForegroundColor Red
                    Write-Host "$Maint" -ForegroundColor Red
                    Write-Host "    Resuming Node..."
                    Resume-ClusterNode -Name $Env:COMPUTERNAME -Failback Immediate
                    $Maint="Failed"
                    EndScript
                }
                IF($Maint -eq "Success"){
                    Write-Host "        SUCCESS: Storage Scale Unit entered Storage Maintenance Mode" -ForegroundColor Green
                
                }
        }

    Function Run-ClusterPre{
        Write-Host "Executing Cluster Pre-Checks..."
        IF(Get-VirtualDisk | Where-Object{$_.OperationalStatus -ine "OK"}){
            Write-Host "    ERROR: Virtual Disk(s) UnHealth Please remediate before continuing" -ForegroundColor Red
            EndScript}
        Try{
            # Suspend Cluster Host to prevent chicken-egg scenario
                Write-Host "    Suspending $env:COMPUTERNAME..."
                Suspend-ClusterNode -Name $env:COMPUTERNAME -Drain -ForceDrain -Wait -ErrorAction Inquire
        }Catch{
            Write-Host "    ERROR: Failed to suspend cluster node. Exiting..." -ForegroundColor Red
            EndScript
            }
            IF(-not $ClusPreERR){
                Write-Host "    SUCCESS: Cluster node suspended." -ForegroundColor Green
            }
    }

        Function Run-DSU{
$DSUReboot=$False
            # CD to DSU dir

                cd $((Get-ChildItem -Path "C:\Program Files\Dell\" -Filter DSU.EXE -Recurse | Sort LastWriteTime | Select -Last 1).FullName -replace 'dsu.exe')

            # Check if HCI and run DSU install needed updates
#Out-File -FilePath c:\ansd.txt -InputObject @('a','c')
                IF($ASHCI -eq "YES" ){
./DSU.exe --catalog-location="$MyTemp\ASHCI-Catalog.xml" /u /q | Out-Default
                }Else{
./DSU.exe /u /q | Out-Default
                }
                Do {  
                    $ProcessesFound = Get-Process -Name DSU -ErrorAction SilentlyContinue
                    If ($ProcessesFound) {
                        Write-Host "    Still running: $($ProcessesFound)"
                        Start-Sleep 10
                    }
                } Until (!$ProcessesFound)
            # Check Status

                $DupsStatus=(Get-Content $((Get-ChildItem -Path "C:\ProgramData\Dell\" -Filter DSU_STATUS.JSON -Recurse | Sort LastWriteTIme | Select -Last 1).FullName)) | ConvertFrom-Json | select -ExpandProperty SystemUpdateStatus 

                Switch($DupsStatus){
                    {$DupsStatus.InvokerInfo.exitStatus -eq 34}{
                        Write-Host "`n`n"
                        Write-Host "Installation Report"
                        "-"*100
                        $DupsStatus.InvokerInfo | FL *
                        }
                    {$DupsStatus.UpdateableComponent}{$DupsStatus = $DupsStatus.UpdateableComponent
                        # Check reboot required
                            Write-Host "`n`n"
                            Write-Host "Installation Report"
                            "-"*100
                            $DupsStatus | FL *
                            Switch($DupsStatus){
                                {$DupsStatus | Where-Object{$_.updateStatus -ne "SUCCESS"}}
                                    {
                                        Write-Host "ERROR: Some updates failed to install. Please review logs for further information. C:\ProgramData\Dell\UpdatePackage\log" -ForegroundColor Red
                                        EndScript
                                    }
                                {$DupsStatus | Where-Object{$_.rebootRequired -eq "True"}}
                               {
$DSUReboot=$True
}
                            }
                    }
                }
Return $DSUReboot

        }
        $IsDSUInstalled="NO"
        IF(-not ($IsDSUInstalled -eq "YES")){
            Write-Host "Downloading Dell System Update(DSU)..."
            #$LatestDSU = 'https://dl.dell.com/FOLDER12418375M/1/Systems-Management_Application_03GC8_WN64_2.1.1.0_A00.EXE'
            $LatestDSU = 'https://dl.dell.com/FOLDER14217017M/1/Systems-Management_Application_RXKJ5_WN64_2.2.0.1_A00.EXE'
            $DSUInstallerLocation=Download-File $LatestDSU
            Write-Host "Installing DSU..."
            Start-Process $DSUInstallerLocation -ArgumentList '/s' -NoNewWindow -Wait
            $DSUInstallStatus=$DSUInstallerLocation.Split('\\')[-1] -replace ".exe",""
            IF(((Get-Content "C:\ProgramData\Dell\UpdatePackage\log\$DSUInstallStatus.txt" | select-string -Pattern 'Exit code ' -SimpleMatch | Select-Object -Last 1) -split "= ")[-1] -eq 1 -or (Get-ChildItem -Path "C:\Program Files\Dell\" -Filter DSU.EXE -Recurse).count -eq 0){
                Write-Host "    ERROR: Failed to install DSU." -ForegroundColor Red
                EndScript
            }Else{Write-Host "    SUCCESS: DSU Installed Successfully." -ForegroundColor Green }
        }
        Write-Host "Gather Server Model Info..."
        # Find Storage Spaces Direct RN or AX info
            $Model=(Get-WmiObject -Class Win32_ComputerSystem -ErrorAction SilentlyContinue).model
            $IsS2d=$False;try {$IsS2d=(Get-ClusterStorageSpacesDirect -ErrorAction SilentlyContinue).state -eq "Enabled"} catch {}
            $NoClusterPre=$True;try {$NoClusterPre=!((Get-Cluster -ErrorAction SilentlyContinue).Name -gt "")} catch {}

            IF(($Model -imatch 'Storage Spaces Direct' -or $Model -imatch 'AX' -or $Model -imatch 'MC')){
                $ASHCI="YES"
                $URL="https://downloads.dell.com/catalog/ASHCI-Catalog.xml.gz"
                $InFile="$MyTemp\ASHCI-Catalog.xml.gz"
                IF ([System.Environment]::OSVersion.OSVersion -match "10.0.14393") {
                   Write-Host "Windows Server 2016 detected" -ForegroundColor Yellow
                   Write-Host "Windows 2016 Ready Nodes can no longer be supported by DART or DSU."
                   Write-Host "Please visit the following url for information on supported bios, driver and firmware versions:"
                   Write-Host "https://dell.github.io/azurestack-docs/docs/hci/supportmatrix/archive/ws2016/"
                   EndScript
                   #$URL="https://dl.dell.com/FOLDER09682297M/1/ASHCI-Catalog.xml.gz"
                   #$URL="https://dl.dell.com/FOLDER07774224M/1/ASHCI-Catalog.xml.gz"
                }
            }Else{
                $ASHCI="NO"
                # Check if node is a Cluster memeber
                IF(Get-Service clussvc -ErrorAction SilentlyContinue){$IsClusterMember = "YES"}Else{$IsClusterMember = "NO"}
                $URL="https://downloads.dell.com/catalog/Catalog.xml.gz"
                $InFile="$MyTemp\Catalog.xml.gz"
                If($IsClusterMember -eq "NO"){
                    # Added to patch none cluster power edge server 
                    $Global:IgnoreChecks = $True
                }
            }
        Write-Host "    SUCCESS: $Model" -ForegroundColor Green
        IF($ASHCI -eq "YES"){
            Write-Host "Downloading Catalog..."
            $CatalogLocation=Download-File $URL
            Write-Host "Expanding Catalog for use..."
            Try{Expand-Gz $InFile}
            Catch{Write-Host "    ERROR: Failed to expand catalog" -ForegroundColor Red}
            Finally{
                IF([System.IO.File]::Exists(($InFile -replace ".gz",""))){
                    Write-Host "    SUCCESS: Catalog expanded" -ForegroundColor Green
                }
            }
            If($Global:IgnoreChecks -ne $True){
                Run-ASHCIPre
                $NoClusterPre=$True
            }
        }
        IF($NoClusterPre -ne $True){
            If($Global:IgnoreChecks -ne $True){
If ($IsS2d) {Run-ASHCIPre} else {Run-ClusterPre}
            }
        }
        If($Global:IgnoreChecks -eq $True){Write-Host "Ignoring ASHCI/Cluster Prechecks" -ForegroundColor Yellow}
        # Check if Windows
$WinReboot=$False
        IF([System.Environment]::OSVersion.VersionString -imatch 'Windows'){
            IF($WindowsUpdates -eq $True){ 
                Write-Host "    Executing Windows Updates..."
                (new-object -Comobject Microsoft.Update.AutoUpdate).detectnow()
                #((New-Object -ComObject Microsoft.Update.Searcher).Search("IsInstalled=0 and Type='Software' and isHidden=0").Updates | ? Title -match '2022-10 Update for Azure Stack HCI, version 22H2').IsHidden=1
                $Updates=(New-Object -ComObject Microsoft.Update.Searcher).Search("IsInstalled=0 and Type='Software' and isHidden=0").Updates
                if($Updates.count -ge 1){
                    Write-Host "The following updates have been found"
                    $Updates | % {Write-Host "$($_.IsDownloaded) $($_.Title)"}
                    Write-Host "Downloading Updates"
                    $djob=Start-Job -Name "djob" -scriptblock {
                        $UpdateDownloader=New-Object -ComObject Microsoft.Update.Downloader
                        $UpdateDownloader.Updates=(New-Object -ComObject Microsoft.Update.Searcher).Search("IsInstalled=0 and Type='Software' and isHidden=0").Updates
                        $UpdateDownloader.Download()
                        } 
                    Do {sleep 9;$e=get-EventLog -LogName System -After ((Get-Date).addseconds(-10)) | ? Source -match "update" | sort timegenerated;if ($e) {Write-Host "$($e.timegenerated) $($e.message)"}} while(!$djob.PSEndTime)
                    Receive-Job -Job $djob
                    write-host "Installing $($Updates.count) Updates"
                    $ujob=Start-Job -Name "ujob" -scriptblock {
                        $UpdateInstaller=New-Object -ComObject Microsoft.Update.Installer
                        $UpdateInstaller.Updates=(New-Object -ComObject Microsoft.Update.Searcher).Search("IsInstalled=0 and Type='Software' and isHidden=0").Updates
                        $UpdateInstaller.Install().RebootRequired
                        }
                    Do {sleep 59;$e=get-EventLog -LogName System -After ((Get-Date).addminutes(-1)) | ? Source -match "update" | sort timegenerated;if ($e) {Write-Host "$($e.timegenerated) $($e.message)"}} while(!$ujob.PSEndTime)
                    $WinReboot=Receive-Job -Job $ujob
if ($WinReboot -ne $True) {
$WinReboot
$WinReboot=$False
}
                } else { write-host "No updates detected" }
}ElseIF($WindowsUpdates -eq $False){Write-Host "    Skipping Windows Updates" -ForegroundColor Yellow}
        }
$DSUReboot=$False
        IF($DriverandFirmware -eq $True){
            Write-Host "    Executing DSU..."
            $DSUReboot=Run-DSU
        }ElseIF($DriverandFirmware -eq $False){Write-Host "    Skipped Dell Drivers and Firmware" -ForegroundColor Yellow}
If ($DSUReboot -eq $True -or $WinReboot -eq $True) {
    Write-Host "Please reboot to complete installation" -ForegroundColor Yellow
    Write-Host "Will create Exit Maintenance Mode Scheduled Task to run at next logon or five minutes after finishing OS boot...." -ForegroundColor Yellow
            try {$Host.UI.RawUI.FlushInputBuffer() } catch {while ($Host.UI.RawUI.KeyAvailable) {
                    $Host.UI.RawUI.ReadKey() | Out-Null
                }}
            try {$Reboot = (Read-Host "Ready to reboot? [y/n]").ToLower()} catch {}
            Switch ($Reboot){
                "y"{
                    $Script='CLS;$DateTime=Get-Date -Format yyyyMMdd_HHmmss;Start-Transcript -NoClobber -Path "C:\programdata\Dell\DART\DART_$DateTime.log";Write-Host "Resuming Cluster Node $ENV:COMPUTERNAME...";Resume-ClusterNode -Name $Env:COMPUTERNAME -Failback Immediate -ErrorAction SilentlyContinue;Get-ClusterNode;Write-Host "Exiting Storage Maintenance Mode...";Get-StorageScaleUnit -FriendlyName "$($Env:ComputerName)" | Disable-StorageMaintenanceMode -ErrorAction SilentlyContinue;Get-PhysicalDisk|Sort DeviceID;Unregister-ScheduledTask -TaskName "Exit Maintenance Mode" -Confirm:$false;Remove-Item -Path c:\dell\exit-maintenancemode.ps1 -Force;stop-Transcript'
                    IF(-not(Test-Path c:\dell)){
                        New-Item -Path "c:\" -Name "Dell" -ItemType "directory"
                    }
                    $Script | Out-File -FilePath c:\dell\exit-maintenancemode.ps1 -Force
                    $trigger=@()
                    $trigger+=New-ScheduledTaskTrigger -AtStartup
                    $trigger[0].Delay='PT5M'
                    $trigger+=New-ScheduledTaskTrigger -AtLogon
                    Register-ScheduledTask -User "system" -TaskName "Exit Maintenance Mode" -Trigger $trigger -Action (New-ScheduledTaskAction -Execute "${Env:WinDir}\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-WindowStyle Hidden -Command `"& 'c:\dell\exit-maintenancemode.ps1'`"") -RunLevel Highest -Settings (New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew) -Force;
                    Restart-Computer -Force
                    EndScript
                    }
                Default {
                    EndScript
                    }
                }
                EndScript
}
        IF($Global:IgnoreChecks -ne $True){
            try {$Host.UI.RawUI.FlushInputBuffer() } catch {while ($Host.UI.RawUI.KeyAvailable) {
                    $Host.UI.RawUI.ReadKey() | Out-Null
                }}
            try {$ExitSMM = (Read-Host "Ready to Resume Cluster Node and exit Storage Maintenance Mode? [y/n]").ToLower()} catch {}
            Switch ($ExitSMM){
                  "y"{
                        # Resume Cluster
                        IF($Global:IgnoreChecks -ne $True){
                            IF(($IsClusterMemeber -eq "YES") -or ($ASHCI -eq "YES")){
                                Write-Host "Resuming Cluster Node $ENV:COMPUTERNAME..."
                                Resume-ClusterNode -Name $Env:COMPUTERNAME -Failback Immediate -ErrorAction SilentlyContinue >$null
                            }
                        }

                        # Disable Storage Maintenance Mode
                        IF($Global:IgnoreChecks -ne $True){
                            IF($ASHCI -eq "YES" -or $isS2d){
                                Write-Host "Exiting Storage Maintenance Mode..."
                                Get-StorageFaultDomain -type StorageScaleUnit | Where-Object {$_.FriendlyName -eq "$($Env:ComputerName)"} | Disable-StorageMaintenanceMode -ErrorAction SilentlyContinue
                            }

                         }
                    }
                Default {
                        $Script='CLS;$DateTime=Get-Date -Format yyyyMMdd_HHmmss;Start-Transcript -NoClobber -Path "C:\programdata\Dell\DART\DART_$DateTime.log";Write-Host "Resuming Cluster Node $ENV:COMPUTERNAME...";Resume-ClusterNode -Name $Env:COMPUTERNAME -Failback Immediate -ErrorAction SilentlyContinue;Get-ClusterNode;Write-Host "Exiting Storage Maintenance Mode...";Get-StorageFaultDomain -type StorageScaleUnit | Where-Object {$_.FriendlyName -eq "$($Env:ComputerName)"} | Disable-StorageMaintenanceMode -ErrorAction SilentlyContinue;Get-PhysicalDisk|Sort DeviceID;Unregister-ScheduledTask -TaskName "Exit Maintenance Mode" -Confirm:$false;Remove-Item -Path c:\dell\exit-maintenancemode.ps1 -Force;stop-Transcript'
                        IF(-not(Test-Path c:\dell)){
                            New-Item -Path "c:\" -Name "Dell" -ItemType "directory"
                        }
                        $Script | Out-File -FilePath c:\dell\exit-maintenancemode.ps1 -Force
                        Write-Host "Creating Exit Maintenance Mode Scheduled Task to run at next logon or five minutes after finishing OS boot...."
                        $trigger=@()
                        $trigger+=New-ScheduledTaskTrigger -AtStartup
                        $trigger[0].Delay='PT5M'
                        $trigger+=New-ScheduledTaskTrigger -AtLogon
                        Register-ScheduledTask -User "system" -TaskName "Exit Maintenance Mode" -Trigger $trigger -Action (New-ScheduledTaskAction -Execute "${Env:WinDir}\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-WindowStyle Hidden -Command `"& 'c:\dell\exit-maintenancemode.ps1'`"") -RunLevel Highest -Settings (New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew) -Force;
                    }
            }
        }
    }#$PSCmdlet.ShouldProcess($param)
}Else{Write-Host "ERROR: Non-Dell Server Detected!" -ForegroundColor Red}# Dell Server Check
Stop-Transcript
}               
               Invoke-DART -IgnoreChecks $IgnoreChecks -IgnoreVersion $IgnoreVersion
