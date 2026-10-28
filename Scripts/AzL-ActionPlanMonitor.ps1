#requires -Version 5.1
<#
.SYNOPSIS
    Azure Local Action Plan Monitor (v14)

.DESCRIPTION
    Read-only Windows Forms dashboard for monitoring currently running Azure
    Local action plans. Reads ProgressAsXml from Get-ActionPlanInstances and
    displays Action, Step, and Task progress in a refreshable grid.

.FEATURES
    - Monitors running action plans only
    - Auto-refresh with configurable interval
    - Tracks selected steps between refreshes
    - Reorder, resize, show, and hide grid columns
    - Filter to active/failed entries and export progress XML

.REQUIREMENTS
    Windows PowerShell 5.1, Windows Forms, and access to the Azure Local
    Get-ActionPlanInstances cmdlet.

.NOTES
    Script:  AzL-ActionPlanMonitor-v14.ps1
    Version: 14
    Mode:    Read-only; does not modify action plans
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object Windows.Forms.Form
$form.Text = 'Azure Local | Action Plan Monitor'
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
$title.Text = 'ACTION PLAN MONITOR'
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
$statusPanel.Controls.Add($label)
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
            if ($targetColumn.Visible -and @($detail.Columns | Where-Object { $_.Visible }).Count -le 1) { return }
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
[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,59)))
[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,34)))
$header.Dock = 'Fill'; $top.Dock = 'Fill'; $detail.Dock = 'Fill'; $statusPanel.Dock = 'Fill'
$detail.Margin = New-Object Windows.Forms.Padding(12,8,12,8)
$detail.ColumnHeadersVisible = $true
$detail.ColumnHeadersHeightSizeMode = [Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::EnableResizing
$detail.ColumnHeadersHeight = 34
$layout.Controls.Add($header,0,0)
$layout.Controls.Add($top,0,1)
$layout.Controls.Add($detail,0,2)
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
        # Match the requested source: only action plans whose Status is Running.
        $results = @(Get-ActionPlanInstances | Where-Object { $_.Status -eq 'Running' })
        foreach ($item in $results) {
            [pscustomobject]@{
                Id = [string]$item.InstanceId
                Status = [string]$item.Status
                Xml = if ($null -eq $item.ProgressAsXml) { '' } else { [string]$item.ProgressAsXml }
            }
        }
    })
    $handle = $ps.BeginInvoke()
    $script:pending = @{ PowerShell=$ps; Handle=$handle }
    $script:lastPoll = Get-Date
    $label.Text = 'Reading running action plans...'
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
function Get-RowKey($element) {
    # XML ancestry identifies repeated step indices on different nodes.
    $parts = New-Object 'System.Collections.Generic.List[string]'
    $current = $element
    while ($current -and $current.NodeType -eq [System.Xml.XmlNodeType]::Element) {
        $kind = $current.LocalName
        if ($kind -in @('Action','Step','Task')) {
            $identity = if ($kind -eq 'Step') { Get-Attribute $current 'FullStepIndex' } else { '' }
            if (!$identity) { $identity = Get-Attribute $current 'RemoteTaskId' }
            if (!$identity) { $identity = Get-Attribute $current 'Type' }
            if (!$identity) { $identity = Get-Attribute $current 'ActionType' }
            if (!$identity) { $identity = Get-Attribute $current 'InterfaceType' }
            if (!$identity) { $identity = Get-Attribute $current 'Name' }
            if (!$identity) { $identity = Get-Attribute $current 'RolePath' }
            $node = Get-Attribute $current 'RemoteNodeName'
            # Same-name siblings can exist: include ordinal only among matching siblings.
            $ordinal = 0
            $previous = $current.PreviousSibling
            while ($previous) {
                if ($previous.NodeType -eq [System.Xml.XmlNodeType]::Element -and $previous.LocalName -eq $kind) {
                    $prevIdentity = if ($kind -eq 'Step') { Get-Attribute $previous 'FullStepIndex' } else { '' }
                    if (!$prevIdentity) { $prevIdentity = Get-Attribute $previous 'RemoteTaskId' }
                    if (!$prevIdentity) { $prevIdentity = Get-Attribute $previous 'Type' }
                    if (!$prevIdentity) { $prevIdentity = Get-Attribute $previous 'ActionType' }
                    if (!$prevIdentity) { $prevIdentity = Get-Attribute $previous 'InterfaceType' }
                    if (!$prevIdentity) { $prevIdentity = Get-Attribute $previous 'Name' }
                    if (!$prevIdentity) { $prevIdentity = Get-Attribute $previous 'RolePath' }
                    if ($prevIdentity -eq $identity -and (Get-Attribute $previous 'RemoteNodeName') -eq $node) { $ordinal++ }
                }
                $previous = $previous.PreviousSibling
            }
            $parts.Insert(0, "$kind`:$identity`:$node`:$ordinal")
        }
        $current = $current.ParentNode
    }
    return ($parts -join '/')
}
function Add-ProgressRow($element,[int]$depth) {
    if ($element.NodeType -ne [System.Xml.XmlNodeType]::Element) { return }
    $kind = $element.LocalName
    if ($kind -notin @('Action','Step','Task')) {
        foreach ($child in $element.ChildNodes) { Add-ProgressRow $child $depth }
        return
    }
    $status = Get-Attribute $element 'Status'
    $name = Get-Attribute $element 'Name'
    if (!$name) { $name = Get-Attribute $element 'Type' }
    if (!$name) { $name = Get-Attribute $element 'ActionType' }
    if (!$name) { $name = Get-Attribute $element 'InterfaceType' }
    if (!$name) { $name = Get-Attribute $element 'RolePath' }
    if (!$name) { $name = $kind }
    $index = Get-Attribute $element 'FullStepIndex'
    $node = Get-Attribute $element 'RemoteNodeName'
    $start = Get-Attribute $element 'StartTimeUtc'
    $end = Get-Attribute $element 'EndTimeUtc'
    $duration = ''
    if ($start) {
        try {
            $begin = [datetime]::Parse($start).ToUniversalTime()
            $finish = if ($end) { [datetime]::Parse($end).ToUniversalTime() } else { [datetime]::UtcNow }
            $span = $finish - $begin
            if ($span.Ticks -ge 0) { $duration = '{0:00}:{1:00}:{2:00}' -f [math]::Floor($span.TotalHours),$span.Minutes,$span.Seconds }
        } catch {}
    }
    $visible = !$onlyActive.Checked -or $status -match 'InProgress|Running|Pending|Fail|Error|Cancel'
    if ($visible) {
        $displayName = $name.TrimStart()
        $rowIndex = $detail.Rows.Add($index,$kind,$status,$displayName,$node,(Get-LocalTimeText $start),(Get-LocalTimeText $end),$duration)
        $row = $detail.Rows[$rowIndex]
        $row.Tag = [pscustomobject]@{ Key=(Get-RowKey $element); Status=$status; Xml=$element.OuterXml }
        $row.Cells['Name'].ToolTipText = Get-Attribute $element 'Description'
        $row.Cells['Status'].Style.Font = New-Object Drawing.Font('Segoe UI Semibold',9,[Drawing.FontStyle]::Bold)
        switch -Regex ($status) {
            'Fail|Error|Cancel' { $row.Cells['Status'].Style.ForeColor=[Drawing.Color]::Firebrick; break }
            'InProgress|Running|Pending' { $row.Cells['Status'].Style.ForeColor=[Drawing.Color]::DarkOrange; break }
            '^Success$' { $row.Cells['Status'].Style.ForeColor=[Drawing.Color]::ForestGreen; break }
            '^Skipped$' { $row.Cells['Status'].Style.ForeColor=[Drawing.Color]::Gray; break }
        }
    }
    foreach ($child in $element.ChildNodes) { Add-ProgressRow $child ($depth+1) }
}
function Show-Selected {
    # Capture user selection before rows are rebuilt; never use row number as identity.
    $oldKey = $script:selectionKey
    $oldStatus = $script:selectionStatus
    $hadSelection = ![string]::IsNullOrEmpty($oldKey)
    $oldFirst = 0
    try { if ($detail.FirstDisplayedScrollingRowIndex -ge 0) { $oldFirst = $detail.FirstDisplayedScrollingRowIndex } } catch {}
    $oldHorizontal = $detail.HorizontalScrollingOffset
    $script:rendering = $true
    $detail.SuspendLayout()
    try {
        $detail.Rows.Clear()
        if (!$script:chosen -or !$script:snapshots.ContainsKey($script:chosen)) { return }
        $data = $script:snapshots[$script:chosen]
        if (!$data.Xml) { $label.Text = 'No ProgressAsXml returned for the running instance'; return }
        $doc = New-Object System.Xml.XmlDocument
        $doc.XmlResolver = $null
        $doc.LoadXml($data.Xml)
        Add-ProgressRow $doc.DocumentElement 0
        $detail.ClearSelection()
        $target = -1
        if ($hadSelection -and $detail.Rows.Count -gt 0) {
            # When the watched step finishes, follow the last visible row.
            for ($i=0; $i -lt $detail.Rows.Count; $i++) {
                if ($detail.Rows[$i].Tag.Key -eq $oldKey) {
                    $newStatus = [string]$detail.Rows[$i].Tag.Status
                    if ($oldStatus -match '^(InProgress|Running|Pending)$' -and $newStatus -notmatch '^(InProgress|Running|Pending)$') {
                        $target = $detail.Rows.Count - 1
                    } else { $target = $i }
                    break
                }
            }
            if ($target -lt 0) { $target = $detail.Rows.Count - 1 }
        }
        if ($target -ge 0) {
            $detail.Rows[$target].Selected = $true
            $preferred = $detail.Columns['Name']
            if (!$preferred.Visible) { $preferred = @($detail.Columns | Where-Object { $_.Visible } | Sort-Object DisplayIndex)[0] }
            if ($preferred) { $detail.CurrentCell = $detail.Rows[$target].Cells[$preferred.Index] }
            $script:selectionKey = [string]$detail.Rows[$target].Tag.Key
            $script:selectionStatus = [string]$detail.Rows[$target].Tag.Status
            try { $detail.FirstDisplayedScrollingRowIndex = [math]::Max(0, $target - 5) } catch {}
        } else {
            $script:selectionKey = ''
            $script:selectionStatus = ''
            if ($detail.Rows.Count -gt 0) {
                try { $detail.FirstDisplayedScrollingRowIndex = [math]::Min($oldFirst,$detail.Rows.Count-1) } catch {}
            }
        }
        try { $detail.HorizontalScrollingOffset = $oldHorizontal } catch {}
    } catch { $label.Text = "XML parse error: $($_.Exception.Message)" }
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
            if (!$id) { continue }
            $script:snapshots[$id] = $entry
        }
        $old = $script:chosen
        if ($old -and $script:snapshots.ContainsKey($old)) { $script:chosen = $old }
        elseif ($script:snapshots.Count -gt 0) {
            $script:chosen = [string](@($script:snapshots.Keys | Sort-Object)[0])
            $script:selectionKey = ''
            $script:selectionStatus = ''
        } else { $script:chosen = '' }
        Show-Selected
        $label.Text = "Running action plans: $($script:snapshots.Count) | Rows: $($detail.Rows.Count) | Updated: $((Get-Date).ToString('HH:mm:ss'))"
    } catch { $label.Text="Discovery error: $($_.Exception.Message)" }
    finally { $p.PowerShell.Dispose() }
}
$detail.Add_SelectionChanged({
    if ($script:rendering) { return }
    if ($detail.SelectedRows.Count -gt 0) {
        $tag = $detail.SelectedRows[0].Tag
        if ($tag) {
            $script:selectionKey = [string]$tag.Key
            $script:selectionStatus = [string]$tag.Status
        }
    }
})
$onlyActive.Add_CheckedChanged({ Show-Selected })
$refresh.Add_Click({ Start-Poll })
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
    if ($auto.Checked -and !$script:pending -and ((Get-Date)-$script:lastPoll).TotalSeconds -ge [double]$interval.Value) { Start-Poll }
})
$form.Add_Shown({ $timer.Start(); Start-Poll })
$form.Add_FormClosing({
    $timer.Stop()
    if ($script:pending) { try { $script:pending.PowerShell.Stop() } catch {}; $script:pending.PowerShell.Dispose() }
    $pool.Close(); $pool.Dispose()
})
[void]$form.ShowDialog()
