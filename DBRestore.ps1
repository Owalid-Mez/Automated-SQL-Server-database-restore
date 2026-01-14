<#
.SYNOPSIS
    Automated SQL Server database restore from .bak, .rar, or .zip files (no external SQL script).

.DESCRIPTION
    - Lists live SQL databases
    - Optional name filtering
    - Extracts .rar and .zip files automatically
    - Verifies and restores backups
    - Logs all operations in UTF-8
#>
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Show-ConfigForm {
    param([hashtable]$Config)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Configuration de la restauration SQL"
    $form.Size = New-Object System.Drawing.Size(500, 500)
    $form.StartPosition = "CenterScreen"

    $font = New-Object System.Drawing.Font("Segoe UI", 9)
    [int]$y = 20
    $controls = @{}

    # --- Create labels and textboxes dynamically ---
    foreach ($key in $Config.Keys) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $key
        $label.Location = New-Object System.Drawing.Point(20, $y)
        $label.Size = New-Object System.Drawing.Size(120, 25)
        $label.Font = $font
        $form.Controls.Add($label)

        $textbox = New-Object System.Windows.Forms.TextBox
        $textbox.Text = $Config[$key]
        $textbox.Location = New-Object System.Drawing.Point(150, $y)
        $textbox.Size = New-Object System.Drawing.Size(300, 25)
        $textbox.Font = $font

        # Mask password field
        if ($key -eq 'Password') {
            $textbox.UseSystemPasswordChar = $true
        }

        $form.Controls.Add($textbox)
        $controls[$key] = $textbox
        $y += 35
    }

    # --- Buttons ---
    $startButton = New-Object System.Windows.Forms.Button
    $startButton.Text = "🚀 Démarrer"
    $startButton.Location  = New-Object System.Drawing.Point(150, [int]($y + 10))
    $startButton.Size = New-Object System.Drawing.Size(100, 35)
    $form.Controls.Add($startButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = " Annuler"
    $cancelButton.Location = New-Object System.Drawing.Point(270, [int]($y + 10))
    $cancelButton.Size = New-Object System.Drawing.Size(100, 35)
    $form.Controls.Add($cancelButton)

    # --- Button Events ---
$startButton.Add_Click({
    $keys = @($Config.Keys)   # ← Copie statique des clés
    foreach ($key in $keys) {
        $Config[$key] = $controls[$key].Text
    }
    $global:UpdatedConfig = $Config
    $form.Tag = "OK"
    $form.Close()
})
$Config["AutoDeleteBak"] = [System.Convert]::ToBoolean($Config["AutoDeleteBak"])
$Config["Parallel"] = [System.Convert]::ToBoolean($Config["Parallel"])

    $cancelButton.Add_Click({
        $form.Tag = "Cancel"
        $form.Close()
    })

    # --- Show the form ---
    $form.ShowDialog() | Out-Null

    if ($form.Tag -eq "OK") {
        return $global:UpdatedConfig
    } else {
        Write-Host " Opération annulée par l'utilisateur." -ForegroundColor Red
        return $null
    }
}

# ================== CONFIGURATION ===================
$Config = @{
    Folder        = "D:"
    RestorePath   = "D:\Restore"
    Instance      = "localhost\SQLEXPRESS"
    Login         = "sa"
    Password      = "123456"
    LogFolder     = "Logs"
    DataPath      = "E:\DATA\BDD"
    Parallel      = $false
    AutoDeleteBak = $false
}

# --- Show editable form ---
$updated = Show-ConfigForm -Config $Config

if ($null -eq $updated) {
    Write-Host " Opération annulée. Rien n’a été modifié." -ForegroundColor Yellow
    return
}

$Config = $updated

Write-Host "`nConfiguration confirmée :"
$Config.GetEnumerator() | ForEach-Object {
    Write-Host ("{0,-15}: {1}" -f $_.Key, $_.Value) -ForegroundColor Cyan
}

# Pause if script was double-clicked
if ($Host.Name -eq 'ConsoleHost') {
    Read-Host "`nAppuyez sur Entrée pour continuer..."
}



# ================== ENVIRONMENT ===================
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Import-Module SqlServer -ErrorAction SilentlyContinue

