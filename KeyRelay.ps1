<#
    .Synopsis
       KeyRelay.ps1
    .DESCRIPTION
       Provides a GUI tool to send text to applications that do not allow pasting.
    .EXAMPLES
       Invoke-KeyRelay
    .Author
       Jim Gandy
#>

Function Invoke-KeyRelay {

# =====================================================
# App Version
# =====================================================
$APP_VERSION = "1.17"

# =====================================================
# APP DATA FOLDER
# =====================================================
$DocumentsFolder = [Environment]::GetFolderPath("MyDocuments")
$AppFolder = Join-Path $DocumentsFolder "KeyRelay"

if (-not (Test-Path $AppFolder)) {
    New-Item -ItemType Directory -Path $AppFolder | Out-Null
}

#region Telemetry Information
# =====================================================
$uploadToAzure = $true
$script:TelemetrySuccessShown = $false

if ($uploadToAzure) {

    Write-Host "Logging Telemetry Information..."

    function Add-TableData {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true)]
            [string]$TableName,

            [Parameter(Mandatory = $true)]
            [string]$PartitionKey,

            [Parameter(Mandatory = $true)]
            [hashtable]$Data,

            [bool]$ShowSuccessOnce = $false
        )

        if (-not $uploadToAzure) { return }

        $RowKey = [guid]::NewGuid().Guid

        $TableSvcSasUrl = 'https://gsetools.table.core.windows.net/?sv=2024-11-04&ss=t&srt=so&sp=a&se=2028-03-11T21:32:20Z&st=2026-03-11T12:17:20Z&spr=https&sig=zYIhaiCnIiphMZLI38Uj6AcJ1WLJOKe4KRMl4WzX818%3D'
        $uri = "https://gsetools.table.core.windows.net/$TableName$($TableSvcSasUrl.Substring($TableSvcSasUrl.IndexOf('?')))"

        $headers = @{
            "Accept"       = "application/json;odata=nometadata"
            "Content-Type" = "application/json"
            "x-ms-version" = "2019-02-02"
        }

        $Data["PartitionKey"] = $PartitionKey
        $Data["RowKey"]       = $RowKey

        $body = $Data | ConvertTo-Json -Depth 5

        $maxRetries = 3
        $attempt = 0
        $success = $false

        while (-not $success -and $attempt -lt $maxRetries) {
            try {
                Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body | Out-Null
                $success = $true

                if (-not $ShowSuccessOnce -or -not $script:TelemetrySuccessShown) {
                    Write-Indent "Telemetry recorded successfully" 1 Green
                    if ($ShowSuccessOnce) {
                        $script:TelemetrySuccessShown = $true
                    }
                }
            }
            catch {
                $attempt++

                if ($attempt -lt $maxRetries) {
                    Write-Indent "Retrying telemetry upload ($attempt/$maxRetries)..." 1 Yellow
                    Start-Sleep -Seconds 2
                }
                else {
                    Write-Indent "Telemetry upload failed after $maxRetries attempts" 1 Yellow
                }
            }
        }
    }

    function Write-Indent {
        param(
            [string]$Message,
            [int]$Level = 1,
            [string]$Color = "Gray"
        )

        $prefix = "  " * $Level
        Write-Host "$prefix$Message" -ForegroundColor $Color
    }

    $CReportID = [guid]::NewGuid().Guid
    Write-Indent "Resolving Geo Location..."

    try {
        if (-not $global:GeoCache) {
            $global:GeoCache = Invoke-RestMethod "https://ipwho.is/" -TimeoutSec 5
        }

        $response = $global:GeoCache

        if ($response.success -eq $true) {
            $country     = $response.country
            $countryCode = $response.country_code
            $region      = $response.region
            $city        = $response.city
            $latitude    = $response.latitude
            $longitude   = $response.longitude
            $timezone    = $response.timezone.id

            Write-Indent "Country: $country" 2
            Write-Indent "Region : $region" 2
        }
    }
    catch {
        Write-Indent "WARN: ipwho lookup failed" 2 Yellow
    }

    $data = @{
        Region      = $region
        Version     = $APP_VERSION
        ReportID    = $CReportID
        country     = $country
        countryCode = $countryCode
        geoRegion   = $region
        city        = $city
        lat         = $latitude
        lon         = $longitude
        timezone    = $timezone
        Timestamp   = (Get-Date).ToUniversalTime().ToString("o")
        HostOS      = [System.Environment]::OSVersion.VersionString
        PSVersion   = $PSVersionTable.PSVersion.ToString()
    }

    $PartitionKey = "KeyRelay"

    Add-TableData `
        -TableName "KeyRelayTelemetryData" `
        -PartitionKey $PartitionKey `
        -Data $data `
        -ShowSuccessOnce $true
}
#endregion

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try { Add-Type -AssemblyName System.Management.Automation } catch {}

# =====================================================
# CONFIG
# =====================================================
$script:TabCompletions = $null
$script:TabCompletionIndex = -1
$script:LastTabInput = $null
$script:LastTabCaret = -1

$APP_TITLE = "KeyRelay v$APP_VERSION - Relaying keystrokes where paste can't go.   By: Jim Gandy"
$HIST_MAX  = 10

$HistoryPath  = Join-Path $AppFolder "KeyRelay.history.json"
$CommandPath  = Join-Path $AppFolder "KeyRelay.commands.json"
$SettingsPath = Join-Path $AppFolder "KeyRelay.settings.json"

$global:IsTyping = $false
$global:History  = @()
$global:Settings = @{}

$PLACEHOLDER_TEXT  = "Paste your command here that you would like to relay..."
$SharedCommandsURL = "https://raw.githubusercontent.com/DellProSupportGse/Tools/main/KeyRelay.Shared.json"

# =====================================================
# KEYBOARD LAYOUT DETECTION
# =====================================================
$global:OriginalKeyboardLayout = ([System.Windows.Forms.InputLanguage]::DefaultInputLanguage).Culture.Name

# =====================================================
# HISTORY
# =====================================================
function Save-History {
    $global:History | ConvertTo-Json -Depth 5 | Set-Content $HistoryPath
}

