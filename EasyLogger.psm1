# ================================
#  EasyLogger - reusable logging
# ================================

<#
.SYNOPSIS
EasyLogger - Module de logs lisibles, structurés et exportables pour PowerShell.

.DESCRIPTION
EasyLogger fournit un système de logs avec icônes, couleurs, timestamp,
indentation par niveau, gestion de buffers multiples (par BufferId),
filtrage par sévérité ou niveau et export dans un fichier.

Comportement général :
- Chaque entrée de log stocke toujours un timestamp brut (propriété Timestamp).
- La propriété Line ne contient pas le timestamp, uniquement l'indentation,
  l'icône et le message.
- L'affichage en console respecte la config ShowTimestamp (Initialize-EasyLogger).
- Les sorties texte (Get-LogText, Save-LogToFile) peuvent optionnellement
  préfixer chaque ligne avec le timestamp via IncludeTimestamp.

Par défaut :
- Write-Log sans paramètre Type produit un log 'Raw'
- Tous les logs vont dans le buffer 'default'
- Initialize-EasyLogger permet de remettre l’environnement de log à zéro par script
  (config + buffers), avec possibilité de surcharger la config.
#>

# ============================================================================
# Configuration par défaut (IMMUTABLE)
# ============================================================================
$script:DefaultLogConfig = [ordered]@{
    ShowTimestamp = $false
    IndentSize    = 1
    IndentChar    = '·'
    ShowConsole   = $true
    Colors        = [ordered]@{
        Add      = 'Blue'
        Info     = 'Cyan'
        Success  = 'Green'
        Error    = 'Red'
        Warning  = 'Yellow'
        Question = 'Magenta'
        Sub      = 'DarkGray'
        Raw      = $null
    }
}

# ============================================================================
# Helper interne : création d'une nouvelle config depuis DefaultLogConfig
# ============================================================================
function New-LogConfigFromDefault {
    $cfg = [ordered]@{}

    foreach ($key in $script:DefaultLogConfig.Keys) {
        if ($key -ne 'Colors') {
            $cfg[$key] = $script:DefaultLogConfig[$key]
        }
    }

    $colorsCopy = [ordered]@{}
    foreach ($ck in $script:DefaultLogConfig.Colors.Keys) {
        $colorsCopy[$ck] = $script:DefaultLogConfig.Colors[$ck]
    }
    $cfg['Colors'] = $colorsCopy

    return $cfg
}

# ============================================================================
# Configuration courante + Buffers (modifiable)
# ============================================================================
if (-not $script:LogConfig) {
    $script:LogConfig = New-LogConfigFromDefault
}

if (-not $script:LogBuffers) {
    $script:LogBuffers = @{}
}

# ============================================================================
# Initialize-EasyLogger
# ============================================================================
function Initialize-EasyLogger {
    <#
    .SYNOPSIS
    Réinitialise entièrement EasyLogger et, optionnellement, surchargre la config.

    .DESCRIPTION
    Initialize-EasyLogger :
    - Réinitialise la config à partir de DefaultLogConfig
    - Applique UNIQUEMENT les paramètres fournis (ShowTimestamp, IndentSize, IndentChar, ShowConsole, Colors)
    - Vide TOUS les buffers de log systématiquement

    À appeler en début de chaque script pour garantir un contexte propre.

    .PARAMETER ShowTimestamp
    Active ou désactive l'affichage du timestamp en console.
    Le timestamp reste toujours stocké dans les entrées de log et peut être réutilisé
    par Get-LogText / Save-LogToFile indépendamment de ce paramètre.

    .PARAMETER IndentSize
    Nombre d'espaces par niveau d'indentation.

    .PARAMETER IndentChar
    Caractère utilisé pour marquer l'indentation.

    .PARAMETER ShowConsole
    Active ou désactive l'affichage console
    (les logs sont toujours stockés dans les buffers).

    .PARAMETER Colors
    Hashtable qui mappe les Types ('Add','Info','Success','Error','Warning','Question','Sub','Raw')
    vers des couleurs supportées par Write-Host.
    #>
    [CmdletBinding()]
    param(
        [bool]$ShowTimestamp,
        [int] $IndentSize,
        [string]$IndentChar,
        [bool]$ShowConsole,
        [hashtable]$Colors
    )

    # Repart des valeurs par défaut
    $cfg = New-LogConfigFromDefault

    if ($PSBoundParameters.ContainsKey('ShowTimestamp')) {
        $cfg.ShowTimestamp = $ShowTimestamp
    }

    if ($PSBoundParameters.ContainsKey('IndentSize')) {
        $cfg.IndentSize = $IndentSize
    }

    if ($PSBoundParameters.ContainsKey('ShowConsole')) {
        $cfg.ShowConsole = $ShowConsole
    }

    if ($PSBoundParameters.ContainsKey('Colors') -and $Colors) {
        foreach ($key in $Colors.Keys) {
            $cfg.Colors[$key] = $Colors[$key]
        }
    }

    if ($PSBoundParameters.ContainsKey('IndentChar')) {
        $cfg.IndentChar = $IndentChar
    }

    $script:LogConfig = $cfg

    # Réinit buffers (toujours, même avec paramètres)
    $script:LogBuffers = @{}
}

