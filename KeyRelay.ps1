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

$APP_VERSION = "1.3.0"

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
    $loaded = $raw | ConvertFrom-Json
    if ($loaded.GetHashCode()) {
        $global:Settings.startDelay=[int]$loaded.startDelay
        $global:Settings.keyDelay=[int]$loaded.keyDelay
        $global:Settings.lineDelay=[int]$loaded.lineDelay
        $global:Settings.enterEach=[bool]$loaded.enterEach
        $global:Settings.TopMost=[bool]$loaded.TopMost
    }
}

function Load-CommandTree {

    $treeCommands.Nodes.Clear()
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
    $dialog.Size = New-Object Drawing.Size(560,500)
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
    $txtCmd.Font = New-Object Drawing.Font("Consolas",10)
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

        if ($specialChars.Contains($char)) {
            [System.Windows.Forms.SendKeys]::SendWait("{$char}")
        }
        else {
            [System.Windows.Forms.SendKeys]::SendWait($char)
        }

        Start-Sleep -Milliseconds $delay
    }
}


function Start-Typing {

    if ($global:IsTyping) { return }

    $text = $txtInput.Text
    if ($text -eq $PLACEHOLDER_TEXT) { return }
    if ([string]::IsNullOrWhiteSpace($text)) { return }


    Maybe-AddToHistory $text

    $startDelay = [int]$inpStartDelay.Text
    $keyDelay   = [int]$inpKeyDelay.Text
    $lineDelay  = [int]$inpLineDelay.Text
    $enterEach  = $chkEnter.Checked

    $lines = ($text -replace "`r`n","`n").Split("`n")

    $global:IsTyping = $true
    Start-Sleep -Seconds $startDelay

    foreach ($line in $lines) {
        if (-not $global:IsTyping) { break }
        Send-CharacterSafe $line $keyDelay
        if ($enterEach) { [System.Windows.Forms.SendKeys]::SendWait("{ENTER}") }
        Start-Sleep -Milliseconds $lineDelay
    }

    $global:IsTyping = $false
}

# =====================================================
# GUI
# =====================================================

$form = New-Object Windows.Forms.Form
$form.Text = $APP_TITLE
$form.Size = New-Object Drawing.Size(1100,800)
$form.StartPosition = "CenterScreen"
$form.AutoScaleMode = "None"

$txtInput = New-Object Windows.Forms.TextBox
$txtInput.Multiline = $true
$txtInput.ScrollBars = "Vertical"
$txtInput.Font = New-Object Drawing.Font("Consolas",10)
$txtInput.SetBounds(12,12,750,500)

# Placeholder setup
$txtInput.ForeColor = [System.Drawing.Color]::Gray
$txtInput.Text = $PLACEHOLDER_TEXT

$tabRight = New-Object Windows.Forms.TabControl
$tabRight.SetBounds(780,12,290,550)

$tabCommands = New-Object Windows.Forms.TabPage
$tabCommands.Text = "Commands"

$treeCommands = New-Object Windows.Forms.TreeView
$treeCommands.Dock = "Fill"
$tabCommands.Controls.Add($treeCommands)

$tabHistory = New-Object Windows.Forms.TabPage
$tabHistory.Text = "History"

$lstHistory = New-Object Windows.Forms.ListBox
$lstHistory.Dock = "Fill"
$tabHistory.Controls.Add($lstHistory)

$tabRight.TabPages.Add($tabCommands)
$tabRight.TabPages.Add($tabHistory)

# =====================================================
# CONTEXT MENU (Tree)
# =====================================================

$treeMenu = New-Object System.Windows.Forms.ContextMenuStrip

$menuRemoveCommand = New-Object System.Windows.Forms.ToolStripMenuItem
$menuRemoveCommand.Text = "Remove Command"

$menuRemoveCategory = New-Object System.Windows.Forms.ToolStripMenuItem
$menuRemoveCategory.Text = "Remove Category"

$treeMenu.Items.AddRange(@(
    $menuRemoveCommand,
    $menuRemoveCategory
))

$treeCommands.ContextMenuStrip = $treeMenu

$script:RightClickedNode = $null