function Load-History {
    $global:History = @()
    if (-not (Test-Path $HistoryPath)) { return }

    $raw = Get-Content $HistoryPath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return }

    $loaded = $raw | ConvertFrom-Json
    if ($loaded -is [System.Collections.IEnumerable]) {
        $global:History = @($loaded)
    }
}

function Refresh-HistoryList {
    $lstHistory.Items.Clear()
    foreach ($item in $global:History) {
        $lstHistory.Items.Add($item) | Out-Null
    }
}

function Maybe-AddToHistory($text) {
    $filtered = $global:History | Where-Object { $_ -ne $text }
    $global:History = @($text) + $filtered | Select-Object -First $HIST_MAX
    Refresh-HistoryList
    Save-History
}

# =====================================================
# COMMAND JSON HELPERS
# =====================================================
function ConvertTo-Array {
    param($InputObject)

    if ($null -eq $InputObject) { return @() }
    if ($InputObject -is [System.Array]) { return @($InputObject) }
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) { return @($InputObject) }
    return @($InputObject)
}

function Ensure-CommandFile {
    if (-not (Test-Path $CommandPath)) {
        $sample = @{
            Commands = @(
                @{
                    Name = "Storage"
                    Children = @(
                        @{
                            Name        = "Get Storage Pools"
                            Command     = "Get-StoragePool -IsPrimordial `$False"
                            Description = "Lists non-primordial storage pools."
                        }
                    )
                }
            )
        }

        $sample | ConvertTo-Json -Depth 20 | Set-Content $CommandPath
    }
}

function Normalize-CommandJson {
    param($JsonObject)

    $normalized = @{
        Commands = @()
    }

    if ($null -eq $JsonObject) {
        return $normalized
    }

    $categories = ConvertTo-Array $JsonObject.Commands

    foreach ($category in $categories) {
        if (-not $category) { continue }
        if (-not $category.Name) { continue }

        $newCategory = @{
            Name     = [string]$category.Name
            Children = @()
        }

        $children = ConvertTo-Array $category.Children
        foreach ($child in $children) {
            if (-not $child) { continue }
            if (-not $child.Name -or -not $child.Command) { continue }

            $newCategory.Children += @{
                Name        = [string]$child.Name
                Command     = [string]$child.Command
                Description = [string]$child.Description
            }
        }

        $normalized.Commands += $newCategory
    }

    return $normalized
}

function Get-CommandJson {
    Ensure-CommandFile
    $raw = Get-Content $CommandPath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return Normalize-CommandJson @{ Commands = @() }
    }

    $json = $raw | ConvertFrom-Json
    return Normalize-CommandJson $json
}

function Save-CommandJson {
    param($JsonObject)

    $normalized = Normalize-CommandJson $JsonObject
    $normalized | ConvertTo-Json -Depth 20 | Set-Content $CommandPath
}

function Add-CommandToJson {
    param(
        [string]$category,
        [string]$name,
        [string]$commandText,
        [string]$description = ""
    )

    $json = Get-CommandJson
    $cat = $json.Commands | Where-Object { $_.Name -eq $category }

    if (-not $cat) {
        $cat = @{
            Name     = $category
            Children = @()
        }
        $json.Commands += $cat
    }

    $existing = $cat.Children | Where-Object { $_.Name -eq $name } | Select-Object -First 1
    if ($existing) {
        $existing.Command = $commandText
        $existing.Description = $description
    }
    else {
        $cat.Children += @{
            Name        = $name
            Command     = $commandText
            Description = $description
        }
    }

    Save-CommandJson $json
}

function Remove-CommandFromJson {
    param($categoryName, $commandName)

    if (-not (Test-Path $CommandPath)) { return }

    $json = Get-CommandJson
    $category = $json.Commands | Where-Object { $_.Name -eq $categoryName }

    if ($category -and $category.Children) {
        $category.Children = @(
            $category.Children | Where-Object { $_.Name -ne $commandName }
        )
    }

    Save-CommandJson $json
}

function Remove-CategoryFromJson {
    param($categoryName)

    if (-not (Test-Path $CommandPath)) { return }

    $json = Get-CommandJson
    $json.Commands = @(
        $json.Commands | Where-Object { $_.Name -ne $categoryName }
    )

    Save-CommandJson $json
}

function Merge-CommandLibraries {
    param(
        $BaseJson,
        $ImportedJson
    )

    $base = Normalize-CommandJson $BaseJson
    $incoming = Normalize-CommandJson $ImportedJson

    foreach ($importCategory in (ConvertTo-Array $incoming.Commands)) {

        $existingCategory = $base.Commands | Where-Object { $_.Name -eq $importCategory.Name } | Select-Object -First 1

        if (-not $existingCategory) {
            $base.Commands += @{
                Name     = $importCategory.Name
                Children = @()
            }
            $existingCategory = $base.Commands | Where-Object { $_.Name -eq $importCategory.Name } | Select-Object -First 1
        }

        foreach ($importChild in (ConvertTo-Array $importCategory.Children)) {
            $existingChild = $existingCategory.Children | Where-Object { $_.Name -eq $importChild.Name } | Select-Object -First 1

            if ($existingChild) {
                $existingChild.Command = $importChild.Command
                $existingChild.Description = $importChild.Description
            }
            else {
                $existingCategory.Children += @{
                    Name        = $importChild.Name
                    Command     = $importChild.Command
                    Description = $importChild.Description
                }
            }
        }
    }

    return $base
}