# ============================================================================
# Write-Log
# ============================================================================
function Write-Log {
    <#
    .SYNOPSIS
    Écrit une entrée de log formatée avec icône, indentation, couleurs et buffers.

    .DESCRIPTION
    Write-Log :
    - génère un timestamp (toujours stocké dans la propriété Timestamp de l'entrée)
    - affiche la ligne en console avec ou sans timestamp selon :
        - la config globale ShowTimestamp (Initialize-EasyLogger)
        - un override local via le paramètre ShowTimestamp de Write-Log
    - stocke la ligne dans les buffers SANS timestamp dans la propriété Line
      (Line contient uniquement indentation + icône + message)

    Les buffers contiennent donc :
    - Timestamp : la date/heure brute de l'événement
    - Level     : niveau d'indentation
    - Type      : type de log (Add, Info, Error, etc.)
    - Message   : message brut
    - Line      : ligne formatée sans timestamp
    - BufferIds : liste des buffers dans lesquels l'entrée est présente
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Add','Info','Success','Error','Warning','Question','Sub','Raw')]
        [string]$Type = 'Raw',

        [int]$Level = 0,

        [Nullable[bool]]$ShowTimestamp,

        [switch]$NoStore,

        [Nullable[bool]]$ShowConsole,

        [string]$ColorOverride,

        [string[]]$BufferIds
    )

    # Buffers cibles
    $targets = @('default')
    if ($BufferIds) {
        $targets += $BufferIds
    }
    $targets = $targets | Select-Object -Unique

    # Création des buffers si manquants
    foreach ($bufId in $targets) {
        if (-not $script:LogBuffers.ContainsKey($bufId)) {
            $script:LogBuffers[$bufId] = @()
        }
    }

    # Icônes
    $iconMap = @{
        Add      = '[+]'
        Info     = '[i]'
        Success  = '[✓]'
        Error    = '[x]'
        Warning  = '[!]'
        Question = '[?]'
        Sub      = '[-]'
        Raw      = ''
    }

    $icon = $iconMap[$Type]

    # Timestamp toujours généré et stocké
    $timestampText = (Get-Date -Format 'dd-MM-yyyy HH:mm:ss')

    # ShowTimestamp : uniquement pour la console
    $useTimestampForConsole = $script:LogConfig.ShowTimestamp
    if ($PSBoundParameters.ContainsKey('ShowTimestamp')) {
        $useTimestampForConsole = $ShowTimestamp
    }

    $prefixConsole = if ($useTimestampForConsole) { "[$timestampText] " } else { '' }
    $prefixStore   = ''   # IMPORTANT : on NE met PAS le timestamp dans Line

    # Indentation
    $indent = if ($Level -gt 0) {
        ((" " + $script:LogConfig.IndentChar + " ") * $script:LogConfig.IndentSize) * $Level
    }
    else {
        ''
    }

    # Lignes finale : une pour la console, une pour le stockage
    if ($Type -eq 'Raw') {
        $lineStore   = "$prefixStore$indent$Message"     # sans timestamp
        $lineConsole = "$prefixConsole$indent$Message"   # avec ou sans timestamp
    }
    else {
        $lineStore   = "$prefixStore$indent$icon $Message"
        $lineConsole = "$prefixConsole$indent$icon $Message"
    }

    # Couleur
    $color = if ($ColorOverride) { $ColorOverride } else { $script:LogConfig.Colors[$Type] }

    # ShowConsole : Affiche où non dans la console
    $showConsoleOutput = $script:LogConfig.ShowConsole
    if ($PSBoundParameters.ContainsKey('ShowConsole')) {
        $showConsoleOutput = $ShowConsole
    }

    if ($showConsoleOutput) {
        if ($color) { Write-Host $lineConsole -ForegroundColor $color }
        else        { Write-Host $lineConsole }
    }

    # Stockage
    if (-not $NoStore) {
        $entry = [PSCustomObject]@{
            Timestamp = $timestampText  # valeur brute
            Level     = $Level
            Type      = $Type
            Message   = $Message
            Line      = $lineStore      # sans timestamp
            BufferIds = $targets
        }

        foreach ($bufId in $targets) {
            $script:LogBuffers[$bufId] += $entry
        }
    }
}

