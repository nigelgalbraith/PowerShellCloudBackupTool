<#
.SYNOPSIS
Core backup operations and utilities
#>

# CONSTANTS
# ======== LOGGING CONSTANTS ========
$LOGFOLDER     = "$PSScriptRoot\..\..\logs"
$LOGS_TO_KEEP  = 10
$timestamp     = Get-Date -Format "yyyyMMdd_HHmmss"
$LOG_FILE_PATH   = Join-Path $LOGFOLDER "backup_$timestamp.log"

# DEPENDENCIES
Add-Type -AssemblyName System.IO.Compression.FileSystem


function Convert-ToHashtable {
    <#
    .SYNOPSIS
    Recursively converts a PSCustomObject into a native PowerShell hashtable.

    .DESCRIPTION
    This function is used to convert data returned from ConvertFrom-Json (which is typically a PSCustomObject)
    into a native PowerShell hashtable structure. It ensures that nested objects and arrays are also converted,
    allowing full hashtable features like .Keys and .GetEnumerator().
    #>

    param ([object]$InputObject)

    # Handle objects by building a hashtable of their properties
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $hashtable = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $hashtable[$property.Name] = Convert-ToHashtable $property.Value
        }
        return $hashtable
    }

    # Convert collections (e.g., arrays) recursively, excluding strings
    elseif ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        return $InputObject | ForEach-Object { Convert-ToHashtable $_ }
    }

    # Return primitive values (e.g., string, int, bool) as-is
    else {
        return $InputObject
    }
}


function Import-JsonFile {
    <#
    .SYNOPSIS
    Loads a JSON file and converts it into a PowerShell object.

    .DESCRIPTION
    This function reads the content of a JSON file from the specified path and converts it 
    into a PowerShell object using ConvertFrom-Json. It is typically used in combination with 
    Convert-ToHashtable when hashtable behavior is needed for enumeration or key access.
    #>

    param (
        [string]$JsonPath
    )

    # Check that the specified JSON file exists
    if (-not (Test-Path $JsonPath)) {
        throw "JSON file not found at $JsonPath"
    }

    # Read the file content and convert the JSON into a PowerShell object
    $raw = Get-Content $JsonPath -Raw | ConvertFrom-Json

    return $raw
}


function Get-ValidBackupJobs {
    <#
    .SYNOPSIS
    Validates backup jobs and returns both valid jobs and any errors encountered.

    .DESCRIPTION
    This function iterates through a collection of backup jobs and verifies that required fields
    (such as source and destination paths) are not empty, that the paths exist, and that the destination 
    is allowed according to the provider’s predefined list. It returns a structured object containing
    the list of valid jobs and any validation error messages for display or logging.
    #>

    param (
        $jobs,                # The list of backup jobs (each with keys like Source, Dest, Key)
        $cloud_providers,     # Cloud provider definitions (should contain .Providers[Key].Destinations)
        $logBox               # (Optional) GUI log box - not used here but available for future extension
    )

    $validJobs = @()  # Store jobs that pass all validation checks
    $errors = @()     # Collect error messages for reporting

    foreach ($job in $jobs) {
        # Check for missing provider key
        if (-not $job.Key) {
            $errors += "Job with no provider key skipped."
            continue
        }

        # Check if source or destination is blank
        if ([string]::IsNullOrWhiteSpace($job.Source) -or [string]::IsNullOrWhiteSpace($job.Dest)) {
            $errors += "Job '$($job.Key)': Source or destination is blank."
            continue
        }

        # Split multiple paths
        $sourcePaths = $job.Source -split "`r`n" | Where-Object { $_ -ne '' -and $_.Trim() -ne '' }

        # Track valid/invalid sources
        $validPaths = @()
        $invalidPaths = @()

        foreach ($path in $sourcePaths) {
            if (Test-Path $path) {
                $validPaths += $path
            } else {
                $invalidPaths += $path
            }
        }

        # If none of the paths exist, flag as an error
        if ($validPaths.Count -eq 0) {
            $errors += "Job '$($job.Key)': None of the source paths exist: $($job.Source)"
            continue
        }

        # (Optional) Warn if only some paths are bad
        if ($invalidPaths.Count -gt 0) {
            Write-Warning "Job '$($job.Key)': Some source paths do not exist: $($invalidPaths -join '; ')"
        }

        # Ensure destination path exists
        if (-not (Test-Path $job.Dest)) {
            $errors += "Job '$($job.Key)': Destination path does not exist: $($job.Dest)"
            continue
        }

        # Ensure destination is among the provider's approved destinations
        $provider = $cloud_providers.Providers[$job.Key]
        $matches = $provider.Destinations | Where-Object { $_ -eq $job.Dest }

        if (-not $matches) {
            $expected = $provider.Destinations -join ", "
            $errors += "Job '$($job.Key)': Destination must include one of: $expected"
            continue
        }

        # Job passed all checks — add to valid list
        $validJobs += $job
    }

    # Return both valid jobs and errors in a structured object
    return [PSCustomObject]@{
        ValidJobs = $validJobs
        Errors    = $errors
    }
}