function Export-CommandsToFile {
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Title = "Export My Commands"
    $dialog.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
    $dialog.FileName = "KeyRelay.commands.export.json"

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    try {
        $json = Get-CommandJson
        $json | ConvertTo-Json -Depth 20 | Set-Content $dialog.FileName
        [System.Windows.Forms.MessageBox]::Show(
            "Commands exported successfully.",
            "KeyRelay",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to export commands.`n`n$($_.Exception.Message)",
            "KeyRelay",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
}

function Import-CommandsFromFile {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Import My Commands"
    $dialog.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    try {
        $raw = Get-Content $dialog.FileName -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            throw "Selected file is empty."
        }

        $imported = $raw | ConvertFrom-Json
        $normalizedImport = Normalize-CommandJson $imported

        if ((ConvertTo-Array $normalizedImport.Commands).Count -eq 0) {
            throw "Selected file does not contain a valid Commands structure."
        }

        $choice = [System.Windows.Forms.MessageBox]::Show(
            "Yes = Merge imported commands into existing My Commands.`nNo = Replace existing My Commands.`nCancel = Abort import.",
            "Import My Commands",
            [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        switch ($choice) {
            ([System.Windows.Forms.DialogResult]::Yes) {
                $existing = Get-CommandJson
                $merged = Merge-CommandLibraries -BaseJson $existing -ImportedJson $normalizedImport
                Save-CommandJson $merged
            }
            ([System.Windows.Forms.DialogResult]::No) {
                Save-CommandJson $normalizedImport
            }
            default {
                return
            }
        }

        Load-CommandTree

        [System.Windows.Forms.MessageBox]::Show(
            "Commands imported successfully.",
            "KeyRelay",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to import commands.`n`n$($_.Exception.Message)",
            "KeyRelay",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
}

# =====================================================
# SETTINGS
# =====================================================
function Save-Settings {
    $global:Settings | ConvertTo-Json -Depth 5 | Set-Content $SettingsPath
}

function Load-Settings {
    $global:Settings = @{}
    if (-not (Test-Path $SettingsPath)) { return }

    $raw = Get-Content $SettingsPath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return }

    (ConvertFrom-Json $raw).psobject.properties | ForEach-Object {
        $global:Settings[$_.Name] = $_.Value
    }
}

function Save-CurrentSettings {
    $global:Settings.startDelay           = [int]$inpStartDelay.Text
    $global:Settings.keyDelay             = [int]$inpKeyDelay.Text
    $global:Settings.lineDelay            = [int]$inpLineDelay.Text
    $global:Settings.enterEach            = $chkEnter.Checked
    $global:Settings.TopMost              = $form.TopMost
    $global:Settings.InvokeCluster        = $chkInvokeCluster.Checked
    $global:Settings.AltTab               = $chkAltTab.Checked
    $global:Settings.PreviewBeforeTyping  = $chkPreview.Checked

    Save-Settings
}

# =====================================================
# TREE LOADERS
# =====================================================
function Load-CommandTree {
    $treeCommands.Nodes.Clear()

    $helperNode = New-Object System.Windows.Forms.TreeNode
    $helperNode.Text = "Helpers"

    $checkLangNode = New-Object System.Windows.Forms.TreeNode
    $checkLangNode.Text = "Check Language Culture"
    $checkLangNode.Tag  = "Add-Type -AssemblyName System.Windows.Forms;([System.Windows.Forms.InputLanguage]::DefaultInputLanguage).Culture.Name"
    $checkLangNode.ToolTipText = "Shows the current Windows input language culture."

    $helperNode.Nodes.Add($checkLangNode) | Out-Null
    $treeCommands.Nodes.Add($helperNode) | Out-Null

    $json = Get-CommandJson
    $sortedCategories = $json.Commands | Sort-Object Name

    foreach ($category in $sortedCategories) {
        $catNode = New-Object System.Windows.Forms.TreeNode
        $catNode.Text = $category.Name
        $treeCommands.Nodes.Add($catNode) | Out-Null

        if ($category.Children) {
            $sortedChildren = $category.Children | Sort-Object Name

            foreach ($child in $sortedChildren) {
                $childNode = New-Object System.Windows.Forms.TreeNode
                $childNode.Text = $child.Name
                $childNode.Tag  = $child.Command

                $desc = [string]$child.Description
                if (-not [string]::IsNullOrWhiteSpace($desc)) {
                    $childNode.ToolTipText = "$desc`n`nCommand:`n$($child.Command)"
                }
                else {
                    $childNode.ToolTipText = "Command:`n$($child.Command)"
                }

                $catNode.Nodes.Add($childNode) | Out-Null
            }
        }
    }

    $treeCommands.ExpandAll()
}

function Load-SharedCommands {
    try {
        $data = Invoke-RestMethod -Uri ($SharedCommandsURL + "?t=$(Get-Date -Format yyyyMMddHHmmss)") -UseBasicParsing

        $treeShared.Nodes.Clear()

        foreach ($category in $data.PSObject.Properties.Name | Sort-Object) {
            $catNode = New-Object System.Windows.Forms.TreeNode
            $catNode.Text = $category

            foreach ($cmd in ($data.$category | Sort-Object Name)) {
                $child = New-Object System.Windows.Forms.TreeNode
                $child.Text = $cmd.Name
                $child.Tag  = $cmd.Command

                if ($cmd.Description) {
                    $child.ToolTipText = "$($cmd.Description)`n`nCommand:`n$($cmd.Command)"
                }
                else {
                    $child.ToolTipText = "Command:`n$($cmd.Command)"
                }

                $catNode.Nodes.Add($child) | Out-Null
            }

            $treeShared.Nodes.Add($catNode)
        }

        $treeShared.ExpandAll()
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to load shared commands from GitHub.",
            "KeyRelay"
        )
    }
}

function Perform-Search {
    if ($txtSearch.Text -eq "Search commands...") { return }

    $query = $txtSearch.Text.ToLower()

    if ($tabRight.SelectedTab.Text -eq "My Commands") {
        Load-CommandTree
        if ($query.Length -eq 0) { return }

        foreach ($node in $treeCommands.Nodes) {
            foreach ($child in @($node.Nodes)) {
                if (-not $child.Text.ToLower().Contains($query) -and
                    -not ($child.Tag -and $child.Tag.ToLower().Contains($query)) -and
                    -not ($child.ToolTipText -and $child.ToolTipText.ToLower().Contains($query))) {
                    $node.Nodes.Remove($child)
                }
                else {
                    $node.Expand()
                }
            }
        }
    }
    elseif ($tabRight.SelectedTab.Text -eq "Shared") {
        Load-SharedCommands
        if ($query.Length -eq 0) { return }

        foreach ($node in $treeShared.Nodes) {
            foreach ($child in @($node.Nodes)) {
                if (-not $child.Text.ToLower().Contains($query) -and
                    -not ($child.Tag -and $child.Tag.ToLower().Contains($query)) -and
                    -not ($child.ToolTipText -and $child.ToolTipText.ToLower().Contains($query))) {
                    $node.Nodes.Remove($child)
                }
                else {
                    $node.Expand()
                }
            }
        }
    }
    elseif ($tabRight.SelectedTab.Text -eq "History") {
        $lstHistory.Items.Clear()

        foreach ($item in $global:History) {
            if ($query.Length -eq 0 -or $item.ToLower().Contains($query)) {
                $lstHistory.Items.Add($item) | Out-Null
            }
        }
    }
}

# =====================================================
# ADD GETWINDOWSTEXT TYPE
# =====================================================
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class User32 {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
}
"@

# =====================================================
# ADD / EDIT COMMAND DIALOG
# =====================================================
function Show-AddCommandDialog {
    param(
        [string]$defaultCommand = "",
        [string]$defaultName = "",
        [string]$defaultDescription = ""
    )

    Ensure-CommandFile

    $previousTopMost = $form.TopMost
    if ($previousTopMost) {
        $form.TopMost = $false
        $btnTop.Text = "Always On Top: OFF"
    }

    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = "Add / Edit Command"
    $dialog.Size = New-Object Drawing.Size(620, 610)
    $dialog.StartPosition = "CenterParent"
    $dialog.AutoScaleMode = "None"

    $lblCat = New-Object Windows.Forms.Label
    $lblCat.Text = "Category:"
    $lblCat.SetBounds(20, 20, 120, 25)

    $cmbCat = New-Object Windows.Forms.ComboBox
    $cmbCat.SetBounds(150, 20, 420, 28)
    $cmbCat.DropDownStyle = "DropDown"

    $json = Get-CommandJson
    foreach ($c in $json.Commands | Sort-Object Name) {
        $cmbCat.Items.Add($c.Name) | Out-Null
    }

    $lblName = New-Object Windows.Forms.Label
    $lblName.Text = "Display Name:"
    $lblName.SetBounds(20, 60, 120, 25)

    $txtName = New-Object Windows.Forms.TextBox
    $txtName.SetBounds(150, 60, 420, 28)
    $txtName.Text = $defaultName

    $lblDesc = New-Object Windows.Forms.Label
    $lblDesc.Text = "Description:"
    $lblDesc.SetBounds(20, 100, 120, 25)

    $txtDesc = New-Object Windows.Forms.TextBox
    $txtDesc.SetBounds(150, 100, 420, 90)
    $txtDesc.Multiline = $true
    $txtDesc.ScrollBars = "Vertical"
    $txtDesc.Text = $defaultDescription

    $lblCmd = New-Object Windows.Forms.Label
    $lblCmd.Text = "Command:"
    $lblCmd.SetBounds(20, 205, 120, 25)

    $txtCmd = New-Object Windows.Forms.TextBox
    $txtCmd.SetBounds(20, 235, 550, 280)
    $txtCmd.Multiline = $true
    $txtCmd.ScrollBars = "Vertical"
    $txtCmd.Font = New-Object Drawing.Font("Consolas", 14)
    $txtCmd.Text = $defaultCommand

    $btnSave = New-Object Windows.Forms.Button
    $btnSave.Text = "Save"
    $btnSave.SetBounds(380, 525, 90, 35)

    $btnCancel = New-Object Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.SetBounds(480, 525, 90, 35)

    $btnSave.Add_Click({
        if (-not $cmbCat.Text -or -not $txtName.Text -or -not $txtCmd.Text) {
            [System.Windows.Forms.MessageBox]::Show("Category, Display Name, and Command are required.")
            return
        }

        Add-CommandToJson `
            -category $cmbCat.Text `
            -name $txtName.Text `
            -commandText $txtCmd.Text `
            -description $txtDesc.Text

        Load-CommandTree
        $dialog.Close()
    })

    $btnCancel.Add_Click({ $dialog.Close() })

    $dialog.Controls.AddRange(@(
        $lblCat, $cmbCat,
        $lblName, $txtName,
        $lblDesc, $txtDesc,
        $lblCmd, $txtCmd,
        $btnSave, $btnCancel
    ))

    [void]$dialog.ShowDialog()

    if ($previousTopMost) {
        $form.TopMost = $true
        $btnTop.Text = "Always On Top: ON"
    }
}

# =====================================================
# TAB COMPLETION
# =====================================================
function Reset-EditorTabCompletion {
    $script:TabCompletions = $null
    $script:TabCompletionIndex = -1
    $script:LastTabInput = $null
    $script:LastTabCaret = -1
}

function Invoke-EditorTabCompletion {
    param(
        [System.Windows.Forms.TextBox]$TextBox
    )

    $inputText = $TextBox.Text
    $cursorPos = $TextBox.SelectionStart

    try {
        $completion = [System.Management.Automation.CommandCompletion]::CompleteInput(
            $inputText,
            $cursorPos,
            $null
        )
    }
    catch {
        return
    }

    if (-not $completion -or -not $completion.CompletionMatches -or $completion.CompletionMatches.Count -eq 0) {
        return
    }

    $sameRequest = (
        $script:LastTabInput -eq $inputText -and
        $script:LastTabCaret -eq $cursorPos -and
        $script:TabCompletions -ne $null
    )

    if (-not $sameRequest) {
        $script:TabCompletions = $completion
        $script:TabCompletionIndex = 0
        $script:LastTabInput = $inputText
        $script:LastTabCaret = $cursorPos
    }
    else {
        $script:TabCompletionIndex++
        if ($script:TabCompletionIndex -ge $script:TabCompletions.CompletionMatches.Count) {
            $script:TabCompletionIndex = 0
        }
    }

    $match = $script:TabCompletions.CompletionMatches[$script:TabCompletionIndex]
    $replacementIndex = $script:TabCompletions.ReplacementIndex
    $replacementLength = $script:TabCompletions.ReplacementLength
    $replacementText = $match.CompletionText

    $before = $inputText.Substring(0, $replacementIndex)
    $after  = $inputText.Substring($replacementIndex + $replacementLength)

    $TextBox.Text = $before + $replacementText + $after
    $TextBox.SelectionStart = ($before + $replacementText).Length
    $TextBox.SelectionLength = 0
}

# =====================================================
# PREVIEW
# =====================================================
function Show-TypingPreview {
    param(
        [string]$TextToSend,
        [bool]$UsingSelection,
        [bool]$UsingClusterWrap,
        [bool]$PressEnterEachLine
    )

    $scopeText = if ($UsingSelection) { "Selection only" } else { "Full editor contents" }
    $clusterText = if ($UsingClusterWrap) { "Yes" } else { "No" }
    $enterText = if ($PressEnterEachLine) { "Yes" } else { "No" }

    $previewMessage = @"
About to send:

Scope: $scopeText
Run on Cluster Nodes: $clusterText
Press Enter After Each Line: $enterText

------------------------------------------------------------
$TextToSend
------------------------------------------------------------

Continue?
"@

    $result = [System.Windows.Forms.MessageBox]::Show(
        $previewMessage,
        "KeyRelay Preview",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )

    return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
}

# =====================================================
# TYPING ENGINE
# =====================================================
function Send-CharacterSafe {
    param($text, $delay)

    $specialChars = '+^%~(){}'

    foreach ($char in $text.ToCharArray()) {
        if (-not $global:IsTyping) { break }

        $translated = $char

        if ($specialChars.Contains($translated)) {
            [System.Windows.Forms.SendKeys]::SendWait("{$translated}")
        }
        else {
            [System.Windows.Forms.SendKeys]::SendWait($translated)
        }

        Start-Sleep -Milliseconds $delay
    }
}

function Start-Typing {
    if ($global:IsTyping) { return }

    $targetCulture = $txtLayout.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($targetCulture)) {
        $targetCulture = $global:OriginalKeyboardLayout
    }

    $restoreKeyboard = $false

    if ($targetCulture -and $targetCulture -ne $global:OriginalKeyboardLayout) {
        try {
            $lang = New-WinUserLanguageList $targetCulture
            Set-WinUserLanguageList $lang -Force -WarningAction SilentlyContinue
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Invalid language code: $targetCulture",
                "Keyboard Layout Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return
        }

        Start-Sleep -Milliseconds 300
        $restoreKeyboard = $true
    }

    if ($global:Settings.AltTab) {
        Start-Sleep -Milliseconds 200
        [System.Windows.Forms.SendKeys]::SendWait("%{TAB}")
        Start-Sleep -Milliseconds 200
    }

    $fullText = $txtInput.Text
    $usingSelection = $txtInput.SelectionLength -gt 0

    $text = if ($usingSelection) {
        $txtInput.SelectedText
    }
    else {
        $fullText
    }

    if ($text -eq $PLACEHOLDER_TEXT) { return }
    if ([string]::IsNullOrWhiteSpace($text)) { return }

    $usingClusterWrap = $chkInvokeCluster.Checked

    if ($usingClusterWrap) {
        $normalized = ($text -replace "`r`n", "`n")
        $text = "Invoke-Command -ComputerName (Get-ClusterNode).Name -ScriptBlock { $normalized }"
    }

    if ($chkPreview.Checked) {
        $continueTyping = Show-TypingPreview `
            -TextToSend $text `
            -UsingSelection $usingSelection `
            -UsingClusterWrap $usingClusterWrap `
            -PressEnterEachLine $chkEnter.Checked

        if (-not $continueTyping) { return }
    }

    Add-TableData -TableName "KeyRelayTelemetryData" -PartitionKey $PartitionKey -Data $data -ShowSuccessOnce $true
    Maybe-AddToHistory $text

    $startDelay = [int]$inpStartDelay.Text
    $keyDelay   = [int]$inpKeyDelay.Text
    $lineDelay  = [int]$inpLineDelay.Text
    $enterEach  = $chkEnter.Checked

    $lines = ($text -replace "`r`n", "`n").Split("`n")

    $global:IsTyping = $true
    $btnType.Enabled = $false
    $btnStop.Enabled = $true

    try {
        Start-Sleep -Seconds $startDelay

        $sb = New-Object System.Text.StringBuilder 256
        [User32]::GetWindowText(([User32]::GetForegroundWindow()), $sb, $sb.Capacity) | Out-Null

        if ($sb.ToString() -eq $APP_TITLE) {
            Write-Warning "Did not switch to another window!!"
            $global:IsTyping = $false
        }

        foreach ($line in $lines) {
            if (-not $global:IsTyping) { break }

            Send-CharacterSafe $line $keyDelay

            if ($enterEach) {
                [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
            }

            Start-Sleep -Milliseconds $lineDelay
        }
    }
    finally {
        $global:IsTyping = $false

        if ($restoreKeyboard) {
            Set-WinUserLanguageList $global:OriginalKeyboardLayout -Force -WarningAction SilentlyContinue
        }

        if ($chkInvokeCluster.Checked) {
            $chkInvokeCluster.Checked = $false
            Save-CurrentSettings
        }

        $btnType.Enabled = $true
        $btnStop.Enabled = $false
    }
}

# =====================================================
# GUI
# =====================================================
$form = New-Object Windows.Forms.Form
$form.Text = $APP_TITLE
$form.Size = New-Object Drawing.Size(1100, 830)
$form.StartPosition = "CenterScreen"
$form.AutoScaleMode = "None"

# =====================================================
# MENU BAR
# =====================================================
$menuStrip = New-Object System.Windows.Forms.MenuStrip

$menuFile = New-Object System.Windows.Forms.ToolStripMenuItem
$menuFile.Text = "File"
$menuFile.Font = New-Object Drawing.Font("Consolas", 9)

$menuImportCommands = New-Object System.Windows.Forms.ToolStripMenuItem
$menuImportCommands.Text = "Import My Commands"

$menuExportCommands = New-Object System.Windows.Forms.ToolStripMenuItem
$menuExportCommands.Text = "Export My Commands"

$menuFile.DropDownItems.Add($menuImportCommands) | Out-Null
$menuFile.DropDownItems.Add($menuExportCommands) | Out-Null

$menuHelp = New-Object System.Windows.Forms.ToolStripMenuItem
$menuHelp.Text = "Help"
$menuHelp.Font = New-Object Drawing.Font("Consolas", 9)

$menuDocs = New-Object System.Windows.Forms.ToolStripMenuItem
$menuDocs.Text = "Documentation"

$menuQuick = New-Object System.Windows.Forms.ToolStripMenuItem
$menuQuick.Text = "Quick Start"

$menuHelp.DropDownItems.Add($menuDocs) | Out-Null
$menuHelp.DropDownItems.Add($menuQuick) | Out-Null

$menuStrip.Items.Add($menuFile) | Out-Null
$menuStrip.Items.Add($menuHelp) | Out-Null

$form.MainMenuStrip = $menuStrip
$form.Controls.Add($menuStrip)

$menuImportCommands.Add_Click({ Import-CommandsFromFile })
$menuExportCommands.Add_Click({ Export-CommandsToFile })

$menuDocs.Add_Click({
    Start-Process "https://github.com/DellProSupportGse/Tools/blob/main/KeyRelayREADME.md"
})

$menuQuick.Add_Click({
    Start-Process "https://github.com/DellProSupportGse/Tools/blob/main/KeyRelayQuickStart.md"
})

$txtInput = New-Object Windows.Forms.TextBox
$txtInput.Multiline = $true
$txtInput.ScrollBars = "Vertical"
$txtInput.Font = New-Object Drawing.Font("Consolas", 14)
$txtInput.SetBounds(12, 40, 750, 470)
$txtInput.AcceptsTab = $true

$txtInput.Add_PreviewKeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Tab) {
        $e.IsInputKey = $true
    }
})

