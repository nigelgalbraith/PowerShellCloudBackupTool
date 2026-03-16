
<#
.SYNOPSIS
Configuration management for backup settings
#>

function Initialize-BackupSettings {
    <#
    .SYNOPSIS
    Loads existing backup settings from file or initializes default settings from cloud provider definitions.

    .DESCRIPTION
    This function attempts to load user-specific backup settings from a JSON file.
    If the file does not exist, it builds and returns a new settings hashtable using the
    "Default" values defined in the provided cloud provider definitions.
    #>
    param (
        [string]$settingsPath,  # Path to the user backup settings JSON file
        $providers              # Hashtable of cloud providers (e.g., Google, Dropbox, etc.)
    )
    # If the settings file exists, load and return it as a hashtable
    if (Test-Path $settingsPath) {
        return Convert-ToHashtable (Get-Content $settingsPath -Raw | ConvertFrom-Json)
    }
    # Otherwise, create new settings based on provider defaults
    $defaults = @{}
    foreach ($key in $providers.Providers.Keys) {
        $defaults[$key] = $providers.Providers[$key].Default
    }
    return $defaults
}


function Save-CurrentSettings {
    <#
    .SYNOPSIS
    Saves current GUI backup settings for each cloud provider to a JSON file.

    .DESCRIPTION
    This function collects user-selected backup configuration values from the GUI controls
    for each defined cloud provider (e.g., source path, destination, zip mode, etc.)
    and saves the resulting settings to a JSON file for persistence between sessions.
    #>
    param (
        $gui,             # The hashtable of GUI controls (TextBoxes, RadioButtons, etc.)
        $providers,       # The loaded cloud provider definitions (must include .Prefix for each)
        $settingsPath     # The output path where backup settings should be saved
    )
    $settings = @{}
    # Loop through each provider and extract values from GUI fields based on the provider's prefix
    foreach ($key in $providers.Providers.Keys) {
        $prefix = $providers.Providers[$key].Prefix
        $settings[$key] = @{
            Source = $gui."Txt${prefix}Source".Text              # Source folder path
            Dest   = $gui."Txt${prefix}Dest".Text                # Destination folder path
            Zip    = $gui."Rdo${prefix}Zip".Checked              # Whether zip backup is selected
            Mirror = $gui."Rdo${prefix}Mirror".Checked           # Whether mirror mode is selected
            Append = $gui."Rdo${prefix}Append".Checked           # Whether append mode is selected
            Name   = $gui."Txt${prefix}ZipName".Text             # Zip filename pattern
            Freq   = $gui."Cmb${prefix}Freq".SelectedItem        # Backup frequency
            Keep   = $gui."Num${prefix}Keep".Value               # Number of zip backups to retain
        }
    }
    # Ensure the target settings directory exists
    $settingsDir = Split-Path -Parent $settingsPath
    if (-not (Test-Path $settingsDir)) {
        New-Item -Path $settingsDir -ItemType Directory | Out-Null
    }
    # Convert settings to JSON and save to the specified path
    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath
}


function Get-BackupTaskName {
    <#
    .SYNOPSIS
    Returns the scheduled task name used by the backup tool.
    #>
    return "CloudBackupTool-AutoBackup"
}


function New-BackupTaskTrigger {
    <#
    .SYNOPSIS
    Creates a scheduled task trigger based on the selected frequency.

    .DESCRIPTION
    This function returns a Windows Scheduled Task trigger for Daily, Weekly,
    or Monthly scheduling using the supplied time value.
    #>
    param (
        [string]$frequency,
        [datetime]$time
    )
    switch ($frequency) {
        "Daily" {
            return New-ScheduledTaskTrigger -Daily -At $time
        }
        "Weekly" {
            return New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At $time
        }
        "Monthly" {
            return New-ScheduledTaskTrigger -Monthly -DaysOfMonth 1 -At $time
        }
        default {
            throw "Unsupported schedule frequency: $frequency"
        }
    }
}


function Register-BackupScheduledTask {
    <#
    .SYNOPSIS
    Creates or updates the scheduled backup task.
    #>
    param (
        [string]$scriptPath,
        [string]$frequency,
        [datetime]$time
    )
    $taskName = Get-BackupTaskName
    $mainScriptPath = Join-Path $scriptPath "main.ps1"
    $trigger = New-BackupTaskTrigger -frequency $frequency -time $time
    $arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$mainScriptPath`" -AutoBackup"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arguments
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Description "Runs the Cloud Backup Tool automatically." `
        -Force | Out-Null
}

function Unregister-BackupScheduledTaskSafe {
    <#
    .SYNOPSIS
    Removes the scheduled backup task if it exists.
    #>
    $taskName = Get-BackupTaskName
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
}

function Get-BackupScheduledTaskStatus {
    <#
    .SYNOPSIS
    Returns the current scheduled backup task status.
    #>
    $taskName = Get-BackupTaskName
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        return [PSCustomObject]@{
            Exists    = $false
            Enabled   = $false
            StateText = "Scheduled Task: Disabled"
        }
    }
    $enabled = $task.Settings.Enabled
    $stateLabel = if ($enabled) { "Enabled" } else { "Disabled" }
    $triggerText = ""
    if ($task.Triggers.Count -gt 0) {
        $trigger = $task.Triggers[0]
        $freq = switch ($trigger.CimClass.CimClassName) {
            "MSFT_TaskDailyTrigger"   { "Daily" }
            "MSFT_TaskWeeklyTrigger"  { "Weekly" }
            "MSFT_TaskMonthlyTrigger" { "Monthly" }
            default                   { "Scheduled" }
        }
        $timeText = ""
        if ($trigger.StartBoundary) {
            try {
                $start = [datetime]$trigger.StartBoundary
                $timeText = $start.ToShortTimeString()
            } catch {
                $timeText = ""
            }
        }
        $triggerText = if ($timeText) { " ($freq at $timeText)" } else { " ($freq)" }
    }
    return [PSCustomObject]@{
        Exists    = $true
        Enabled   = $enabled
        StateText = "Scheduled Task: $stateLabel$triggerText"
    }
}

Export-ModuleMember -Function Initialize-BackupSettings, Save-CurrentSettings, Get-BackupTaskName, New-BackupTaskTrigger, Register-BackupScheduledTask, Unregister-BackupScheduledTaskSafe, Get-BackupScheduledTaskStatus