# ============================================================================
# Write-LogProgress (wrapper sur Write-Progress)
# ============================================================================
function Write-LogProgress {
    <#
    .SYNOPSIS
    Affiche une barre de progression en haut de la console.

    .DESCRIPTION
    Write-LogProgress utilise Write-Progress pour afficher une barre de progression
    native PowerShell au-dessus des logs EasyLogger.

    - Ne stocke rien dans les buffers
    - N'affiche rien si la console est désactivée (ShowConsole = $false)

    .PARAMETER Current
    Valeur courante (étape en cours).

    .PARAMETER Total
    Valeur totale (nombre d'étapes).

    .PARAMETER Label
    Texte affiché comme Activity.

    .PARAMETER Id
    Identifiant Write-Progress (permet d'avoir plusieurs barres si besoin).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Current,

        [Parameter(Mandatory)]
        [int]$Total,

        [string]$Label = "Processing",

        [int]$Id = 1
    )

    if (-not $script:LogConfig.ShowConsole) {
        return
    }

    if ($Total -le 0) { $Total = 1 }

    $percent = [math]::Floor(($Current / $Total) * 100)
    if ($percent -lt 0)   { $percent = 0 }
    if ($percent -gt 100) { $percent = 100 }

    if ($Current -ge $Total) {
        Write-Progress -Id $Id -Activity $Label -Completed
    }
    else {
        Write-Progress -Id $Id -Activity $Label -Status "$Current / $Total ($percent%)" -PercentComplete $percent
    }
}

# ============================================================================
# Stop-LogProgress
# ============================================================================
function Stop-LogProgress {
    <#
    .SYNOPSIS
    Termine une ou plusieurs barres de progression Write-Progress.

    .DESCRIPTION
    Stop-LogProgress clôt une ou plusieurs barres de progression
    affichées via Write-LogProgress.

    - Ne fait rien si la console est désactivée (ShowConsole = $false)

    .PARAMETER Id
    Identifiant de la barre à clôturer.

    .PARAMETER All
    Si spécifié, clôt toutes les barres (IDs 1 à 10 par défaut).

    .PARAMETER Label
    Texte affiché dans la barre lors de la complétion.
    #>
    [CmdletBinding(DefaultParameterSetName='ById')]
    param(
        # --- Mode 1 : Arrêt d'un ID spécifique ---
        [Parameter(ParameterSetName='ById')]
        [int]$Id = 1,

        # --- Mode 2 : Arrêt de toutes les barres ---
        [Parameter(ParameterSetName='All')]
        [switch]$All,

        # Commun aux deux modes
        [string]$Label = "Terminé"
    )

    # Respect du ShowConsole
    if (-not $script:LogConfig.ShowConsole) {
        return
    }

    if ($PSCmdlet.ParameterSetName -eq 'All') {
        foreach ($i in 1..10) {
            Write-Progress -Id $i -Activity $Label -Completed
        }
    }
    else {
        Write-Progress -Id $Id -Activity $Label -Completed
    }
}

# ============================================================================
# Get-LogText
# ============================================================================
function Get-LogText {
    <#
    .SYNOPSIS
    Retourne les lignes d'un buffer sous forme de texte.

    .DESCRIPTION
    Get-LogText lit les entrées d'un buffer donné (par défaut 'default'),
    applique éventuellement des filtres de niveau d'indentation et de sévérité,
    puis renvoie un texte concaténé (une ligne par entrée).

    - Les lignes sont basées sur la propriété Line stockée par Write-Log
      (indentation + icône + message, sans timestamp).
    - Si IncludeTimestamp = $true, chaque ligne est préfixée par [Timestamp]
      en utilisant la propriété Timestamp stockée dans l'entrée.
    - Si IncludeTimestamp = $false, les lignes sont renvoyées telles qu'elles
      ont été stockées dans Line (sans timestamp).

    .PARAMETER MaxLevel
    Niveau d'indentation maximum à inclure (-1 = aucun filtre).

    .PARAMETER MinSeverity
    Gravité minimale à inclure :
      - All     : aucune restriction
      - Info    : Info, Warning, Error, etc.
      - Warning : Warning, Error
      - Error   : uniquement Error

    .PARAMETER BufferId
    Identifiant du buffer à lire (par défaut 'default').

    .PARAMETER IncludeTimestamp
    Si $true, préfixe chaque ligne avec [Timestamp].
    Si $false, renvoie uniquement la propriété Line (sans timestamp).
    #>
    [CmdletBinding()]
    param(
        [int]$MaxLevel = -1,

        [ValidateSet('All','Info','Warning','Error')]
        [string]$MinSeverity = 'All',

        [string]$BufferId = 'default',

        [bool]$IncludeTimestamp = $true
    )

    if (-not $script:LogBuffers.ContainsKey($BufferId)) {
        return ''
    }

    $logs = $script:LogBuffers[$BufferId]
    if (-not $logs) { return '' }

    # Filtre niveau
    if ($MaxLevel -ge 0) {
        $logs = $logs | Where-Object { $_.Level -le $MaxLevel }
    }

    # Gravité
    $severityRank = @{
        Add      = 1
        Info     = 1
        Sub      = 1
        Question = 1
        Success  = 1
        Raw      = 1
        Warning  = 2
        Error    = 3
    }

    if ($MinSeverity -ne 'All') {
        $minRank = switch ($MinSeverity) {
            Info    { 1 }
            Warning { 2 }
            Error   { 3 }
        }
        $logs = $logs | Where-Object { $severityRank[$_.Type] -ge $minRank }
    }

    if (-not $logs) { return '' }

    $lines = foreach ($log in $logs) {
        if ($IncludeTimestamp -and $log.Timestamp) {
            "[{0}] {1}" -f $log.Timestamp, $log.Line
        }
        else {
            $log.Line
        }
    }

    return ($lines -join [Environment]::NewLine)
}

# ============================================================================
# Get-LogObject
# ============================================================================
function Get-LogObject {
    <#
    .SYNOPSIS
    Retourne les entrées d'un buffer EasyLogger sous forme d'objets.

    .DESCRIPTION
    Get-LogObject permet de récupérer les logs d'un buffer sous forme
    d'objets structurés (PSCustomObject), en appliquant les mêmes filtres
    que Get-LogText :

        - MaxLevel      : niveau d'indentation maximal
        - MinSeverity   : gravité minimale
        - BufferId      : buffer à lire

    Chaque objet retourné contient les champs suivants :

        Timestamp   : date/heure brute (string)
        Level       : niveau d'indentation (int)
        Type        : type de log (string)
        Message     : message brut (string)
        Line        : rendu sans timestamp (string)
        BufferIds   : buffers où l'entrée est présente

    Idéal pour :
        - traitements automatisés
        - export structurel vers CSV / JSON
        - filtrages plus poussés
        - réanalyse après Import-LogBuffers

    .PARAMETER MaxLevel
    Niveau d'indentation maximum (-1 = aucun filtre).

    .PARAMETER MinSeverity
    Gravité minimale (All, Info, Warning, Error).

    .PARAMETER BufferId
    Identifiant du buffer (par défaut 'default').
    #>
    [CmdletBinding()]
    param(
        [int]$MaxLevel = -1,

        [ValidateSet('All','Info','Warning','Error')]
        [string]$MinSeverity = 'All',

        [string]$BufferId = 'default'
    )

    if (-not $script:LogBuffers.ContainsKey($BufferId)) {
        return @()   # tableau vide
    }

    $logs = $script:LogBuffers[$BufferId]
    if (-not $logs) { return @() }

    # --- Gravité cohérente avec Get-LogText ---
    $severityRank = @{
        Add      = 1
        Info     = 1
        Sub      = 1
        Question = 1
        Success  = 1
        Raw      = 1
        Warning  = 2
        Error    = 3
    }

    # Filtre niveau
    if ($MaxLevel -ge 0) {
        $logs = $logs | Where-Object { $_.Level -le $MaxLevel }
    }

    # Filtre gravité
    $minRank = switch ($MinSeverity) {
        'All'     { 1 }
        'Info'    { 1 }
        'Warning' { 2 }
        'Error'   { 3 }
    }

    $logs = $logs | Where-Object { $severityRank[$_.Type] -ge $minRank }

    return $logs
}


# ============================================================================
# Clear-LogBuffer
# ============================================================================
function Clear-LogBuffer {
    <#
    .SYNOPSIS
    Efface un buffer ou tous les buffers.

    .DESCRIPTION
    Clear-LogBuffer permet de :
    - vider un buffer spécifique (si BufferId est fourni)
    - vider tous les buffers (si aucun BufferId n'est fourni)
    #>
    [CmdletBinding()]
    param(
        [string]$BufferId
    )

    if ($BufferId) {
        if ($script:LogBuffers.ContainsKey($BufferId)) {
            $script:LogBuffers[$BufferId] = @()
        }
    }
    else {
        $script:LogBuffers = @{}
    }
}

# ============================================================================
# Save-LogToFile
# ============================================================================
function Save-LogToFile {
    <#
    .SYNOPSIS
    Sauvegarde un buffer de log dans un fichier texte.

    .DESCRIPTION
    Save-LogToFile récupère le contenu d'un buffer via Get-LogText, en appliquant
    les filtres de niveau et de sévérité, puis écrit le résultat dans un fichier.

    - Le paramètre IncludeTimestamp contrôle si les lignes écrites dans le fichier
      sont préfixées avec [Timestamp] ou non.
    - L'encodage peut être choisi parmi UTF8, UTF8NoBOM, ASCII, Unicode.
    - Avec -Append, le contenu est ajouté en fin de fichier si celui-ci existe déjà.

    .PARAMETER Path
    Chemin du fichier de sortie.

    .PARAMETER Encoding
    Encodage du fichier (UTF8 par défaut).

    .PARAMETER MaxLevel
    Niveau d'indentation maximum à inclure (-1 = aucun filtre).

    .PARAMETER MinSeverity
    Gravité minimale à inclure (All, Info, Warning, Error).

    .PARAMETER BufferId
    Identifiant du buffer à sauvegarder (par défaut 'default').

    .PARAMETER Append
    Si spécifié, ajoute le contenu à la fin du fichier existant.

    .PARAMETER IncludeTimestamp
    Si $true, écrit chaque ligne avec [Timestamp] en tête.
    Si $false, écrit les lignes telles que stockées dans Line (sans timestamp).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateSet('UTF8','UTF8NoBOM','ASCII','Unicode')]
        [string]$Encoding = 'UTF8',

        [int]$MaxLevel = -1,

        [ValidateSet('All','Info','Warning','Error')]
        [string]$MinSeverity = 'All',

        [string]$BufferId = 'default',

        [switch]$Append,

        [bool]$IncludeTimestamp = $true
    )

    $content = Get-LogText -MaxLevel $MaxLevel -MinSeverity $MinSeverity -BufferId $BufferId -IncludeTimestamp:$IncludeTimestamp
    if ([string]::IsNullOrEmpty($content)) { return }

    switch ($Encoding) {
        'UTF8'      { $enc = New-Object System.Text.UTF8Encoding($false) }
        'UTF8NoBOM' { $enc = New-Object System.Text.UTF8Encoding($false) }
        'ASCII'     { $enc = [System.Text.Encoding]::ASCII }
        'Unicode'   { $enc = [System.Text.Encoding]::Unicode }
    }

    if ($Append -and (Test-Path $Path)) {
        [System.IO.File]::AppendAllText($Path, [Environment]::NewLine + $content, $enc)
    }
    else {
        [System.IO.File]::WriteAllText($Path, $content, $enc)
    }
}