$txtInput.Add_KeyDown({
    param($sender, $e)

    if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::A) {
        $txtInput.SelectAll()
        $e.SuppressKeyPress = $true
        return
    }

    if ($txtInput.Text -eq $PLACEHOLDER_TEXT) {
        $txtInput.Text = ""
        $txtInput.ForeColor = [System.Drawing.Color]::Black
    }

    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Tab) {
        Invoke-EditorTabCompletion -TextBox $txtInput
        $e.SuppressKeyPress = $true
        return
    }

    Reset-EditorTabCompletion
})

$txtInput.Add_TextChanged({
    Reset-EditorTabCompletion
})

$txtInput.ForeColor = [System.Drawing.Color]::Gray
$txtInput.Text = $PLACEHOLDER_TEXT

$lblSearch = New-Object Windows.Forms.Label
$lblSearch.Text = "Search:"
$lblSearch.SetBounds(780, 545, 60, 25)

$txtSearch = New-Object Windows.Forms.TextBox
$txtSearch.SetBounds(840, 543, 230, 25)
$txtSearch.Text = "Search commands..."
$txtSearch.ForeColor = [System.Drawing.Color]::Gray

$tabRight = New-Object Windows.Forms.TabControl
$tabRight.SetBounds(780, 40, 290, 490)

