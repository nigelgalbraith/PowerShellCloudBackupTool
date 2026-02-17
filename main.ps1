# CLOUD STORAGE BACKUP TOOL #

# CONSTANTS
$CONFIG_PATH = "$PSScriptRoot\config\mainConfig.json"

# ============ DEPENDENCIES ============
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
# ======================================

# ============ MODULE IMPORTS ============
# Import Core Modules
Import-Module "$PSScriptRoot\modules\Core\BackupConfig.psm1" -Force -Verbose
Import-Module "$PSScriptRoot\modules\Core\BackupCore.psm1" -Force -Verbose

# Import GUI Modules
Import-Module "$PSScriptRoot\modules\GUI\BackupUI.psm1" -Force -Verbose
Import-Module "$PSScriptRoot\modules\GUI\FileSystemUI.psm1" -Force -Verbose

function Write-Log {
    <#
    .SYNOPSIS
    Writes a timestamped log message to both the GUI log box and a log file.

    .DESCRIPTION
    This function formats a log message with a timestamp and optional error prefix,
    appends it to a TextBox in the GUI, and writes it to a log file on disk.
    It also performs basic log rotation by keeping only a limited number of recent logs.
    #>

    param (
        [System.Windows.Forms.TextBox]$logBox,  # The GUI log output box
        [string]$message,                       # The log message to write
        [switch]$Error                          # Whether the message is an error
    )

    # Format the log message with timestamp and prefix
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $prefix = if ($Error) { "[ERROR]" } else { "[INFO]" }
    $fullMessage = "[$timestamp] $prefix $message"

    # Append the message to the GUI TextBox
    $logBox.AppendText("$fullMessage`r`n")
    $logBox.SelectionStart = $logBox.Text.Length
    $logBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()

    # Ensure the log folder exists
    if (-not (Test-Path $logFolder)) {
        New-Item -Path $logFolder -ItemType Directory | Out-Null
    }

    # Append the message to the log file on disk
    Add-Content -Path $logFilePath -Value $fullMessage

    # Perform log rotation (keep only the newest $logs_to_keep log files)
    $allLogs = Get-ChildItem -Path $logFolder -Filter "backup_*.log" | Sort-Object LastWriteTime -Descending
    if ($allLogs.Count -gt $logsToKeep) {
        $allLogs | Select-Object -Skip $logsToKeep | Remove-Item -Force
    }
}


# ============ APPLICATION ENTRY POINT ============