if (!(Test-Path $Config.LogFolder)) {
    New-Item -ItemType Directory -Path $Config.LogFolder | Out-Null
}

$LogFile = Join-Path $Config.LogFolder "RestoreLog_$(Get-Date -Format yyyyMMdd_HHmmss).txt"

Function Write-Log {
    param([string]$Message, [string]$Color = "Gray")
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$time - $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $Message -ForegroundColor $Color
}

# ================== ASK: COPY OR DIRECT RESTORE (.bak / .rar / .zip) ===================

# Detect existing backup-related files
$existingBak = Get-ChildItem "$($Config.RestorePath)\*.bak" -ErrorAction SilentlyContinue
$existingRar = Get-ChildItem "$($Config.RestorePath)\*.rar" -ErrorAction SilentlyContinue
$existingZip = Get-ChildItem "$($Config.RestorePath)\*.zip" -ErrorAction SilentlyContinue

if ($existingBak -or $existingRar -or $existingZip) {
    Write-Host "`nDes fichiers de sauvegarde ont été détectés dans $($Config.RestorePath):" -ForegroundColor Yellow

    if ($existingBak) { Write-Host " - $($existingBak.Count) fichier(s) .bak" -ForegroundColor Gray }
    if ($existingRar) { Write-Host " - $($existingRar.Count) fichier(s) .rar" -ForegroundColor Gray }
    if ($existingZip) { Write-Host " - $($existingZip.Count) fichier(s) .zip" -ForegroundColor Gray }

    Write-Host "`nSouhaitez-vous restaurer directement ou copier de nouvelles sauvegardes ?" -ForegroundColor Cyan
    Write-Host "[1] Restaurer directement les fichiers existants"
    Write-Host "[2] Copier automatiquement depuis le réseau avant restauration"

    $copyChoice = Read-Host "`nEntrez 1 ou 2"

    $DoCopy = $false
    if ($copyChoice -eq '2') {
        Write-Log "Copie réseau sélectionnée avant restauration." "Green"
        $DoCopy = $true
    } else {
        Write-Log "Restauration directe sélectionnée — les fichiers existants seront utilisés." "Yellow"
    }

} else {
    Write-Host "`nAucun fichier .bak, .rar ou .zip trouvé dans $($Config.RestorePath)." -ForegroundColor Cyan
    Write-Host "Souhaitez-vous copier automatiquement les fichiers de sauvegarde depuis le réseau," `
        "ou bien passer directement à la restauration ?" -ForegroundColor Cyan
    Write-Host "[1] Copier automatiquement les fichiers"
    Write-Host "[2] Passer directement à la restauration (aucune copie réseau)"
    $copyChoice = Read-Host "`nEntrez 1 ou 2"

    $DoCopy = $true
    if ($copyChoice -eq '2') {
        Write-Log "Mode restauration directe sélectionné — saut de la phase de copie réseau." "Yellow"
        $DoCopy = $false
    } else {
        Write-Log "Mode copie automatique sélectionné." "Green"
    }
}


# ================== GLOBAL PROGRESS TRACKER ===================
$GlobalProgress = @{
    Step = 0
    TotalSteps = 3  # Copy, Extract, Restore
}
function Show-GlobalProgress {
    param([string]$Status)
    $GlobalProgress.Step++
    $percent = [math]::Round(($GlobalProgress.Step / $GlobalProgress.TotalSteps) * 100, 0)
    Write-Progress -Id 0 -Activity "Progression générale" `
                   -Status $Status `
                   -PercentComplete $percent
}