$tabCommands = New-Object Windows.Forms.TabPage
$tabCommands.Text = "My Commands"
$tabCommands.Font = New-Object Drawing.Font("Consolas", 10)

$tabShared = New-Object Windows.Forms.TabPage
$tabShared.Text = "Shared"
$tabShared.Font = New-Object Drawing.Font("Consolas", 10)

$treeShared = New-Object Windows.Forms.TreeView
$treeShared.Dock = "Fill"
$treeShared.ShowNodeToolTips = $true

$treeCommands = New-Object Windows.Forms.TreeView
$treeCommands.Dock = "Fill"
$treeCommands.ShowNodeToolTips = $true

$tabShared.Controls.Add($treeShared)
$tabCommands.Controls.Add($treeCommands)

$tabHistory = New-Object Windows.Forms.TabPage
$tabHistory.Text = "History"
$tabHistory.Font = New-Object Drawing.Font("Consolas", 10)

$lstHistory = New-Object Windows.Forms.ListBox
$lstHistory.Dock = "Fill"
$tabHistory.Controls.Add($lstHistory)

$tabRight.TabPages.Add($tabCommands) | Out-Null
$tabRight.TabPages.Add($tabShared) | Out-Null
$tabRight.TabPages.Add($tabHistory) | Out-Null

