<#

.SYNOPSIS

    Azure Local Action Plan Reader (v37)



.DESCRIPTION

    Read-only Windows Forms dashboard for running and historical Azure

    Local action plans. Reads ProgressAsXml from Get-ActionPlanInstances and

    displays Action, Step, and Task progress in a refreshable grid.



.FEATURES

    - Automatically reads running plans; offers historical plan selection when idle

    - Auto-refresh with configurable interval

    - Tracks selected steps between refreshes

    - Reorder, resize, show, and hide grid columns

    - Filter to active/failed entries and export progress XML



.REQUIREMENTS

    Windows PowerShell 5.1, Windows Forms, and access to the Azure Local

    Get-ActionPlanInstances cmdlet.



.NOTES

    Script:  AzL-ActionPlanReader-v37.ps1

    Version: 36

    Mode:    Read-only; does not modify action plans

#>



Add-Type -AssemblyName System.Windows.Forms

Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()



$form = New-Object Windows.Forms.Form

$form.Text = 'Azure Local | Action Plan Reader v37'

$form.Size = New-Object Drawing.Size(1250,780)

$form.StartPosition = 'CenterScreen'

$form.MinimumSize = New-Object Drawing.Size(980,560)

$form.BackColor = [Drawing.Color]::FromArgb(245,247,251)

$form.Font = New-Object Drawing.Font('Segoe UI',9)

$navy = [Drawing.Color]::FromArgb(24,38,61)

$blue = [Drawing.Color]::FromArgb(35,102,218)

$muted = [Drawing.Color]::FromArgb(95,108,126)

$lineColor = [Drawing.Color]::FromArgb(222,229,238)





# Dedicated title and toolbar rows, with no overlap over the grid headers.

$header = New-Object Windows.Forms.Panel

$header.BackColor = $navy

$header.Margin = New-Object Windows.Forms.Padding(0)

$title = New-Object Windows.Forms.Label

$title.Text = 'ACTION PLAN READER'

$title.ForeColor = [Drawing.Color]::White

$title.Font = New-Object Drawing.Font('Segoe UI Semibold',15,[Drawing.FontStyle]::Bold)

$title.SetBounds(20,12,400,32)

$header.Controls.Add($title)

$subtitle = New-Object Windows.Forms.Label

$subtitle.Text = 'AZURE LOCAL  /  LIVE EXECUTION'

$subtitle.ForeColor = [Drawing.Color]::FromArgb(169,194,230)

$subtitle.Font = New-Object Drawing.Font('Segoe UI',8)

$subtitle.SetBounds(22,44,350,18)

$header.Controls.Add($subtitle)

$top = New-Object Windows.Forms.Panel

$top.BackColor = [Drawing.Color]::White

$top.Margin = New-Object Windows.Forms.Padding(0)

$refresh = New-Object Windows.Forms.Button

$refresh.Text = 'Refresh now'; $refresh.SetBounds(18,13,112,32)

$refresh.FlatStyle = 'Flat'; $refresh.FlatAppearance.BorderSize = 0

$refresh.BackColor = $blue; $refresh.ForeColor = [Drawing.Color]::White

$refresh.Font = New-Object Drawing.Font('Segoe UI Semibold',9)

$top.Controls.Add($refresh)

$auto = New-Object Windows.Forms.CheckBox

$auto.Text = 'Auto refresh'; $auto.Checked = $true; $auto.SetBounds(147,18,112,23)

$top.Controls.Add($auto)

$intervalLabel = New-Object Windows.Forms.Label

$intervalLabel.Text = 'Every'; $intervalLabel.SetBounds(266,20,42,20)

$intervalLabel.ForeColor = $muted; $top.Controls.Add($intervalLabel)

$interval = New-Object Windows.Forms.NumericUpDown

$interval.Minimum=5; $interval.Maximum=300; $interval.Value=10

$interval.SetBounds(308,16,58,27); $top.Controls.Add($interval)

$secondsLabel = New-Object Windows.Forms.Label

$secondsLabel.Text = 'sec'; $secondsLabel.SetBounds(374,20,30,20)

$secondsLabel.ForeColor = $muted; $top.Controls.Add($secondsLabel)

$onlyActive = New-Object Windows.Forms.CheckBox

$onlyActive.Text = 'Active / failed only'; $onlyActive.SetBounds(415,18,147,23)

$top.Controls.Add($onlyActive)

$save = New-Object Windows.Forms.Button

$save.Text = 'Export XML'; $save.SetBounds(580,13,112,32)

$save.FlatStyle = 'Flat'; $save.FlatAppearance.BorderColor = $lineColor

$save.BackColor = [Drawing.Color]::White; $save.ForeColor = $navy

$top.Controls.Add($save)

$columnsButton = New-Object Windows.Forms.Button

$columnsButton.Text = 'Columns'; $columnsButton.SetBounds(704,13,105,32)

$columnsButton.FlatStyle = 'Flat'; $columnsButton.FlatAppearance.BorderColor = $lineColor

$columnsButton.BackColor = [Drawing.Color]::White; $columnsButton.ForeColor = $navy

$top.Controls.Add($columnsButton)

$statusPanel = New-Object Windows.Forms.Panel

$statusPanel.BackColor = [Drawing.Color]::White

$statusPanel.Margin = New-Object Windows.Forms.Padding(0)

$label = New-Object Windows.Forms.Label

$label.AutoSize = $false; $label.Text = 'Ready - waiting for running action plan'

$label.ForeColor = $muted; $label.Font = New-Object Drawing.Font('Segoe UI',9)

$label.Dock = 'Fill'; $label.TextAlign = 'MiddleLeft'

$label.Padding = New-Object Windows.Forms.Padding(20,0,0,0)

$progress = New-Object Windows.Forms.ProgressBar

$progress.Dock = 'Right'

$progress.Width = 210

$progress.Style = [Windows.Forms.ProgressBarStyle]::Marquee

$progress.MarqueeAnimationSpeed = 25

$progress.Visible = $false

$statusPanel.Controls.Add($label)

$statusPanel.Controls.Add($progress)

function Set-Loading([bool]$loading, [string]$message = '') {

    $progress.Visible = $loading

    $progress.MarqueeAnimationSpeed = if ($loading) { 25 } else { 0 }

    if ($message) { $label.Text = $message }

}