# ============================================================================
# Get-LogBufferIds
# ============================================================================
function Get-LogBufferIds {
    <#
    .SYNOPSIS
    Retourne la liste des BufferIds connus par EasyLogger.

    .DESCRIPTION
    Get-LogBufferIds lit la table interne $script:LogBuffers et renvoie
    la liste des identifiants de buffers.

    - Par défaut, seuls les buffers contenant au moins une entrée sont retournés.
    - Avec -Exclude, certains buffers peuvent être exclus de la liste.

    .EXAMPLE
    Get-LogBufferIds

    .EXAMPLE
    Get-LogBufferIds -Exclude 'default'
    #>
    [CmdletBinding()]
    param(
        [string[]]$Exclude  # ex: 'default' ou @('default','audit*')
    )

    if (-not $script:LogBuffers) {
        return @()
    }

    # Buffers non vides uniquement
    $ids = $script:LogBuffers.GetEnumerator() |
        Where-Object { $_.Value -and $_.Value.Count -gt 0 } |
        ForEach-Object { $_.Key }

    # Exclusions
    if ($Exclude) {
        foreach ($pattern in $Exclude) {
            $ids = $ids | Where-Object { $_ -notlike $pattern }
        }
    }

    return ($ids | Sort-Object)
}

# ============================================================================
# Get-LogSummary
# ============================================================================
function Get-LogSummary {
    <#
    .SYNOPSIS
    Affiche ou retourne une synthèse des logs d'un buffer.

    .DESCRIPTION
    Get-LogSummary parcourt un buffer de log (par défaut 'default'), applique
    les mêmes filtres que Get-LogText (MaxLevel, MinSeverity), puis calcule :

    - le nombre total d'entrées retenues
    - la plage temporelle (premier et dernier timestamp)
    - la durée couverte par les logs (Last - First)
    - la répartition par Type (Add, Info, Success, Error, Warning, Question, Sub, Raw)
    - la répartition par "sévérité" :
        - Debug : Add, Info, Sub, Question, Success, Raw
        - Warning  : Warning
        - Error    : Error
    - les Types inclus / exclus en fonction du filtre MinSeverity

    Par défaut, la fonction retourne un texte formaté simple, lisible, pensé
    comme un petit résumé de fin de script.

    Avec -AsObject, elle retourne un objet structuré (PSCustomObject) contenant
    toutes les informations détaillées pour un traitement ultérieur.

    .PARAMETER MaxLevel
    Niveau d'indentation maximum à inclure (-1 = aucun filtre).

    .PARAMETER MinSeverity
    Gravité minimale à inclure :
      - All     : aucune restriction
      - Info    : Debug, Warning, Error
      - Warning : Warning, Error
      - Error   : uniquement Error

    .PARAMETER BufferId
    Identifiant du buffer à analyser (par défaut 'default').

    .PARAMETER AsObject
    Si spécifié, retourne un objet structuré au lieu d'une chaîne formatée.
    #>
    [CmdletBinding()]
    param(
        [int]$MaxLevel = -1,

        [ValidateSet('All','Info','Warning','Error')]
        [string]$MinSeverity = 'All',

        [string]$BufferId = 'default',

        [switch]$AsObject
    )

    # Helper interne pour construire un objet "vide"
    function New-EmptyLogSummaryObject {
        param(
            [string]$BufferId,
            [int]$MaxLevel,
            [string]$MinSeverity
        )

        return [PSCustomObject]@{
            BufferId         = $BufferId
            TotalEntries     = 0
            MaxLevel         = $MaxLevel
            MinSeverity      = $MinSeverity
            IncludedTypes    = @()
            ExcludedTypes    = @()
            FirstTimestamp   = $null
            LastTimestamp    = $null
            Duration         = $null
            DurationSeconds  = $null
            CountsByType     = @{}
            CountsBySeverity = @{}
        }
    }

    if (-not $script:LogBuffers.ContainsKey($BufferId)) {
        if ($AsObject) {
            return New-EmptyLogSummaryObject -BufferId $BufferId -MaxLevel $MaxLevel -MinSeverity $MinSeverity
        }
        else {
            return "Get-LogSummary : aucun buffer trouvé avec l'ID '$BufferId'."
        }
    }

    $logs = $script:LogBuffers[$BufferId]
    if (-not $logs) {
        if ($AsObject) {
            return New-EmptyLogSummaryObject -BufferId $BufferId -MaxLevel $MaxLevel -MinSeverity $MinSeverity
        }
        else {
            return "Get-LogSummary : le buffer '$BufferId' ne contient aucune entrée."
        }
    }

    # --- Règles de sévérité cohérentes avec Get-LogText ---
    $severityRank = @{
        Add      = 1
        Info     = 1
        Sub      = 1
        Question = 1
        Success  = 1
        Raw      = 1
        Warning  = 2
        Error    = 3
    }

    $severityNameMap = @{
        1 = 'Debug'
        2 = 'Warning'
        3 = 'Error'
    }

    # --- Filtre niveau ---
    if ($MaxLevel -ge 0) {
        $logs = $logs | Where-Object { $_.Level -le $MaxLevel }
    }

    # --- Filtre sévérité ---
    $minRank = switch ($MinSeverity) {
        'All'     { 1 }
        'Info'    { 1 }
        'Warning' { 2 }
        'Error'   { 3 }
    }

    $logs = $logs | Where-Object { $severityRank[$_.Type] -ge $minRank }

    if (-not $logs) {
        if ($AsObject) {
            return New-EmptyLogSummaryObject -BufferId $BufferId -MaxLevel $MaxLevel -MinSeverity $MinSeverity
        }
        else {
            return "Get-LogSummary : aucune entrée ne correspond aux filtres (BufferId='$BufferId', MaxLevel=$MaxLevel, MinSeverity=$MinSeverity)."
        }
    }

    $total = $logs.Count

    # Plage temporelle (on suppose les logs ajoutés dans l'ordre)
    $firstTs = $logs[0].Timestamp
    $lastTs  = $logs[-1].Timestamp

    # Durée
    $firstDt   = $null
    $lastDt    = $null
    $duration  = $null
    $durSec    = $null
    try {
        if ($firstTs -and $lastTs) {
            $firstDt  = [datetime]::ParseExact($firstTs, 'dd-MM-yyyy HH:mm:ss', $null)
            $lastDt   = [datetime]::ParseExact($lastTs,  'dd-MM-yyyy HH:mm:ss', $null)
            if ($firstDt -and $lastDt) {
                $duration = $lastDt - $firstDt
                $durSec   = [math]::Round($duration.TotalSeconds, 2)
            }
        }
    }
    catch {
        # On laisse Duration à $null si le parse échoue
    }

    # Répartition par type
    $countsByType = @{}
    $logs | Group-Object Type | Sort-Object Name | ForEach-Object {
        $countsByType[$_.Name] = $_.Count
    }

    # Répartition par sévérité
    $countsBySeverity = @{
        Debug = 0
        Warning  = 0
        Error    = 0
    }

    foreach ($log in $logs) {
        $rank         = $severityRank[$log.Type]
        $severityName = $severityNameMap[$rank]
        $countsBySeverity[$severityName]++
    }

    # Types inclus / exclus
    $includedTypes = @()
    $excludedTypes = @()

    foreach ($type in $severityRank.Keys) {
        $rank = $severityRank[$type]
        if ($rank -ge $minRank) {
            $includedTypes += $type
        }
        else {
            $excludedTypes += $type
        }
    }

    if ($AsObject) {
        return [PSCustomObject]@{
            BufferId         = $BufferId
            TotalEntries     = $total
            MaxLevel         = $MaxLevel
            MinSeverity      = $MinSeverity
            IncludedTypes    = $includedTypes
            ExcludedTypes    = $excludedTypes
            FirstTimestamp   = $firstTs
            LastTimestamp    = $lastTs
            Duration         = $duration
            DurationSeconds  = $durSec
            CountsByType     = $countsByType
            CountsBySeverity = $countsBySeverity
        }
    }
    else {
        $nl    = [Environment]::NewLine
        $lines = @()

        $lines += ""
        $lines += "┌─────────────────────────────────────────────────────────────┐"
        $lines += "│                     Résumé des journaux                     │"
        $lines += "└─────────────────────────────────────────────────────────────┘"
        $lines += "Buffer           : $BufferId"
        $lines += "Entrées          : $total"

        $timeRange =
            if ($firstTs -and $lastTs) {
                "$firstTs  ->  $lastTs"
            }
            else {
                "N/A"
            }
        $lines += "Plage temporelle : $timeRange"

        $durationText =
            if ($duration) {
                "{0} ({1} s)" -f $duration.ToString(), $durSec
            }
            else {
                "N/A"
            }
        $lines += "Durée            : $durationText"

        $lines += "────────────────────────── Sévérité ───────────────────────────"
        $lines += "Quantité par sévérité :"
        $lines += (" - {0,-10} : {1,5}" -f 'Debug', $countsBySeverity['Debug'])
        $lines += (" - {0,-10} : {1,5}" -f 'Warning',  $countsBySeverity['Warning'])
        $lines += (" - {0,-10} : {1,5}" -f 'Error',    $countsBySeverity['Error'])
        $lines += "───────────────────────────────────────────────────────────────"

        return ($lines -join $nl)
    }
}