$treeCommands.Add_NodeMouseClick({
    param($sender,$e)

    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {

        $treeCommands.SelectedNode = $e.Node
        $script:RightClickedNode = $e.Node

        if ($e.Node.Tag) {
            # Leaf
            $menuRemoveCommand.Visible = $true
            $menuRemoveCategory.Visible = $false
        }
        else {
            # Category (branch)
            $menuRemoveCommand.Visible = $false
            $menuRemoveCategory.Visible = $true
        }
    }
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

Load-Settings
if ($global:Settings.count -eq 0) {
   $global:Settings=@{}
   $global:Settings.startDelay=4
   $global:Settings.keyDelay=35
   $global:Settings.lineDelay=120
   $global:Settings.enterEach=$true
   $global:Settings.TopMost=$false
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
$lblStart.SetBounds(10,10,120,25)

$inpStartDelay = New-Object Windows.Forms.TextBox
$inpStartDelay.Text = "4"
$inpStartDelay.SetBounds(140,8,50,25)

$lblKey = New-Object Windows.Forms.Label
$lblKey.Text = "Per-Key Delay (ms)"
$lblKey.SetBounds(210,10,130,25)

$inpKeyDelay = New-Object Windows.Forms.TextBox
$inpKeyDelay.Text = "35"
$inpKeyDelay.SetBounds(350,8,50,25)

$lblLine = New-Object Windows.Forms.Label
$lblLine.Text = "Between Lines (ms)"
$lblLine.SetBounds(420,10,140,25)

$inpLineDelay = New-Object Windows.Forms.TextBox
$inpLineDelay.Text = "120"
$inpLineDelay.SetBounds(570,8,60,25)

$chkEnter = New-Object Windows.Forms.CheckBox
$chkEnter.Text = "Press Enter After Each Line"
$chkEnter.Checked = $true
$chkEnter.SetBounds(10,45,250,25)

$btnType = New-Object Windows.Forms.Button
$btnType.Text = "Type It"
$btnType.SetBounds(10,90,100,35)

$btnStop = New-Object Windows.Forms.Button
$btnStop.Text = "STOP"
$btnStop.SetBounds(120,90,100,35)

$btnClear = New-Object Windows.Forms.Button
$btnClear.Text = "Clear Editor"
$btnClear.SetBounds(230,90,120,35)

$btnTop = New-Object Windows.Forms.Button
$btnTop.Text = "Always On Top: OFF"
$btnTop.SetBounds(370,90,170,35)

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
$btnReload,$btnAdd,$btnAddHist,$btnClearHist,
$panelBottom
))

$inpStartDelay.Text=$global:Settings.startDelay.ToString()
$inpKeyDelay.Text=$global:Settings.keyDelay.ToString()
$inpLineDelay.Text=$global:Settings.lineDelay.ToString()
$chkEnter.Checked=[bool]$global:Settings.enterEach
$enterEach = $chkEnter.Checked
$form.TopMost=[bool]$global:Settings.TopMost
$btnTop.Text = "Always On Top: " + ($(if($form.TopMost){"ON"}else{"OFF"}))

# EVENTS

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
        $global:Settings.startDelay=$inpStartDelay.Text
        $global:Settings.keyDelay=$inpKeyDelay.Text
        $global:Settings.lineDelay=$inpLineDelay.Text
        $global:Settings.enterEach=$chkEnter.Checked
        $global:Settings['TopMost']=$form.TopMost
        Save-Settings
})
$inpStartDelay.Add_Leave({
        $global:Settings.startDelay=[int]$inpStartDelay.Text
        $global:Settings.keyDelay=[int]$inpKeyDelay.Text
        $global:Settings.lineDelay=[int]$inpLineDelay.Text
        $global:Settings.enterEach=$chkEnter.Checked
        $global:Settings['TopMost']=$form.TopMost
        Save-Settings
})
$inpLineDelay.Add_Leave({
        $global:Settings.startDelay=[int]$inpStartDelay.Text
        $global:Settings.keyDelay=[int]$inpKeyDelay.Text
        $global:Settings.lineDelay=[int]$inpLineDelay.Text
        $global:Settings.enterEach=$chkEnter.Checked
        $global:Settings['TopMost']=$form.TopMost
        Save-Settings
})
$chkEnter.Add_Leave({
        $global:Settings.startDelay=[int]$inpStartDelay.Text
        $global:Settings.keyDelay=[int]$inpKeyDelay.Text
        $global:Settings.lineDelay=[int]$inpLineDelay.Text
        $global:Settings.enterEach=$chkEnter.Checked
        $global:Settings['TopMost']=$form.TopMost
        Save-Settings
})


$btnType.Add_Click({ Start-Typing })
$btnStop.Add_Click({ $global:IsTyping=$false })
$btnClear.Add_Click({ $txtInput.Clear() })
$btnExit.Add_Click({
        $global:Settings.startDelay=[int]$inpStartDelay.Text
        $global:Settings.keyDelay=[int]$inpKeyDelay.Text
        $global:Settings.lineDelay=[int]$inpLineDelay.Text
        $global:Settings.enterEach=$chkEnter.Checked
        $global:Settings['TopMost']=$form.TopMost
        Save-Settings
$form.Close() })

$btnTop.Add_Click({
        $form.TopMost = -not $form.TopMost
        $global:Settings.startDelay=[int]$inpStartDelay.Text
        $global:Settings.keyDelay=[int]$inpKeyDelay.Text
        $global:Settings.lineDelay=[int]$inpLineDelay.Text
        $global:Settings.enterEach=$chkEnter.Checked
        $global:Settings['TopMost']=$form.TopMost
        Save-Settings
        $btnTop.Text = "Always On Top: " + ($(if($form.TopMost){"ON"}else{"OFF"}))
})

$btnReload.Add_Click({ Load-CommandTree })
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
$form.Activate()
})

[void]$form.ShowDialog()
}