function New-BackupJobs {
    <#
    .SYNOPSIS
    Builds a list of backup job objects from GUI input fields.

    .DESCRIPTION
    This function loops through all defined cloud providers and creates a backup job object 
    for each provider where a source path is specified in the GUI. It gathers values from 
    related form controls (e.g., destination path, zip mode, frequency) and assembles them 
    into a structured object that represents a pending backup task.
    #>

    param (
        $gui,               # The GUI control hashtable containing user input fields
        $cloud_providers    # The loaded cloud provider definitions (including .Prefix for each)
    )

    $jobs = @()  # Initialize the job list

    foreach ($key in $cloud_providers.Providers.Keys) {
        $prefix = $cloud_providers.Providers[$key].Prefix
        $source = $gui."Txt${prefix}Source".Text
        
        # Only include jobs where a source path is provided
        if (-not [string]::IsNullOrWhiteSpace($source)) {
            $jobs += [PSCustomObject]@{
                Key       = $key                                   # Cloud provider key (e.g., Google, Dropbox)
                Source    = $source                                # Source folder path for backup
                Dest      = $gui."Txt${prefix}Dest".Text           # Destination folder path
                Zip       = $gui."Rdo${prefix}Zip".Checked         # Whether to perform a zip backup
                Mirror    = $gui."Rdo${prefix}Mirror".Checked      # Whether to mirror files (sync exact copy)
                Append    = $gui."Rdo${prefix}Append".Checked      # Whether to append new files only
                ZipName   = $gui."Txt${prefix}ZipName".Text        # Zip file name pattern
                Frequency = $gui."Cmb${prefix}Freq".SelectedItem   # Backup frequency (e.g., daily, weekly)
                Keep      = $gui."Num${prefix}Keep".Value          # Number of zip backups to retain
            }
        }
    }

    return $jobs
}