# =====================================================
# CONTEXT MENU
# =====================================================
$treeMenu = New-Object System.Windows.Forms.ContextMenuStrip

$menuCopyCommand = New-Object System.Windows.Forms.ToolStripMenuItem
$menuCopyCommand.Text = "Copy Command"

$menuEditCommand = New-Object System.Windows.Forms.ToolStripMenuItem
$menuEditCommand.Text = "Edit Command"

$menuRemoveCommand = New-Object System.Windows.Forms.ToolStripMenuItem
$menuRemoveCommand.Text = "Remove Command"

$menuRemoveCategory = New-Object System.Windows.Forms.ToolStripMenuItem
$menuRemoveCategory.Text = "Remove Category"

$treeMenu.Items.AddRange(@(
    $menuCopyCommand,
    $menuEditCommand,
    $menuRemoveCommand,
    $menuRemoveCategory
))

$treeCommands.ContextMenuStrip = $treeMenu
$treeShared.ContextMenuStrip   = $treeMenu

$script:RightClickedNode = $null

$treeCommands.Add_NodeMouseClick({
    param($sender, $e)

    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        $treeCommands.SelectedNode = $e.Node
        $script:RightClickedNode = $e.Node

        if ($e.Node.Tag) {
            $menuCopyCommand.Visible = $true
            $menuEditCommand.Visible = $true
            $menuRemoveCommand.Visible = $true
            $menuRemoveCategory.Visible = $false
        }
        else {
            $menuCopyCommand.Visible = $false
            $menuEditCommand.Visible = $false
            $menuRemoveCommand.Visible = $false
            $menuRemoveCategory.Visible = $true
        }
    }
})

$treeShared.Add_NodeMouseClick({
    param($sender, $e)

    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        $treeShared.SelectedNode = $e.Node
        $script:RightClickedNode = $e.Node

        if ($e.Node.Tag) {
            $menuCopyCommand.Visible = $true
            $menuEditCommand.Visible = $false
            $menuRemoveCommand.Visible = $false
            $menuRemoveCategory.Visible = $false
        }
        else {
            $menuCopyCommand.Visible = $false
            $menuEditCommand.Visible = $false
            $menuRemoveCommand.Visible = $false
            $menuRemoveCategory.Visible = $false
        }
    }
})

$treeShared.Add_NodeMouseDoubleClick({
    param($sender, $e)
    if ($e.Node.Tag) {
        $txtInput.Text = $e.Node.Tag
        $txtInput.ForeColor = [System.Drawing.Color]::Black
    }
})