function Set-RefreshMode([bool]$isHistorical) {

    if ($isHistorical) {

        $auto.Checked = $false

        $auto.Enabled = $false

        $interval.Enabled = $false

    } else {

        $auto.Enabled = $true

        $interval.Enabled = $auto.Checked

    }

}

$detail = New-Object Windows.Forms.DataGridView

$detail.Dock = 'Fill'

$detail.ReadOnly = $true

$detail.AllowUserToAddRows = $false

$detail.AllowUserToDeleteRows = $false

$detail.AllowUserToResizeRows = $false

$detail.RowHeadersVisible = $false

$detail.SelectionMode = 'FullRowSelect'

$detail.MultiSelect = $false

$detail.AutoSizeColumnsMode = 'None'

$detail.ScrollBars = [System.Windows.Forms.ScrollBars]::Both

$detail.AllowUserToResizeColumns = $true

$detail.AllowUserToOrderColumns = $true

$detail.ColumnHeadersHeightSizeMode = 'AutoSize'

$detail.ClipboardCopyMode = 'EnableAlwaysIncludeHeaderText'

$detail.BackgroundColor = [Drawing.Color]::White

$detail.BorderStyle = 'None'

$detail.GridColor = $lineColor

$detail.Font = New-Object Drawing.Font('Segoe UI',9)

$detail.EnableHeadersVisualStyles = $false

$detail.ColumnHeadersDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(234,240,248)

$detail.ColumnHeadersDefaultCellStyle.ForeColor = $navy

$detail.ColumnHeadersDefaultCellStyle.Font = New-Object Drawing.Font('Segoe UI Semibold',9,[Drawing.FontStyle]::Bold)

$detail.ColumnHeadersDefaultCellStyle.SelectionBackColor = [Drawing.Color]::FromArgb(234,240,248)

$detail.ColumnHeadersDefaultCellStyle.SelectionForeColor = $navy

$detail.DefaultCellStyle.BackColor = [Drawing.Color]::White

$detail.DefaultCellStyle.ForeColor = $navy

$detail.DefaultCellStyle.SelectionBackColor = [Drawing.Color]::FromArgb(216,231,255)

$detail.DefaultCellStyle.SelectionForeColor = $navy

$detail.AlternatingRowsDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(247,249,252)

$detail.AlternatingRowsDefaultCellStyle.SelectionBackColor = [Drawing.Color]::FromArgb(216,231,255)

$detail.AlternatingRowsDefaultCellStyle.SelectionForeColor = $navy

$detail.RowTemplate.Height = 29

$detail.CellBorderStyle = 'SingleHorizontal'

$detail.ColumnHeadersBorderStyle = 'Single'



$detail.Columns.Add('Index','Step') | Out-Null

$detail.Columns.Add('Type','Type') | Out-Null

$detail.Columns.Add('Status','Status') | Out-Null

$detail.Columns.Add('Name','Name') | Out-Null

$detail.Columns.Add('Node','Node') | Out-Null

$detail.Columns.Add('Start','Start') | Out-Null

$detail.Columns.Add('End','End') | Out-Null

$detail.Columns.Add('Duration','Duration') | Out-Null

$widths = @(110,75,105,520,115,145,145,105)

for ($c=0; $c -lt $detail.Columns.Count; $c++) { $detail.Columns[$c].Width=$widths[$c] }

# Do not use Fill: it clips long values to the remaining viewport width.

# Each column retains its own width, and the grid scrolls horizontally.

$detail.Columns['Name'].AutoSizeMode = 'None'

$detail.Columns['Name'].Width = 650

$detail.Columns['Name'].MinimumWidth = 100

# Double-click a header divider to fit the complete column content.

$detail.Add_ColumnHeaderMouseDoubleClick({

    param($sender,$e)

    if ($e.ColumnIndex -ge 0) {

        $sender.AutoResizeColumn($e.ColumnIndex, [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::AllCells)

    }

})

$detail.Columns['Name'].DefaultCellStyle.WrapMode = 'False'



# Drag column headers to reorder; right-click a header or use Columns to show/hide.

# Column objects are never recreated during refresh, so order/visibility/width persist.

$columnMenu = New-Object Windows.Forms.ContextMenuStrip

function Update-ColumnMenu {

    $columnMenu.Items.Clear()

    foreach ($col in @($detail.Columns | Sort-Object DisplayIndex)) {

        $item = New-Object Windows.Forms.ToolStripMenuItem

        $item.Text = [string]$col.HeaderText

        $item.Checked = [bool]$col.Visible

        $item.CheckOnClick = $false

        $item.Tag = [string]$col.Name

        $item.Add_Click({

            param($sender,$eventArgs)

            $targetColumn = $detail.Columns[[string]$sender.Tag]

            if ($targetColumn.Visible -and @($detail.Columns | Where-Object { $\_.Visible }).Count -le 1) { return }

            $targetColumn.Visible = -not $targetColumn.Visible

            Update-ColumnMenu

        })

        [void]$columnMenu.Items.Add($item)

    }

    [void]$columnMenu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))

    $reset = New-Object Windows.Forms.ToolStripMenuItem('Reset columns')

    $reset.Add_Click({

        $names = @('Index','Type','Status','Name','Node','Start','End','Duration')

        for ($i=0; $i -lt $names.Count; $i++) {

            $detail.Columns[$names[$i]].Visible = $true

            $detail.Columns[$names[$i]].DisplayIndex = $i

        }

        $defaultWidths = @(110,75,105,650,115,145,145,105)

        for ($i=0; $i -lt $names.Count; $i++) { $detail.Columns[$names[$i]].Width = $defaultWidths[$i] }

        Update-ColumnMenu

    })

    [void]$columnMenu.Items.Add($reset)

}

$columnsButton.Add_Click({

    Update-ColumnMenu

    $columnMenu.Show($columnsButton, (New-Object Drawing.Point(0,$columnsButton.Height)))

})

$detail.Add_ColumnHeaderMouseClick({

    param($sender,$e)

    if ($e.Button -eq [Windows.Forms.MouseButtons]::Right) {

        Update-ColumnMenu

        $columnMenu.Show([Windows.Forms.Cursor]::Position)

    }

})



