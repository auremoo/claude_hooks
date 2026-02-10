# Claude Code Hooks

Collection de hooks [Claude Code](https://docs.anthropic.com/en/docs/claude-code) pour proteger les donnees sensibles lors de sessions de developpement avec un LLM.

## Arborescence

```
source/hook/
├── install.sh                      # Installateur generique (auto-decouverte)
├── README.md
├── check-sensitive/                # Hook: detection donnees sensibles
│   ├── hook.json                   #   Metadonnees (event, matcher, timeout)
│   ├── hook.sh                     #   Script principal
│   └── sensitive_patterns.txt      #   Patterns regex a detecter
└── <nouveau-hook>/                 # Ajouter d'autres hooks ici
    ├── hook.json
    ├── hook.sh
    └── ...
```

## Installation

### Tous les hooks d'un coup

```bash
bash source/hook/install.sh /chemin/vers/mon-projet
```

### Un hook specifique

```bash
bash source/hook/install.sh /chemin/vers/mon-projet check-sensitive
```

### Dans le projet courant

```bash
bash source/hook/install.sh .
```

L'installateur :
- Auto-decouvre les hooks depuis les sous-dossiers (via `hook.json`)
- Cree `.claude/hooks/` et `.claude/settings.json` dans le projet cible
- **Merge** la config si `settings.json` existe deja (preserve les autres cles)
- **Idempotent** : relancer n'ecrase pas les fichiers de config utilisateur

## Hooks disponibles

### check-sensitive

Scanne chaque fichier **avant** qu'il soit envoye au serveur Anthropic (via Read, Grep, Edit, Write). Si des patterns sensibles sont detectes, l'utilisateur voit un avertissement et doit confirmer.

**Patterns detectes** (configurable dans `sensitive_patterns.txt`) :
- Noms de clients / entreprises
- Localisations (villes, sites industriels, usines)
- Adresses IP de production
- Hostnames / FQDN internes
- Credentials hardcodes
- Donnees personnelles (emails, badges)

**Apres installation**, editer `.claude/hooks/sensitive_patterns.txt` :

```
# Noms de clients
MonClient
FilialeDuClient

# Sites
VilleUsine
NomSite

# IPs production
10\.135\.
192\.168\.50\.
```

## Creer un nouveau hook

1. Creer un sous-dossier dans `source/hook/` :

```bash
mkdir source/hook/mon-nouveau-hook
```

2. Creer `hook.json` avec les metadonnees :

```json
{
  "name": "mon-nouveau-hook",
  "description": "Description courte du hook",
  "event": "PreToolUse",
  "matcher": "Read|Grep|Edit|Write",
  "timeout": 5,
  "files": ["hook.sh", "config.txt"]
}
```

| Champ         | Description                                              |
|---------------|----------------------------------------------------------|
| `name`        | Identifiant unique du hook                               |
| `description` | Affichee pendant l'installation                          |
| `event`       | `PreToolUse` ou `PostToolUse`                            |
| `matcher`     | Outils interceptes (regex, ex: `Read\|Write\|Bash`)     |
| `timeout`     | Secondes max avant abandon                               |
| `files`       | Fichiers a copier. `hook.sh` = script principal (requis) |

3. Ecrire `hook.sh` - le script principal :

```bash
#!/bin/bash
# Recoit le JSON du hook sur stdin :
# {"tool_name":"Read","tool_input":{"file_path":"/some/path"}}
INPUT=$(cat)

# Votre logique ici...

# Pour bloquer/avertir, retourner :
python3 -c "
import json
result = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'ask',    # ask | deny | allow
        'permissionDecisionReason': 'Votre message ici'
    }
}
print(json.dumps(result))
"

# Pour laisser passer silencieusement :
exit 0
```

4. Installer :

```bash
bash source/hook/install.sh /chemin/vers/projet mon-nouveau-hook
```

## Pre-requis

- **bash** (Cygwin, Git Bash, WSL, ou Linux/macOS natif)
- **python3** (utilise a la place de `jq` pour le parsing JSON)

## Conseils

- Combiner le hook regex avec une regle dans `CLAUDE.md` pour une protection contextuelle :
  ```
  Si tu detectes un nom de client ou une localisation precise, informe-moi avant d'envoyer les donnees.
  ```
- Le hook ne ralentit pas le workflow : timeout de 5s, `exit 0` si aucun match
- Les patterns sont case-insensitive (`grep -iE`)
