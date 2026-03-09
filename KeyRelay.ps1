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

$APP_VERSION = "1.13.2"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# =====================================================
# CONFIG
# =====================================================

$APP_TITLE = "KeyRelay v$APP_VERSION - Relaying keystrokes where paste can't go.   By: Jim Gandy"

$HIST_MAX  = 10

$DocumentsFolder = [Environment]::GetFolderPath("MyDocuments")
$AppFolder = Join-Path $DocumentsFolder "KeyRelay"
if (-not (Test-Path $AppFolder)) { New-Item -ItemType Directory -Path $AppFolder | Out-Null }

$HistoryPath = Join-Path $AppFolder "KeyRelay.history.json"
$CommandPath = Join-Path $AppFolder "KeyRelay.commands.json"
$SettingsPath = Join-Path $AppFolder "KeyRelay.settings.json"

$global:IsTyping = $false
$global:History  = @()
$global:Settings  = @{}
$PLACEHOLDER_TEXT = "Paste your command here that you would like to relay..."
$SharedCommandsURL = "https://raw.githubusercontent.com/DellProSupportGse/Tools/main/KeyRelay.Shared.json"


# =====================================================
# KEYBOARD LAYOUT DETECTION
# =====================================================

$global:OriginalKeyboardLayout = ([system.windows.forms.inputlanguage]::DefaultInputLanguage).culture.name

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
# COMMAND JSON
# =====================================================

function Ensure-CommandFile {
    if (-not (Test-Path $CommandPath)) {

        $sample = @{
            Commands = @(
                @{
                    Name = "Storage"
                    Children = @(
                        @{ Name="Get Storage Pools"; Command="Get-StoragePool -IsPrimordial `$False" }
                    )
                }
            )
        }

        $sample | ConvertTo-Json -Depth 20 | Set-Content $CommandPath
    }
}

function Add-CommandToJson {
    param($category,$name,$commandText)

    Ensure-CommandFile
    $json = Get-Content $CommandPath -Raw | ConvertFrom-Json

    $cat = $json.Commands | Where-Object { $_.Name -eq $category }

    if (-not $cat) {
        $cat = @{ Name=$category; Children=@() }
        $json.Commands += $cat
    }

    $cat.Children += @{ Name=$name; Command=$commandText }

    $json | ConvertTo-Json -Depth 20 | Set-Content $CommandPath
}

function Remove-CommandFromJson {
    param($categoryName, $commandName)

    if (-not (Test-Path $CommandPath)) { return }

    $json = Get-Content $CommandPath -Raw | ConvertFrom-Json
    $category = $json.Commands | Where-Object { $_.Name -eq $categoryName }

    if ($category -and $category.Children) {
        $category.Children = @(
            $category.Children | Where-Object { $_.Name -ne $commandName }
        )
    }

    $json | ConvertTo-Json -Depth 20 | Set-Content $CommandPath
}

function Remove-CategoryFromJson {
    param($categoryName)

    if (-not (Test-Path $CommandPath)) { return }

    $json = Get-Content $CommandPath -Raw | ConvertFrom-Json

    $json.Commands = @(
        $json.Commands | Where-Object { $_.Name -ne $categoryName }
    )

    $json | ConvertTo-Json -Depth 20 | Set-Content $CommandPath
}

function Save-Settings {
    $global:Settings | ConvertTo-Json -Depth 5 | Set-Content $SettingsPath
    }

function Load-Settings {
    $global:Settings = @{}
    if (-not (Test-Path $SettingsPath)) { return }
    $raw = Get-Content $SettingsPath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return }
    (ConvertFrom-Json $raw).psobject.properties | Foreach { $global:Settings[$_.Name] = $_.Value }
}

function Save-CurrentSettings {

    $global:Settings.startDelay=[int]$inpStartDelay.Text
    $global:Settings.keyDelay=[int]$inpKeyDelay.Text
    $global:Settings.lineDelay=[int]$inpLineDelay.Text
    $global:Settings.enterEach=$chkEnter.Checked
    $global:Settings['TopMost']=$form.TopMost
    $global:Settings.InvokeCluster=$chkInvokeCluster.Checked
    $global:Settings.AltTab=$chkAltTab.Checked

    Save-Settings

}