# ============================================================================
# Export-LogBuffers
# ============================================================================
function Export-LogBuffers {
    <#
    .SYNOPSIS
    Exporte tous les buffers EasyLogger dans un fichier JSON.

    .DESCRIPTION
    Export-LogBuffers sérialise la table interne $script:LogBuffers dans un
    objet "package" contenant quelques métadonnées (version, date, machine,
    utilisateur, nom de session), puis écrit le tout dans un fichier JSON
    encodé en UTF-8 (sans BOM).

    Le fichier JSON généré est destiné à être réimporté plus tard avec
    Import-LogBuffers, afin de pouvoir rejouer Get-LogText / Get-LogSummary
    a posteriori (par exemple dans un autre script, une autre session ou une
    autre machine).

    Le format JSON est le suivant :

        {
          "Version": "1.0",
          "ExportDate": "2025-11-18 18:05:00",
          "Machine": "MACHINE01",
          "User": "Dylan",
          "Session": "NomDeSession",
          "Buffers": {
            "default": [ ... ],
            "debug":   [ ... ]
          }
        }

    .PARAMETER Path
    Chemin du fichier JSON à créer.

    .PARAMETER SessionName
    Nom logique de la session de logs (simplement informatif, stocké dans le JSON).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$SessionName = "EasyLoggerSession"
    )

    $package = [PSCustomObject]@{
        Version    = '1.0'
        ExportDate = (Get-Date -Format 'dd-MM-yyyy HH:mm:ss')
        Machine    = $env:COMPUTERNAME
        User       = $env:USERNAME
        Session    = $SessionName
        Buffers    = $script:LogBuffers
    }

    $json = $package | ConvertTo-Json -Depth 10

    # Écriture en UTF-8 sans BOM (cohérent avec Save-LogToFile)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json, $enc)
}