function Invoke-FileCopyOperation {
    <#
    .SYNOPSIS
    Executes a Robocopy file copy operation in either Mirror or Append mode, for multiple paths.

    .DESCRIPTION
    This function prepares and launches Robocopy processes to copy files/folders from source(s) 
    to the destination directory. It supports:
    - "Mirror" mode (exact replica with deletions)
    - "Append" mode (add/update only)

    Accepts semicolon-separated paths and handles each one independently.
    #>

    param (
        [string]$source,            # Semicolon-separated source paths
        [string]$dest,              # Destination directory for backup
        [string]$mode,              # "Mirror" or "Append"
        $logBox,                    # TextBox for GUI logging
        $progressBar,               # Progress bar for GUI feedback
        [int]$retries,              # Retry attempts
        [int]$wait,                 # Wait between retries
        [int]$threads               # Robocopy multithread count
    )

    # --- Base robocopy arguments ---
    $baseArgs = @(
        "/Z",                         # Restartable mode
        "/R:$retries",               # Retry count
        "/W:$wait",                  # Wait time
        "/MT:$threads",              # Multithreading
        "/TEE",                      # Output to console and log
        "/NDL",                      # Suppress directory list
        "/NFL"                       # Suppress file list
    )

    # --- Mode-specific arguments ---
    $modeArgs = if ($mode -eq "Mirror") { "/MIR" } else { "/E /XX" }

    # --- Split input source into array ---
    $sourcePaths = $source -split "`r`n" | Where-Object { $_ -ne '' -and $_.Trim() -ne '' }

    foreach ($src in $sourcePaths) {
        if (-not (Test-Path $src)) { continue }

        $isDir = (Get-Item $src).PSIsContainer

        if ($isDir) {
            $destPath = Join-Path $dest (Split-Path $src -Leaf)
            $robocopySource = $src
            $robocopyDest   = $destPath
            $extraArgs = @()
        } else {
            # Mirror parent folder and exclude the file (if Mirror mode)
            $parentDir = Split-Path $src -Parent
            $folderName = Split-Path $parentDir -Leaf
            $destPath = Join-Path $dest $folderName
            $robocopySource = $parentDir
            $robocopyDest   = $destPath
            $extraArgs = if ($mode -eq "Mirror") { @("/IF", "/XF", "`"$src`"") } else { @() }
        }

        $allArgs = @("`"$robocopySource`"", "`"$robocopyDest`"") + $baseArgs + $modeArgs + $extraArgs

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "robocopy.exe"
        $psi.Arguments = $allArgs -join " "
        $psi.RedirectStandardOutput = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        Write-Log -logBox $logBox -message "Starting $mode operation from $robocopySource to $robocopyDest"

        $process = Start-ProcessWithOutput -processStartInfo $psi -logBox $logBox -progressBar $progressBar

        Write-Log -logBox $logBox -message "$mode operation completed (Exit code: $($process.ExitCode))"
    }
}

function Invoke-ZipOperation {
    <#
    .SYNOPSIS
    Performs a zip backup operation with retention and error handling.

    .DESCRIPTION
    This function creates a compressed `.zip` archive of a specified source folder.
    It uses the frequency (e.g., Daily, Weekly) to generate a suffix for the zip filename,
    deletes any existing archive with the same name, and then creates a new one.
    After completion, it enforces a retention policy by limiting the number of zip files
    retained in the destination directory. Errors are logged and shown to the user.
    #>

    param (
        [string]$source,       # The folder to back up
        [string]$dest,         # The folder where the zip should be saved
        [string]$zipName,      # Base name for the zip archive
        [string]$frequency,    # Frequency (Daily, Weekly, Monthly) to determine zip suffix
        [int]$keepCount,       # Number of zip files to retain
        $logBox                # GUI log textbox for status messages
    )

    try {
        # Generate suffix based on frequency (e.g., "2025-07-26-daily")
        $suffix = Get-ZipSuffix -frequency $frequency

        # Combine name and suffix to form full zip file path
        $zipPath = Join-Path $dest "$zipName-$suffix.zip"
        
        # Log the beginning of the zip operation
        Write-Log -logBox $logBox -message "Starting zip operation for $source"

        # Remove an existing zip file with the same name if it exists
        Remove-ExistingZip -zipPath $zipPath -logBox $logBox

        # Create the new zip archive
        New-ZipArchive -source $source -destination $zipPath

        # Log success
        Write-Log -logBox $logBox -message "Successfully created zip: $zipPath"

        # Apply retention: delete older zip files beyond the keep count
        Set-BackupRetention -dest $dest -zipName $zipName -keepCount $keepCount -logBox $logBox

    } catch {
        # Log the error and show a message box
        Write-Log -logBox $logBox -message "ERROR during zip operation: $($_.Exception.Message)" -Error
        [System.Windows.Forms.MessageBox]::Show(
            "Zip operation failed: $($_.Exception.Message)", 
            "Error", 
            'OK', 
            'Error'
        )
    }
}

function Start-ProcessWithOutput {
    <#
    .SYNOPSIS
    Starts a background process, logs output to the GUI, and updates a progress bar.

    .DESCRIPTION
    This function launches a background process using the specified StartInfo configuration.
    It reads the process's standard output line-by-line, logs each line to a GUI text box,
    and provides visual feedback by incrementally updating a progress bar. It returns the 
    completed process object after execution finishes.
    #>

    param (
        $processStartInfo,   # A fully configured System.Diagnostics.ProcessStartInfo object
        $logBox,             # TextBox control to which output lines will be logged
        $progressBar         # ProgressBar control to visually indicate task progress
    )

    # Create and configure a new Process instance
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processStartInfo

    # Start the external process
    $null = $process.Start()

    $count = 0

    # Read output line-by-line and log it to the GUI
    while (-not $process.StandardOutput.EndOfStream) {
        $line = $process.StandardOutput.ReadLine()                          # Read a line of output
        Write-Log -logBox $logBox -message $line                            # Log the output line
        Update-Progress -progressBar $progressBar -value (++$count % 100)  # Animate progress bar
    }

    # Wait for process to exit and finalize progress bar
    $process.WaitForExit()
    Update-Progress -progressBar $progressBar -value 100

    return $process
}


function Update-Progress {
    <#
    .SYNOPSIS
    Updates the GUI progress bar value and refreshes the UI.

    .DESCRIPTION
    This function sets the progress bar to a specified value, ensuring it does not exceed 100%.
    It also processes any pending Windows Forms events using `DoEvents()` to keep the GUI 
    responsive during long-running tasks such as file copying or compression.
    #>

    param (
        $progressBar,        # The Windows Forms ProgressBar control to update
        [int]$value          # The new value to assign to the progress bar
    )

    # Clamp the progress value to a maximum of 100 to prevent UI errors
    $progressBar.Value = [Math]::Min(100, $value)

    # Force the GUI to process pending events and stay responsive
    [System.Windows.Forms.Application]::DoEvents()
}


function Get-ZipSuffix {
    <#
    .SYNOPSIS
    Returns a suffix string for zip file names based on backup frequency.

    .DESCRIPTION
    This function generates a string suffix to append to backup zip filenames
    based on the specified frequency. This helps identify and differentiate 
    archives by their scheduling pattern:
    - Daily → 3-letter weekday (e.g., Mon)
    - Weekly → Start date of the current week (Sunday, yyyy-MM-dd)
    - Monthly → 3-letter month abbreviation (e.g., Jan)
    If an unrecognized frequency is provided, it returns a default "Backup" string.
    #>

    param (
        [string]$frequency  # Frequency type: Daily, Weekly, or Monthly
    )

    switch ($frequency) {
        # Use 3-letter day of week for daily backups (e.g., Mon, Tue)
        "Daily"   { return (Get-Date).DayOfWeek.ToString().Substring(0,3) }

        # Use the start date of the current week (Sunday)
        "Weekly"  { return (Get-Date).AddDays(-([int](Get-Date).DayOfWeek)).ToString("yyyy-MM-dd") }

        # Use 3-letter month abbreviation (e.g., Jan, Feb)
        "Monthly" { return (Get-Date).ToString("MMM") }

        # Default fallback if frequency is invalid or missing
        default   { return "Backup" }
    }
}


function Remove-ExistingZip {
    <#
    .SYNOPSIS
    Removes an existing zip file if it already exists.

    .DESCRIPTION
    This function checks whether a zip archive already exists at the specified path.
    If it does, the file is forcefully deleted. This is typically called before creating
    a new backup archive to prevent conflicts or duplicates. The deletion is also logged
    to the GUI via the provided log box.
    #>

    param (
        [string]$zipPath,   # Full path of the zip file to check and remove
        $logBox             # GUI text box for logging messages
    )

    # Check if the zip file already exists
    if (Test-Path $zipPath) {
        # Log the removal
        Write-Log -logBox $logBox -message "Removing existing zip: $zipPath"

        # Forcefully delete the existing zip file
        Remove-Item $zipPath -Force
    }
}


function New-ZipArchive {
    <#
    .SYNOPSIS
    Creates a zip archive from a source directory using optimal compression.

    .DESCRIPTION
    This function uses .NET's built-in `System.IO.Compression.ZipFile` class to create
    a `.zip` file from the specified source directory. It applies optimal compression
    and does not include the root folder in the archive. The resulting zip is saved to
    the provided destination path.
    #>

    param (
        [string]$source,        # Path to the folder to zip
        [string]$destination    # Full path where the zip archive should be created
    )

    # Create the zip archive using optimal compression
    [System.IO.Compression.ZipFile]::CreateFromDirectory($source, $destination, 'Optimal', $false)
}


function Set-BackupRetention {
    <#
    .SYNOPSIS
    Enforces a retention policy by deleting older zip backups beyond the keep count.

    .DESCRIPTION
    This function helps manage disk space and backup hygiene by retaining only the most 
    recent N backup zip files in the destination folder. It searches for all zip files 
    that match a specific name pattern (e.g., "BackupName-*.zip"), sorts them by 
    modification date (newest first), and removes any extras beyond the keep count.
    #>

    param (
        [string]$dest,         # Destination folder containing zip backups
        [string]$zipName,      # Base name of the zip files (e.g., "MyBackup")
        [int]$keepCount,       # Number of recent backups to retain
        $logBox                # GUI text box for logging status
    )

    # Get zip files matching the naming pattern, sorted by newest first
    $zips = Get-ChildItem $dest -Filter "$zipName-*.zip" | Sort-Object LastWriteTime -Descending

    # If there are more backups than allowed, remove the oldest ones
    if ($zips.Count -gt $keepCount) {
        $zips | Select-Object -Skip $keepCount | Remove-Item -Force

        # Log the enforcement action
        Write-Log -logBox $logBox -message "Enforced retention policy (kept $keepCount backups)"
    }
}


function Wait-ForSyncCompletion {
    <#
    .SYNOPSIS
    Waits until no recent file changes are detected in the specified paths.

    .DESCRIPTION
    This function monitors one or more directories for ongoing file sync activity,
    such as uploads to cloud storage providers. It checks for recently modified files
    within a specified time window and waits until no such activity is detected across
    all given paths. Logging is provided for each check and upon completion.
    #>

    param (
        $paths,                     # Array of paths to monitor for changes
        $logBox,                    # TextBox control to display sync status updates
        [int]$intervalSeconds,      # Delay between sync status checks (e.g., 3 seconds)
        [int]$waitSeconds           # Look-back time window for "recent" file activity (e.g., 10 seconds)
    )

    # Log the beginning of the sync monitoring process
    Write-Log -logBox $logBox -message "Monitoring sync status..."

    while ($true) {
        $allClear = $true

        foreach ($path in $paths) {
            # Skip this path if it doesn't exist
            if (-not (Test-Path $path)) { continue }

            # Find files recently modified within the defined wait window
            $recent = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
                      Where-Object { $_.LastWriteTime -gt (Get-Date).AddSeconds(-$waitSeconds) }

            # If recent files are found, log and pause before next check
            if ($recent) {
                $allClear = $false
                Write-Log -logBox $logBox -message "Active sync detected in $path"
                break
            }
        }

        # Exit loop if all paths show no recent activity
        if ($allClear) { break }

        # Wait before performing another sync check
        Start-Sleep -Seconds $intervalSeconds
    }

    # Log that sync appears complete
    Write-Log -logBox $logBox -message "All sync operations completed"
}


function Start-BackupProcess {
    <#
    .SYNOPSIS
    Executes all backup jobs (zip or file) and waits for sync completion.

    .DESCRIPTION
    This function iterates over a list of backup jobs and performs either a zip backup
    or a file copy (Mirror or Append) depending on each job's settings. After processing
    all jobs, it monitors the destination folders for ongoing sync activity (e.g., cloud sync)
    and waits until all operations are complete. It uses GUI components for logging and progress display.
    #>

    param (
        $jobs,          # List of backup jobs (built from GUI input)
        $gui,           # Reference to the GUI components (LogBox, ProgressBar, etc.)
        $copySettings   # Copy-related settings (retries, wait, threads, post-backup delay, etc.)
    )

    foreach ($job in $jobs) {
        if ($job.Zip) {
            # ---- Run ZIP backup ----
            Invoke-ZipOperation -source $job.Source -dest $job.Dest `
                -zipName $job.ZipName -frequency $job.Frequency `
                -keepCount $job.Keep -logBox $gui.LogBox
        } else {
            # ---- Run FILE backup (Mirror or Append) ----
            $mode = if ($job.Mirror) { "Mirror" } else { "Append" }

            Invoke-FileCopyOperation -source $job.Source -dest $job.Dest `
                -mode $mode -logBox $gui.LogBox -progressBar $gui.ProgressBar `
                -retries $copySettings.RobocopyRetries `
                -wait    $copySettings.RobocopyWait `
                -threads $copySettings.RobocopyThreads
        }
    }

    # ---- Monitor all destination folders for sync activity (e.g., Google Drive, Dropbox) ----
    $destPaths = $jobs.Dest | Where-Object { -not [string]::IsNullOrEmpty($_) }

    if ($destPaths) {
        Wait-ForSyncCompletion -paths $destPaths -logBox $gui.LogBox `
            -intervalSeconds $copySettings.SyncCheckInterval `
            -waitSeconds     $copySettings.SyncWaitSeconds
    }

    # ---- Final log message and optional delay before exiting or shutting down ----
    Write-Log -logBox $gui.LogBox -message "Backup process completed"
    Start-Sleep -Seconds $copySettings.PostBackupDelay
}


Export-ModuleMember -Function Convert-ToHashtable, Import-JsonFile, Get-ValidBackupJobs, 
    New-BackupJobs, Invoke-FileCopyOperation, Invoke-ZipOperation, Start-ProcessWithOutput, 
    Update-Progress, Get-ZipSuffix, Remove-ExistingZip, New-ZipArchive, Set-BackupRetention,
    Wait-ForSyncCompletion, Start-BackupProcess