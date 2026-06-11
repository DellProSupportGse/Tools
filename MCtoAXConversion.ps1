Function Test-MCtoAXConversion {
param(
    [switch]$DoConversion,
    [switch]$PrepareSBE
)
    # ══════════════════════════════════════════════════════════════════════════════
    # SECTION 1 — Cluster & Node Verification | Dell ACP / Azure Local
    # ══════════════════════════════════════════════════════════════════════════════

    Import-Module FailoverClusters
    $ver="0.44"
    Write-Host "TMC2AX version $ver"

    # 1. Verify the cluster service is running
    Write-Host "`n Verifying cluster service..." -ForegroundColor Yellow
    try {
        # Out-Null prevents clutter; we just need to know it doesn't error out
        Get-Cluster -ErrorAction Stop | Out-Null 
    }
    catch {
        Write-Error "Cluster service is not running or accessible. Error: $_" -ErrorAction Stop
    }

    # 2. Verify the status of all cluster nodes
    Write-Host "`n Getting cluster node statuses..." -ForegroundColor Yellow
    try {
        $clusterNodes = Get-ClusterNode -ErrorAction Stop
    }
    catch {
        Write-Error "Could not retrieve cluster nodes. Ensure the Failover Cluster service is running. Error: $_" -ErrorAction Stop
    }

    # 3. Confirm all nodes report State = Up
    Write-Host "`n Checking for nodes NOT in 'Up' state..." -ForegroundColor Yellow
    $downNodes = $clusterNodes | Where-Object { $_.State -ne "Up" }

    if (-not $clusterNodes -or $downNodes) {
        $downList = $downNodes.Name -join ", "
        Write-Error "CRITICAL: One or more cluster nodes are down or unreachable: $downList. Halting script execution." -ErrorAction Stop
    }

    Write-Host "All cluster nodes report State = Up. Proceeding..." -ForegroundColor Green

    # 4. Filter for APEX Cloud Platform / APEXCP-related resources
    Write-Host "`n Filtering for ACP VM cluster group..." -ForegroundColor Yellow

    <#$acpKeywords = @(
        "APEX Cloud Platform Manager",
        "APEXCP",
        "Cloud Platform",
        "CloudPlatformManager"   # Matches: Cloud Platform Manager VM
    )#>
    $acpGroup=Get-ClusterGroup -Name "APEX Cloud Platform Manager" -ErrorAction SilentlyContinue
    $acpGroup | Select Name,OwnerNode,State,Priority | Format-Table -AutoSize
    <#$acpResources = Get-ClusterResource | Where-Object {
        $name = $_.Name
        $acpKeywords | Where-Object { $name -like "*$_*" }
    }#>
    if ($acpGroup -and $DoConversion) {
        Write-Host "Stopping ACP VM cluster group and setting priority to 0" -ForegroundColor Cyan
        #foreach ($CR in $acpResources.Name) {
            #Stop-ClusterResource -Name $CR -Verbose
        $acpGroup.Priority=0
        Stop-ClusterGroup $acpGroup | Out-Null
        $acpGroup=Get-ClusterGroup -Name "APEX Cloud Platform Manager"

        #}
        #$acpResources = Get-ClusterResource | Where-Object {
        #$name = $_.Name
        #$acpKeywords | Where-Object { $name -like "*$_*" }
    #}
    }
    if ($acpGroup) {
        Write-Host "`nACP VM cluster group found:" -ForegroundColor Cyan
        $acpGroup | Select Name,OwnerNode,State,Priority | Format-Table -AutoSize
        If ($acpGroup.State -eq "Online" -or $acpGroup.Priority -ne 0) {
            Write-Warning "ACP VM cluster group should be offline and priority set to 0"
            $conversionDone=$false
        } else {
            $conversionDone=$true
        }
    } else {
        Write-Host "No ACP VM cluster group found." -ForegroundColor Green
        $conversionDone=$true
    }

    # ══════════════════════════════════════════════════════════════════════════════
    # SECTION 2 — BitLocker Recovery Key Retrieval | Azure Local 23H2
    # ══════════════════════════════════════════════════════════════════════════════

    $exportFilePath = "C:\DeleteAfterConversion.txt"

    Write-Host "`n Retrieving BitLocker Recovery Keys for all cluster nodes..." -ForegroundColor Yellow

    try {
        # Retrieve BitLocker recovery info for the cluster
        $recoveryKeys = Get-AsRecoveryKeyInfo -ErrorAction Stop

        if ($recoveryKeys) {
            # Display the keys in the console for immediate verification
            $recoveryKeys | Format-Table ComputerName, PasswordID, RecoveryKey -AutoSize

            # Save the output to a text file on Node 1
            "Please keep this backup of your Bitlocker keys for the cluster" | Out-File -FilePath $exportFilePath -Force
            $recoveryKeys | Select-Object ComputerName, PasswordID, RecoveryKey | Out-File -FilePath $exportFilePath -Force -Append
            
            Write-Host "BitLocker recovery keys successfully exported to $exportFilePath" -ForegroundColor Green
            Write-Warning "Please copy file $exportFilePath off the cluster"
        } else {
            Write-Warning "Command executed but returned no keys. Verify that BitLocker is fully provisioned on the cluster volumes."
        }
    }
    catch {
        Write-Error "CRITICAL: Failed to retrieve BitLocker recovery keys. Error: $_" -ErrorAction Stop
    }

    $sbeEnv = Get-SolutionUpdateEnvironment -ErrorAction Stop
    $currentSbeStr = $sbeEnv.CurrentSbeVersion.ToString().Trim()
    if ([version]$currentSbeStr -lt [version]"4.2.2511" -and $currentSbeStr -ne "2.1.0.0") {
        IF ($DoConversion) {
            #Write-Host "WARNING: You must be at or above SBE 4.2.2511.* before converting." -ForegroundColor Yellow;break
            Set-OverrideUpdateConfiguration -ResetDefaultOemUpdateUri
            #Set-OverrideUpdateConfiguration -OverrideOemUpdateUri htps://azurestackreleases.download.prss.microsoft.com/dbazure/AzureStackHCI/UpdateManifest/SBE_Discovery_nomatch.xml
            Write-Host "Removing installed SBE version of '$currentSbeStr'"
            #$eceClient = Create-ECEClientSimple
            #$eceClient.GetOemVersion()
            #$eceClient.SetOemVersion("2.1.0.0")
            $eceClient = create-ECEClientSimple;$eceClient.SetOemVersion("2.1.0.0").GetAwaiter().GetResult()
            Get-ClusterGroup "Azure Stack HCI*Orchestrator*" | Stop-ClusterGroup | Move-ClusterGroup | Start-ClusterGroup
            Get-ClusterGroup "Azure Stack HCI*Update*" | Stop-ClusterGroup | Move-ClusterGroup | Start-ClusterGroup
            Write-Host "Please wait a full 15 minutes and re-run this script. Current time is "
            break
            $sbeEnv = Get-SolutionUpdateEnvironment -ErrorAction Stop
            $currentSbeStr = $sbeEnv.CurrentSbeVersion.ToString().Trim()
            if ([version]$currentSbeStr -lt [version]"4.2.2511" -and $currentSbeStr -ne "2.1.0.0") {
                Write-Host "Could not change oem vesion to 2.1.0.0" -ForegroundColor DarkYellow
                $conversionDone=$false
            }
        } else {
            Write-Host "SBE version cannot directly upgrade to AX SBE. Will need to set SBE OEM version to 2.1.0.0" -ForegroundColor Yellow
            $conversionDone=$false
        }
        
    } else {
        Write-Host "Current SBE version $currentSbeStr is good"
    }
    # ══════════════════════════════════════════════════════════════════════════════
    # SECTION 3 — ACP Parameter Cleanup, Core Resource, and Group Health Validation
    # ══════════════════════════════════════════════════════════════════════════════

    # ------------------------------------------------------------------------------
    # 3.1: ACP Parameter Cleanup on Cluster IP Address
    # ------------------------------------------------------------------------------
    $ipResourceName = "Cluster IP Address"
    Write-Host "`n Getting ACP parameters from '$ipResourceName'..." -ForegroundColor Yellow

    $acpParams = @(
        "ACP_SupportedExtensionVersion", 
        "ACP_ManagerCertThumbprint", 
        "ACP_ManagerVersion", 
        "ACP_ManagerIP"
    )

    foreach ($param in $acpParams) {
        try {
            $paramExists = Get-ClusterResource -Name $ipResourceName -ErrorAction Stop | 
                           Get-ClusterParameter -Name $param -ErrorAction SilentlyContinue
        
            if ($paramExists) {
                If ($DoConversion) {
                    Write-Host "  -> Deleting parameter: $param" -ForegroundColor Cyan
                    Get-ClusterResource -Name $ipResourceName | Set-ClusterParameter -Name $param -Delete -ErrorAction Stop
                }
            }
        }
        catch {
            Write-Warning "Failed to delete parameter '$param'. Error: $_"
        }
    }

    # Verify clean parameter state
    $remainingAcpParams = Get-ClusterResource -Name $ipResourceName | 
                          Get-ClusterParameter | 
                          Where-Object { $_.Name -like "ACP_*" }

    if ($remainingAcpParams) {
        Write-Warning "The following ACP parameters need to be deleted:"
        $remainingAcpParams | Format-Table Name, Value -AutoSize
        $conversionDone=$false
    } else {
        Write-Host "No ACP private parameters remain on the Cluster IP Address." -ForegroundColor Green
        #$conversionDone=$true
    }

    # ------------------------------------------------------------------------------
    # 3.2: Core Resource Health Validation (Excluding VMs & Available Storage)
    # ------------------------------------------------------------------------------
    Write-Host "`n Validating health of core cluster resources..." -ForegroundColor Yellow

    $coreResources = Get-ClusterResource | Where-Object { 
        $_.ResourceType -ne "Virtual Machine" -and $_.ResourceType -ne "Virtual Machine Configuration" -and 
        $_.OwnerGroup -ne "Available Storage" 
    }

    $faultedResourcesCount = 0
    foreach ($res in $coreResources) {
        if ($res.State -eq "Failed" -or $res.State -eq "Offline") {
            Write-Error "Cluster resource '$($res.Name)' in group '$($res.OwnerGroup)' is in an unhealthy state: $($res.State)"
            $faultedResourcesCount++
        }
    }

    if ($faultedResourcesCount -eq 0) {
        Write-Host "All core non-VM cluster resources are Online." -ForegroundColor Green
    }

    # ------------------------------------------------------------------------------
    # 3.3: HCI & Control Plane Group Validation
    # ------------------------------------------------------------------------------
    Write-Host "`n Validating Azure Stack HCI and Control Plane Cluster Groups..." -ForegroundColor Yellow

    $targetGroups = @(
        "Azure Stack HCI Download Service Cluster Group",
        "Azure Stack HCI Health Service Cluster Group",
        "Azure Stack HCI Orchestrator Service Cluster Group",
        "Azure Stack HCI Update Service Cluster Group",
        "Cloud Management",
        "Cluster Group",
        "SDDC Group"
    )

    $faultedGroupsCount = 0

    # Validate explicit groups
    foreach ($groupName in $targetGroups) {
        $group = Get-ClusterGroup -Name $groupName -ErrorAction SilentlyContinue
    
        if (-not $group) {
            Write-Error "CRITICAL: Cluster group '$groupName' NOT FOUND." -ErrorAction Stop
            $faultedGroupsCount++
        } elseif ($group.State -ne "Online") {
            Write-Error "CRITICAL: Cluster group '$groupName' state is $($group.State)" -ErrorAction Stop
            $faultedGroupsCount++
        } else {
            #Write-Host "  -> [$groupName] is ONLINE" -ForegroundColor Green
        }
    }

    # Validate dynamic control plane group
    $controlPlaneGroups = Get-ClusterGroup | Where-Object { $_.Name -match "-control-plan" }

    if (-not $controlPlaneGroups) {
        Write-Error "CRITICAL: No cluster group matching '-control-plan' was found." -ErrorAction Stop
        $faultedGroupsCount++
    } else {
        foreach ($cpGroup in $controlPlaneGroups) {
            if ($cpGroup.State -ne "Online") {
                Write-Error "CRITICAL: Control plane group '$($cpGroup.Name)' state is $($cpGroup.State)" -ErrorAction Stop
                $faultedGroupsCount++
            } else {
               # Write-Host "  -> [$($cpGroup.Name)] is ONLINE" -ForegroundColor Green
            }
        }
    }

    if ($faultedGroupsCount -eq 0) {
        Write-Host "All required HCI and Control Plane cluster groups are Online." -ForegroundColor Green
    } else {
        Write-Error "Detected $faultedGroupsCount missing or offline cluster group(s). Resolution required before proceeding." -ErrorAction Stop
    }

    # ══════════════════════════════════════════════════════════════════════════════
    # SECTION 4 — AzCliExtensions Directory Relocation & Environment Variable Fix
    # ══════════════════════════════════════════════════════════════════════════════

    $sourcePath = "D:\CloudContent\AzCliExtensions"
    $destPath   = "C:\CloudContent\AzCliExtensions"
    $envVarName = "AZURE_EXTENSION_DIR"

    # 1. Verify if the directory exists on D:
    Write-Host "`n Checking for AzCliExtensions on the D drive..." -ForegroundColor Yellow

    if (Test-Path -Path $sourcePath) {
        Write-Host "  -> Directory found at $sourcePath. Should be relocated to C." -ForegroundColor Cyan

        # 2. Move the directory to C:
        if ($DoConversion) {
            try {
                Write-Host "`n Moving directory to C: drive..." -ForegroundColor Yellow
                Move-Item -Path $sourcePath -Destination $destPath -Force -ErrorAction Stop
                Remove-Item $sourcePath -Confirm:$false -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "Directory successfully moved to $destPath" -ForegroundColor Green
                #$conversionDone=$true
            }
            catch {
                Write-Error "CRITICAL: Failed to move directory. Ensure no files are actively open. Error: $_" -ErrorAction Stop
                $conversionDone=$false
            }
        }

        # 3. Update the Machine-level Environment Variable
        if ($DoConversion) {
            try {
                Write-Host "`n Updating '$envVarName' Machine environment variable..." -ForegroundColor Yellow
                [System.Environment]::SetEnvironmentVariable($envVarName, $destPath, 'Machine')
                Write-Host "Environment variable updated in Machine registry." -ForegroundColor Green
            }
            catch {
                Write-Error "CRITICAL: Failed to set environment variable. Ensure PowerShell is running as Administrator. Error: $_" -ErrorAction Stop
                $conversionDone=$false
            }
        }
    } else {
        if ($conversionDone){ 
            Write-Host "  -> Directory not found at $sourcePath. Either it was already moved or this is a standard AX deployment." -ForegroundColor DarkGray
        } else {
            Write-Host "Directory not found at $sourcePath."
        }
        #$conversionDone=$true
    }

    # 4 & 5. Verify the Machine environment variable explicitly
    Write-Host "`n Verifying Machine-scoped environment variable resolution..." -ForegroundColor Yellow

    # Query the Machine scope directly instead of the Process scope ($env:)
    $currentEnv = [System.Environment]::GetEnvironmentVariable($envVarName, 'Machine')
    $filesMoved=(gci $destPath -ErrorAction SilentlyContinue).count

    if ($currentEnv -eq $destPath -and $filesMoved -gt 0) {
        Write-Host "Machine scope '$envVarName' evaluates to: $currentEnv and files exist in the correct path" -ForegroundColor Green
        #$conversionDone=$true
    } else {
        Write-Warning "Mismatch detected. Machine scope '$envVarName' currently evaluates to: '$currentEnv'. Expected: '$destPath'. or files do not exist in expected path"
        $conversionDone=$false
    }

    # ══════════════════════════════════════════════════════════════════════════════
    # SECTION 5 — Dell AX SBE Hardware Mapping & RequiredSolution Update Check
    # ══════════════════════════════════════════════════════════════════════════════

    Write-Host "`n Retrieving system state and mapping hardware family..." -ForegroundColor Yellow
    
    try {
        # 1a. Retrieve current SBE and Solution versions (Safely cast to string)
        $sbeEnv = Get-SolutionUpdateEnvironment -ErrorAction Stop
        $currentSbeStr = $sbeEnv.CurrentSbeVersion.ToString().Trim()
        $currentSolutionVersion = $sbeEnv.CurrentVersion.ToString().Trim()
    
        $currentSbeVer = [version]$currentSbeStr
    
        Write-Host "  -> Current SBE Version: $currentSbeStr" -ForegroundColor Cyan
        Write-Host "  -> Current Solution (OS) Version: $currentSolutionVersion" -ForegroundColor Cyan

        # 1b. Retrieve and map hardware model
        $systemModel = [string](Get-CimInstance -ClassName Win32_ComputerSystem).Model.Trim()
        $targetFamily = $null

        if ($systemModel -match "4510[cC]|4520[cC]|[A-Za-z]+-?\d6\d") {
            $targetFamily = "AX-16G-45n0c"
        } elseif ($systemModel -match "[A-Za-z]+-?\d4\d") {
            $targetFamily = "AX-14G"
        } elseif ($systemModel -match "[A-Za-z]+-?\d5\d") {
            $targetFamily = "AX-15G"
        } elseif ($systemModel -match "[A-Za-z]+-?\d7\d") {
            $targetFamily = "AX-17G"
        } else {
            Write-Error "CRITICAL: Could not map system model '$systemModel' to a known AX generation." -ErrorAction Stop
        }

        Write-Host "  -> System Model Identified: $systemModel" -ForegroundColor Cyan
        Write-Host "  -> Mapped SBE Family: $targetFamily" -ForegroundColor Cyan
    }
    catch {
        Write-Error "CRITICAL: Failed to retrieve system state or validate prerequisites. Error: $_" -ErrorAction Stop
    }

    Write-Host "`n Querying manifest and evaluating 'ValidatedConfigurations' compatibility..." -ForegroundColor Yellow

    $xmlPath = "$env:temp\outfile.xml"
    $manifestUrl = "https://aka.ms/AzureStackSBEUpdate/DellEMC"
    $compatibleUpdates = @()

    Write-Host "Please copy file $exportFilePath off the cluster!!!!!" -ForegroundColor Black -BackgroundColor White
    notepad $exportFilePath

    try {
        Invoke-WebRequest -Uri $manifestUrl -UseBasicParsing -OutFile $xmlPath -ErrorAction Stop
        $xmlData = [xml](Get-Content $xmlPath)
    
        # 2a. Filter updates by Family and validate against the Solution package version array
        foreach ($update in $xmlData.SBEUpdatesManifest.ApplicableUpdate) {
        
            if ([string]$update.Family -ne $targetFamily) { continue }
        
            $isCompatible = $false
        
            # Traverse the XML/Object schema to extract the array of Solution wildcard patterns
            $solutionPackages = $update.ValidatedConfigurations.RequiredPackages.Package | Where-Object { $_.type -eq "Solution" }
        
            # Force into an array to handle single-item vs multi-item returns cleanly
            $reqPatterns = @($solutionPackages.version)
        
            foreach ($pattern in $reqPatterns) {
                $cleanPattern = [string]$pattern.Trim()
            
                # Use PowerShell's -like operator for exact wildcard match against the OS string
                if ($currentSolutionVersion -like $cleanPattern) {
                    $isCompatible = $true
                    break
                }
            }
        
            if ($isCompatible) {
                $compatibleUpdates += $update
            }
        }
        if ([version]$currentSbeStr -lt [version]"4.2.2511" -and $currentSbeStr -ne "2.1.0.0") {
            $isCompatible = $false
            $compatibleUpdates = @()
        }
        if (-not $compatibleUpdates) {
            Write-Warning "No SBE updates found in the manifest compatible with Family [$targetFamily] AND Solution Version [$currentSolutionVersion]."
            if (Test-Path $xmlPath) { Remove-Item $xmlPath -Force }
            #return
        }

        # 2b. Sort the compatible updates and extract the maximum version
        $sortedUpdates=@()
        $sortedUpdates += $compatibleUpdates | Sort-Object { [version]([string]$_.version) }
        $latestSbeStr = [string]$sortedUpdates[-1].version
        $latestSbeVer = [version]$latestSbeStr
    
        Write-Host "  -> Maximum Compatible SBE for [$targetFamily] on OS [$currentSolutionVersion]: $latestSbeStr" -ForegroundColor Cyan
    } catch {
        Write-Error "CRITICAL: Failed to download or parse the Dell SBE manifest. Error: $_" -ErrorAction Stop
    } finally {
        if (Test-Path $xmlPath) { Remove-Item $xmlPath -Force }
    }

    Write-Host "`n Comparing SBE versions..." -ForegroundColor Yellow

    if ($latestSbeVer -gt $currentSbeVer) {
        Write-Host "A compatible SBE update is available ($latestSbeStr > $currentSbeStr)." -ForegroundColor Green
    } elseif ($latestSbeVer -eq $currentSbeVer) {
        Write-Host "The cluster is already running the maximum compatible SBE version ($currentSbeStr)." -ForegroundColor Green
    } else {
        Write-Warning "Anomaly detected: Current SBE ($currentSbeStr) is HIGHER than the catalog's maximum compatible update ($latestSbeStr)."
    }
    Write-Host "Please copy file $exportFilePath off the cluster!!!!!" -ForegroundColor DarkYellow
    notepad $exportFilePath

    # ══════════════════════════════════════════════════════════════════════════════
    # SECTION 6 — SBE Auto-Download, Extraction, and Installation
    # ══════════════════════════════════════════════════════════════════════════════
    if ($latestSbeVer -gt $currentSbeVer) {
        $extractionFolder = "C:\ClusterStorage\Infrastructure_1\SBE\SBE_Extracted_Payload"
        $tempFolder = $env:TEMP

        Write-Host "`n Locating Dell driver download page from release notes table..." -ForegroundColor Yellow

        # Extract the wave from the latest SBE version (e.g., "2603" from "5.0.2603.1641")
        $sbeWave = $latestSbeStr.Split('.')[2]
        $releaseNotesUrl = "https://dell.github.io/azurestack-docs/docs/hci/supportmatrix/2603/sbereleasenotes/"
        If ($sbeWave -ge "2506") {
            try {
                Write-Host "  -> Scraping: $releaseNotesUrl" -ForegroundColor Cyan
                $releaseNotesResponse = Invoke-WebRequest -Uri $releaseNotesUrl -UseBasicParsing -ErrorAction Stop
    
                # Anchor Regex: Find the exact SBE version <td>, then non-greedily (.*?) find the NEXT Dell driver URL
                $searchPattern = "(?si)<td>\s*$([regex]::Escape($latestSbeStr))\s*</td>.*?href=`"(https://www\.dell\.com/support/[^`"]+driverid=[a-zA-Z0-9]+)`""
    
                if ($releaseNotesResponse.Content -match $searchPattern) {
                    $driverPageUrl = $matches[1]
                } else {
                    Write-Error "CRITICAL: Could not locate the version '$latestSbeStr' or its adjacent driver URL on the release notes page." -ErrorAction Stop
                }
    
                Write-Host "Found exact driver page: $driverPageUrl" -ForegroundColor Green
            } catch {
                Write-Error "CRITICAL: Failed to scrape Dell GitHub release notes. Error: $_" -ErrorAction Stop
            }
        } else {
            Write-Error "CRITICAL: Current SBE version is too low to peform the update" -ErrorAction Stop
        }

        Write-Host "`n Locating exact SBE zip file for $targetFamily (v$latestSbeStr)..." -ForegroundColor Yellow

        try {
            $driverPageResponse = Invoke-WebRequest -Uri $driverPageUrl -UseBasicParsing -ErrorAction Stop
    
            # Define the pattern with a leading wildcard
            $expectedZipPattern = "*Bundle_SBE_Dell_${targetFamily}_${latestSbeStr}.zip"
    
            # Filter the Links property using the -like operator
            $zipLink = $driverPageResponse.Links | Where-Object { $_.href -like $expectedZipPattern } | Select-Object -First 1

            if (-not $zipLink) {
                Write-Error "CRITICAL: Could not find zip file matching '$expectedZipPattern' on the driver page." -ErrorAction Stop
            }
    
            $zipUrl = $zipLink.href
            $zipFileName = ($zipUrl -split '/')[-1]
            $tempZipPath = Join-Path $tempFolder $zipFileName

            Write-Host "Found target zip link: $zipFileName" -ForegroundColor Green
            Write-Host "Full link is $zipUrl" -ForegroundColor Green
        } catch {
            If ($_ -match "Access Denied") {
                Write-Host "Could not retrive download file url. Please download from $driverPageUrl" -ForegroundColor Yellow
            } else {
                Write-Host "CRITICAL: Failed to scrape Dell Drivers page or match filename. Error: $_" -ForegroundColor Red
            }
        }
    }
    If ($conversionDone) {
        If ($latestSbeVer -gt $currentSbeVer) {
            if (!(Test-Path $extractionFolder)) { New-Item -ItemType Directory -path (Split-Path $extractionFolder -Parent) -Name (Split-Path $extractionFolder -Leaf) -ErrorAction SilentlyContinue -Force}
            Write-Host "Downloading the SBE package requires logging into the Dell site which cannot be done in this script at this time"
            Write-host "Please download and extract the SBE package to $extractionFolder"
            If ((gci $extractionFolder).count -lt 3 -and $PrepareSBE) {Write-Host "SBE folder is not correct. Please extract the files from the zip directly into the expected folder";$PrepareSBE=$false;break}
        } else {
            Write-Host "Conversion has been completed and no SBE updates are avaiable" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Conversion has not been completed" -ForegroundColor Yellow
        break
    }

    If ($PrepareSBE -and $conversionDone -and ($latestSbeVer -gt $currentSbeVer)) {
        <#

        Write-Host "`n Downloading and extracting SBE payload..." -ForegroundColor Yellow

        try {
            Write-Host "  -> Downloading to: $tempZipPath (This may take several minutes)" -ForegroundColor Cyan
            Invoke-WebRequest -Uri $zipUrl -OutFile $tempZipPath -UseBasicParsing -ErrorAction Stop
    
            Write-Host "  -> Extracting to: $extractionFolder" -ForegroundColor Cyan
    
            if (Test-Path $extractionFolder) { Remove-Item -Path "$extractionFolder\*" -Recurse -Force }
            else { New-Item -ItemType Directory -Path $extractionFolder | Out-Null }

            Expand-Archive -Path $tempZipPath -DestinationPath $extractionFolder -Force -ErrorAction Stop
            Write-Host "[Confirmed signal] Extraction complete." -ForegroundColor Green
        } catch {
            Write-Error "CRITICAL: Failed to download or extract the SBE zip file. Error: $_" -ErrorAction Stop
        } finally {
            if (Test-Path $tempZipPath) { Remove-Item $tempZipPath -Force }
        }
        #>

        # ------------------------------------------------------------------------------
        # 6.2: Load the SBE and Run Pre-Installation Health Check
        # ------------------------------------------------------------------------------
        Write-Host "`n Adding Solution Update (SBE) to the cluster..." -ForegroundColor Yellow

        try {
            Write-Host "  -> Sideloading from: $extractionFolder" -ForegroundColor Cyan
            Add-SolutionUpdate -SourceFolder $extractionFolder -ErrorAction Stop
        } catch {
            Write-Error "CRITICAL: Failed to add Solution Update. Error: $_" -ErrorAction Stop
        }

        Write-Host "`n Verifying SBE State is 'Ready'..." -ForegroundColor Yellow
        $sbePackage = Get-SolutionUpdate | Where-Object { $_.PackageType -eq "SBE" -and $_.Version -eq $latestSbeStr }


        if ($sbePackage.State -ne "Ready") {
            Write-Error "CRITICAL: SBE Package State is '$($sbePackage.State)'. Expected 'Ready'." -ErrorAction Stop
        } else {
            Write-Host "SBE Package is Loaded and Ready." -ForegroundColor Green
            Set-OverrideUpdateConfiguration -ResetDefaultOemUpdateUri
        }

        Write-Host "`n Running Pre-Installation Health Check (-PrepareOnly)..." -ForegroundColor Yellow
        try {
            $sbePackage | Start-SolutionUpdate -PrepareOnly -ErrorAction Stop
            Write-Host "PrepareOnly health check initiated. Monitor state via Get-SolutionUpdate." -ForegroundColor Green
        } catch {
            Write-Warning "Failed to start Pre-Installation check. Error: $_"
        }

        # Note: In a fully automated script, you would poll Get-SolutionUpdate until State returns to "Ready" 
        # and then execute: Start-SolutionUpdate to apply the SBE. For safety, the script pauses here.
        Write-Host "If the SBE finishes preparing and has state ReadyToInstall then please run Start-SolutionUpdate -Id $($sbePackage.ResourceID) to install the SBE update. Script stopping"
        Break

        # ------------------------------------------------------------------------------
        # 6.3: Post-Installation Validation
        # ------------------------------------------------------------------------------
        Write-Host "`n Validating SBE Environment and AX Version..." -ForegroundColor Yellow

        $sbeEnv = Get-SolutionUpdateEnvironment
        $currentSbeVersion = $sbeEnv.CurrentSbeVersion

        # Version 4.0.0.0 indicates a partial/incomplete installation
        if ($currentSbeVersion -eq "4.0.0.0") {
            Write-Error "CRITICAL: SBE reports version 4.0.0.0. The SBE is only partially installed and requires remediation."
        } else {
            Write-Host "Active SBE Version: $currentSbeVersion" -ForegroundColor Green
        }

        Write-Host "`n Running Post-Installation Environment Readiness Checks..." -ForegroundColor Yellow
        try {
            $readinessResult = Test-EnvironmentReadiness -ErrorAction Stop
            $criticalFailures = $readinessResult | Where-Object { $_.Severity -eq "Critical" -and $_.Status -ne "Success" }

            if ($criticalFailures) {
                Write-Error "CRITICAL: Environment Readiness tests failed:"
                $criticalFailures | Format-Table Name, Status, Severity -AutoSize
            } else {
                Write-Host "All Critical Environment Readiness tests passed." -ForegroundColor Green
            }
        } catch {
            Write-Warning "Failed to execute Test-EnvironmentReadiness. Error: $_"
        }

        Write-Host "`n Confirming APEX MC to AX Recognition..." -ForegroundColor Yellow
        Write-Host "Manual Action Required: Check Dell OpenManage Integration with Windows Admin Center (OMIMSWAC) or Azure Arc. Verify that your MC nodes (e.g., MC-760/MC-660) are recognized cleanly as AX infrastructure under the active SBE." -ForegroundColor Cyan
    }
}