# PowerShell Cloud Backup Tool

A Windows PowerShell GUI tool for running structured, repeatable backups into cloud-sync folders (Google Drive, Dropbox, Mega).

This tool was built to make cloud backups predictable, modular, and configurable.

Everything is driven by configuration files and small, focused modules.

---

## Overview

The project is structured around:

- `main.ps1` (entry point)
- Modular `.psm1` files under `Modules/`
- JSON configuration files under `config/`
- Robocopy for file operations
- Built-in zip compression
- Structured logging

Each component has a clear responsibility.

---

## Features

Per provider tab (Google / Dropbox / Mega), you can:

- Select multiple source folders or files
- Choose a restricted destination path (defined per provider)
- Select backup type:
  - **File Backup**
    - **Append** – copy new/updated files only
    - **Mirror** – make destination exactly match source (deletes removed files)
  - **Zip Backup**
    - Create timestamped archive
    - Choose frequency label (Daily / Weekly / Monthly)
    - Define how many archives to retain
- Run:
  - **Backup**
  - **Backup + Shutdown** (waits for sync before powering off)

---

## Step-by-Step Usage

### Step 1 — Launch

Run:

```powershell
.\main.ps1
```

Or double-click:

```
BackupTool.bat
```

The GUI loads previous saved settings automatically.

---

### Step 2 — Configure Source and Destination

- Use Browse buttons to select one or more source paths.
- Each provider has its own tab.
- Destination must match one of the allowed provider paths defined in `cloudProviders.json`.

This prevents accidental backups to unintended locations.

---

### Step 3 — Choose File Backup Mode

If **File Backup** is selected:

- **Append**  
  Adds new or changed files to destination without deleting anything.

- **Mirror**  
  Makes destination identical to source (uses Robocopy mirror behaviour).
   ⚠️ Important: Mirror mode can permanently delete files from the destination if they no longer exist in the source.
   While most cloud providers offer a recycle bin (often ~30 days), recovery is not guaranteed use this mode carefully.

---

### Step 4 — Choose Zip Backup Mode

If **Zip Backup** is selected:

- Compress source into timestamped archive
- Choose frequency label
- Define how many previous zip backups to retain

Useful for versioned backups or historical snapshots.

---

### Step 5 — Run Backup or Shutdown

- Click **Backup** to execute.
- Click **Backup + Shutdown** to:
  - Run backup
  - Attempt to wait for cloud sync completion
  - Shutdown system

Note:
Cloud sync detection depends on provider behaviour. In some cases, shutdown may occur before full sync completes. If unsure, run a normal backup first and verify sync manually.

---

### Step 6 — Review the Log

After execution:

- View real-time log in GUI terminal window
- Logs are saved to:

```
<user-home>\logs\
```

Each run generates a timestamped log file.

---

## Architecture

### Entry Point

`main.ps1`

Responsible for:

- Loading configuration
- Initialising GUI
- Handling user actions
- Dispatching to modules

---

### Modules

#### BackupConfig.psm1
- Loads `mainConfig.json`
- Loads layout settings
- Handles application-wide configuration

#### BackupCore.psm1
- Validates source/destination
- Runs Robocopy operations
- Creates zip archives
- Applies retention rules
- Detects cloud sync completion
- Writes logs

#### BackupUI.psm1
- Builds GUI layout
- Creates provider tabs
- Handles button events

#### FileSystemUI.psm1
- Builds multi-select TreeView picker
- Returns selected paths to main form

---

## Configuration Files

Located in `config/`:

- `mainConfig.json` – layout, UI defaults
- `cloudProviders.json` – provider definitions and allowed destinations
- `backupSettings.json` – user selections (saved between sessions)

You can modify or extend providers without editing core script logic.

---

## Logging

- Logs written per run
- Timestamped filenames
- Stored in user home directory
- Printed to GUI terminal in real time
- Retention controlled by config

---

## Requirements

- Windows
- PowerShell (5.1 or 7+)
- Robocopy (built into Windows)

---

## License

MIT License.

Anyone is free to use, modify, distribute, or improve this code.
