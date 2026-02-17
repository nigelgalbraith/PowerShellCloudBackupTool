<#
.SYNOPSIS
UI components for file system interaction
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

<#
.SYNOPSIS
Displays a graphical folder and file picker using a TreeView with checkboxes.

.DESCRIPTION
This function launches a Windows Forms dialog that allows the user to browse and select 
multiple files and folders from all available drives. Users can check folders and files 
to include them in their selection. When the user clicks OK, the function returns a list 
of full paths for all selected (checked) items. If the user cancels, it returns an empty array.
#>

function Show-MultiFolderFilePicker {
    param (
        [int]$TreeFormWidth,
        [int]$TreeFormHeight,
        [int]$TreeX,
        [int]$TreeY,
        [int]$TreeWidth,
        [int]$TreeHeight,
        [int]$TreeOKX,
        [int]$TreeOKY,
        [int]$TreeCancelX,
        [int]$TreeCancelY,
        [int]$TreeButtonWidth,
        [int]$TreeButtonHeight,
        [string[]]$PreSelected = @()
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Create form
    $form = New-Object Windows.Forms.Form
    $form.Text = "Select Files and Folders"
    $form.Size = New-Object Drawing.Size($TreeFormWidth, $TreeFormHeight)
    $form.StartPosition = 'CenterScreen'

    # TreeView control
    $treeView = New-Object Windows.Forms.TreeView
    $treeView.CheckBoxes = $true
    $treeView.Location = New-Object Drawing.Point($TreeX, $TreeY)
    $treeView.Size = New-Object Drawing.Size($TreeWidth, $TreeHeight)
    $form.Controls.Add($treeView)

    # OK button
    $btnOK = New-Object Windows.Forms.Button
    $btnOK.Text = "OK"
    $btnOK.Location = New-Object Drawing.Point($TreeOKX, $TreeOKY)
    $btnOK.Size     = New-Object Drawing.Size($TreeButtonWidth, $TreeButtonHeight)
    $btnOK.Anchor = 'Bottom,Right'
    $btnOK.Add_Click({
        $form.DialogResult = 'OK'
        $form.Close()
    })
    $form.Controls.Add($btnOK)

    # Cancel button
    $btnCancel = New-Object Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object Drawing.Point($TreeCancelX, $TreeCancelY)
    $btnCancel.Size = New-Object Drawing.Size($TreeButtonWidth, $TreeButtonHeight)
    $btnCancel.Anchor = 'Bottom,Right'
    $btnCancel.Add_Click({
        $form.DialogResult = 'Cancel'
        $form.Close()
    })
    $form.Controls.Add($btnCancel)

    # Lazy-load subfolders/files
    function Load-TreeChildren {
        param($node)
        $path = $node.Tag
        try {
            $node.Nodes.Clear()
            Get-ChildItem -Path $path -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $child = New-Object Windows.Forms.TreeNode
                $child.Text = $_.Name
                $child.Tag = $_.FullName
                $child.Nodes.Add('Loading...') | Out-Null
                $node.Nodes.Add($child)
                
                # If parent is checked, check the child immediately
                if ($node.Checked) {
                    $child.Checked = $true
                }
            }
            Get-ChildItem -Path $path -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $file = New-Object Windows.Forms.TreeNode
                $file.Text = $_.Name
                $file.Tag = $_.FullName
                $node.Nodes.Add($file)
                
                # If parent is checked, check the file immediately
                if ($node.Checked) {
                    $file.Checked = $true
                }
            }
        } catch {}
    }

    # Expand event to load children
    $treeView.add_BeforeExpand({
        param($s, $e)
        $node = $e.Node
        if ($node.Nodes.Count -eq 1 -and $node.Nodes[0].Text -eq 'Loading...') {
            Load-TreeChildren $node
        }
    })

    # Check/uncheck all children when a parent node is checked
    $treeView.add_AfterCheck({
        param($sender, $e)
        $node = $e.Node
        # Only process if the check state was changed by the user
        if ($e.Action -ne [System.Windows.Forms.TreeViewAction]::Unknown) {
            # Skip if this is a file node (leaf node)
            if ($node.Nodes.Count -gt 0) {
                # Recursively check/uncheck all children
                $stack = New-Object System.Collections.Stack
                $stack.Push($node)
                
                while ($stack.Count -gt 0) {
                    $current = $stack.Pop()
                    
                    # Only change nodes that aren't already in the correct state
                    if ($current.Checked -ne $node.Checked) {
                        $current.Checked = $node.Checked
                    }
                    
                    # Push all children onto the stack
                    foreach ($child in $current.Nodes) {
                        $stack.Push($child)
                    }
                }
            }
        }
    })

    # Recursively collect checked paths
    function Get-CheckedPaths {
        param($nodes)
        $all = @()
        foreach ($node in $nodes) {
            # Only include paths that are explicitly checked (not just inherited from parent)
            if ($node.Checked -and $node.Tag -is [string]) {
                # For directories, only include if parent isn't checked (to avoid duplicates)
                $parentChecked = $false
                $parent = $node.Parent
                while ($parent -ne $null) {
                    if ($parent.Checked) {
                        $parentChecked = $true
                        break
                    }
                    $parent = $parent.Parent
                }
                
                if (-not $parentChecked) {
                    $all += $node.Tag
                }
            }
            
            # Always recurse to check children
            if ($node.Nodes.Count -gt 0) {
                $all += Get-CheckedPaths $node.Nodes
            }
        }
        return $all
    }

    # Recursively pre-check nodes and expand to show them
    function Set-CheckedPaths {
        param (
            [System.Windows.Forms.TreeNodeCollection]$nodes,
            [string[]]$targets
        )

        foreach ($node in $nodes) {
            # Skip empty or irrelevant nodes
            if (-not $node.Tag) { continue }

            # Check if any target path starts with this node
            $matches = $targets | Where-Object { $_ -like "$($node.Tag)*" }

            if ($matches.Count -eq 0) {
                continue  # No need to go deeper
            }

            # If this exact node matches a selected path, check it
            if ($targets -contains $node.Tag) {
                $node.Checked = $true
                # Expand parent nodes to make this visible
                $parent = $node.Parent
                while ($parent -ne $null) {
                    $parent.Expand()
                    $parent = $parent.Parent
                }
            }

            # Load children if this might contain a match
            if ($node.Nodes.Count -eq 1 -and $node.Nodes[0].Text -eq 'Loading...') {
                Load-TreeChildren $node
            }

            # Recurse into children
            if ($node.Nodes.Count -gt 0) {
                Set-CheckedPaths -nodes $node.Nodes -targets $targets
            }
        }
    }

    # Populate root drives
    [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady } | ForEach-Object {
        $root = New-Object Windows.Forms.TreeNode
        $root.Text = $_.Name
        $root.Tag = $_.RootDirectory.FullName
        $root.Nodes.Add('Loading...') | Out-Null
        $treeView.Nodes.Add($root)
    }

    # Apply preselected paths
    if ($PreSelected.Count -gt 0) {
        Set-CheckedPaths -nodes $treeView.Nodes -targets $PreSelected
    }

    # Show dialog and return checked paths
    $result = $form.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return Get-CheckedPaths $treeView.Nodes
    } else {
        return @()
    }
}


