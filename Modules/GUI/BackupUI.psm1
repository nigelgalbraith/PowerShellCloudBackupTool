<#
.SYNOPSIS
Main backup form and UI components
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function New-MainForm {
    <#
    .SYNOPSIS
    Creates and returns the main form for the Cloud Backup Tool GUI.

    .DESCRIPTION
    This function initializes the main Windows Forms GUI window for the Cloud Backup Tool.
    It sets the window title, dimensions, starting position, and font based on provided parameters.
    The resulting form object is returned for use in constructing the rest of the GUI.
    #>

    param (
        [int]$formWidth,             # Width of the main form (in pixels)
        [int]$formHeight,            # Height of the main form (in pixels)
        [string]$startPosition,      # Form start position (e.g., 'CenterScreen', 'Manual')
        [string]$defaultFont         # Font to use throughout the form (e.g., 'Microsoft Sans Serif, 8pt')
    )

    # Create a new instance of a Windows Form
    $form = New-Object Windows.Forms.Form

    # Set the form's title text
    $form.Text = "Cloud Backup Tool"

    # Set the form's width and height
    $form.Size = New-Object Drawing.Size($formWidth, $formHeight)

    # Define where the form appears on screen when launched
    $form.StartPosition = $startPosition

    # Set the default font for all controls on the form
    $form.Font = $defaultFont

    # Return the form object for further customization or display
    return $form
}

function New-ProviderTabs {
    <#
    .SYNOPSIS
    Creates a tab control containing one tab per cloud provider.

    .DESCRIPTION
    This function builds a tabbed interface where each tab corresponds to a different cloud provider
    (e.g., Google Drive, Dropbox). Each tab is populated with input controls such as text fields,
    radio buttons, and dropdowns using the provider's prefix and saved user settings.

    A shared control map reference is updated with all control references for later access (e.g., Save/Load).
    #>

    param (
        $providers,                    # Hashtable of cloud provider definitions
        $settings,                     # User backup settings keyed by provider name
        [ref]$controlMap,              # Reference to a hashtable to store control references
        [int]$tabWidth,                # Width of the tab control
        [int]$tabHeight,               # Height of the tab control
        [int]$tabX,                    # X-position of the tab control on the form
        [int]$tabY,                    # Y-position of the tab control on the form
        $providerLayout                # Layout hashtable passed to Add-ProviderControls
    )

    # Create the main tab control container
    $tabControl = New-Object Windows.Forms.TabControl
    $tabControl.Size = New-Object Drawing.Size($tabWidth, $tabHeight)
    $tabControl.Location = New-Object Drawing.Point($tabX, $tabY)

    # Loop through each provider and create a tab
    foreach ($entry in $providers.Providers.GetEnumerator()) {
        $tab = New-Object Windows.Forms.TabPage
        $tab.Text = $entry.Value.Label  # Use label (e.g., "Dropbox", "Google Drive")

        # Populate controls on the tab using provider-specific logic
        $controls = Add-ProviderControls `
            -tab $tab `
            -prefix $entry.Value.Prefix `
            -settings $settings.$($entry.Key) `
            -layout $providerLayout

        # Add the tab to the main control
        $tabControl.TabPages.Add($tab)

        # Store created control references into shared map for later access
        foreach ($key in $controls.Keys) {
            $controlMap.Value[$key] = $controls[$key]
        }
    }

    return $tabControl
}


