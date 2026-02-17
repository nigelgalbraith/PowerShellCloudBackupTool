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
    
    # If the settings file exists, load and return it
    if (Test-Path $settingsPath) {
        return Get-Content $settingsPath -Raw | ConvertFrom-Json
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

    # Convert settings to JSON and save to the specified path
    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath
}


Export-ModuleMember -Function Initialize-BackupSettings, Save-CurrentSettings