# ============================================================================
# Import-LogBuffers
# ============================================================================
function Import-LogBuffers {
    <#
    .SYNOPSIS
    Importe des buffers EasyLogger depuis un fichier JSON.

    .DESCRIPTION
    Import-LogBuffers lit un fichier JSON généré par Export-LogBuffers,
    récupère la propriété Buffers et reconstruit la table interne
    $script:LogBuffers.

    - Le format attendu est celui produit par Export-LogBuffers.
    - L'import REMPLACE entièrement les buffers actuels.
    - Les entrées sont normalisées en tableaux, même si un buffer ne contient
      qu'une seule entrée, de manière à rester cohérent avec la structure
      interne habituelle ($script:LogBuffers['id'] = @(...)).

    Exemple d'utilisation :

        Import-LogBuffers -Path "C:\logs\session.json"
        Get-LogSummary
        Get-LogText -MinSeverity Warning -IncludeTimestamp:$true

    .PARAMETER Path
    Chemin du fichier JSON à lire.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Import-LogBuffers : fichier introuvable '$Path'."
    }

    $rawJson = Get-Content -Path $Path -Raw
    $package = $rawJson | ConvertFrom-Json

    if (-not ($package.PSObject.Properties.Name -contains 'Buffers')) {
        throw "Import-LogBuffers : le fichier JSON ne contient pas de propriété 'Buffers'."
    }

    $buffers = $package.Buffers

    if (-not $buffers) {
        # On importe quand même, mais on part sur une table vide
        $script:LogBuffers = @{}
        return
    }

    $newBuffers = @{}

    foreach ($prop in $buffers.PSObject.Properties) {
        $name  = $prop.Name
        $value = $prop.Value

        if ($null -eq $value) {
            $newBuffers[$name] = @()
        }
        elseif ($value -is [System.Array]) {
            $newBuffers[$name] = @($value)
        }
        else {
            # Un seul objet -> on le force en tableau pour rester cohérent
            $newBuffers[$name] = @($value)
        }
    }

    # Remplace complètement les buffers actuels
    $script:LogBuffers = $newBuffers
}


# ============================================================================
# Export public module members
# ============================================================================
Export-ModuleMember -Function `
    Initialize-EasyLogger, `
    Write-Log, `
    Write-LogProgress, `
    Get-LogText, `
    Clear-LogBuffer, `
    Save-LogToFile, `
    Get-LogBufferIds, `
    Stop-LogProgress, `
    Get-LogSummary, `
    Export-LogBuffers, `
    Import-LogBuffers, `
    Get-LogObject