function Load-CommandTree {

    $treeCommands.Nodes.Clear()
    # -----------------------------------------------------
    # Built-in Helper Commands
    # -----------------------------------------------------

    $helperNode = New-Object System.Windows.Forms.TreeNode
    $helperNode.Text = "Helpers"

    $checkLangNode = New-Object System.Windows.Forms.TreeNode
    $checkLangNode.Text = "Check Language Culture"
    $checkLangNode.Tag  = "([system.windows.forms.inputlanguage]::DefaultInputLanguage).culture.name"

    $helperNode.Nodes.Add($checkLangNode) | Out-Null
    $treeCommands.Nodes.Add($helperNode) | Out-Null

    Ensure-CommandFile

    $json = Get-Content $CommandPath -Raw | ConvertFrom-Json

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
                $childNode.Tag = $child.Command
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

                $catNode.Nodes.Add($child)
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
                    -not ($child.Tag -and $child.Tag.ToLower().Contains($query))) {

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
                    -not ($child.Tag -and $child.Tag.ToLower().Contains($query))) {

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
# ADD COMMAND DIALOG
# =====================================================

function Show-AddCommandDialog {
    param(
        [string]$defaultCommand = "",
        [string]$defaultName = "",
        [bool]$restoreTopMost = $false
    )

    Ensure-CommandFile

    # Temporarily disable Always On Top
    $previousTopMost = $form.TopMost
    if ($previousTopMost) {
        $form.TopMost = $false
        $btnTop.Text = "Always On Top: OFF"
    }

    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = "Add New Command"
    $dialog.Size = New-Object Drawing.Size(560,510)
    $dialog.StartPosition = "CenterParent"
    $dialog.AutoScaleMode = "None"

    $lblCat = New-Object Windows.Forms.Label
    $lblCat.Text = "Category:"
    $lblCat.SetBounds(20,20,120,25)

    $cmbCat = New-Object Windows.Forms.ComboBox
    $cmbCat.SetBounds(150,20,360,28)
    $cmbCat.DropDownStyle = "DropDown"

    $json = Get-Content $CommandPath -Raw | ConvertFrom-Json
    foreach ($c in $json.Commands) { $cmbCat.Items.Add($c.Name) | Out-Null }

    $lblName = New-Object Windows.Forms.Label
    $lblName.Text = "Display Name:"
    $lblName.SetBounds(20,65,120,25)

    $txtName = New-Object Windows.Forms.TextBox
    $txtName.SetBounds(150,65,360,28)
    $txtName.Text = $defaultName

    $lblCmd = New-Object Windows.Forms.Label
    $lblCmd.Text = "Command:"
    $lblCmd.SetBounds(20,110,120,25)

    $txtCmd = New-Object Windows.Forms.TextBox
    $txtCmd.SetBounds(20,140,490,260)
    $txtCmd.Multiline = $true
    $txtCmd.ScrollBars = "Vertical"
    $txtCmd.Font = New-Object Drawing.Font("Consolas",14)
    $txtCmd.Text = $defaultCommand

    $btnSave = New-Object Windows.Forms.Button
    $btnSave.Text = "Save"
    $btnSave.SetBounds(300,410,90,35)

    $btnCancel = New-Object Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.SetBounds(400,410,90,35)

    $btnSave.Add_Click({
        if (-not $cmbCat.Text -or -not $txtName.Text -or -not $txtCmd.Text) {
            [System.Windows.Forms.MessageBox]::Show("All fields required.")
            return
        }

        Add-CommandToJson $cmbCat.Text $txtName.Text $txtCmd.Text
        Load-CommandTree
        $dialog.Close()
    })

    $btnCancel.Add_Click({ $dialog.Close() })

    $dialog.Controls.AddRange(@(
        $lblCat,$cmbCat,
        $lblName,$txtName,
        $lblCmd,$txtCmd,
        $btnSave,$btnCancel
    ))

    $dialog.ShowDialog()
}


# =====================================================
# TYPING ENGINE
# =====================================================

function Send-CharacterSafe {
    param($text,$delay)

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

    $text = $txtInput.Text
    if ($text -eq $PLACEHOLDER_TEXT) { return }
    if ([string]::IsNullOrWhiteSpace($text)) { return }

    if ($chkInvokeCluster.Checked) {
        $normalized = ($text -replace "`r`n","`n")
        $text = "Invoke-Command -ComputerName (Get-ClusterNode).Name -ScriptBlock { $normalized }"
    }

    Maybe-AddToHistory $text

    $startDelay = [int]$inpStartDelay.Text
    $keyDelay   = [int]$inpKeyDelay.Text
    $lineDelay  = [int]$inpLineDelay.Text
    $enterEach  = $chkEnter.Checked

    $lines = ($text -replace "`r`n","`n").Split("`n")

    $global:IsTyping = $true
    $btnType.Enabled = $false
    $btnStop.Enabled = $true

    try {

        Start-Sleep -Seconds $startDelay

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

        $btnType.Enabled = $true
        $btnStop.Enabled = $false

    }
}

# =====================================================
# GUI
# =====================================================

$form = New-Object Windows.Forms.Form
$form.Text = $APP_TITLE
$form.Size = New-Object Drawing.Size(1100,800)
$form.StartPosition = "CenterScreen"
$form.AutoScaleMode = "None"

# =====================================================
# MENU BAR
# =====================================================

$menuStrip = New-Object System.Windows.Forms.MenuStrip

$menuHelp = New-Object System.Windows.Forms.ToolStripMenuItem
$menuHelp.Text = "Help"
$menuHelp.Font = New-Object Drawing.Font("Consolas",9)

$menuDocs = New-Object System.Windows.Forms.ToolStripMenuItem
$menuDocs.Text = "Documentation"

$menuQuick = New-Object System.Windows.Forms.ToolStripMenuItem
$menuQuick.Text = "Quick Start"

$menuHelp.DropDownItems.Add($menuDocs)
$menuHelp.DropDownItems.Add($menuQuick)

$menuStrip.Items.Add($menuHelp)

$form.MainMenuStrip = $menuStrip
$form.Controls.Add($menuStrip)

# Open GitHub Documentation
$menuDocs.Add_Click({
    Start-Process "https://github.com/DellProSupportGse/Tools/blob/main/KeyRelayREADME.md"
})

# Open Quick Start
$menuQuick.Add_Click({
    Start-Process "https://github.com/DellProSupportGse/Tools/blob/main/KeyRelayQuickStart.md"
})


$txtInput = New-Object Windows.Forms.TextBox
$txtInput.Multiline = $true
$txtInput.ScrollBars = "Vertical"
$txtInput.Font = New-Object Drawing.Font("Consolas",14)
$txtInput.SetBounds(12,40,750,470)
$txtInput.Add_KeyDown({
    if ($_.Control -and $_.KeyCode -eq 'A') {
        $txtInput.SelectAll()
        $_.SuppressKeyPress = $true
    }
})

# Placeholder setup
$txtInput.ForeColor = [System.Drawing.Color]::Black
$txtInput.Text = $PLACEHOLDER_TEXT

$lblSearch = New-Object Windows.Forms.Label
$lblSearch.Text = "Search:"
$lblSearch.SetBounds(780,545,60,25)

$txtSearch = New-Object Windows.Forms.TextBox
$txtSearch.SetBounds(840,543,230,25)
$txtSearch.Text = "Search commands..."
$txtSearch.ForeColor = [System.Drawing.Color]::Gray

$tabRight = New-Object Windows.Forms.TabControl
$tabRight.SetBounds(780,40,290,490)

$tabCommands = New-Object Windows.Forms.TabPage
$tabCommands.Text = "My Commands"
$tabCommands.Font = New-Object Drawing.Font("Consolas",10)

$tabShared = New-Object Windows.Forms.TabPage
$tabShared.Text = "Shared"
$tabShared.Font = New-Object Drawing.Font("Consolas",10)

$treeShared = New-Object Windows.Forms.TreeView
$treeShared.Dock = "Fill"
$treeShared.ShowNodeToolTips = $true

$tabShared.Controls.Add($treeShared)

$treeCommands = New-Object Windows.Forms.TreeView
$treeCommands.Dock = "Fill"
$tabCommands.Controls.Add($treeCommands)

$tabHistory = New-Object Windows.Forms.TabPage
$tabHistory.Text = "History"
$tabHistory.Font = New-Object Drawing.Font("Consolas",10)

$lstHistory = New-Object Windows.Forms.ListBox
$lstHistory.Dock = "Fill"
$tabHistory.Controls.Add($lstHistory)

$tabRight.TabPages.Add($tabCommands)
$tabRight.TabPages.Add($tabShared)
$tabRight.TabPages.Add($tabHistory)


# =====================================================
# CONTEXT MENU (Tree)
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
$treeShared.ContextMenuStrip = $treeMenu

$script:RightClickedNode = $null

$treeCommands.Add_NodeMouseClick({
    param($sender,$e)

    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {

        $treeCommands.SelectedNode = $e.Node
        $script:RightClickedNode = $e.Node

        if ($e.Node.Tag) {
            # Leaf (command)
            $menuCopyCommand.Visible = $true
            $menuEditCommand.Visible = $true
            $menuRemoveCommand.Visible = $true
            $menuRemoveCategory.Visible = $false
        }
        else {
            # Category
            $menuCopyCommand.Visible = $false
            $menuEditCommand.Visible = $false
            $menuRemoveCommand.Visible = $false
            $menuRemoveCategory.Visible = $true
        }

    }
})

$treeShared.Add_NodeMouseClick({
    param($sender,$e)

    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {

        $treeShared.SelectedNode = $e.Node
        $script:RightClickedNode = $e.Node

        if ($e.Node.Tag) {
            # Leaf (command)
            $menuCopyCommand.Visible = $true
            $menuEditCommand.Visible = $false
            $menuRemoveCommand.Visible = $false
            $menuRemoveCategory.Visible = $false
        }
        else {
            # Category
            $menuCopyCommand.Visible = $false
            $menuEditCommand.Visible = $false
            $menuRemoveCommand.Visible = $false
            $menuRemoveCategory.Visible = $false
        }

    }
})


$treeShared.Add_NodeMouseDoubleClick({
param($sender,$e)

if ($e.Node.Tag) {
    $txtInput.Text = $e.Node.Tag
}

})


# Edit Command (leaf)
$menuEditCommand.Add_Click({

    if (-not $script:RightClickedNode) { return }

    $commandName  = $script:RightClickedNode.Text
    $categoryName = $script:RightClickedNode.Parent.Text
    $commandText  = $script:RightClickedNode.Tag

    # Remove existing command
    Remove-CommandFromJson $categoryName $commandName

    # Open dialog prefilled so user can edit it
    Show-AddCommandDialog $commandText $commandName
})

# Remove Command (leaf)
$menuRemoveCommand.Add_Click({

    if (-not $script:RightClickedNode) { return }

    $commandName  = $script:RightClickedNode.Text
    $categoryName = $script:RightClickedNode.Parent.Text

    Remove-CommandFromJson $categoryName $commandName
    Load-CommandTree
})

# Remove Category (branch)
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


Load-Settings
if ($global:Settings.count -eq 0) {
   $global:Settings=@{}
   $global:Settings.startDelay=4
   $global:Settings.keyDelay=35
   $global:Settings.lineDelay=120
   $global:Settings.enterEach=$true
   $global:Settings.TopMost=$false
   $global:Settings.InvokeCluster=$false
   $global:Settings.AltTab=$false
   Save-Settings
}

# Right Buttons
$btnReload = New-Object Windows.Forms.Button
$btnReload.Text = "Reload Commands"
$btnReload.SetBounds(780,580,290,30)

$btnAdd = New-Object Windows.Forms.Button
$btnAdd.Text = "Add Command"
$btnAdd.SetBounds(780,615,290,30)

$btnAddHist = New-Object Windows.Forms.Button
$btnAddHist.Text = "Add From History"
$btnAddHist.SetBounds(780,650,290,30)

$btnClearHist = New-Object Windows.Forms.Button
$btnClearHist.Text = "Clear History"
$btnClearHist.SetBounds(780,685,290,30)

# Bottom panel
$panelBottom = New-Object Windows.Forms.Panel
$panelBottom.SetBounds(12,530,750,200)

$lblStart = New-Object Windows.Forms.Label
$lblStart.Text = "Start Delay (sec)"
$lblStart.SetBounds(10,10,110,25)

$inpStartDelay = New-Object Windows.Forms.TextBox
$inpStartDelay.Text = "4"
$inpStartDelay.SetBounds(125,8,30,25)

$lblKey = New-Object Windows.Forms.Label
$lblKey.Text = "Per-Key Delay (ms)"
$lblKey.SetBounds(165,10,130,25)

$inpKeyDelay = New-Object Windows.Forms.TextBox
$inpKeyDelay.Text = "35"
$inpKeyDelay.SetBounds(300,8,30,25)

$lblLine = New-Object Windows.Forms.Label
$lblLine.Text = "Between Lines (ms)"
$lblLine.SetBounds(340,10,130,25)

$inpLineDelay = New-Object Windows.Forms.TextBox
$inpLineDelay.Text = "120"
$inpLineDelay.SetBounds(475,8,30,25)

$chkEnter = New-Object Windows.Forms.CheckBox
$chkEnter.Text = "Press Enter After Each Line"
$chkEnter.Checked = $true
$chkEnter.SetBounds(10,45,250,25)

$chkInvokeCluster = New-Object Windows.Forms.CheckBox
$chkInvokeCluster.Text = "Run on Cluster Nodes"
$chkInvokeCluster.SetBounds(265,45,170,25)
$panelBottom.Controls.Add($chkInvokeCluster)

$chkAltTab = New-Object Windows.Forms.CheckBox
$chkAltTab.Text = "Select Previous Window on Type It"
$chkAltTab.SetBounds(475,45,250,25)
$panelBottom.Controls.Add($chkAltTab)

$lblLayout = New-Object Windows.Forms.Label
$lblLayout.Text = "Target Lang (ex: fr-FR)"
$lblLayout.SetBounds(520,10,180,25)

$txtLayout = New-Object Windows.Forms.TextBox
$txtLayout.SetBounds(700,10,40,25)
$txtLayout.Text = $global:OriginalKeyboardLayout
$options = @("en-US", "zh-CN", "en-GB", "fr-CA","es-ES", "ar-SA", "pt-BR", "fr-FR", "ja-JP", "ru-RU", "de-DE", "hi-IN")
$txtLayout.AutoCompleteMode = 'SuggestAppend'
$txtLayout.AutoCompleteSource = 'CustomSource'
$txtLayout.AutoCompleteCustomSource.AddRange($options)

$panelBottom.Controls.AddRange(@($lblLayout,$txtLayout))

$btnType = New-Object Windows.Forms.Button
$btnType.Text = "Type It"
$btnType.SetBounds(10,90,100,35)

$btnStop = New-Object Windows.Forms.Button
$btnStop.Text = "STOP"
$btnStop.SetBounds(120,90,100,35)
$btnStop.Enabled = $false

$btnClear = New-Object Windows.Forms.Button
$btnClear.Text = "Clear Editor"
$btnClear.SetBounds(230,90,120,35)

$btnTop = New-Object Windows.Forms.Button
$btnTop.Text = "Always On Top: OFF"
$btnTop.SetBounds(370,90,180,35)

$btnExit = New-Object Windows.Forms.Button
$btnExit.Text = "Exit"
$btnExit.SetBounds(560,90,100,35)

$panelBottom.Controls.AddRange(@(
$lblStart,$inpStartDelay,
$lblKey,$inpKeyDelay,
$lblLine,$inpLineDelay,
$chkEnter,
$btnType,$btnStop,$btnClear,$btnTop,$btnExit
))

$form.Controls.AddRange(@(
$txtInput,$tabRight,
$lblSearch,$txtSearch,
$btnReload,$btnAdd,$btnAddHist,$btnClearHist,
$panelBottom
))


$inpStartDelay.Text=$global:Settings.startDelay.ToString()
$inpKeyDelay.Text=$global:Settings.keyDelay.ToString()
$inpLineDelay.Text=$global:Settings.lineDelay.ToString()
$chkEnter.Checked=[bool]$global:Settings.enterEach
$enterEach = $chkEnter.Checked
$form.TopMost=[bool]$global:Settings.TopMost
$chkInvokeCluster.Checked=[bool]$global:Settings.InvokeCluster
$chkAltTab.Checked=[bool]$global:Settings.AltTab

$btnTop.Text = "Always On Top: " + ($(if($form.TopMost){"ON"}else{"OFF"}))

# EVENTS
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


# Placeholder behavior (corrected)
$txtInput.Add_GotFocus({
    if ($txtInput.Text -eq $PLACEHOLDER_TEXT) {
        # Keep placeholder visible when form opens
        $txtInput.SelectAll()
    }
})

$txtInput.Add_KeyDown({
    if ($txtInput.Text -eq $PLACEHOLDER_TEXT) {
        $txtInput.Text = ""
        $txtInput.ForeColor = [System.Drawing.Color]::Black
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
$inpKeyDelay.Add_Leave({
    Save-CurrentSettings
})
$inpStartDelay.Add_Leave({
    Save-CurrentSettings
})
$inpLineDelay.Add_Leave({
    Save-CurrentSettings
})
$chkEnter.Add_Leave({
    Save-CurrentSettings
})
$chkAltTab.Add_Leave({
    Save-CurrentSettings
})

$btnType.Add_Click({ [void](Start-Typing) })
$btnStop.Add_Click({
    $global:IsTyping = $false
})

$btnClear.Add_Click({ $txtInput.Clear() })
$btnExit.Add_Click({
    Save-CurrentSettings
$form.Close() })

$btnTop.Add_Click({
        $form.TopMost = -not $form.TopMost
    Save-CurrentSettings
        $btnTop.Text = "Always On Top: " + ($(if($form.TopMost){"ON"}else{"OFF"}))
})
$form.Add_Closing({param($sender,$e)
    Save-CurrentSettings
})


$btnReload.Add_Click({
    Load-CommandTree
    Load-SharedCommands
})

$btnAdd.Add_Click({ Show-AddCommandDialog "" "" })

$btnAddHist.Add_Click({
if ($lstHistory.SelectedIndex -lt 0) {
[System.Windows.Forms.MessageBox]::Show("Select a history item first.")
return
}
$cmd = $global:History[$lstHistory.SelectedIndex]
$defaultName = ($cmd -split "`r?`n")[0]
Show-AddCommandDialog $cmd $defaultName
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

        # Clear memory
        $global:History = @()

        # Clear UI
        $lstHistory.Items.Clear()

        # Force write empty JSON array
        Set-Content -Path $HistoryPath -Value "[]"
    }
})



$treeCommands.Add_NodeMouseDoubleClick({
param($sender,$e)
if ($e.Node.Tag) { $txtInput.Text = $e.Node.Tag }
})

$lstHistory.Add_DoubleClick({
if ($lstHistory.SelectedIndex -ge 0) {
$txtInput.Text = $global:History[$lstHistory.SelectedIndex]
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