function Show-FolderPicker {
    <#
    .SYNOPSIS
    Opens a folder browser dialog and returns the selected path.

    .DESCRIPTION
    This function creates and displays a standard Windows folder browser dialog,
    allowing the user to select a directory. If an initial path is provided and
    exists, the dialog will open to that location. The selected folder path is
    returned if the user confirms; otherwise, $null is returned.
    #>

    param (
        $initialPath  # Optional starting folder for the dialog
    )

    # ---- Create the Folder Browser Dialog ----
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog

    # ---- Set initial folder if path is valid ----
    if ($initialPath -and (Test-Path $initialPath)) {
        $dialog.SelectedPath = $initialPath
    }

    # ---- Show the dialog and return the selected path if confirmed ----
    if ($dialog.ShowDialog() -eq "OK") {
        return $dialog.SelectedPath
    }

    # ---- Return null if the user cancelled ----
    return $null
}


function New-LabelTextBrowseRow {
    <#
    .SYNOPSIS
    Creates a labeled text box with a browse button for folder selection.

    .DESCRIPTION
    Generates a row of GUI controls including a label, a text box (pre-filled with a given value),
    and a browse button that opens a folder browser dialog. The browse button is linked to update
    the text box with the selected folder path.

    This function returns a hashtable containing references to the label, textbox, and button, so
    they can be inserted into a layout or stored for future access.
    #>

    param (
        [string]$label,             # The label text to display beside the textbox
        [string]$value,             # Initial text value for the textbox
        [int]$y,                    # Vertical Y position for this row
        [int]$labelWidth,           # Width of the label control
        [int]$textBoxWidth,         # Width of the textbox control
        [int]$browseButtonWidth,    # Width of the browse button control
        [int]$browseButtonHeight,    # Width of the browse button control
        [int]$textBoxHeight,        # Height for all controls in this row
        [int]$labelX,               # X position of the label
        [int]$textBoxX,             # X position of the textbox
        [int]$buttonX,              # X position of the browse button
        [bool]$multiSelect = $true, # Whether to use multi-folder picker
        [int]$TreeFormWidth,
        [int]$TreeFormHeight,
        [int]$TreeX,
        [int]$TreeY,
        [int]$TreeWidth,
        [int]$TreeHeight,
        [int]$TreeOKX,
        [int]$TreeOKY,
        [int]$TreeCancelX,
        [int]$TreeCancelY,
        [int]$TreeButtonWidth,
        [int]$TreeButtonHeight
    )

    # ---- Create the Label ----
    $lbl = New-Object Windows.Forms.Label
    $lbl.Text = "${label}:"
    $lbl.Location = New-Object Drawing.Point($labelX, $y)
    $lbl.Size = New-Object Drawing.Size($labelWidth, $textBoxHeight)

    # ---- Create the TextBox ----
    $txtBox = New-Object Windows.Forms.TextBox
    $txtBox.Text = $value
    $txtBox.Location = New-Object Drawing.Point($textBoxX, $y)
    $txtBox.Size = New-Object Drawing.Size($textBoxWidth, $textBoxHeight)
    $txtBox.Multiline = $true
    $txtBox.ScrollBars = 'Vertical'

    # ---- Create the Browse Button ----
    $btn = New-Object Windows.Forms.Button
    $btn.Text = "Browse"
    $btn.Location = New-Object Drawing.Point($buttonX, $y)
    $btn.Size = New-Object Drawing.Size($browseButtonWidth, $browseButtonHeight)
    $btn.Tag = @{
        TextBox        = $txtBox
        Multi          = $multiSelect
        TreeFormWidth  = $TreeFormWidth
        TreeFormHeight = $TreeFormHeight
        TreeX          = $TreeX
        TreeY          = $TreeY
        TreeWidth      = $TreeWidth
        TreeHeight     = $TreeHeight
        TreeOKX        = $TreeOKX
        TreeOKY        = $TreeOKY
        TreeCancelX    = $TreeCancelX
        TreeCancelY    = $TreeCancelY
        TreeButtonWidth = $TreeButtonWidth
        TreeButtonHeight = $TreeButtonHeight
    }

    # ---- On Click: Open Folder Dialog and Update TextBox ---     
    $btn.Add_Click({
        $txtBox = $this.Tag["TextBox"]
        $useMulti = $this.Tag["Multi"]
        if ($useMulti) {
            $paths = Show-MultiFolderFilePicker `
                -TreeFormWidth  $this.Tag["TreeFormWidth"] `
                -TreeFormHeight $this.Tag["TreeFormHeight"] `
                -TreeX          $this.Tag["TreeX"] `
                -TreeY          $this.Tag["TreeY"] `
                -TreeWidth      $this.Tag["TreeWidth"] `
                -TreeHeight     $this.Tag["TreeHeight"] `
                -TreeOKX        $this.Tag["TreeOKX"] `
                -TreeOKY        $this.Tag["TreeOKY"] `
                -TreeCancelX    $this.Tag["TreeCancelX"] `
                -TreeCancelY    $this.Tag["TreeCancelY"] `
                -TreeButtonWidth $this.Tag["TreeButtonWidth"] `
                -TreeButtonHeight $this.Tag["TreeButtonHeight"] `
                -PreSelected ($txtBox.Text -split "`r`n" | Where-Object { $_.Trim() -ne '' })

            if ($paths.Count -gt 0) {
                $validPaths = $paths | Where-Object { $_ -and ($_ -is [string]) -and $_.Trim() }
                if ($validPaths.Count -gt 0) {
                    $txtBox.Text = ($validPaths -join "`r`n")
                }
            }
        } else {
            $folder = Show-FolderPicker -initialPath $txtBox.Text
            if ($folder) { $txtBox.Text = $folder }
        }
    })

    return @{ Label = $lbl; TextBox = $txtBox; Button = $btn }
}


Export-ModuleMember -Function Show-MultiFolderFilePicker, Show-FolderPicker, New-LabelTextBrowseRow