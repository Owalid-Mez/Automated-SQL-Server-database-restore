#SQL Server Automated Restore Script

Automated SQL Server database restore from .bak, .rar, or .zip files using PowerShell (no external SQL scripts required).
This script provides a full-featured GUI and automation for restoring databases from local or network backups, with logging, optional parallel execution, and archive extraction.

#Features

- Lists live SQL Server databases dynamically.
- Optional filtering of databases by name.
- Copies backup files from a network share before restoring.
- Automatically extracts .rar and .zip archives.
- Verifies backups using RESTORE VERIFYONLY.
- Restores selected databases with progress tracking.
- Supports parallel restoration for multiple databases.
- Full UTF-8 logging of all operations.
- Optionally deletes .bak files after restoration.

#Requirements

- Windows PowerShell 5.1+
- SQL Server module (SqlServer) installed
- Permissions to execute RESTORE DATABASE and xp_cmdshell on SQL Server
- WinRAR (unrar.exe) or 7-Zip (7z.exe) installed for archive extraction
- Network access if copying backups from a network share

#Installation

1- Clone or download this repository
2- Place the script and required batch or backup files in a safe folder.
3- Ensure the SQL Server module is installed:
4- Install-Module SqlServer -Scope CurrentUser

#Configuration

The script uses a GUI form to configure parameters. Default configuration values:
Parameter	Description
Folder	-> Base folder for backups
RestorePath -> Path where .bak, .rar, or .zip files are copied/extracted
Instance ->	SQL Server instance name (e.g., localhost\SQLEXPRESS)
Login	SQL -> Server login username
Password ->	SQL Server login password
LogFolder ->	Folder to store logs
DataPath ->	Path for restored database files (.mdf & .ldf)
Parallel ->	Run restores in parallel (true/false)
AutoDeleteBak ->	Delete .bak files after successful restore (true/false)

#Usage

- Run the script in PowerShell. If double-clicked, it will pause for user input.
- Configure parameters in the GUI form (instance, credentials, paths, etc.).
- Choose backup files:
 * If .bak, .rar, or .zip files already exist in the restore path, you can:
    - Restore directly, or
    - Copy new files from a network share
 * You can select network sources and specific subfolders to copy.
- Filter databases by name if desired (start, end, or contain).
- Select databases to restore.
- Confirm the operation by typing a randomly generated word (safety confirmation).
- The script will verify backups, extract archives, and restore databases.
- Monitor progress in the console with a progress bar.
- Logs are saved in the specified LogFolder.

#Notes

- The script supports .rar and .zip archives; at least one extraction tool must be installed.
- Parallel restore can speed up operations but requires sufficient server resources.
- Network copy credentials are stored in the script—consider securing them or using a secure vault.
- Always test restores in a non-production environment before running on live servers.

#Logging

Logs are created in the LogFolder with a timestamped filename:
RestoreLog_YYYYMMDD_HHMMSS.txt


Logs include:

- SQL Server connection checks
- Backup file verification
- Archive extraction details
- Restore progress and errors
- Optional deletion of .bak files

#License

This project is licensed under the MIT License