function Add-ProviderControls {
    <#
    .SYNOPSIS
    Adds all GUI controls for a cloud provider’s backup tab.

    .DESCRIPTION
    This function dynamically generates and adds all necessary GUI elements to a tab page for a specific
    cloud provider, based on its prefix and settings. Controls include source/destination path inputs,
    backup type selectors (zip or file), file mode options (mirror/append), and zip configuration fields.
    
    It returns a hashtable of all created control references, indexed by standardized control names for
    later access by other parts of the application (such as Save/Load logic or backup execution).
    #>

    param (
        $tab,                          # The tab page to populate with controls
        [string]$prefix,               # Provider prefix (used to name controls)
        $settings,                     # Default or loaded user settings for this provider
        [hashtable]$layout             # Layout definitions for spacing and control sizes
    )

    $controls = @{ }
    $y = $layout.YSmallSpacing 

    # ---- Header Label ----
    $lblHeader = New-Object Windows.Forms.Label
    $lblHeader.Text = $tab.Text
    $lblHeader.Font = $layout.HeaderFont
    $lblHeader.Location = New-Object Drawing.Point($layout.XLeftMargin, $y)
    $lblHeader.Size = New-Object Drawing.Size($layout.HeaderWidth, $layout.HeaderHeight)
    $tab.Controls.Add($lblHeader)
    $y += $layout.HeaderHeight

    # ---- Source and Destination Paths ----
    foreach ($type in @("Source", "Dest")) {
        $height = if ($type -eq "Source") { $layout.TextBoxHeightSrc } else { $layout.TextBoxHeightDest }
        $isSource = ($type -eq "Source")
        $row = New-LabelTextBrowseRow `
            -label "$($tab.Text) $type" `
            -value $settings.$type `
            -y $y `
            -labelWidth $layout.LabelWidth `
            -textBoxWidth $layout.TextBoxWidth `
            -BrowseButtonHeight $layout.BrowseButtonHeight `
            -BrowseButtonWidth $layout.BrowseButtonWidth `
            -TextBoxHeight $height `
            -labelX $layout.LabelX `
            -textBoxX $layout.TextBoxX `
            -buttonX $layout.BrowseButtonX `
            -multiSelect:$isSource `
            -TreeFormWidth $layout.TreeFormWidth `
            -TreeFormHeight $layout.TreeFormHeight `
            -TreeX $layout.TreeX `
            -TreeY $layout.TreeY `
            -TreeWidth $layout.TreeWidth `
            -TreeHeight $layout.TreeHeight `
            -TreeOKX $layout.TreeOKX `
            -TreeOKY $layout.TreeOKY `
            -TreeCancelX $layout.TreeCancelX `
            -TreeCancelY $layout.TreeCancelY `
            -TreeButtonWidth $layout.TreeButtonWidth `
            -TreeButtonHeight $layout.TreeButtonHeight 

        $tab.Controls.AddRange(@($row.Label, $row.TextBox, $row.Button))
        $controls["Txt${prefix}${type}"] = $row.TextBox
        $y += $height + $layout.YSmallSpacing 
    }

    # ---- Backup Type Group (Zip/File) ----
    $grpType = New-Object Windows.Forms.GroupBox
    $grpType.Text = "Backup Type"
    $grpType.Location = New-Object Drawing.Point($layout.XLeftMargin, $y)
    $grpType.Size = New-Object Drawing.Size($layout.GroupBoxWidth, $layout.GroupBoxHeight)
    $tab.Controls.Add($grpType)

    $rdoFile = New-Object Windows.Forms.RadioButton
    $rdoFile.Text = "File Backup"
    $rdoFile.Location = New-Object Drawing.Point($layout.XLeftMargin, $layout.InnerRadioY)
    $grpType.Controls.Add($rdoFile)
    $controls["Rdo${prefix}File"] = $rdoFile

    $rdoZip = New-Object Windows.Forms.RadioButton
    $rdoZip.Text = "Zip Backup"
    $rdoZip.Location = New-Object Drawing.Point($layout.XLabelOffset, $layout.InnerRadioY)
    $grpType.Controls.Add($rdoZip)
    $controls["Rdo${prefix}Zip"] = $rdoZip
    $y += $layout.GroupBoxHeight + $layout.YSmallSpacing 

    # ---- Zip/File Explanation Label ----
    $lblExplain = New-Object Windows.Forms.Label
    $lblExplain.Text = ""
    $lblExplain.Location = New-Object Drawing.Point($layout.XLeftMargin, $y)
    $lblExplain.Size = New-Object Drawing.Size($layout.ExplainLabelWidth, $layout.ExplainLabelHeight)
    $lblExplain.TextAlign = 'TopLeft'
    $lblExplain.ForeColor = $layout.ExplainTextColor
    $tab.Controls.Add($lblExplain)
    $controls["Lbl${prefix}Explain"] = $lblExplain
    $y += $layout.ExplainLabelHeight + $layout.YSmallSpacing 

    # ---- File Mode Group (Mirror/Append) ----
    $grpMode = New-Object Windows.Forms.GroupBox
    $grpMode.Text = "File Mode"
    $grpMode.Location = New-Object Drawing.Point($layout.XLeftMargin, $y)
    $grpMode.Size = New-Object Drawing.Size($layout.GroupBoxWidth, $layout.GroupBoxHeight)
    $tab.Controls.Add($grpMode)
    $controls["Grp${prefix}Mode"] = $grpMode

    $rdoMirror = New-Object Windows.Forms.RadioButton
    $rdoMirror.Text = "Mirror"
    $rdoMirror.Location = New-Object Drawing.Point($layout.XLeftMargin, $layout.InnerRadioY)
    $grpMode.Controls.Add($rdoMirror)
    $controls["Rdo${prefix}Mirror"] = $rdoMirror

    $rdoAppend = New-Object Windows.Forms.RadioButton
    $rdoAppend.Text = "Append"
    $rdoAppend.Location = New-Object Drawing.Point($layout.XLabelOffset, $layout.InnerRadioY)
    $grpMode.Controls.Add($rdoAppend)
    $controls["Rdo${prefix}Append"] = $rdoAppend
    $y += $layout.GroupBoxHeight + $layout.YSmallSpacing

    # Zip Start pint when visable
    $zipStartY = $y

    # ---- Mirror/Append Explanation Label ----
    $lblModeExplain = New-Object Windows.Forms.Label
    $lblModeExplain.Text = ""
    $lblModeExplain.Location = New-Object Drawing.Point($layout.XLeftMargin, $y)
    $lblModeExplain.Size = New-Object Drawing.Size($layout.ExplainLabelWidth, $layout.ExplainLabelHeight)
    $lblModeExplain.TextAlign = 'TopLeft'
    $lblModeExplain.ForeColor = $layout.ModeExplainTextColor
    $tab.Controls.Add($lblModeExplain)
    $controls["Lbl${prefix}ModeExplain"] = $lblModeExplain
    $y += $layout.ExplainLabelHeight + $layout.YSmallSpacing 

    # ---- Frequency Dropdown ----
    $lblFreq = New-Object Windows.Forms.Label
    $lblFreq.Text = "Frequency:"
    $y += $layout.YSmallSpacing
    $lblFreq.Location = New-Object Drawing.Point($layout.XLeftMargin, $y)
    $tab.Controls.Add($lblFreq)

    $cmbFreq = New-Object Windows.Forms.ComboBox
    $cmbFreq.Items.AddRange($layout.DefaultFrequencies)
    $cmbFreq.DropDownStyle = 'DropDownList'
    $cmbFreq.SelectedItem = $settings.Freq
    $cmbFreq.Location = New-Object Drawing.Point($layout.XLabelOffset, $y)
    $cmbFreq.Size = New-Object Drawing.Size($layout.ComboBoxWidth, $layout.ControlHeight)
    $tab.Controls.Add($cmbFreq)
    $controls["Cmb${prefix}Freq"] = $cmbFreq
    $y = $zipStartY 

    # ---- Zip Name ----
    $lblName = New-Object Windows.Forms.Label
    $lblName.Text = "Zip Backup Name:"
    $lblName.Location = New-Object Drawing.Point($layout.XLeftMargin, $y)
    $tab.Controls.Add($lblName)

    $txtName = New-Object Windows.Forms.TextBox
    $txtName.Text = $settings.Name
    $txtName.Location = New-Object Drawing.Point($layout.XLabelOffset, $y)
    $txtName.Size = New-Object Drawing.Size($layout.TextBoxWidth, $layout.ControlHeight)
    $tab.Controls.Add($txtName)
    $controls["Txt${prefix}ZipName"] = $txtName
    $y += $layout.ControlHeight + $layout.YSmallSpacing   
    
    # ---- Zip Retention Count ----
    $lblKeep = New-Object Windows.Forms.Label
    $lblKeep.Text = "Zips to keep:"
    $lblKeep.Location = New-Object Drawing.Point($layout.XLeftMargin, $y)
    $tab.Controls.Add($lblKeep)

    $numKeep = New-Object Windows.Forms.NumericUpDown
    $numKeep.Value = if ($settings.Keep) { $settings.Keep } else { $layout.DefaultKeepCount }
    $numKeep.Location = New-Object Drawing.Point($layout.XLabelOffset, $y)
    $numKeep.Size = New-Object Drawing.Size($layout.NumericWidth, $layout.ControlHeight)
    $tab.Controls.Add($numKeep)
    $controls["Num${prefix}Keep"] = $numKeep
    $y += $layout.ControlHeight + $layout.YSmallSpacing  


    # ---- Configure Initial State and Behaviors ----
    $zipControls = @($lblFreq, $cmbFreq, $lblName, $txtName, $lblKeep, $numKeep)
    $rdoFile.Tag = @{ Label = $lblExplain; ZipControls = $zipControls; ModeGroup = $grpMode; ModeLabel = $lblModeExplain }
    $rdoZip.Tag = $rdoFile.Tag

    if ($settings.Zip) {
        $rdoZip.Checked = $true
        $grpMode.Visible = $false
        $lblExplain.Text = "Zip Backup:`nCompresses the source folder into a zip archive and stores it."
        $zipControls | ForEach-Object { $_.Visible = $true }
    } else {
        $rdoFile.Checked = $true
        $grpMode.Visible = $true
        $lblExplain.Text = "File Backup:`nUses Robocopy to mirror or append files to the destination folder."
        $zipControls | ForEach-Object { $_.Visible = $false }

        if ($settings.Mirror) {
            $rdoMirror.Checked = $true
            $lblModeExplain.Text = "Mirror:`nOnly selected source folders are mirrored to the destination.
                                            `nExisting files are overwritten, and files missing in the source folder are deleted from the corresponding destination folder.
                                            `nFolders not included in the source selection will remain untouched in the destination."
        } else {
            $rdoAppend.Checked = $true
            $lblModeExplain.Text = "Append:`nAdds new files and overwrites changed ones in the selected source folders.
                                    `nFiles and folders outside the selected source are not affected."
        }
    }

    # ---- Event Handlers for Zip/File Selection ----
    $rdoFile.Add_CheckedChanged({
        if ($this.Checked) {
            $this.Tag.Label.Text = "File Backup:`nUses Robocopy to mirror or append files to the destination folder."
            $this.Tag.ModeGroup.Visible = $true
            $this.Tag.ModeLabel.Visible = $true
            $this.Tag.ZipControls | ForEach-Object { $_.Visible = $false }
        }
    })

    $rdoZip.Add_CheckedChanged({
        if ($this.Checked) {
            $zipName = $this.Tag.ZipControls | Where-Object { $_ -is [System.Windows.Forms.TextBox] } | Select-Object -First 1
            $freqBox = $this.Tag.ZipControls | Where-Object { $_ -is [System.Windows.Forms.ComboBox] } | Select-Object -First 1
            $keepBox = $this.Tag.ZipControls | Where-Object { $_ -is [System.Windows.Forms.NumericUpDown] } | Select-Object -First 1

            $name = if ($zipName) { $zipName.Text } else { "<name>" }
            $freq = if ($freqBox) { $freqBox.SelectedItem } else { "Daily" }
            $keep = if ($keepBox) { $keepBox.Value } else { $layout.DefaultKeepCount }

            $suffix = switch ($freq) {
                "Daily"   { (Get-Date).DayOfWeek.ToString().Substring(0,3) }
                "Weekly"  { (Get-Date).AddDays(-([int](Get-Date).DayOfWeek)).ToString("yyyy-MM-dd") }
                "Monthly" { (Get-Date).ToString("MMM") }
            }

            $this.Tag.Label.Text = "Zip Backup:`nThis will overwrite the file '$name-$suffix.zip' in the destination folder.`nLatest $keep backup$(if ($keep -ne 1) {'s'} else {''}) will be kept."
            $this.Tag.ModeGroup.Visible = $false
            $this.Tag.ModeLabel.Visible = $false
            $this.Tag.ZipControls | ForEach-Object { $_.Visible = $true }
        }
    })

    # ---- File Mode Description Update ----
    $rdoMirror.Tag = $lblModeExplain
    $rdoMirror.Add_CheckedChanged({
        if ($this.Checked) {
            $this.Tag.Text = "Mirror:`nOnly selected source folders are mirrored to the destination.
                                    `nExisting files are overwritten, and files missing in the source folder are deleted from the corresponding destination folder.
                                    `nFolders not included in the source selection will remain untouched in the destination."
        }
    })

    $rdoAppend.Tag = $lblModeExplain
    $rdoAppend.Add_CheckedChanged({
        if ($this.Checked) {
            $this.Tag.Text = "Append:`nAdds new files and overwrites changed ones in the selected source folders.
                                    `nFiles and folders outside the selected source are not affected."
        }
    })

    return $controls
}


function New-ProgressBar {
    <#
    .SYNOPSIS
    Creates and returns a progress bar positioned below the tab control.

    .DESCRIPTION
    This function initializes a new Windows Forms progress bar at a specified location
    with defined width and height. It is typically used to visually indicate progress 
    during file copy or zip operations in the Cloud Backup Tool.
    #>

    param (
        [int]$x,       # X position of the progress bar
        [int]$y,       # Y position (usually beneath tab control)
        [int]$width,   # Width of the progress bar
        [int]$height   # Height of the progress bar
    )

    # ---- Create and configure the progress bar control ----
    $progressBar = New-Object Windows.Forms.ProgressBar

    $progressBar.Location = New-Object Drawing.Point($x, $y)
    $progressBar.Size     = New-Object Drawing.Size($width, $height)

    # Set progress range from 0 to 100%
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100

    return $progressBar
}


function New-LogBox {
    <#
    .SYNOPSIS
    Creates and returns a read-only multi-line text box for displaying log output.

    .DESCRIPTION
    This function initializes a Windows Forms TextBox configured for multiline log output.
    It supports vertical scrolling, custom colors, and fonts, and is read-only to prevent user edits.
    Intended for use in the GUI as a live log display during backup operations.
    #>

    param (
        [int]$x,                  # X position (usually aligned with tab control)
        [int]$y,                  # Y position of the log box
        [int]$width,              # Width of the log box
        [int]$height,             # Height of the log box
        [string]$backColor,       # Background color (e.g., 'Black')
        [string]$foreColor,       # Foreground/text color (e.g., 'White')
        [string]$font             # Font specification (e.g., 'Consolas, 9pt')
    )

    # ---- Create and configure the log output box ----
    $logBox = New-Object Windows.Forms.TextBox

    $logBox.Multiline  = $true                  # Allow multiple lines
    $logBox.ScrollBars = "Vertical"             # Add vertical scrollbar
    $logBox.ReadOnly   = $true                  # Prevent user editing

    # ---- Apply appearance settings ----
    $logBox.BackColor = $backColor              # Set background color
    $logBox.ForeColor = $foreColor              # Set text color
    $logBox.Font      = $font                   # Set font

    # ---- Position and size ----
    $logBox.Location = New-Object Drawing.Point($x, $y)
    $logBox.Size     = New-Object Drawing.Size($width, $height)

    return $logBox
}


function New-Buttons {
    <#
    .SYNOPSIS
    Creates and returns Cancel, Backup, and Backup & Shutdown buttons centered at the bottom of the form.

    .DESCRIPTION
    This function calculates button positions based on form width and provided dimensions, then
    generates three Windows Forms buttons: Cancel, Backup, and Backup & Shutdown. These buttons
    are returned as a hashtable so event handlers can be assigned elsewhere in the application.
    #>

    param (
        [int]$formWidth,        # Total width of the main form (used to center the button group)
        [int]$buttonHeight,     # Height of each button
        [int]$startY,           # Y-position of the button row
        [int]$cancelWidth,      # Width of the Cancel button
        [int]$backupWidth,      # Width of the Backup button
        [int]$shutdownWidth,    # Width of the Backup & Shutdown button
        [int]$spacing           # Horizontal space between buttons
    )

    # ---- Calculate total width of all buttons plus spacing ----
    $totalWidth = $cancelWidth + $spacing + $backupWidth + $spacing + $shutdownWidth

    # ---- Center button group on the form ----
    $startX = [math]::Floor(($formWidth - $totalWidth) / 2)

    # ---- Create Cancel button ----
    $btnCancel = New-Object Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Size = New-Object Drawing.Size($cancelWidth, $buttonHeight)
    $btnCancel.Location = New-Object Drawing.Point($startX, $startY)

    # ---- Create Backup button ----
    $btnBackup = New-Object Windows.Forms.Button
    $btnBackup.Text = "Backup"
    $btnBackup.Size = New-Object Drawing.Size($backupWidth, $buttonHeight)
    $btnBackup.Location = New-Object Drawing.Point(($startX + $cancelWidth + $spacing), $startY)

    # ---- Create Backup & Shutdown button ----
    $btnShutdown = New-Object Windows.Forms.Button
    $btnShutdown.Text = "Backup && Shutdown"
    $btnShutdown.Size = New-Object Drawing.Size($shutdownWidth, $buttonHeight)
    $btnShutdown.Location = New-Object Drawing.Point(
        ($startX + $cancelWidth + $spacing + $backupWidth + $spacing),
        $startY
    )

    # ---- Return all buttons in a hashtable for easy referencing ----
    return @{
        Cancel   = $btnCancel
        Backup   = $btnBackup
        Shutdown = $btnShutdown
    }
}


Export-ModuleMember -Function New-MainForm, New-ProviderTabs, Add-ProviderControls, 
    New-ProgressBar, New-LogBox, New-Buttons