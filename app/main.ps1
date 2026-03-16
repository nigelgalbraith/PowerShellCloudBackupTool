param (
    [switch]$AutoBackup
)

# CLOUD STORAGE BACKUP TOOL #

# CONSTANTS
$CONFIG_PATH = "$PSScriptRoot\config\mainConfig.json"

# ============ DEPENDENCIES ============
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.Windows.Forms.Application]::EnableVisualStyles()
# ======================================

# ============ MODULE IMPORTS ============
# Import Core Modules
Import-Module "$PSScriptRoot\modules\Core\BackupConfig.psm1" -Force -Verbose
Import-Module "$PSScriptRoot\modules\Core\BackupCore.psm1" -Force -Verbose
# Import GUI Modules
Import-Module "$PSScriptRoot\modules\GUI\BackupUI.psm1" -Force -Verbose
Import-Module "$PSScriptRoot\modules\GUI\FileSystemUI.psm1" -Force -Verbose


function Resolve-AppPath {
    param(
        [string]$BasePath,
        [string]$ChildPath
    )

    if ([System.IO.Path]::IsPathRooted($ChildPath)) {
        return $ChildPath
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $ChildPath))
}

function Write-Log {
    <#
    .SYNOPSIS
    Writes a timestamped log message to both the GUI log box and a log file.

    .DESCRIPTION
    This function formats a log message with a timestamp and optional error prefix,
    appends it to a TextBox in the GUI when available, and writes it to a log file on disk.
    It also performs basic log rotation by keeping only a limited number of recent logs.
    #>
    param (
        $logBox,                                  # The GUI log output box (optional in AutoBackup mode)
        [string]$message,                         # The log message to write
        [switch]$ErrorMsg                            # Whether the message is an error
    )
    # Format the log message with timestamp and prefix
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $prefix = if ($ErrorMsg) { "[ERROR]" } else { "[INFO]" }
    $fullMessage = "[$timestamp] $prefix $message"
    # Append the message to the GUI TextBox when available
    if ($null -ne $logBox) {
        $logBox.AppendText("$fullMessage`r`n")
        $logBox.SelectionStart = $logBox.Text.Length
        $logBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    } else {
        Write-Host $fullMessage
    }
    # Ensure the log folder exists
    if (-not (Test-Path $script:logFolder)) {
        New-Item -Path $script:logFolder -ItemType Directory | Out-Null
    }
    # Append the message to the log file on disk
    Add-Content -Path $script:logFilePath -Value $fullMessage
    # Perform log rotation (keep only the newest configured log files)
    $allLogs = Get-ChildItem -Path $script:logFolder -Filter "backup_*.log" | Sort-Object LastWriteTime -Descending
    if ($allLogs.Count -gt $script:logsToKeep) {
        $allLogs | Select-Object -Skip $script:logsToKeep | Remove-Item -Force
    }
}