$menuEditCommand.Add_Click({
    if (-not $script:RightClickedNode) { return }

    $commandName  = $script:RightClickedNode.Text
    $categoryName = $script:RightClickedNode.Parent.Text
    $commandText  = $script:RightClickedNode.Tag

    $json = Get-CommandJson
    $category = $json.Commands | Where-Object { $_.Name -eq $categoryName } | Select-Object -First 1
    $command = $null
    if ($category) {
        $command = $category.Children | Where-Object { $_.Name -eq $commandName } | Select-Object -First 1
    }

    Remove-CommandFromJson $categoryName $commandName

    Show-AddCommandDialog `
        -defaultCommand $commandText `
        -defaultName $commandName `
        -defaultDescription ([string]$command.Description)
})

$menuRemoveCommand.Add_Click({
    if (-not $script:RightClickedNode) { return }

    $commandName  = $script:RightClickedNode.Text
    $categoryName = $script:RightClickedNode.Parent.Text

    Remove-CommandFromJson $categoryName $commandName
    Load-CommandTree
})

$menuRemoveCategory.Add_Click({
    if (-not $script:RightClickedNode) { return }

    $categoryName = $script:RightClickedNode.Text

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Remove entire category '$categoryName' and all commands?",
        "Confirm Remove",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        Remove-CategoryFromJson $categoryName
        Load-CommandTree
    }
})

$menuCopyCommand.Add_Click({
    if ($script:RightClickedNode -and $script:RightClickedNode.Tag) {
        [System.Windows.Forms.Clipboard]::SetText($script:RightClickedNode.Tag)
    }
})

# =====================================================
# DEFAULT SETTINGS
# =====================================================
Load-Settings
if ($global:Settings.Count -eq 0) {
    $global:Settings = @{}
    $global:Settings.startDelay          = 4
    $global:Settings.keyDelay            = 35
    $global:Settings.lineDelay           = 120
    $global:Settings.enterEach           = $true
    $global:Settings.TopMost             = $false
    $global:Settings.InvokeCluster       = $false
    $global:Settings.AltTab              = $false
    $global:Settings.PreviewBeforeTyping = $false
    Save-Settings
}

# =====================================================
# RIGHT BUTTONS
# =====================================================
$btnReload = New-Object Windows.Forms.Button
$btnReload.Text = "Reload Commands"
$btnReload.SetBounds(780, 580, 290, 30)

$btnAdd = New-Object Windows.Forms.Button
$btnAdd.Text = "Add Command"
$btnAdd.SetBounds(780, 615, 290, 30)

$btnAddHist = New-Object Windows.Forms.Button
$btnAddHist.Text = "Add From History"
$btnAddHist.SetBounds(780, 650, 290, 30)

$btnClearHist = New-Object Windows.Forms.Button
$btnClearHist.Text = "Clear History"
$btnClearHist.SetBounds(780, 685, 290, 30)

# =====================================================
# BOTTOM PANEL
# =====================================================
$panelBottom = New-Object Windows.Forms.Panel
$panelBottom.SetBounds(12, 530, 750, 230)

$lblStart = New-Object Windows.Forms.Label
$lblStart.Text = "Start Delay (sec)"
$lblStart.SetBounds(10, 10, 110, 25)

$inpStartDelay = New-Object Windows.Forms.TextBox
$inpStartDelay.Text = "4"
$inpStartDelay.SetBounds(125, 8, 30, 25)

$lblKey = New-Object Windows.Forms.Label
$lblKey.Text = "Per-Key Delay (ms)"
$lblKey.SetBounds(165, 10, 130, 25)

$inpKeyDelay = New-Object Windows.Forms.TextBox
$inpKeyDelay.Text = "35"
$inpKeyDelay.SetBounds(300, 8, 30, 25)

$lblLine = New-Object Windows.Forms.Label
$lblLine.Text = "Between Lines (ms)"
$lblLine.SetBounds(340, 10, 130, 25)

$inpLineDelay = New-Object Windows.Forms.TextBox
$inpLineDelay.Text = "120"
$inpLineDelay.SetBounds(475, 8, 30, 25)

$chkEnter = New-Object Windows.Forms.CheckBox
$chkEnter.Text = "Press Enter After Each Line"
$chkEnter.Checked = $true
$chkEnter.SetBounds(10, 45, 250, 25)

$chkInvokeCluster = New-Object Windows.Forms.CheckBox
$chkInvokeCluster.Text = "Run on Cluster Nodes"
$chkInvokeCluster.SetBounds(265, 45, 170, 25)

$chkAltTab = New-Object Windows.Forms.CheckBox
$chkAltTab.Text = "Select Previous Window on Type It"
$chkAltTab.SetBounds(475, 45, 250, 25)

$chkPreview = New-Object Windows.Forms.CheckBox
$chkPreview.Text = "Preview Before Typing"
$chkPreview.SetBounds(10, 70, 180, 25)

$lblLayout = New-Object Windows.Forms.Label
$lblLayout.Text = "Target Lang (ex: fr-FR)"
$lblLayout.SetBounds(520, 10, 180, 25)

$txtLayout = New-Object Windows.Forms.TextBox
$txtLayout.SetBounds(700, 10, 40, 25)
$txtLayout.Text = $global:OriginalKeyboardLayout

$options = @("en-US", "zh-CN", "en-GB", "fr-CA", "es-ES", "ar-SA", "pt-BR", "fr-FR", "ja-JP", "ru-RU", "de-DE", "hi-IN")
$txtLayout.AutoCompleteMode = 'SuggestAppend'
$txtLayout.AutoCompleteSource = 'CustomSource'
$txtLayout.AutoCompleteCustomSource.AddRange($options)

$btnType = New-Object Windows.Forms.Button
$btnType.Text = "Type It"
$btnType.SetBounds(10, 105, 100, 35)

$btnStop = New-Object Windows.Forms.Button
$btnStop.Text = "STOP"
$btnStop.SetBounds(120, 105, 100, 35)
$btnStop.Enabled = $false

$btnClear = New-Object Windows.Forms.Button
$btnClear.Text = "Clear Editor"
$btnClear.SetBounds(230, 105, 120, 35)

$btnTop = New-Object Windows.Forms.Button
$btnTop.Text = "Always On Top: OFF"
$btnTop.SetBounds(370, 105, 180, 35)

$btnExit = New-Object Windows.Forms.Button
$btnExit.Text = "Exit"
$btnExit.SetBounds(560, 105, 100, 35)

$lnkIssue = New-Object System.Windows.Forms.LinkLabel
$lnkIssue.Text = "Found a bug? Open a GitHub issue"
$lnkIssue.AutoSize = $true
$lnkIssue.SetBounds(10, 175, 220, 25)
$lnkIssue.LinkColor = [System.Drawing.Color]::Blue
$lnkIssue.ActiveLinkColor = [System.Drawing.Color]::Red
$lnkIssue.VisitedLinkColor = [System.Drawing.Color]::Purple
$lnkIssue.TabStop = $true

$lnkIssue.Add_LinkClicked({
    param($sender, $e)
    Start-Process "https://github.com/DellProSupportGse/Tools/issues"
})

$panelBottom.Controls.AddRange(@(
    $lblStart, $inpStartDelay,
    $lblKey, $inpKeyDelay,
    $lblLine, $inpLineDelay,
    $chkEnter, $chkInvokeCluster, $chkAltTab, $chkPreview,
    $lblLayout, $txtLayout,
    $btnType, $btnStop, $btnClear, $btnTop, $btnExit,
    $lnkIssue
))

$form.Controls.AddRange(@(
    $txtInput, $tabRight,
    $lblSearch, $txtSearch,
    $btnReload, $btnAdd, $btnAddHist, $btnClearHist,
    $panelBottom
))

# =====================================================
# APPLY SETTINGS TO CONTROLS
# =====================================================
$inpStartDelay.Text         = $global:Settings.startDelay.ToString()
$inpKeyDelay.Text           = $global:Settings.keyDelay.ToString()
$inpLineDelay.Text          = $global:Settings.lineDelay.ToString()
$chkEnter.Checked           = [bool]$global:Settings.enterEach
$form.TopMost               = [bool]$global:Settings.TopMost
$chkInvokeCluster.Checked   = [bool]$global:Settings.InvokeCluster
$chkAltTab.Checked          = [bool]$global:Settings.AltTab
$chkPreview.Checked         = [bool]$global:Settings.PreviewBeforeTyping

$btnTop.Text = "Always On Top: " + ($(if ($form.TopMost) { "ON" } else { "OFF" }))

# =====================================================
# EVENTS
# =====================================================
$txtSearch.Add_GotFocus({
    if ($txtSearch.Text -eq "Search commands...") {
        $txtSearch.Text = ""
        $txtSearch.ForeColor = [System.Drawing.Color]::Black
    }
})

$txtSearch.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($txtSearch.Text)) {
        $txtSearch.Text = "Search commands..."
        $txtSearch.ForeColor = [System.Drawing.Color]::Gray
    }
})

$txtSearch.Add_TextChanged({
    Perform-Search
})

$tabRight.Add_SelectedIndexChanged({
    Perform-Search
})

$txtInput.Add_GotFocus({
    if ($txtInput.Text -eq $PLACEHOLDER_TEXT) {
        $txtInput.SelectAll()
    }
})

$txtInput.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($txtInput.Text)) {
        $txtInput.ForeColor = [System.Drawing.Color]::Gray
        $txtInput.Text = $PLACEHOLDER_TEXT
    }
})

$txtInput.Add_Leave({
    if ([string]::IsNullOrWhiteSpace($txtInput.Text)) {
        $txtInput.ForeColor = [System.Drawing.Color]::Gray
        $txtInput.Text = $PLACEHOLDER_TEXT
    }
})

$inpKeyDelay.Add_Leave({ Save-CurrentSettings })
$inpStartDelay.Add_Leave({ Save-CurrentSettings })
$inpLineDelay.Add_Leave({ Save-CurrentSettings })

$chkEnter.Add_CheckedChanged({ Save-CurrentSettings })
$chkAltTab.Add_CheckedChanged({ Save-CurrentSettings })
$chkInvokeCluster.Add_CheckedChanged({ Save-CurrentSettings })
$chkPreview.Add_CheckedChanged({ Save-CurrentSettings })

$btnType.Add_Click({
    [void](Start-Typing)
})

$btnStop.Add_Click({
    $global:IsTyping = $false
})

$btnClear.Add_Click({
    $txtInput.Clear()
})

$btnExit.Add_Click({
    Save-CurrentSettings
    $form.Close()
})

$btnTop.Add_Click({
    $form.TopMost = -not $form.TopMost
    Save-CurrentSettings
    $btnTop.Text = "Always On Top: " + ($(if ($form.TopMost) { "ON" } else { "OFF" }))
})

$form.Add_Closing({
    param($sender, $e)
    Save-CurrentSettings
})

$btnReload.Add_Click({
    Load-CommandTree
    Load-SharedCommands
})

$btnAdd.Add_Click({
    Show-AddCommandDialog "" "" ""
})

$btnAddHist.Add_Click({
    if ($lstHistory.SelectedIndex -lt 0) {
        [System.Windows.Forms.MessageBox]::Show("Select a history item first.")
        return
    }

    $cmd = $global:History[$lstHistory.SelectedIndex]
    $defaultName = ($cmd -split "`r?`n")[0]
    Show-AddCommandDialog $cmd $defaultName ""
})

$btnClearHist.Add_Click({
    if ($global:History.Count -eq 0) { return }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Are you sure you want to clear all history?",
        "Confirm Clear History",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        $global:History = @()
        $lstHistory.Items.Clear()
        Set-Content -Path $HistoryPath -Value "[]"
    }
})

$treeCommands.Add_NodeMouseDoubleClick({
    param($sender, $e)
    if ($e.Node.Tag) {
        $txtInput.Text = $e.Node.Tag
        $txtInput.ForeColor = [System.Drawing.Color]::Black
    }
})

$lstHistory.Add_DoubleClick({
    if ($lstHistory.SelectedIndex -ge 0) {
        $txtInput.Text = $global:History[$lstHistory.SelectedIndex]
        $txtInput.ForeColor = [System.Drawing.Color]::Black
    }
})

Load-History
Refresh-HistoryList

$form.Add_Shown({
    Load-CommandTree
    Load-SharedCommands
    $form.Activate()
})

[void]$form.ShowDialog()
}