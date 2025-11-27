# 🌟 EasyLogger — Module de Logging PowerShell Moderne

[![license](https://img.shields.io/badge/License-MIT-green.svg)]()
[![PowerShell Gallery](https://img.shields.io/badge/PowerShell-Module-orange?logo=powershell)]()

EasyLogger est un module PowerShell léger conçu pour produire des logs :

- lisibles  
- structurés  
- colorés  
- multi-buffers  
- facilement exportables et réimportables 
- accessibles sous forme d’objets

Il fonctionne aussi bien pour de petits scripts que pour des automatisations complexes.

---
## 🚀 TL;DR

```powershell
Import-Module EasyLogger
Initialize-EasyLogger -ShowTimestamp:$true

Write-Log "Démarrage" -Type Add
Write-Log "Étape OK"  -Type Success
Write-Log "Oups..."   -Type Error -BufferIds "errors"

Get-LogText -BufferIds "errors"

# Export / Import complet
Export-LogBuffers -Path "session.json" -SessionName "Backup"
Import-LogBuffers -Path "session.json"

# Analyse
Get-LogSummary
$objects = Get-LogObject
```

---

# ✨ Fonctionnalités principales

## 🧩 Types de logs avec icônes

| Type      | Icon  | Description             |
|-----------|-------|-------------------------|
| Add       | [+]   | Début d'étape           |
| Info      | [i]   | Information             |
| Success   | [✓]   | Succès                  |
| Error     | [x]   | Erreur                  |
| Warning   | [!]   | Avertissement           |
| Question  | [?]   | Question                |
| Sub       | [-]   | Sous-étape              |
| Raw       |       | Ligne brute             |

```powershell
Write-Log "Hello world"
Write-Log "Fichier OK" -Type Success
```
Affichage typique (si le timestamp est activé) :
```powershell
[01-01-2025 10:40:23] Hello world
[01-01-2025 10:40:23] [✓] Fichier OK
```
## 🕒 Gestion de l'affichage en console
 
- Sur chaque Write-Log on peut forcer l'affichage où non du journal en console (en réécriture du paramètre global)
```powershell
Write-Log "Étape principale" -Type Add -ShowConsole $false #Masque la commande dans la console mais elle sera dans le buffer par défaut
```

---

## 📐 Indentation avec `-Level`, `IndentSize` et `IndentChar`

L'indentation est contrôlée par :

- `Level` (paramètre de `Write-Log`) : niveau logique d'indentation  
- `IndentSize` (config globale) : nombre de répétitions du motif d'indentation par niveau  
- `IndentChar` (config globale) : caractère utilisé pour marquer l'indentation (par défaut `·`)

Exemple simple :

```powershell
Write-Log "Étape principale" -Type Add
Write-Log "Sous-action" -Type Sub -Level 1
```

Résultat (avec IndentChar = `·` et IndentSize = 1) :

```
[01-01-2025 10:40:23] [+] Étape principale
[01-01-2025 10:40:23]  ·  [-] Sous-action
```

---
## 🕒 Gestion des timestamps

- L’affichage console respecte `ShowTimestamp`  
- Le timestamp est **toujours stocké**  
- L’export texte peut l’inclure ou non (`IncludeTimestamp`)

---

## 🕒 Override du timestamp

```powershell
Write-Log "Sans timestamp" -ShowTimestamp:$false
Write-Log "Avec timestamp" -ShowTimestamp:$true
```
---


## 🗂 Multi-buffers

Permet de séparer différents types de logs (API, debug, audit…).

```powershell
Write-Log "OK" -Type Success -BufferIds "hc"
Write-Log "Debug HTTP" -Type Info -BufferIds "debug","hc"
```

Récupération :

```powershell
Get-LogText -BufferId "hc"
Get-LogText -BufferId "debug"
```
--- 
## 🎛️ Récupérer la liste des buffers (`Get-LogBufferIds`)

```powershell
Get-LogBufferIds
Get-LogBufferIds -Exclude "default"
Get-LogBufferIds -Exclude @("debug*", "session-*")
```

---

## ❌ Supprimer un où plusieurs buffers
```powershell
Clear-LogBuffer #Supprime tout les buffers
Clear-LogBuffer -BufferId "test" #Supprime le buffer test
```
---

## 📊 Barre de progression (`Write-LogProgress`)

`Write-LogProgress` est un wrapper léger autour de `Write-Progress` qui :

- affiche une barre de progression native en haut de la console  
- ne stocke **rien** dans les buffers  
- ne fait rien si `ShowConsole = $false` dans la configuration

Signature :

```powershell
Write-LogProgress -Current <int> -Total <int> [-Label <string>] [-Id <int>]
```

Exemple :

```powershell
$items = 1..10
$tot   = $items.Count
$idx   = 0

foreach ($item in $items) {
    $idx++

    Write-LogProgress -Current $idx -Total $tot -Label "Traitement des éléments"

    Write-Log "Traitement de l'élément $item" -Type Info
    Start-Sleep -Milliseconds 200
}

# Dernier appel pour marquer la progression comme terminée
Write-LogProgress -Current $tot -Total $tot -Label "Traitement des éléments"
```

`Stop-LogProgress` permet de stopper `Write-LogProgress` (par exemple en cas d'erreur).
Exemple:
```powershell
Stop-LogProgress -All -Label "Erreur"

#Où seulement une barre de progression :
Stop-LogProgress -Id 2
```

## 📄 Export vers fichier

```powershell
Save-LogToFile -Path "C:\logs\run.log"
```

Avec filtres :

```powershell
Save-LogToFile -Path "C:\logs\errors.log" -MinSeverity Error
Save-LogToFile -Path "C:\logs\short.log"  -MaxLevel 1 -ShowTimestamp $false
```

---


## 🎚 Filtrage des logs (Get-LogText)

```powershell
Get-LogText -MinSeverity Warning -MaxLevel 1
```

---

## 🔥 Récupération format Objet : `Get-LogObject`

`Get-LogObject` retourne **toutes les entrées du buffer sous forme d’objets structurés**.

```powershell
$logs = Get-LogObject
$logs | Format-Table
```

Chaque entrée contient :

- Timestamp  
- Level  
- Type  
- Message  
- Line  
- BufferIds  

C’est idéal pour :

- analyser les logs  
- les importer en SQL  
- les traiter dans un script  
- les transformer en CSV  

---

# 🔄 Export / Import JSON complet

## Exporter tous les buffers

```powershell
Export-LogBuffers -Path "session.json" -SessionName "Backup-Nuit"
```

Génère un fichier JSON contenant :

- les buffers  
- les entrées  
- les timestamps  
- les métadonnées machine / utilisateur  
- la version du module  

## Réimporter plus tard

```powershell
Import-LogBuffers -Path "session.json"
```

Les buffers sont restaurés **dans l’état exact de l’export**, y compris :

- toutes les entrées  
- l’ordre  
- les niveaux  
- les types  

Super utile pour :

- rejouer des logs  
- analyser hors-ligne  
- consolider des scripts longs  
- stocker des sessions de débogage  

---

# 📊 Résumé final (Get-LogSummary)

Affichage lisible :

```text
┌─────────────────────────────────────────────────────────────┐
│                     Résumé des journaux                     │
└─────────────────────────────────────────────────────────────┘
Buffer           : default
Entrées          : 4
Plage temporelle : 18-11-2025 17:25:21  ->  18-11-2025 17:25:21
Durée            : 00:00:00 (0 s)
────────────────────────── Sévérité ───────────────────────────
Quantité par sévérité :
 - Debug      :     1
 - Warning    :     1
 - Error      :     2
───────────────────────────────────────────────────────────────
```

Mode objet :

```powershell
$s = Get-LogSummary -AsObject
$s.DurationSeconds
```

---

# ⚙️ Configuration avec `Initialize-EasyLogger`

`Initialize-EasyLogger` permet :

- de **réinitialiser complètement** la configuration et les buffers  
- de **surcharger uniquement** certains paramètres, les autres restant à leur valeur par défaut.

### Valeurs par défaut

Par défaut, la configuration utilisée est :

```powershell
ShowTimestamp = $false
IndentSize    = 1
IndentChar    = '·'
ShowConsole   = $true
Colors        = @{
    Add      = 'Blue'
    Info     = 'Cyan'
    Success  = 'Green'
    Error    = 'Red'
    Warning  = 'Yellow'
    Question = 'Magenta'
    Sub      = 'DarkGray'
    Raw      = $null
}
```

### Exemple : configuration minimale

```powershell
Initialize-EasyLogger
```

> Réinitialise la config avec les valeurs par défaut et vide tous les buffers.

### Exemple : Activer le timestamp dans la console

```powershell
Initialize-EasyLogger -ShowTimestamp:$true
```

### Exemple : changer le style d'indentation

```powershell
Initialize-EasyLogger -IndentSize 2 -IndentChar '>'
```

Résultat typique pour `Level = 1` :

```
[01-01-2025 10:40:23]  >  >  [i] Exemple
```

### Exemple : désactiver l'affichage console

```powershell
Initialize-EasyLogger -ShowConsole:$false
```

Les logs ne sont plus affichés en console mais restent disponibles dans les buffers (`Get-LogText`, `Save-LogToFile`, etc.).

### Exemple : personnaliser les couleurs

```powershell
Initialize-EasyLogger -Colors @{
    Info    = 'White'
    Success = 'DarkGreen'
    Error   = 'DarkRed'
}
```

Seules les couleurs indiquées sont modifiées, les autres gardent leur valeur par défaut.

---

# 🔧 Installation

####  Méthode 1 : En téléchargeant plaçant directement les fichiers à la main :
Créer le dossier :

```
Documents\PowerShell\Modules\EasyLogger\
```

Y placer :

- `EasyLogger.psd1`
- `EasyLogger.psm1`

#### Méthode 2 : En téléchargeant directement depuis github (recommandé):

Se rendre avec le terminal dans le dossier `Documents\PowerShell\Modules\EasyLogger\` de l'utilisateur courant (où dans le dossier `Modules` dans Program File pour l'installation en global sur la machine) puis :
```powershell
git clone https://github.com/msyslab/easylogger
```
Pour mettre à jour le module en cas de nouvelle release, se rendre dans le dossier easylogger puis :
```
git pull
```

Pour l'importer dans un script :

```powershell
Import-Module EasyLogger -Force #Le -Force permet de recharger tout le module à chaque fois. Nécessaire en cas de mise à jour.
Initialize-EasyLogger
```

---

## 🧩 Import avec préfixe (en cas de conflit de noms)

Si un autre module définit déjà une fonction `Write-Log` ou `Get-LogText`, vous pouvez importer EasyLogger avec un **préfixe** pour éviter les conflits :

```powershell
Import-Module EasyLogger -Prefix EL
```

Les fonctions seront alors disponibles sous les noms :

- `ELInitialize-EasyLogger`
- `ELWrite-Log`
- `ELWrite-LogProgress`
- `ELGet-LogText`
- `ELGet-LogObject`
- `ELClear-LogBuffer`
- `ELSave-LogToFile`
- `ELGet-LogBufferIds`
- `ELExport-LogBuffers`
- `ELImport-LogBuffers`
- `ELGet-LogBufferIds`
- `ELGet-LogSummary`

Exemple :

```powershell
Import-Module EasyLogger -Prefix EL

ELInitialize-EasyLogger
ELWrite-Log "Test avec préfixe" -Type Info
```

---

# 🚀 Exemple complet

```powershell
Initialize-EasyLogger -IndentSize 1 -IndentChar '·' -ShowTimestamp:$true

Write-Log "Start" -Type Add
Write-Log "API..." -Type Sub -Level 1
Write-Log "OK" -Type Success -BufferIds "api"


Save-LogToFile -Path "C:\logs\all.log"
Save-LogToFile -Path "C:\logs\debug.log" -BufferId "api"

Export-LogBuffers -Path "session.json"

Import-LogBuffers -Path "session.json"

Get-LogSummary
```

---

# 📚 Fonctions disponibles

| Fonction              | Description                                  |
|-----------------------|----------------------------------------------|
| Initialize-EasyLogger | Reset complet                                |
| Write-Log             | Ajoute une entrée                            |
| Write-LogProgress     | Barre de progression                         |
| Stop-LogProgress      | Termine une barre                            |
| Clear-LogBuffer       | Vide un buffer                               |
| Get-LogText           | Retourne le texte des logs                   |
| Get-LogObject         | Retourne les logs en objets                  |
| Save-LogToFile        | Export texte                                 |
| Export-LogBuffers     | Export JSON complet                          |
| Import-LogBuffers     | Import JSON complet                          |
| Get-LogBufferIds      | Liste les buffers                            |
| Get-LogSummary        | Résumé synthétique                           |

