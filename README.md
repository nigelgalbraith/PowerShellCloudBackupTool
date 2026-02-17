# PowerShell Cloud Backup Tool

A Windows PowerShell GUI tool for running repeatable backups into cloud-sync folders (Google Drive / Dropbox / Mega).

It’s designed for practical daily use:
- pick one or more source folders/files
- choose a provider destination (restricted to approved destinations per provider)
- run **File Backup** (Mirror/Append) or **Zip Backup**
- keep a rolling set of zip snapshots
- log everything to a timestamped log file and the GUI terminal

---

## What It Does

Per provider tab, you can configure:

- **Source**: one or more paths (stored as multiple lines)
- **Destination**: must match one of that provider’s allowed destinations (defined in JSON)
- **Backup Type**
  - **File** backup
    - **Mirror**: sync to match source (uses Robocopy mirror behaviour)
    - **Append**: add/update without deleting (copy only)
  - **Zip** backup
    - Frequency label (daily/weekly/monthly) + a name pattern
    - Keep a set number of recent zip backups
- Optional “Backup + Shutdown” workflow (when enabled in the UI)

---

## How It Works

- `main.ps1` loads configuration from `config/mainConfig.json`
- Cloud providers and destination restrictions come from `config/cloudProviders.json`
- User settings are stored in `config/backupSettings.json`
- Core logic is in modular `.psm1` files under `Modules/`
  - Config + settings load/save
  - Job validation
  - File copy operations (Robocopy)
  - Zip creation + retention
  - GUI construction (WinForms) and a multi-select TreeView source picker

---

## Requirements

- Windows
- PowerShell (Windows PowerShell 5.1 or PowerShell 7+)
- Robocopy available (built into Windows)
- Execution policy allowing local script execution (or use the provided launcher)

---

## Run

### Option A: Double-click
- `BackupTool.bat`

### Option B: PowerShell
```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\main.ps1