# Four dedicated layout rows guarantee the grid header remains visible.

$layout = New-Object Windows.Forms.TableLayoutPanel

$layout.Dock = 'Fill'

$layout.ColumnCount = 1

$layout.RowCount = 4

$layout.Margin = New-Object Windows.Forms.Padding(0)

$layout.Padding = New-Object Windows.Forms.Padding(0)

[void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))

[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,70)))

[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,94)))

[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))

[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,34)))

$header.Dock = 'Fill'; $top.Dock = 'Fill'; $detail.Dock = 'Fill'; $statusPanel.Dock = 'Fill'

$detail.Margin = New-Object Windows.Forms.Padding(12,8,12,8)

$detail.ColumnHeadersVisible = $true

$detail.ColumnHeadersHeightSizeMode = [Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::EnableResizing

$detail.ColumnHeadersHeight = 34

$layout.Controls.Add($header,0,0)

$layout.Controls.Add($top,0,1)

# Split view: virtual grid above, error details below. No extra XML parsing on selection.

$split = New-Object Windows.Forms.SplitContainer

$split.Dock = 'Fill'

$split.Orientation = [Windows.Forms.Orientation]::Horizontal

$split.SplitterWidth = 6

$split.Panel1MinSize = 120

$split.Panel2MinSize = 90

$split.Margin = New-Object Windows.Forms.Padding(0)

$detail.Margin = New-Object Windows.Forms.Padding(12,8,12,3)

$split.Panel1.Controls.Add($detail)

$errorPanel = New-Object Windows.Forms.Panel

$errorPanel.Dock = 'Fill'

$errorPanel.BackColor = [Drawing.Color]::White

$errorHeader = New-Object Windows.Forms.Label

$errorHeader.Text = 'SELECT A ROW TO VIEW DETAILS / ERRORS'

$errorHeader.Dock = 'Top'

$errorHeader.Height = 28

$errorHeader.Padding = New-Object Windows.Forms.Padding(12,6,0,0)

$errorHeader.ForeColor = $navy

$errorHeader.Font = New-Object Drawing.Font('Segoe UI Semibold',9)

$errorText = New-Object Windows.Forms.TextBox

$errorText.Multiline = $true

$errorText.ReadOnly = $true

$errorText.ScrollBars = [Windows.Forms.ScrollBars]::Both

$errorText.WordWrap = $false

$errorText.Dock = 'Fill'

$errorText.Font = New-Object Drawing.Font('Consolas',9)

$errorText.BorderStyle = 'None'

$errorText.BackColor = [Drawing.Color]::FromArgb(248,250,253)

$errorText.Text = 'Select a failed step, task, or action to inspect its XML details.'

$errorPanel.Controls.Add($errorText)

# Copy button sits on the right side of the DETAILS header.
$copyDetails = New-Object Windows.Forms.Button
$copyDetails.Text = 'Copy Details'
$copyDetails.Size = New-Object Drawing.Size(112,24)
$copyDetails.Anchor = [Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Right
$copyDetails.FlatStyle = 'Flat'
$copyDetails.FlatAppearance.BorderColor = $lineColor
$copyDetails.BackColor = [Drawing.Color]::White
$copyDetails.ForeColor = $navy
$copyDetails.Font = New-Object Drawing.Font('Segoe UI',8)
$copyDetails.Enabled = $false
$copyDetails.Cursor = [Windows.Forms.Cursors]::Hand
$copyDetailsTimer = New-Object Windows.Forms.Timer
$copyDetailsTimer.Interval = 1800
$copyDetailsTimer.Add_Tick({
    $copyDetailsTimer.Stop()
    $copyDetails.Text = 'Copy Details'
})
$copyDetails.Add_Click({
    if ([string]::IsNullOrWhiteSpace($errorText.Text) -or !$copyDetails.Enabled) { return }
    try {
        $copyText = "Action Plan: $($planNameLabel.Text -replace '^ACTION PLAN: ', '')`r`nInstance ID: $($script:selectedInstanceId)`r`n`r`n$($errorText.Text)"
        [Windows.Forms.Clipboard]::SetText($copyText)
        $copyDetails.Text = 'Copied!'
        $copyDetailsTimer.Stop()
        $copyDetailsTimer.Start()
    } catch {
        [Windows.Forms.MessageBox]::Show("Unable to copy details: $($_.Exception.Message)", 'Action Plan Reader') | Out-Null
    }
})
$errorPanel.Controls.Add($errorHeader)
$errorHeader.Controls.Add($copyDetails)
$copyDetails.Location = New-Object Drawing.Point(0,2)
$errorHeader.Add_Resize({ $copyDetails.Left = [math]::Max(0,$errorHeader.ClientSize.Width - $copyDetails.Width - 12) })
$copyDetails.Left = [math]::Max(0,$errorHeader.ClientSize.Width - $copyDetails.Width - 12)

$split.Panel2.Controls.Add($errorPanel)

$split.Add_SizeChanged({

    if ($split.Height -gt 300 -and !$script:splitInitialized) {

        $script:splitInitialized = $true

        $split.SplitterDistance = [math]::Max(120,[int]($split.Height * 0.67))

    }

})

$layout.Controls.Add($split,0,2)

$layout.Controls.Add($statusPanel,0,3)

$form.Controls.Add($layout)



# One background runspace is used for discovery; no UI thread is blocked by AzL commands.

$pool = [runspacefactory]::CreateRunspacePool(1,1)

$pool.Open()

$script:pending = $null

$script:snapshots = @{}

$script:chosen = ''

$script:lastPoll = [datetime]::MinValue

$script:selectionKey = ''

$script:selectionStatus = ''

$script:rendering = $false

$script:historical = $false

$script:pickerOpen = $false

$script:pickerDismissed = $false

$script:lastRenderedId = ''

$script:lastRenderedXml = ''

$script:statusFont = New-Object Drawing.Font('Segoe UI Semibold',9,[Drawing.FontStyle]::Bold)



function Get-XmlText($value) {

    if ($null -eq $value) { return '' }

    if ($value -is [xml]) { return $value.OuterXml }

    if ($value -is [System.Xml.XmlNode]) { return $value.OuterXml }

    return [string]$value

}

function Start-Poll {

    if ($script:pending) { return }

    $ps = [powershell]::Create()

    $ps.RunspacePool = $pool

    [void]$ps.AddScript({

        $ErrorActionPreference = 'Stop'

        foreach ($item in @(Get-ActionPlanInstances)) {

            # Different Azure Local builds expose timestamps under different properties.

            # Prefer instance-level metadata; fall back to the progress XML timeline.

            $startValue = ''

            $endValue = ''

            foreach ($propertyName in @('StartTimeUtc','StartTime','StartedAt','StartDateTime','CreatedTime','CreationTime')) {

                $property = $item.PSObject.Properties[$propertyName]

                if ($property -and $null -ne $property.Value -and [string]$property.Value -ne '') {

                    $startValue = [string]$property.Value; break

                }

            }

            foreach ($propertyName in @('EndTimeUtc','EndTime','CompletedAt','CompletionTime','EndDateTime','FinishTime')) {

                $property = $item.PSObject.Properties[$propertyName]

                if ($property -and $null -ne $property.Value -and [string]$property.Value -ne '') {

                    $endValue = [string]$property.Value; break

                }

            }

            $xmlText = if ($null -eq $item.ProgressAsXml) { '' } elseif ($item.ProgressAsXml -is [System.Xml.XmlNode]) { $item.ProgressAsXml.OuterXml } else { [string]$item.ProgressAsXml }

            # Avoid scanning every historical ProgressAsXml during discovery.

            # The XML is parsed only for the plan the user actually opens.

            [pscustomobject]@{

                Id = [string]$item.InstanceId

                Status = [string]$item.Status

                Name = if ($item.Name) { [string]$item.Name } elseif ($item.ActionPlanName) { [string]$item.ActionPlanName } else { [string]$item.InstanceId }

                Start = $startValue

                End = $endValue

                Xml = $xmlText

            }

        }

    })

    $handle = $ps.BeginInvoke()

    $script:pending = @{ PowerShell=$ps; Handle=$handle }

    $script:lastPoll = Get-Date

    Set-Loading $true 'Loading action plan instances...'

}



# Centered loading overlay for opening a selected action plan.

$loadOverlay = New-Object Windows.Forms.Panel

$loadOverlay.Size = New-Object Drawing.Size(370,116)

$loadOverlay.BackColor = [Drawing.Color]::White

$loadOverlay.BorderStyle = 'FixedSingle'

$loadOverlay.Visible = $false

$loadTitle = New-Object Windows.Forms.Label

$loadTitle.Text = 'Loading selected action plan...'

$loadTitle.Font = New-Object Drawing.Font('Segoe UI Semibold',11,[Drawing.FontStyle]::Bold)

$loadTitle.ForeColor = $navy

$loadTitle.SetBounds(20,17,330,28)

$loadBar = New-Object Windows.Forms.ProgressBar

$loadBar.SetBounds(20,62,328,22)

$loadBar.Style = [Windows.Forms.ProgressBarStyle]::Marquee

$loadBar.MarqueeAnimationSpeed = 0

$loadOverlay.Controls.AddRange(@($loadTitle,$loadBar))

# Overlay the center of the data grid, not the bottom status bar.

$detail.Controls.Add($loadOverlay)

function Position-LoadOverlay {

    $loadOverlay.Left = [math]::Max(0,[int](($detail.ClientSize.Width - $loadOverlay.Width)/2))

    $loadOverlay.Top = [math]::Max(0,[int](($detail.ClientSize.Height - $loadOverlay.Height)/2))

}

$detail.Add_Resize({ Position-LoadOverlay })

function Show-LoadOverlay {

    Position-LoadOverlay

    $loadOverlay.Visible = $true

    $loadOverlay.BringToFront()

    $loadTitle.Text = "Loading selected action plan..."

    $loadBar.MarqueeAnimationSpeed = 25

    # Give WinForms a chance to paint the indicator before XML rows are built.

    [System.Windows.Forms.Application]::DoEvents()

}

function Hide-LoadOverlay {

    $loadBar.MarqueeAnimationSpeed = 0

    $loadOverlay.Visible = $false

}



function Show-PlanPicker {

    if ($script:pickerOpen) { return }

    $script:pickerOpen = $true

    try {

        $picker = New-Object Windows.Forms.Form

        $picker.Text = 'Select an action plan to load'

        $picker.Size = New-Object Drawing.Size(960,490)

        $picker.MinimumSize = New-Object Drawing.Size(650,350)

        $picker.StartPosition = 'CenterParent'

        $picker.BackColor = [Drawing.Color]::White

        $picker.Font = New-Object Drawing.Font('Segoe UI',9)

        $pickerGrid = New-Object Windows.Forms.DataGridView

        $pickerGrid.Dock = 'Fill'

        $pickerGrid.ReadOnly = $true

        $pickerGrid.AllowUserToAddRows = $false

        $pickerGrid.AllowUserToDeleteRows = $false

        $pickerGrid.RowHeadersVisible = $false

        $pickerGrid.SelectionMode = 'FullRowSelect'

        $pickerGrid.MultiSelect = $false

        $pickerGrid.AutoSizeColumnsMode = 'None'

        $pickerGrid.BackgroundColor = [Drawing.Color]::White

        $pickerGrid.EnableHeadersVisualStyles = $false

        $pickerGrid.ColumnHeadersDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(234,240,248)

        $pickerGrid.ColumnHeadersHeight = 34

        foreach ($col in @(@('Name','Action plan',280),@('Status','Status',110),@('Start','Start',155),@('End','End',155),@('Id','Instance ID',220))) {

            $i = $pickerGrid.Columns.Add($col[0],$col[1]); $pickerGrid.Columns[$i].Width = $col[2]

        }

        foreach ($entry in @($script:snapshots.Values | Sort-Object Start -Descending)) {

            [void]$pickerGrid.Rows.Add($entry.Name,$entry.Status,$entry.Start,$entry.End,$entry.Id)

        }

        $buttons = New-Object Windows.Forms.Panel

        $buttons.Dock = 'Bottom'; $buttons.Height = 58

        $load = New-Object Windows.Forms.Button

        $load.Text = 'Load Selected'; $load.SetBounds(14,12,130,34)

        $load.BackColor = $blue; $load.ForeColor = [Drawing.Color]::White

        $load.FlatStyle = 'Flat'; $load.FlatAppearance.BorderSize = 0

        $load.Add_Click({

            if ($pickerGrid.SelectedRows.Count -eq 0) { return }

            $picker.Tag = [string]$pickerGrid.SelectedRows[0].Cells['Id'].Value

            $picker.DialogResult = [Windows.Forms.DialogResult]::OK

            $picker.Close()

        })

        $cancel = New-Object Windows.Forms.Button

        $cancel.Text = 'Cancel'; $cancel.SetBounds(156,12,100,34)

        $cancel.Add_Click({ $picker.DialogResult = [Windows.Forms.DialogResult]::Cancel; $picker.Close() })

        $buttons.Controls.AddRange(@($load,$cancel))

        $picker.Controls.Add($pickerGrid); $picker.Controls.Add($buttons)

        $picker.AcceptButton = $load

        $pickerGrid.Add_CellDoubleClick({ if ($pickerGrid.SelectedRows.Count -gt 0) { $load.PerformClick() } })

        if ($pickerGrid.Rows.Count -gt 0) { $pickerGrid.Rows[0].Selected = $true }

        if ($picker.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) {

            $script:chosen = [string]$picker.Tag
            Update-PlanIdentity

            $script:historical = $true

            $script:pickerDismissed = $false

            $script:selectionKey = ''; $script:selectionStatus = ''

            Show-LoadOverlay

            try { Show-Selected } finally { Hide-LoadOverlay }

            Set-RefreshMode $true

            $label.Text = "Historical plan | Rows: $($detail.Rows.Count) | $($script:lastLoadTiming)"

        } else { $script:pickerDismissed = $true }

        $picker.Dispose()

    } finally { $script:pickerOpen = $false }

}



function Get-Attribute($element,[string]$name) {

    if ($element -and $element.Attributes -and $element.Attributes[$name]) { return $element.Attributes[$name].Value }

    return ''

}

function Get-LocalTimeText([string]$utc) {

    if ([string]::IsNullOrWhiteSpace($utc)) { return '' }

    try { return ([datetime]::Parse($utc).ToLocalTime()).ToString('yyyy-MM-dd HH:mm:ss') }

    catch { return '' }

}

# Build stable row identities in one pass; avoid repeated sibling scans (quadratic cost).

$script:keyCounters = @{}

function Get-RowKey($element) {

    $parent = $element.ParentNode

    $parentKey = if ($parent -and $script:nodeKeys.ContainsKey($parent)) { $script:nodeKeys[$parent] } else { '' }

    $kind = [string]$element.LocalName

    $identity = ''

    foreach ($field in @('FullStepIndex','RemoteTaskId','Type','ActionType','InterfaceType','Name','RolePath')) {

        $identity = Get-Attribute $element $field

        if ($identity) { break }

    }

    $node = Get-Attribute $element 'RemoteNodeName'

    $counterKey = "$parentKey/$kind\`:$identity\`:$node"

    $ordinal = 0

    if ($script:keyCounters.ContainsKey($counterKey)) { $ordinal = $script:keyCounters[$counterKey] }

    $script:keyCounters[$counterKey] = $ordinal + 1

    $key = "$counterKey\`:$ordinal"

    $script:nodeKeys[$element] = $key

    return $key

}

# Virtual grid: store values in RAM rather than allocating DataGridViewRow objects.

$script:virtualRows = New-Object 'System.Collections.Generic.List[object]'

$detail.VirtualMode = $true

$detail.Add_CellValueNeeded({

    param($sender,$e)

    if ($e.RowIndex -ge 0 -and $e.RowIndex -lt $script:virtualRows.Count -and $e.ColumnIndex -ge 0) {

        $e.Value = $script:virtualRows[$e.RowIndex].Values[$e.ColumnIndex]

    }

})

$detail.Add_CellToolTipTextNeeded({

    param($sender,$e)

    if ($e.RowIndex -ge 0 -and $e.RowIndex -lt $script:virtualRows.Count -and $e.ColumnIndex -eq 3) {

        $e.ToolTipText = $script:virtualRows[$e.RowIndex].Description

    }

})

$detail.Add_CellFormatting({

    param($sender,$e)

    if ($e.ColumnIndex -ne 2 -or $e.RowIndex -lt 0 -or $e.RowIndex -ge $script:virtualRows.Count) { return }

    $status = $script:virtualRows[$e.RowIndex].Status

    $e.CellStyle.Font = $script:statusFont

    switch -Regex ($status) {

        'Fail|Error|Cancel' { $e.CellStyle.ForeColor=[Drawing.Color]::Firebrick; break }

        'InProgress|Running|Pending' { $e.CellStyle.ForeColor=[Drawing.Color]::DarkOrange; break }

        '^Success$' { $e.CellStyle.ForeColor=[Drawing.Color]::ForestGreen; break }

        '^Skipped$' { $e.CellStyle.ForeColor=[Drawing.Color]::Gray; break }

    }

})

# Compile the hot XML-to-row path once. PowerShell remains responsible for UI only.

Add-Type -ReferencedAssemblies @('System.dll','System.Core.dll','System.Xml.dll') -TypeDefinition @'

using System;

using System.Collections.Generic;

using System.Globalization;

using System.Xml;

public sealed class AzlProgressRow {

    public object[] Values { get; set; }

    public string Status { get; set; }

    public string Key { get; set; }

    public string Description { get; set; }

    public XmlElement Element { get; set; }

}

public static class AzlFastProgress {

    static string Attr(XmlElement e, string name) { return e.GetAttribute(name); }

    static string First(XmlElement e, params string[] names) {

        foreach (string n in names) { string v=Attr(e,n); if (!String.IsNullOrEmpty(v)) return v; }

        return "";

    }

    static string Time(string s) {

        if (String.IsNullOrWhiteSpace(s)) return "";

        DateTimeOffset t;

        return DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out t)

            ? t.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss") : "";

    }

    static string Duration(string start, string end) {

        if (String.IsNullOrEmpty(start)) return "";

        DateTimeOffset a,b;

        if (!DateTimeOffset.TryParse(start,CultureInfo.InvariantCulture,DateTimeStyles.AssumeUniversal,out a)) return "";

        if (String.IsNullOrEmpty(end)) b=DateTimeOffset.UtcNow;

        else if (!DateTimeOffset.TryParse(end,CultureInfo.InvariantCulture,DateTimeStyles.AssumeUniversal,out b)) return "";

        TimeSpan d=b-a;

        return d.Ticks<0 ? "" : String.Format(CultureInfo.InvariantCulture,"{0:00}:{1:00}:{2:00}",(long)d.TotalHours,d.Minutes,d.Seconds);

    }

    public static List<AzlProgressRow> Build(XmlDocument doc, bool activeOnly) {

        var rows=new List<AzlProgressRow>(2048);

        var counters=new Dictionary<string,int>(StringComparer.Ordinal);

        var stack=new Stack<Tuple<XmlElement,string>>();

        if (doc.DocumentElement != null) stack.Push(Tuple.Create(doc.DocumentElement,""));

        while (stack.Count>0) {

            var item=stack.Pop(); XmlElement e=item.Item1;

            string kind=e.LocalName;

            string identity=First(e,"FullStepIndex","RemoteTaskId","Type","ActionType","InterfaceType","Name","RolePath");

            string baseKey=item.Item2+"/"+kind+":"+identity+":"+Attr(e,"RemoteNodeName");

            int ordinal; counters.TryGetValue(baseKey,out ordinal); counters[baseKey]=ordinal+1;

            string key=baseKey+":"+ordinal.ToString(CultureInfo.InvariantCulture);

            if (kind=="Action" || kind=="Step" || kind=="Task") {

                string status=Attr(e,"Status");

                bool show=!activeOnly || status.IndexOf("InProgress",StringComparison.OrdinalIgnoreCase)>=0 ||

                    status.IndexOf("Running",StringComparison.OrdinalIgnoreCase)>=0 ||

                    status.IndexOf("Pending",StringComparison.OrdinalIgnoreCase)>=0 ||

                    status.IndexOf("Fail",StringComparison.OrdinalIgnoreCase)>=0 ||

                    status.IndexOf("Error",StringComparison.OrdinalIgnoreCase)>=0 ||

                    status.IndexOf("Cancel",StringComparison.OrdinalIgnoreCase)>=0;

                if (show) {

                    string name=First(e,"Name","Type","ActionType","InterfaceType","RolePath");

                    if (name.Length==0) name=kind;

                    string begin=Attr(e,"StartTimeUtc"), finish=Attr(e,"EndTimeUtc");

                    rows.Add(new AzlProgressRow {

                        Values=new object[]{Attr(e,"FullStepIndex"),kind,status,name.TrimStart(),Attr(e,"RemoteNodeName"),Time(begin),Time(finish),Duration(begin,finish)},

                        Status=status, Key=key, Description=Attr(e,"Description"), Element=e

                    });

                }

            }

            // Reverse push preserves XML document order.

            for (XmlNode child=e.LastChild;child!=null;child=child.PreviousSibling)

                if (child is XmlElement) stack.Push(Tuple.Create((XmlElement)child,key));

        }

        return rows;

    }

}

'@ -ErrorAction Stop



function Show-Selected {

    $oldKey = $script:selectionKey

    $oldStatus = $script:selectionStatus

    $oldFirst = 0

    try { if ($detail.FirstDisplayedScrollingRowIndex -ge 0) { $oldFirst = $detail.FirstDisplayedScrollingRowIndex } } catch {}

    $oldHorizontal = $detail.HorizontalScrollingOffset

    $script:rendering = $true

    $detail.SuspendLayout()

    try {

        $detail.RowCount = 0

        $script:virtualRows.Clear()

        $errorText.Text = "Select a row to view its XML details."
        $copyDetails.Enabled = $false

        Update-PlanIdentity
        if (!$script:chosen -or !$script:snapshots.ContainsKey($script:chosen)) { return }

        $data = $script:snapshots[$script:chosen]

        if (!$data.Xml) { $label.Text = 'No ProgressAsXml returned for the selected instance'; return }

        $loadTitle.Text = 'Parsing action plan XML in memory...'

        $doc = New-Object System.Xml.XmlDocument

        $doc.XmlResolver = $null

        $watch = [System.Diagnostics.Stopwatch]::StartNew()

        $doc.LoadXml($data.Xml)

        $parseMs = $watch.ElapsedMilliseconds

        $builtRows = [AzlFastProgress]::Build($doc, [bool]$onlyActive.Checked)

        foreach ($builtRow in $builtRows) { [void]$script:virtualRows.Add($builtRow) }

        $buildMs = $watch.ElapsedMilliseconds - $parseMs

        $loadTitle.Text = "Displaying $($script:virtualRows.Count) rows..."

        $detail.RowCount = $script:virtualRows.Count

        $gridMs = $watch.ElapsedMilliseconds - $parseMs - $buildMs

        $script:lastLoadTiming = "XML: ${parseMs}ms | Build: ${buildMs}ms | Grid: ${gridMs}ms"

        $script:lastRenderedId = $script:chosen

        $script:lastRenderedXml = $data.Xml

        $detail.ClearSelection()

        $target = -1

        if ($oldKey -and $script:virtualRows.Count -gt 0) {

            for ($i=0; $i -lt $script:virtualRows.Count; $i++) {

                if ($script:virtualRows[$i].Key -eq $oldKey) {

                    $newStatus = [string]$script:virtualRows[$i].Status

                    if ($oldStatus -match '^(InProgress|Running|Pending)$' -and $newStatus -notmatch '^(InProgress|Running|Pending)$') { $target = $script:virtualRows.Count-1 }

                    else { $target = $i }

                    break

                }

            }

            if ($target -lt 0) { $target = $script:virtualRows.Count-1 }

        }

        if ($target -ge 0) {

            $preferred = $detail.Columns['Name']

            if (!$preferred.Visible) { $preferred = @($detail.Columns | Where-Object Visible | Sort-Object DisplayIndex)[0] }

            if ($preferred) { $detail.CurrentCell = $detail.Rows[$target].Cells[$preferred.Index] }

            $detail.Rows[$target].Selected = $true

            $script:selectionKey = [string]$script:virtualRows[$target].Key

            $script:selectionStatus = [string]$script:virtualRows[$target].Status

            try { $detail.FirstDisplayedScrollingRowIndex = [math]::Max(0,$target-5) } catch {}

            Show-RowDetails $target

        } else {

            $script:selectionKey = ''; $script:selectionStatus = ''

            if ($detail.RowCount -gt 0) { try { $detail.FirstDisplayedScrollingRowIndex = [math]::Min($oldFirst,$detail.RowCount-1) } catch {} }

        }

        try { $detail.HorizontalScrollingOffset = $oldHorizontal } catch {}

    } catch { $label.Text = "XML parse error: $($\_.Exception.Message)" }

    finally { $detail.ResumeLayout(); $script:rendering = $false }

}

function Finish-Poll {

    if (!$script:pending -or !$script:pending.Handle.IsCompleted) { return }

    $p=$script:pending; $script:pending=$null

    try {

        $result = @($p.PowerShell.EndInvoke($p.Handle))

        $script:snapshots = @{}

        foreach ($entry in $result) {

            $id = [string]$entry.Id

            if ($id) { $script:snapshots[$id] = $entry }

        }

        $running = @($result | Where-Object { $\_.Status -eq 'Running' })

        if ($running.Count -gt 0) {

            $script:pickerDismissed = $false

            if (!$script:chosen -or !$script:snapshots.ContainsKey($script:chosen) -or $script:historical -or $script:snapshots[$script:chosen].Status -ne 'Running') {

                $script:chosen = [string]$running[0].Id

                $script:selectionKey = ''; $script:selectionStatus = ''

            }

            $script:historical = $false

            Set-RefreshMode $false

            if ($script:lastRenderedId -ne $script:chosen -or $script:lastRenderedXml -cne $script:snapshots[$script:chosen].Xml) { Show-Selected }

            $label.Text = "Running action plans: $($running.Count) | Rows: $($detail.Rows.Count) | Updated: $((Get-Date).ToString('HH:mm:ss'))"

        } else {

            if ($script:historical -and $script:chosen -and $script:snapshots.ContainsKey($script:chosen)) {

                if ($script:lastRenderedId -ne $script:chosen -or $script:lastRenderedXml -cne $script:snapshots[$script:chosen].Xml) { Show-Selected }

                $label.Text = "Historical action plan: $($script:chosen) | Rows: $($detail.Rows.Count) | Updated: $((Get-Date).ToString('HH:mm:ss'))"

            } else {

                $script:chosen = ''; $script:historical = $false

                Set-RefreshMode $true

                $detail.RowCount = 0

                $script:virtualRows.Clear()

                $label.Text = "No running action plans | Available instances: $($script:snapshots.Count)"

                if ($script:snapshots.Count -gt 0 -and !$script:pickerDismissed) {

                    # Defer the modal dialog until after the poll finishes.

                    $form.BeginInvoke([Action]{ Show-PlanPicker }) | Out-Null

                }

            }

        }

    } catch { $label.Text="Discovery error: $($\_.Exception.Message)" }

    finally { Set-Loading $false; $p.PowerShell.Dispose() }

}

# Extract detail only for the clicked row; retain original XML elements in RAM.

function Show-RowDetails([int]$index) {

    if ($index -lt 0 -or $index -ge $script:virtualRows.Count) { return }

    try {

        $item = $script:virtualRows[$index]

        $element = $item.Element

        if ($null -eq $element) { return }

        $kind = [string]$item.Values[1]

        $status = [string]$item.Status

        $errorHeader.Text = "DETAILS  /  $kind  /  $status  /  $($item.Values[3])"

        $lines = New-Object 'System.Collections.Generic.List[string]'

        [void]$lines.Add("$kind DETAILS")

        [void]$lines.Add("Name: $($item.Values[3])")

        [void]$lines.Add("Status: $status")

        if ($item.Values[0]) { [void]$lines.Add("Step: $($item.Values[0])") }

        if ($item.Values[4]) { [void]$lines.Add("Node: $($item.Values[4])") }

        foreach ($field in @('Start','End','Duration')) {

            $column = @{ Start=5; End=6; Duration=7 }[$field]

            if ($item.Values[$column]) { [void]$lines.Add("${field}: $($item.Values[$column])") }

        }

        [void]$lines.Add('')

        [void]$lines.Add('DESCRIPTION')

        $description = [string]$element.GetAttribute('Description')

        if ([string]::IsNullOrWhiteSpace($description)) { $description = [string]$element.GetAttribute('Descriptions') }

        if ([string]::IsNullOrWhiteSpace($description)) { $description = '(No description provided for this element)' }

        [void]$lines.Add($description)

        [void]$lines.Add('')

        [void]$lines.Add('XML ATTRIBUTES')

        foreach ($attribute in $element.Attributes) {

            if ($attribute.Name -in @('Description','Descriptions')) { continue }

            [void]$lines.Add("$($attribute.Name): $($attribute.Value)")

        }

        # Only inspect exception nodes when an error is involved. Avoid scanning

        # the complete XML subtree for successful actions/steps/tasks.

        if ($status -match '(?i)error|fail|cancel') {

            [void]$lines.Add('')

            [void]$lines.Add('FAILURE DETAILS')

            # Limit inspection to exception nodes belonging to the selected item.

            # For parent Action/Step rows, avoid traversing thousands of descendant tasks.

            $exceptions = $element.SelectNodes('./Exception | ./Error/Exception | ./Task/Exception | ./Task/Error/Exception')

            $exceptionCount = 0

            foreach ($exception in $exceptions) {

                if ($exceptionCount -ge 5) {

                    [void]$lines.Add('Additional exceptions omitted (first 5 shown).')

                    break

                }

                $exceptionCount++

                [void]$lines.Add("Exception #$exceptionCount")

                foreach ($field in @('Message','MachineName','StackTrace','Raw')) {

                    $child = $exception.SelectSingleNode($field)

                    if ($null -ne $child -and ![string]::IsNullOrWhiteSpace($child.InnerText)) {

                        [void]$lines.Add("${field}:")

                        $detailValue = [string]$child.InnerText

                        if ($detailValue.Length -gt 12000) { $detailValue = $detailValue.Substring(0,12000) + ' ... [truncated]' }

                        [void]$lines.Add($detailValue)

                    }

                }

                foreach ($attr in $exception.Attributes) {

                    [void]$lines.Add("$($attr.Name): $($attr.Value)")

                }

                [void]$lines.Add('')

            }

            if ($exceptionCount -eq 0) {

                [void]$lines.Add('No Exception element is present beneath the selected item.')

                [void]$lines.Add('The status alone does not establish the underlying failure reason.')

            }

        }

        $errorText.Text = [string]::Join([Environment]::NewLine,$lines)
        $copyDetails.Enabled = $true

        $errorText.SelectionStart = 0

        $errorText.SelectionLength = 0

        $errorText.ScrollToCaret()

    } catch {

        $errorText.Text = "Unable to display selected row details: $($\_.Exception.Message)"

    }

}

$detail.Add_SelectionChanged({

    if ($script:rendering) { return }

    if ($detail.SelectedRows.Count -gt 0) {

        $index = $detail.SelectedRows[0].Index

        $tag = if ($index -lt $script:virtualRows.Count) { $script:virtualRows[$index] } else { $null }

        if ($tag) {

            $script:selectionKey = [string]$tag.Key

            $script:selectionStatus = [string]$tag.Status

            Show-RowDetails $index

        }

    }

})

$onlyActive.Add_CheckedChanged({ Show-Selected })

$auto.Add_CheckedChanged({ $interval.Enabled = $auto.Enabled -and $auto.Checked })

$refresh.Add_Click({ $script:pickerDismissed = $false; Start-Poll })

$pickButton = New-Object Windows.Forms.Button

$pickButton.Text = 'Select Plan'; $pickButton.SetBounds(821,13,112,32)

$pickButton.FlatStyle = 'Flat'; $pickButton.FlatAppearance.BorderColor = $lineColor

$pickButton.BackColor = [Drawing.Color]::White; $pickButton.ForeColor = $navy

$top.Controls.Add($pickButton)

# Always-visible selected plan identity. The ID field can be selected/copied.
$planIdentity = New-Object Windows.Forms.Panel
$planIdentity.Dock = 'Bottom'
$planIdentity.Height = 34
$planIdentity.BackColor = [Drawing.Color]::FromArgb(234,240,248)

$planNameLabel = New-Object Windows.Forms.Label
$planNameLabel.Text = 'ACTION PLAN: None selected'
$planNameLabel.AutoEllipsis = $true
$planNameLabel.ForeColor = $navy
$planNameLabel.Font = New-Object Drawing.Font('Segoe UI Semibold',9)
$planNameLabel.SetBounds(14,7,1095,22)
$planNameLabel.Anchor = 'Top,Left,Right'
$planIdentity.Controls.Add($planNameLabel)

# The full Instance ID is displayed inline next to the action plan name.
# Keep the ID separately in memory for clipboard operations.
$script:selectedInstanceId = ''

$copyId = New-Object Windows.Forms.Button
$copyId.Text = 'Copy ID'
$copyId.SetBounds(1125,5,90,25)
$copyId.Anchor = 'Top,Right'
$copyId.Enabled = $false
$copyId.FlatStyle = 'Flat'
$copyId.FlatAppearance.BorderColor = $lineColor
$copyId.Add_Click({
    if ($script:selectedInstanceId) {
        try { [Windows.Forms.Clipboard]::SetText($script:selectedInstanceId) }
        catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Copy ID failed') | Out-Null }
    }
})
$planIdentity.Controls.Add($copyId)
$top.Controls.Add($planIdentity)

function Update-PlanIdentity {
    if ($script:chosen -and $script:snapshots.ContainsKey($script:chosen)) {
        $entry = $script:snapshots[$script:chosen]
        $name = [string]$entry.Name
        if ([string]::IsNullOrWhiteSpace($name)) { $name = '(Unnamed action plan)' }
        $script:selectedInstanceId = [string]$entry.Id
        $planNameLabel.Text = "ACTION PLAN: $name  [$($entry.Status)]    |    INSTANCE ID: $($script:selectedInstanceId)"
        $planNameLabel.AccessibleDescription = $planNameLabel.Text
        $copyId.Enabled = $true
    } else {
        $planNameLabel.Text = 'ACTION PLAN: None selected'
        $script:selectedInstanceId = ''
        $copyId.Enabled = $false
    }
}


$pickButton.Add_Click({

    if ($script:snapshots.Count -gt 0) { Show-PlanPicker }

    else { [Windows.Forms.MessageBox]::Show('No action plan instances are available.','Action Plan Reader') | Out-Null }

})

$save.Add_Click({

    if (!$script:chosen -or !$script:snapshots.ContainsKey($script:chosen)) { return }

    $dialog=New-Object Windows.Forms.SaveFileDialog

    $dialog.Filter='XML files (*.xml)|*.xml'; $dialog.FileName="AzL-Progress-$($script:chosen).xml"

    if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {

        [IO.File]::WriteAllText($dialog.FileName,$script:snapshots[$script:chosen].Xml,[Text.Encoding]::UTF8)

    }

})

$timer=New-Object Windows.Forms.Timer

$timer.Interval=500

$timer.Add_Tick({

    Finish-Poll

    if ($auto.Enabled -and $auto.Checked -and !$script:historical -and !$script:pickerOpen -and !$script:pending -and ((Get-Date)-$script:lastPoll).TotalSeconds -ge [double]$interval.Value) { Start-Poll }

})

$form.Add_Shown({ $timer.Start(); Start-Poll })

$form.Add_FormClosing({

    $timer.Stop()
    $copyDetailsTimer.Stop()
    $copyDetailsTimer.Dispose()

    if ($script:pending) { try { $script:pending.PowerShell.Stop() } catch {}; $script:pending.PowerShell.Dispose() }

    $script:statusFont.Dispose()

    $pool.Close(); $pool.Dispose()

})

[void]$form.ShowDialog()