if ($DoCopy) {

# ================== COPY LATEST BACKUP FOLDER (.RAR) WITH NETWORK LOGIN ===================

# --- Let user choose between multiple network roots ---
$availableRoots = @(
    "\\192.168.100.9\Public\auto_saves_250",
    "\\192.168.100.9\Public\auto_saves_249"
)

Write-Host "`nSources disponibles :" -ForegroundColor Cyan
for ($i = 0; $i -lt $availableRoots.Count; $i++) {
    Write-Host "[$($i+1)] $($availableRoots[$i])"
}

$rootChoice = Read-Host "`nEntrez le numéro de la source à utiliser (ex: 1 ou 2)"
if ($rootChoice -match '^\d+$' -and $rootChoice -ge 1 -and $rootChoice -le $availableRoots.Count) {
    $SourceRoot = $availableRoots[$rootChoice - 1]
} else {
    Write-Host "Choix invalide. Utilisation de la première source par défaut." -ForegroundColor Yellow
    $SourceRoot = $availableRoots[0]
}

$Destination  = $Config.RestorePath
$NetworkUser  = "NetUser"
$NetworkPass  = "PassW0rd"   # You can replace this with Read-Host -AsSecureString for security

Write-Log "Connexion au partage réseau $SourceRoot..." "Cyan"

# --- Connect to network share ---
try {
    net use $SourceRoot /delete /yes | Out-Null 2>&1
    $cmd = "net use `"$SourceRoot`" /user:`"$NetworkUser`" `"$NetworkPass`"" 
    Invoke-Expression $cmd | Out-Null
    Write-Log "Connexion réussie au partage réseau." "Green"
} catch {
    Write-Log "Erreur de connexion au partage réseau : $_" "Red"
    exit
}

# --- Locate latest dated folder ---
# Prompt user
$userInput = Read-Host "Entrez une date (YYYY_MM_DD), tapez 'yesterday' ou laissez vide pour la dernière sauvegarde"

# Get all backup folders
$backupFolders = Get-ChildItem -Path $SourceRoot -Directory | Where-Object { $_.Name -match '^\d{4}_\d{2}_\d{2}$' }

if (-not $backupFolders) {
    Write-Log "Aucun dossier de sauvegarde trouvé dans $SourceRoot." "Red"
    exit
}

if ([string]::IsNullOrWhiteSpace($userInput)) {
    # --- Automatic: latest folder ---
    $latestFolder = $backupFolders | Sort-Object Name -Descending | Select-Object -First 1
    Write-Log "Dernier dossier trouvé : $($latestFolder.Name)" "Green"
}
elseif ($userInput -eq 'yesterday') {
    $yesterday = (Get-Date).AddDays(-1).ToString('yyyy_MM_dd')
    $latestFolder = $backupFolders | Where-Object { $_.Name -eq $yesterday } | Select-Object -First 1
    if ($latestFolder) {
        Write-Log "Dossier d'hier trouvé : $($latestFolder.Name)" "Green"
    } else {
        Write-Log "Aucun dossier pour hier ($yesterday)." "Yellow"
        exit
    }
}
elseif ($userInput -match '^\d{4}_\d{2}_\d{2}$') {
    $latestFolder = $backupFolders | Where-Object { $_.Name -eq $userInput } | Select-Object -First 1
    if ($latestFolder) {
        Write-Log "Dossier sélectionné : $($latestFolder.Name)" "Green"
    } else {
        Write-Log "Aucun dossier pour la date $userInput." "Yellow"
        exit
    }
}
else {
    Write-Log "Format de date invalide." "Red"
    exit
}

# --- List subfolders (e.g., Comptabilité, Stock, Commercial) ---
$subFolders = Get-ChildItem -Path $latestFolder.FullName -Directory
if (-not $subFolders) {
    Write-Log "Aucun sous-dossier trouvé dans $($latestFolder.Name)." "Red"
    exit
}

Write-Host "`nSous-dossiers disponibles :" -ForegroundColor Cyan
$index = 1
$folderMap = @{}
foreach ($f in $subFolders) {
    Write-Host "[$index] $($f.Name)"
    $folderMap[$index] = $f
    $index++
}

# --- Let user choose subfolder(s) ---
$selection = Read-Host "`nEntrez le(s) numéro(s) du ou des dossiers à copier (ex: 1,2 ou 'all' pour tout)"
if ($selection -eq "all") {
    $selectedFolders = $subFolders
} else {
    $selectedFolders = @()
    $selection -split "," | ForEach-Object {
        $num = $_.Trim()
        if ($folderMap.ContainsKey([int]$num)) {
            $selectedFolders += $folderMap[[int]$num]
        }
    }
}

if (-not $selectedFolders -or $selectedFolders.Count -eq 0) {
    Write-Log "Aucun dossier sélectionné." "Red"
    exit
}

Write-Host "`nDossiers sélectionnés :" -ForegroundColor Yellow
$selectedFolders | ForEach-Object { Write-Host " - $($_.Name)" }

# --- Ask for file name filter ---
$filterText = Read-Host "`nSouhaitez-vous copier uniquement certains fichiers ? (laisser vide pour tout copier)"
if ($filterText) {
    Write-Log "Filtrage activé : seuls les fichiers contenant '$filterText' seront copiés." "Yellow"
} else {
    Write-Log "Aucun filtre appliqué, tous les fichiers .rar seront copiés." "Yellow"
}

# --- Cleanup old .rar files ---
Write-Log "Nettoyage des anciens fichiers .rar dans $Destination..." "Yellow"
Get-ChildItem -Path $Destination -Filter *.rar -ErrorAction SilentlyContinue | Remove-Item -Force

# --- Copy .rar files from each selected folder ---
foreach ($folder in $selectedFolders) {
    Write-Log "Copie des fichiers .rar depuis $($folder.FullName)..." "Cyan"
    $rarFiles = Get-ChildItem -Path $folder.FullName -Filter *.rar -ErrorAction SilentlyContinue

    if ($filterText) {
        $rarFiles = $rarFiles | Where-Object { $_.Name -match [regex]::Escape($filterText) }
    }

    if (-not $rarFiles) {
        Write-Log "Aucun fichier .rar correspondant trouvé dans $($folder.Name)." "Yellow"
        continue
    }

 $total = $rarFiles.Count
$count = 0

foreach ($file in $rarFiles) {
        if ($global:abort) {
        Write-Host "`n Annulé par l'utilisateur." -ForegroundColor Red
        Write-Log "Annulé manuellement." "Red"
        break
    }
    $count++
    $percent = [math]::Round(($count / $total) * 100, 0)

    Write-Progress -Activity "Copie des fichiers .rar" `
                   -Status "Copie de $($file.Name) ($count sur $total)" `
                   -PercentComplete $percent

    try {
        $destFile = Join-Path $Destination $file.Name
        Copy-Item -Path $file.FullName -Destination $destFile -Force
        Write-Log "Copié : $($file.Name)" "Gray"
    } catch {
        Write-Log "Erreur lors de la copie de $($file.Name) : $_" "Red"
    }
}

Write-Progress -Activity "Copie des fichiers .rar" -Completed -Status "Terminé"
}

Write-Log "Tous les fichiers .rar sélectionnés ont été copiés vers $Destination." "Green"
Show-GlobalProgress "Copie des fichiers terminée"
# --- Disconnect network share ---
net use $SourceRoot /delete /yes | Out-Null 2>&1
Write-Log "Déconnexion du partage réseau effectuée." "Gray"
}