# Entry point for the Cloud Backup Tool GUI; initializes components, loads settings, and handles events.
function Main {
    <#
    .SYNOPSIS
    Launches the Cloud Backup Tool GUI.

    .DESCRIPTION
    Entry point for initializing configuration, creating UI components, and wiring up backup logic.
    This function sets up the full form layout, loads provider definitions and user settings, 
    and attaches actions for Backup, Cancel, and Shutdown operations.
    #>
    try {
        # ------------------------------
        # LOAD CONFIGURATION AND RESOURCES
        # ------------------------------
        $config = Convert-ToHashtable (Import-JsonFile -JsonPath $CONFIG_PATH)

        # Logging varaiables
        $script:logFolder = Join-Path $env:USERPROFILE $CONFIG.Locations.LogPath
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $script:logFilePath = Join-Path $script:logFolder "backup_$timestamp.log"
        $script:logsToKeep   = $CONFIG.Logging.LogsToKeep


        # Load cloud providers and current saved settings
        $cloud_providers = Convert-ToHashtable (Import-JsonFile -jsonPath $config.Locations.ProviderPath)
        $settings = Initialize-BackupSettings -settingsPath $config.Locations.SettingsPath -providers $cloud_providers

        # ------------------------------
        # EXTRACT UI LAYOUT DEFINITIONS
        # ------------------------------

        # Calculate form width using layout config
        $formWidth = 
            $config.Layout.Margins.Left + 
            $config.Layout.Spacing.XSmall + 
            $config.Layout.Labels.Width + 
            $config.Layout.Spacing.XSmall + 
            $config.Layout.TextBoxes.Width + 
            $config.Layout.Spacing.XSmall + 
            $config.Layout.BrowseButtons.Width + 
            $config.Layout.Spacing.XSmall + 
            $config.Layout.Margins.Right

        # Calculate form height using vertical component stacking
        $formHeight = 
            $config.Layout.TabControl.Y +
            $config.Layout.TabControl.Height +
            $config.Layout.Spacing.YBig +          
            $config.Layout.Buttons.Height +
            $config.Layout.Spacing.YSmall +
            $config.Layout.ProgressBar.Height +
            $config.Layout.Spacing.YSmall +
            $config.Layout.LogBox.Height +
            $config.Layout.Spacing.YBig

        # Form-level layout
        $form_layout = @{
            formWidth     = $formWidth
            formHeight    = $formHeight
            startPosition = $config.Layout.Form.StartPosition
            defaultFont   = $config.Layout.Fonts.Default
        }

        # TabControl layout
        $tabWidth = $formWidth - $config.Layout.Spacing.XSmall - $config.Layout.Margins.Right
        $tab_layout = @{
            tabWidth  = $tabWidth
            tabHeight = $config.Layout.TabControl.Height
            tabX      = $config.Layout.TabControl.X
            tabY      = $config.Layout.TabControl.Y
        }

        # Provider layout: controls inside each provider tab
        $provider_layout = @{
            # Margins & Offsets
            XLeftMargin          = $config.Layout.Margins.Left
            XLabelOffset         = $config.Layout.Offsets.LabelX
            LabelX               = $config.Layout.Labels.X
            TextBoxX             = $config.Layout.TextBoxes.X
            BrowseButtonX        = $config.Layout.BrowseButtons.X
            InnerRadioY          = $config.Layout.Offsets.InnerRadioY
            YSmallSpacing        = $config.Layout.Spacing.YSmall

            # Label, TextBox, Button Sizing
            LabelWidth           = $config.Layout.Labels.Width
            TextBoxWidth         = $config.Layout.TextBoxes.Width
            TextBoxHeightSrc     = $config.Layout.TextBoxes.HeightSrc
            TextBoxHeightDest    = $config.Layout.TextBoxes.HeightDest
            BrowseButtonWidth    = $config.Layout.BrowseButtons.Width
            BrowseButtonHeight   = $config.Layout.BrowseButtons.Height

            # Group Box / Header / Control Heights
            GroupBoxWidth        = $config.Layout.GroupBoxes.Width
            GroupBoxHeight       = $config.Layout.GroupBoxes.Height
            HeaderWidth          = $config.Layout.Headers.Width
            HeaderHeight         = $config.Layout.Headers.Height
            ControlHeight        = $config.Layout.Control.Height

            # Explanation Labels
            ExplainLabelWidth    = $config.Layout.ExplainLabels.Width
            ExplainLabelHeight   = $config.Layout.ExplainLabels.Height

            # Dropdowns & Inputs
            ComboBoxWidth        = $config.Layout.ComboBoxes.Width
            NumericWidth         = $config.Layout.NumericInputs.Width

            # Fonts & Colors
            HeaderFont           = $config.Layout.Fonts.Header
            ModeExplainTextColor = $config.Layout.Colors.ModeExplainText
            ExplainTextColor     = $config.Layout.Colors.ExplainText

            # Zip defaults
            DefaultFrequencies   = $config.ZipSettings.Frequencies
            DefaultKeepCount     = $config.ZipSettings.KeepCount

            # TreeView Picker Modal
            TreeFormWidth        = $config.Tree.Form.Width
            TreeFormHeight       = $config.Tree.Form.Height
            TreeX                = $config.Tree.TreeView.X
            TreeY                = $config.Tree.TreeView.Y
            TreeWidth            = $config.Tree.TreeView.Width
            TreeHeight           = $config.Tree.TreeView.Height
            TreeOKX              = $config.Tree.Buttons.OK.X
            TreeOKY              = $config.Tree.Buttons.OK.Y
            TreeCancelX          = $config.Tree.Buttons.Cancel.X
            TreeCancelY          = $config.Tree.Buttons.Cancel.Y
            TreeButtonWidth      = $config.Tree.Buttons.Width
            TreeButtonHeight     = $config.Tree.Buttons.Height
        }

        # Buttons layout
        $buttonY = $config.Layout.TabControl.Height + $config.Layout.Spacing.YSmall

        $button_layout = @{
            formWidth     = $formWidth
            buttonHeight  = $config.Layout.Buttons.Height
            startY        = $buttonY
            cancelWidth   = $config.Layout.Buttons.Cancel.Width
            backupWidth   = $config.Layout.Buttons.Backup.Width
            shutdownWidth = $config.Layout.Buttons.Shutdown.Width
            spacing       = $config.Layout.Spacing.XMed
        }

        # Progress bar layout
        $progesswidth = $formWidth - $config.Layout.Spacing.XMed
        $progressY = $buttonY + $config.Layout.Buttons.Height + $config.Layout.Spacing.YSmall

        $progress_layout = @{
            X      = $config.Layout.TabControl.X
            Y      = $progressY
            Width  = $progesswidth
            Height = $config.Layout.ProgressBar.Height
        }

        # LogBox layout
        $logBoxwidth = $formWidth - $config.Layout.Spacing.XBig
        $logBoxY = $progressY + $config.Layout.ProgressBar.Height + $config.Layout.Spacing.YSmall

        $logbox_layout = @{
            X         = $config.Layout.TabControl.X
            Y         = $logBoxY
            Width     = $logBoxwidth
            Height    = $config.Layout.LogBox.Height
            BackColor = $config.Layout.Colors.LogBoxBack
            ForeColor = $config.Layout.Colors.LogBoxFore
            Font      = $config.Layout.Fonts.Log
        }

        # Robocopy engine settings
        $robocopy_settings = @{
            Retries           = $config.Robocopy.Retries
            Wait              = $config.Robocopy.Wait
            Threads           = $config.Robocopy.Threads
            PostBackupDelay   = $config.Robocopy.PostBackupDelay
            SyncCheckInterval = $config.Robocopy.SyncCheckInterval
        }
  
        # ------------------------------
        # CREATE UI COMPONENTS
        # ------------------------------

        $form       = New-MainForm @form_layout
        $controlMap = @{}

        $tabControl = New-ProviderTabs `
            -providers $cloud_providers `
            -settings $settings `
            -controlMap ([ref]$controlMap) `
            @tab_layout `
            -providerLayout $provider_layout

        $progressBar = New-ProgressBar @progress_layout
        $logBox      = New-LogBox @logbox_layout
        $buttons     = New-Buttons @button_layout

        # Add components to the form
        $form.Controls.AddRange(@(
            $tabControl, $progressBar, $logBox,
            $buttons.Cancel, $buttons.Backup, $buttons.Shutdown
        ))

        # ------------------------------
        # CREATE GUI CONTEXT OBJECT
        # ------------------------------

        $gui = [PSCustomObject]@{
            Form        = $form
            LogBox      = $logBox
            ProgressBar = $progressBar
            BtnCancel   = $buttons.Cancel
            BtnBackup   = $buttons.Backup
            BtnShutdown = $buttons.Shutdown
        }

        # Add all control references (e.g., TxtGDriveSource) to GUI
        foreach ($key in $controlMap.Keys) {
            $gui | Add-Member -MemberType NoteProperty -Name $key -Value $controlMap[$key]
        }

        # ------------------------------
        # WIRE UP BUTTON EVENTS
        # ------------------------------

        # Cancel button: closes the form
        $gui.BtnCancel.Add_Click({ $gui.Form.Close() })

        # Backup button
        $gui.BtnBackup.Add_Click({
            Save-CurrentSettings -gui $gui -providers $cloud_providers -settingsPath $config.Locations.SettingsPath
            $jobs    = New-BackupJobs -gui $gui -cloud_providers $cloud_providers
            $result  = Get-ValidBackupJobs -jobs $jobs -cloud_providers $cloud_providers -logBox $gui.LogBox
            $valid   = $result.ValidJobs
            $errors  = $result.Errors

            if ($errors.Count -gt 0) {
                foreach ($err in $errors) { Write-Log -logBox $gui.LogBox -message $err -Error }
                Write-Log -logBox $gui.LogBox -message "One or more jobs are invalid. Backup cancelled." -Error
                return
            }

            Start-BackupProcess -jobs $valid -gui $gui -copySettings $robocopy_settings
            $gui.Form.Close()
        })

        # Backup + Shutdown button
        $gui.BtnShutdown.Add_Click({
            Save-CurrentSettings -gui $gui -providers $cloud_providers -settingsPath $config.Locations.SettingsPath
            $jobs    = New-BackupJobs -gui $gui -cloud_providers $cloud_providers
            $result  = Get-ValidBackupJobs -jobs $jobs -cloud_providers $cloud_providers -logBox $gui.LogBox
            $valid   = $result.ValidJobs
            $errors  = $result.Errors

            if ($errors.Count -gt 0) {
                foreach ($err in $errors) { Write-Log -logBox $gui.LogBox -message $err -Error }
                Write-Log -logBox $gui.LogBox -message "One or more jobs are invalid. Backup cancelled." -Error
                return
            }

            Start-BackupProcess -jobs $valid -gui $gui -copySettings $robocopy_settings
            Write-Log -logBox $gui.LogBox -message "Initiating system shutdown..."
            Stop-Computer -Force
        })

        # ------------------------------
        # DISPLAY THE FORM
        # ------------------------------
        [void]$form.ShowDialog()
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Fatal error: $($_.Exception.Message)", "Error", 'OK', 'Error')
    }
}


# Start the application
Main