function Start-AutoBackupMode {
    <#
    .SYNOPSIS
    Runs the backup process without launching the GUI.

    .DESCRIPTION
    This function loads the saved backup settings, builds the backup job list,
    validates the jobs, and runs the backup process in automatic mode. It is
    intended for use by Windows Task Scheduler when main.ps1 is launched with
    the -AutoBackup switch.
    #>
    param (
        $config,
        $cloud_providers,
        $backup_settings,
        $copySettings
    )
    # Build a minimal GUI-like object for logging/progress compatibility
    $autoGui = [PSCustomObject]@{
        LogBox = $null
        ProgressBar = $null
    }
    # Build backup jobs from saved settings instead of live form controls
    $jobs = @()
    foreach ($key in $cloud_providers.Providers.Keys) {
        if (-not $backup_settings.ContainsKey($key)) { continue }
        $providerSettings = $backup_settings[$key]
        if (-not [string]::IsNullOrWhiteSpace($providerSettings.Source)) {
            $zipName = if (-not [string]::IsNullOrWhiteSpace($providerSettings.ZipName)) { $providerSettings.ZipName } else { $providerSettings.Name }
            $frequency = if (-not [string]::IsNullOrWhiteSpace($providerSettings.Frequency)) { $providerSettings.Frequency } else { $providerSettings.Freq }
            $jobs += [PSCustomObject]@{
                Key       = $key
                Source    = $providerSettings.Source
                Dest      = $providerSettings.Dest
                Zip       = [bool]$providerSettings.Zip
                Mirror    = [bool]$providerSettings.Mirror
                Append    = [bool]$providerSettings.Append
                ZipName   = $zipName
                Frequency = $frequency
                Keep      = [int]$providerSettings.Keep
            }
        }
    }
    # Validate jobs before running
    $validation = Get-ValidBackupJobs -jobs $jobs -cloud_providers $cloud_providers -logBox $null
    if ($validation.Errors.Count -gt 0) {
        foreach ($errorMessage in $validation.Errors) {
            Write-Log -logBox $null -message $errorMessage -Error
        }
        return
    }
    # Run the backup process
    Start-BackupProcess -jobs $validation.ValidJobs -gui $autoGui -copySettings $copySettings
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
    and attaches actions for Backup, Cancel, Shutdown, and Scheduled Backup operations.
    #>
    param (
        [switch]$AutoBackup
    )
    try {
        # ------------------------------
        # LOAD CONFIGURATION AND RESOURCES
        # ------------------------------
        $config = Convert-ToHashtable (Import-JsonFile -JsonPath $CONFIG_PATH)
        $appRoot = $PSScriptRoot
        $settingsPath = Resolve-AppPath -BasePath $appRoot -ChildPath $config.Locations.SettingsPath
        $providerPath = Resolve-AppPath -BasePath $appRoot -ChildPath $config.Locations.ProviderPath
        $logFolder    = Resolve-AppPath -BasePath $appRoot -ChildPath $config.Locations.LogPath
        $script:logFolder = $logFolder
        $script:logsToKeep = $config.Logging.LogsToKeep
        $cloud_providers = Convert-ToHashtable (Import-JsonFile -JsonPath $providerPath)
        $settings = Initialize-BackupSettings -settingsPath $settingsPath -providers $cloud_providers
        # Logging variables
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        if ($AutoBackup) {
            $script:logFilePath = Join-Path $script:logFolder "backup_auto_$timestamp.log"
        } else {
            $script:logFilePath = Join-Path $script:logFolder "backup_$timestamp.log"
        }
        # Robocopy engine settings
        $robocopy_settings = @{
            RobocopyRetries   = $config.Robocopy.Retries
            RobocopyWait      = $config.Robocopy.Wait
            RobocopyThreads   = $config.Robocopy.Threads
            PostBackupDelay   = $config.Robocopy.PostBackupDelay
            SyncCheckInterval = $config.Robocopy.SyncCheckInterval
            SyncWaitSeconds   = $config.Robocopy.SyncWaitSeconds
        }
        # Run scheduled / automatic mode before building the GUI
        if ($AutoBackup) {
            Start-AutoBackupMode -config $config -cloud_providers $cloud_providers -backup_settings $settings -copySettings $robocopy_settings
            return
        }
        # ------------------------------
        # EXTRACT UI LAYOUT DEFINITIONS
        # ------------------------------
        # Calculate form width using layout config
        $formWidth = $config.Layout.Margins.Left + $config.Layout.Spacing.XSmall + $config.Layout.Labels.Width + $config.Layout.Spacing.XSmall + $config.Layout.TextBoxes.Width + $config.Layout.Spacing.XSmall + $config.Layout.BrowseButtons.Width + $config.Layout.Spacing.XSmall + $config.Layout.Margins.Right

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
        $buttonY = $config.Layout.TabControl.Y + $config.Layout.TabControl.Height + $config.Layout.Spacing.YSmall
        $button_layout = @{
            formWidth     = $formWidth
            buttonHeight  = $config.Layout.Buttons.Height
            startY        = $buttonY
            cancelWidth   = $config.Layout.Buttons.Cancel.Width
            backupWidth   = $config.Layout.Buttons.Backup.Width
            shutdownWidth = $config.Layout.Buttons.Shutdown.Width
            spacing       = $config.Layout.Spacing.XMed
        }

        # Work out where the bottom button row ends
        $buttonBottom = $buttonY + $config.Layout.Buttons.Height

        # Schedule section vertical positions
        $scheduleRowY = $buttonBottom + $config.Layout.Spacing.YSmall

        # Schedule section widths
        $comboWidth = $config.Layout.Schedule.FrequencyComboBox.Width
        $comboHeight = $config.Layout.Schedule.FrequencyComboBox.Height
        $timeWidth = $config.Layout.Schedule.TimePicker.Width
        $timeHeight = $config.Layout.Schedule.TimePicker.Height
        $scheduleButtonWidth = $config.Layout.Schedule.Buttons.Schedule.Width
        $unscheduleButtonWidth = $config.Layout.Schedule.Buttons.Unschedule.Width
        $scheduleButtonHeight = $config.Layout.Schedule.Buttons.Height
        $scheduleSpacing = $config.Layout.Spacing.XMed

        # Centre the schedule controls as one group
        $scheduleGroupWidth =
            $comboWidth +
            $scheduleSpacing +
            $timeWidth +
            $scheduleSpacing +
            $scheduleButtonWidth +
            $scheduleSpacing +
            $unscheduleButtonWidth

        $scheduleGroupX = [int](($formWidth - $scheduleGroupWidth) / 2)

        # Status label layout
        $statusLabelWidth = $config.Layout.Schedule.StatusLabel.Width
        $statusLabelHeight = $config.Layout.Schedule.StatusLabel.Height
        $statusLabelX = [int](($formWidth - $statusLabelWidth) / 2)
        $statusLabelY = $scheduleRowY + $scheduleButtonHeight + $config.Layout.Spacing.YSmall

        # Work out the bottom of the schedule controls section
        $scheduleBottom = $statusLabelY + $statusLabelHeight

        # Schedule layout
        $schedule_layout = @{
            comboX                  = $scheduleGroupX
            comboY                  = $scheduleRowY
            comboWidth              = $comboWidth
            comboHeight             = $comboHeight
            timeX                   = $scheduleGroupX + $comboWidth + $scheduleSpacing
            timeY                   = $scheduleRowY
            timeWidth               = $timeWidth
            timeHeight              = $timeHeight
            scheduleButtonX         = $scheduleGroupX + $comboWidth + $scheduleSpacing + $timeWidth + $scheduleSpacing
            scheduleButtonY         = $scheduleRowY
            scheduleButtonWidth     = $scheduleButtonWidth
            scheduleButtonHeight    = $scheduleButtonHeight
            unscheduleButtonX       = $scheduleGroupX + $comboWidth + $scheduleSpacing + $timeWidth + $scheduleSpacing + $scheduleButtonWidth + $scheduleSpacing
            unscheduleButtonY       = $scheduleRowY
            unscheduleButtonWidth   = $unscheduleButtonWidth
            unscheduleButtonHeight  = $scheduleButtonHeight
            statusLabelX            = $statusLabelX
            statusLabelY            = $statusLabelY
            statusLabelWidth        = $statusLabelWidth
            statusLabelHeight       = $statusLabelHeight
        }
        # Progress bar layout
        $progressWidth = $formWidth - ($config.Layout.TabControl.X * 2)
        $progressY = $scheduleBottom + $config.Layout.Spacing.YSmall
        $progress_layout = @{
            X      = $config.Layout.TabControl.X
            Y      = $progressY
            Width  = $progressWidth
            Height = $config.Layout.ProgressBar.Height
        }

        # Log box layout
        $logBoxWidth = $formWidth - ($config.Layout.TabControl.X * 2)
        $logBoxHeight = $config.Layout.LogBox.Height
        $logBoxY = $progressY + $config.Layout.ProgressBar.Height + $config.Layout.Spacing.YSmall
        $logbox_layout = @{
            X         = $config.Layout.TabControl.X
            Y         = $logBoxY
            Width     = $logBoxWidth
            Height    = $logBoxHeight
            BackColor = $config.Layout.Colors.LogBoxBack
            ForeColor = $config.Layout.Colors.LogBoxFore
            Font      = $config.Layout.Fonts.Log
        }

        # Calculate form height from the actual bottom-most control
        $formHeight = $logBoxY + $logBoxHeight + $config.Layout.Spacing.YBig 
        # Form-level layout
        $form_layout = @{
            formWidth     = $formWidth
            formHeight    = $formHeight
            startPosition = $config.Layout.Form.StartPosition
            defaultFont   = $config.Layout.Fonts.Default
        }
        # ------------------------------
        # CREATE UI COMPONENTS
        # ------------------------------
        $form = New-MainForm @form_layout
        $controlMap = @{}
        $tabControl = New-ProviderTabs -providers $cloud_providers -settings $settings -controlMap ([ref]$controlMap) @tab_layout -providerLayout $provider_layout
        $progressBar = New-ProgressBar @progress_layout
        $logBox = New-LogBox @logbox_layout
        $buttons = New-Buttons @button_layout
        $scheduleControls = New-ScheduleControls @schedule_layout
        # Add components to the form
        $form.Controls.AddRange(@(
            $tabControl,
            $progressBar,
            $logBox,
            $buttons.Cancel,
            $buttons.Backup,
            $buttons.Shutdown,
            $scheduleControls.FrequencyComboBox,
            $scheduleControls.TimePicker,
            $scheduleControls.ScheduleButton,
            $scheduleControls.UnscheduleButton,
            $scheduleControls.StatusLabel
        ))
        # ------------------------------
        # CREATE GUI CONTEXT OBJECT
        # ------------------------------
        $gui = [PSCustomObject]@{
            Form                 = $form
            LogBox               = $logBox
            ProgressBar          = $progressBar
            BtnCancel            = $buttons.Cancel
            BtnBackup            = $buttons.Backup
            BtnShutdown          = $buttons.Shutdown
            CmbScheduleFrequency = $scheduleControls.FrequencyComboBox
            TimeSchedule         = $scheduleControls.TimePicker
            BtnScheduleBackup    = $scheduleControls.ScheduleButton
            BtnUnscheduleBackup  = $scheduleControls.UnscheduleButton
            LblScheduleStatus    = $scheduleControls.StatusLabel
        }
        # Set task status
        $taskStatus = Get-BackupScheduledTaskStatus
        $gui.LblScheduleStatus.Text = $taskStatus.StateText
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
            Save-CurrentSettings -gui $gui -providers $cloud_providers -settingsPath $settingsPath
            $jobs = New-BackupJobs -gui $gui -cloud_providers $cloud_providers
            $result = Get-ValidBackupJobs -jobs $jobs -cloud_providers $cloud_providers -logBox $gui.LogBox
            $valid = $result.ValidJobs
            $errors = $result.Errors
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
            Save-CurrentSettings -gui $gui -providers $cloud_providers -settingsPath $settingsPath
            $jobs = New-BackupJobs -gui $gui -cloud_providers $cloud_providers
            $result = Get-ValidBackupJobs -jobs $jobs -cloud_providers $cloud_providers -logBox $gui.LogBox
            $valid = $result.ValidJobs
            $errors = $result.Errors
            if ($errors.Count -gt 0) {
                foreach ($err in $errors) { Write-Log -logBox $gui.LogBox -message $err -Error }
                Write-Log -logBox $gui.LogBox -message "One or more jobs are invalid. Backup cancelled." -Error
                return
            }
            Start-BackupProcess -jobs $valid -gui $gui -copySettings $robocopy_settings
            Write-Log -logBox $gui.LogBox -message "Initiating system shutdown..."
            Stop-Computer -Force
        })
        # Schedule Backup button
        $gui.BtnScheduleBackup.Add_Click({
            try {
                Save-CurrentSettings -gui $gui -providers $cloud_providers -settingsPath $settingsPath
                $frequency = $gui.CmbScheduleFrequency.SelectedItem.ToString()
                $time = $gui.TimeSchedule.Value
                Register-BackupScheduledTask -scriptPath $PSScriptRoot -frequency $frequency -time $time
                Write-Log -logBox $gui.LogBox -message "Scheduled backup task created: $frequency at $($time.ToShortTimeString())"
                $taskStatus = Get-BackupScheduledTaskStatus
                $gui.LblScheduleStatus.Text = $taskStatus.StateText
                [System.Windows.Forms.MessageBox]::Show("Scheduled backup created successfully.", "Scheduled Backup", 'OK', 'Information')
            } catch {
                Write-Log -logBox $gui.LogBox -message "Failed to create scheduled backup: $($_.Exception.Message)" -Error
                [System.Windows.Forms.MessageBox]::Show("Failed to create scheduled backup: $($_.Exception.Message)", "Error", 'OK', 'Error')
            }
        })
        # Unschedule Backup button
        $gui.BtnUnscheduleBackup.Add_Click({
            try {
                Unregister-BackupScheduledTaskSafe
                Write-Log -logBox $gui.LogBox -message "Scheduled backup task removed."
                $taskStatus = Get-BackupScheduledTaskStatus
                $gui.LblScheduleStatus.Text = $taskStatus.StateText
                [System.Windows.Forms.MessageBox]::Show("Scheduled backup removed successfully.", "Scheduled Backup", 'OK', 'Information')
            } catch {
                Write-Log -logBox $gui.LogBox -message "Failed to remove scheduled backup: $($_.Exception.Message)" -Error
                [System.Windows.Forms.MessageBox]::Show("Failed to remove scheduled backup: $($_.Exception.Message)", "Error", 'OK', 'Error')
            }
        })
        # ------------------------------
        # DISPLAY THE FORM
        # ------------------------------
        [void]$form.ShowDialog()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Fatal error: $($_.Exception.Message)", "Error", 'OK', 'Error')
    }
}


# Start the application
Main -AutoBackup:$AutoBackup