# ================== FETCH DATABASES ===================
Write-Log "Récupération de la liste des bases de données à partir du serveur SQL..." "Cyan"

try {
    $dbList = Invoke-Sqlcmd -ServerInstance $Config.Instance -Username $Config.Login -Password $Config.Password  -QueryTimeout 0 `
        -Query "SELECT name FROM sys.databases WHERE name NOT IN ('master','tempdb','model','msdb') ORDER BY name"
} catch {
    Write-Log "Erreur : impossible de se connecter à l'instance SQL $($Config.Instance)" "DarkRed"
    exit
}

if (-not $dbList) { Write-Log "Aucune base trouvée sur le serveur." "DarkRed"; exit }

# ================== FILTER ===================
$filterChoice = Read-Host "Souhaitez-vous filtrer les bases par nom ? (o/n)"
if ($filterChoice -eq 'o') {
    $filterType = Read-Host "Type de filtre ? (start / end / contain)"
    $filterValue = Read-Host "Entrez le texte du filtre"
    
    switch ($filterType.ToLower()) {
        'start'   { $dbList = $dbList | Where-Object { $_.name -like "$filterValue*" } }
        'end'     { $dbList = $dbList | Where-Object { $_.name -like "*$filterValue" } }
        'contain' { $dbList = $dbList | Where-Object { $_.name -like "*$filterValue*" } }
        default   { Write-Host "Filtre non reconnu." -ForegroundColor Yellow }
    }
}

if (-not $dbList -or $dbList.Count -eq 0) {
    Write-Log "Aucune base correspondante trouvée." "DarkRed"
    exit
}

# ================== SELECTION ===================
$index = 1
$dbMap = @{}
foreach ($db in $dbList) {
    Write-Host ("[{0}] {1}" -f $index, $db.name)
    $dbMap[$index] = $db.name
    $index++
}
function Confirm-Action {
    param(
        [string]$Message = "Confirmez l'opération",
        [int]$Length = 6
    )

    # 🔹 Generate a random word (letters only)
    $chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    $rand = -join ((1..$Length) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })

    Write-Host ""
    Write-Host "$Message" -ForegroundColor Yellow
    Write-Host "Veuillez taper le mot suivant pour confirmer : " -NoNewline
    Write-Host $rand -ForegroundColor Cyan

    $input = Read-Host " Votre saisie"

    if ($input -ne $rand) {
        Write-Host " Confirmation échouée. Processus annulé." -ForegroundColor Red
        exit
    }

    Write-Host " Confirmation réussie." -ForegroundColor Green
}
$selection = Read-Host "Entrez les numéros à restaurer (ex: 1,3,5 ou 1-3 ou 'all')"

if ($selection -eq "all") {
    $selectedDBs = $dbList.name
} else {
    $selectedDBs = @()
    
    # Split by comma
    $parts = $selection -split "," | ForEach-Object { $_.Trim() }

    foreach ($part in $parts) {
        if ($part -match '^\d+$') {
            # Single number
            if ($dbMap.ContainsKey([int]$part)) { $selectedDBs += $dbMap[[int]$part] }
        }
        elseif ($part -match '^(\d+)-(\d+)$') {
            # Range, e.g., 1-3
            $start = [int]$matches[1]
            $end   = [int]$matches[2]
            for ($i = $start; $i -le $end; $i++) {
                if ($dbMap.ContainsKey($i)) { $selectedDBs += $dbMap[$i] }
            }
        }
    }
}


if (-not $selectedDBs) { Write-Log "Aucune base sélectionnée."; exit }

Write-Host "`nBases sélectionnées:" -ForegroundColor Yellow
$selectedDBs | ForEach-Object { Write-Host " - $_" }

Confirm-Action "Cette opération va restaurer les bases et potentiellement écraser des données."

# ================== ARCHIVE EXTRACTION (.RAR / .ZIP) ===================
$rarFiles = Get-ChildItem "$($Config.RestorePath)\*.rar" -ErrorAction SilentlyContinue
$zipFiles = Get-ChildItem "$($Config.RestorePath)\*.zip" -ErrorAction SilentlyContinue

if ($rarFiles -or $zipFiles) {
    Write-Log "Extraction des fichiers d'archives (.rar / .zip)..." "Cyan"

    # --- Détection automatique des outils disponibles ---
    $unrarPath = "C:\Program Files\WinRAR\unrar.exe"
    $sevenZipPath = "C:\Program Files\7-Zip\7z.exe"



    $useTool = $null
    if (Test-Path $unrarPath) {
        $useTool = "WinRAR"
        Write-Log "Utilisation de WinRAR pour l'extraction." "Green"
    } elseif (Test-Path $sevenZipPath) {
        $useTool = "7-Zip"
        Write-Log "WinRAR introuvable — utilisation de 7-Zip." "Yellow"
    } else {
        Write-Log " Aucun extracteur trouvé (WinRAR ni 7-Zip). Extraction impossible." "Red"
        exit 1
    }

    # --- Extraction des fichiers RAR ---
    if ($rarFiles) {
        Write-Log "Extraction des fichiers .RAR..." "Cyan"
        $totalRar = $rarFiles.Count
        $indexRar = 0

        foreach ($rar in $rarFiles) {
            $indexRar++
            $percent = [math]::Round(($indexRar / $totalRar) * 100, 0)
            Write-Progress -Activity "Extraction RAR" -Status $rar.Name -PercentComplete $percent

            try {
                if ($useTool -eq "WinRAR") {
                    Start-Process -FilePath $unrarPath -ArgumentList "e -y `"$($rar.FullName)`" `"$($Config.RestorePath)`"" -Wait -NoNewWindow
                } elseif ($useTool -eq "7-Zip") {
                    Start-Process -FilePath $sevenZipPath -ArgumentList "x `"$($rar.FullName)`" -o`"$($Config.RestorePath)`" -y" -Wait -NoNewWindow
                }

                Write-Log " Archive extraite : $($rar.Name)" "Green"
                Remove-Item $rar.FullName -Force
            } catch {
                Write-Log " Erreur lors de l'extraction de $($rar.Name) : $_" "Red"
            }
        }

        Write-Progress -Activity "Extraction RAR" -Completed
    }

    # --- Extraction des fichiers ZIP ---
    if ($zipFiles) {
        Write-Log "Extraction des fichiers .ZIP..." "Cyan"
        $totalZip = $zipFiles.Count
        $indexZip = 0

        foreach ($zip in $zipFiles) {
            $indexZip++
            $percent = [math]::Round(($indexZip / $totalZip) * 100, 0)
            Write-Progress -Activity "Extraction ZIP" -Status $zip.Name -PercentComplete $percent

            try {
                Expand-Archive -Path $zip.FullName -DestinationPath $Config.RestorePath -Force
                Write-Log " Archive extraite : $($zip.Name)" "Green"
                Remove-Item $zip.FullName -Force
            } catch {
                Write-Log " Erreur lors de l'extraction de $($zip.Name) : $_" "Red"
            }
        }

        Write-Progress -Activity "Extraction ZIP" -Completed
    }
}

# ================== FIND BAK FILES ===================
$bakFiles = Get-ChildItem "$($Config.RestorePath)\*.bak" -ErrorAction SilentlyContinue
if (-not $bakFiles) { Write-Log "Aucun fichier .bak trouvé."; exit }

$selectedFiles = @()
foreach ($db in $selectedDBs) {
    $match = $bakFiles | Where-Object { $_.BaseName -eq $db }
    if ($match) { $selectedFiles += $match } 
    else { Write-Log " Aucun fichier .bak trouvé pour '$db'." "Yellow" }
}

if (-not $selectedFiles) { Write-Log "Aucun fichier .bak correspondant."; exit }
Write-Log "Bases à restaurer : $($selectedFiles.BaseName -join ', ')" "Cyan"


# ================== RESTORE FUNCTION ===================
function Restore-Database {
    param(
        [Parameter(Mandatory = $true)] $bakFile,
        [Parameter(Mandatory = $true)] $Config
    )

    $dbName = [System.IO.Path]::GetFileNameWithoutExtension($bakFile.Name)
    Write-Output "[$dbName] Démarrage restauration..."

    try {
        $fileList = Invoke-Sqlcmd -ServerInstance $Config.Instance -Username $Config.Login -Password $Config.Password -QueryTimeout 0 `
            -Query "RESTORE FILELISTONLY FROM DISK = N'$($bakFile.FullName)'"

        if (-not $fileList) {
            Write-Output " [$dbName] Impossible de lire les métadonnées du backup."
            return
        }

        $logicalData = ($fileList | Where-Object { $_.Type -eq 'D' }).LogicalName
        $logicalLog  = ($fileList | Where-Object { $_.Type -eq 'L' }).LogicalName

        $mdfDest = Join-Path $Config.DataPath "$dbName.mdf"
        $ldfDest = Join-Path $Config.DataPath "$dbName.ldf"

        Invoke-Sqlcmd -ServerInstance $Config.Instance -Username $Config.Login -Password $Config.Password  -QueryTimeout 0 `
            -Query "IF EXISTS (SELECT name FROM sys.databases WHERE name = N'$dbName')
                    ALTER DATABASE [$dbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;"

        $restoreQuery = @"
RESTORE DATABASE [$dbName]
FROM DISK = N'$($bakFile.FullName)'
WITH FILE = 1,
MOVE N'$logicalData' TO N'$mdfDest',
MOVE N'$logicalLog'  TO N'$ldfDest',
REPLACE, STATS = 5;
"@

        Invoke-Sqlcmd -ServerInstance $Config.Instance -Username $Config.Login -Password $Config.Password -QueryTimeout 0 -Query $restoreQuery 
        Write-Output " [$dbName] restauration terminée avec succès."

        Invoke-Sqlcmd -ServerInstance $Config.Instance -Username $Config.Login -Password $Config.Password -QueryTimeout 0 `
            -Query "ALTER DATABASE [$dbName] SET MULTI_USER;"

     if ([System.Convert]::ToBoolean($Config.AutoDeleteBak)) {
    Remove-Item $bakFile.FullName -Force
    Write-Output " [$dbName] Fichier .bak supprimé."
}

    } catch {
        Write-Output " [$dbName] Erreur : $_"
    }
}
# ================== VERIFY BACKUPS ===================
Write-Log "Vérification des fichiers bak (RESTORE VERIFYONLY)..." "Cyan"

$totalRestores = $selectedFiles.Count
$done = 0

foreach ($bak in $selectedFiles) {
    try {
        Invoke-Sqlcmd -ServerInstance $Config.Instance -Username $Config.Login -Password $Config.Password -QueryTimeout 0 `
            -Query "RESTORE VERIFYONLY FROM DISK = N'$($bak.FullName)';"
        Write-Log " Vérification réussie pour $($bak.Name)." "Green"
    } catch {
        Write-Log " Échec de la vérification du backup $($bak.Name) : $_" "Red"
    }
}

Write-Progress -Activity "Restauration SQL" -Completed -Status "Terminé"
Show-GlobalProgress "Restauration terminée"
Write-Progress -Id 0 -Activity "Progression générale" -Completed -Status "Processus complet terminé"


# ================== RESTORE LOOP (Parallel + Progress) ===================
Write-Log "Début de la restauration..." "Cyan"

$totalJobs = $selectedFiles.Count
$completed = 0

if ([System.Convert]::ToBoolean($Config.Parallel) -and $selectedFiles.Count -gt 1) {
    Write-Log "Mode parallèle activé — lancement de plusieurs restaurations simultanées..." "Yellow"

    # Capture function definition for child jobs
    $restoreFunc = ${function:Restore-Database}

    $jobs = @()
    foreach ($bak in $selectedFiles) {
        $jobs += Start-Job -ScriptBlock {
            param($bakPath, $Config, $restoreFunc)

            Import-Module SqlServer -ErrorAction SilentlyContinue

            # Correct: Redefine function in memory
            Set-Item function:Restore-Database $restoreFunc

            $bakFile = Get-Item $bakPath
            Restore-Database -bakFile $bakFile -Config $Config
        } -ArgumentList $bak.FullName, $Config, $restoreFunc
    }

    Write-Host "`n Suivi des restaurations en parallèle..." -ForegroundColor Cyan

    while ($true) {
        $completed = ($jobs | Where-Object { $_.State -eq 'Completed' }).Count
        $percent = [math]::Round(($completed / $totalJobs) * 100, 0)
        Write-Progress -Activity "Progression globale des restaurations" `
                       -Status "$completed / $totalJobs terminées" `
                       -PercentComplete $percent

        if ($completed -eq $totalJobs) { break }
        Start-Sleep -Seconds 2
    }

    $results = $jobs | Receive-Job
    foreach ($line in $results) { Write-Log $line }

    Write-Progress -Activity "Progression globale des restaurations" -Completed
    $jobs | Remove-Job | Out-Null

} else {
    Write-Log "Mode séquentiel activé — une restauration à la fois..." "Yellow"
    foreach ($bak in $selectedFiles) {
        $completed++
        $percent = [math]::Round(($completed / $totalJobs) * 100, 0)
        Write-Progress -Activity "Restauration séquentielle" -Status "$completed / $totalJobs" -PercentComplete $percent
        Restore-Database -bakFile $bak -Config $Config
    }
    Write-Progress -Activity "Restauration séquentielle" -Completed
}

Write-Log "=== Toutes les bases de données sélectionnées ont été traitées ===" "Green"

Write-Host "`nAppuyez sur une touche pour fermer..." -ForegroundColor Yellow
[void][System.Console]::ReadKey($true)
