# Claude Code Hooks

Collection de 26 hooks [Claude Code](https://docs.anthropic.com/en/docs/claude-code) pour securiser, automatiser et ameliorer les sessions de developpement avec un LLM — de l'informatique pure a l'informatique industrielle.

## Arborescence

```
claude-hooks/
├── install.sh                          # Installateur generique (auto-decouverte)
├── README.md
│
│   ── SECURITE & PROTECTION ──
├── check-sensitive/                    # Detection donnees sensibles
├── dangerous-command-guard/            # Blocage commandes dangereuses
├── branch-protection/                  # Protection branches principales
├── file-scope-guard/                   # Restriction perimetre fichiers
├── no-secret-commit/                   # Detection secrets avant commit
├── auto-backup/                        # Backup auto avant modification
│
│   ── WORKFLOW & PRODUCTIVITE ──
├── auto-test-runner/                   # Lancement auto des tests associes
├── context-usage-monitor/              # Suivi volume de contexte consomme
├── session-recap/                      # Resume temps reel de la session
├── change-logger/                      # Journal des modifications
├── large-file-guard/                   # Alerte fichiers volumineux
│
│   ── QUALITE DE CODE ──
├── commit-convention/                  # Validation Conventional Commits
├── architecture-boundary/              # Respect des frontieres d'architecture
├── complexity-guard/                   # Alerte complexite cyclomatique
├── import-validator/                   # Imports interdits & patterns dangereux
├── naming-convention/                  # Conventions de nommage
│
│   ── DEVOPS & INFRASTRUCTURE ──
├── env-guard/                          # Prevention melange d'environnements
├── infra-cost-estimator/               # Alerte avant provisioning cloud
├── docker-best-practices/              # Verification bonnes pratiques Docker
│
│   ── INFORMATIQUE INDUSTRIELLE ──
├── plc-safety-guard/                   # Securite code automate (IEC 61131-3)
├── protocol-validator/                 # Validation protocoles (Modbus, OPC-UA, MQTT)
├── network-segmentation/               # Segmentation IT/OT (IEC 62443)
├── realtime-constraint/                # Contraintes temps reel / embarque
├── firmware-changelog/                 # Changelog firmware avec peripheriques
├── safety-standard-check/              # Conformite normes (IEC 61508, MISRA, DO-178C)
└── hardware-register-guard/            # Protection registres hardware critiques
```

## Installation

### Tous les hooks d'un coup

```bash
bash install.sh /chemin/vers/mon-projet
```

### Un hook specifique

```bash
bash install.sh /chemin/vers/mon-projet check-sensitive
```

### Dans le projet courant

```bash
bash install.sh .
```

L'installateur :
- Auto-decouvre les hooks depuis les sous-dossiers (via `hook.json`)
- Cree `.claude/hooks/` et `.claude/settings.json` dans le projet cible
- **Merge** la config si `settings.json` existe deja (preserve les autres cles)
- **Idempotent** : relancer n'ecrase pas les fichiers de config utilisateur

---

# Securite & Protection

## 1. check-sensitive

> Scanne chaque fichier **avant** qu'il soit envoye au serveur Anthropic.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PreToolUse` |
| **Matcher** | `Read\|Grep\|Edit\|Write` |
| **Action** | Demande confirmation si patterns detectes |

**Ce qu'il detecte** (configurable dans `sensitive_patterns.txt`) :
- Noms de clients / entreprises
- Localisations (villes, sites industriels)
- Adresses IP de production
- Hostnames / FQDN internes
- Credentials hardcodes
- Donnees personnelles (emails, badges)

**Configuration** — editer `.claude/hooks/sensitive_patterns.txt` :

```
# Noms de clients
MonClient
FilialeDuClient

# IPs production
10\.135\.
192\.168\.50\.
```

---

## 2. dangerous-command-guard

> Bloque les commandes shell dangereuses avant execution.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PreToolUse` |
| **Matcher** | `Bash` |
| **Action** | Demande confirmation si commande dangereuse detectee |

**Commandes bloquees** (configurable dans `dangerous_patterns.txt`) :
- **Fichiers** : `rm -rf`, `shred`, `wipe`
- **Git** : `git push --force`, `git reset --hard`, `git clean -f`, `git branch -D`
- **Base de donnees** : `DROP TABLE`, `TRUNCATE`, `DELETE FROM ... ;`
- **Systeme** : `mkfs`, `dd of=/dev/`, `chmod 777`, `kill -9`
- **Containers** : `docker system prune`, `kubectl delete`, `terraform destroy`
- **Packages** : `npm -g uninstall`, `pip uninstall -y`, `apt remove -y`

---

## 3. branch-protection

> Empeche les commits et pushes directs sur les branches protegees.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PreToolUse` |
| **Matcher** | `Bash` |
| **Action** | Demande confirmation si commit/push sur branche protegee |

**Branches protegees par defaut** (configurable dans `protected_branches.txt`) :
`main`, `master`, `production`, `prod`, `release`

---

## 4. file-scope-guard

> Restreint l'acces aux fichiers dans un perimetre autorise.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PreToolUse` |
| **Matcher** | `Read\|Write\|Edit\|Grep\|Glob` |
| **Action** | Bloque (deny) les chemins sensibles, demande confirmation pour le reste |

**Comportement** :
- **Toujours bloque** : `~/.ssh/`, `~/.gnupg/`, `~/.aws/`, `~/.config/gh/`, `/etc/shadow`, `/etc/passwd`
- **Autorise** : fichiers sous `$PROJECT_DIR` (par defaut)
- **Demande confirmation** : tout le reste

**Configuration** — editer `allowed_paths.txt` :

```
$PROJECT_DIR
/home/user/shared-libs
/tmp
```

---

## 5. no-secret-commit

> Scanne les fichiers stages pour detecter des secrets avant un git commit.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PreToolUse` |
| **Matcher** | `Bash` |
| **Action** | Demande confirmation si secrets detectes |

**Secrets detectes** (configurable dans `secret_patterns.txt`) :
- **Cles API** : AWS (`AKIA...`), Google (`AIza...`), GitHub (`ghp_...`), Stripe (`sk_live_...`)
- **Tokens** : access tokens, bearer tokens, JWT secrets, Slack (`xox...`)
- **Credentials** : mots de passe en dur, connection strings (mongodb://, mysql://)
- **Cles privees** : RSA, EC, PGP, OpenSSH
- **Variables d'env** : `*_SECRET`, `*_TOKEN`, `*_PASSWORD`

---

## 6. auto-backup

> Cree une copie de sauvegarde de chaque fichier avant modification.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PreToolUse` |
| **Matcher** | `Edit\|Write` |
| **Action** | Silencieux — copie dans `.claude/backups/` |

- Sauvegarde dans `.claude/backups/<nom_fichier>.<timestamp>.bak`
- Conserve les **20 derniers backups** par fichier (nettoyage auto)
- Ne s'active que pour les fichiers existants

**Restaurer un fichier** :

```bash
ls .claude/backups/
cp .claude/backups/src_index.ts.20240315_143022.bak src/index.ts
```

---

# Workflow & Productivite

## 7. auto-test-runner

> Lance automatiquement les tests associes apres chaque modification de code.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PostToolUse` |
| **Matcher** | `Edit\|Write` |
| **Timeout** | 30s |
| **Action** | Silencieux — log les resultats dans `.claude/test-results.log` |

**Frameworks supportes** :
- **JavaScript/TypeScript** : Jest, Vitest (detecte `*.test.ts`, `*.spec.js`, `__tests__/`)
- **Python** : Pytest (detecte `test_*.py`, `*_test.py`, `tests/`)
- **Go** : `go test` (detecte `*_test.go`)
- **C#** : xUnit/NUnit (detecte `*Tests.cs`, `*Test.cs`)

**Fonctionnement** : quand `src/utils/helper.ts` est modifie, le hook cherche `src/utils/helper.test.ts` ou `__tests__/helper.test.ts` et le lance.

---

## 8. context-usage-monitor

> Suit le volume de donnees lues par Claude et alerte a l'approche des limites.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PostToolUse` |
| **Matcher** | `Read\|Grep` |
| **Action** | Notification aux seuils configures |

**Seuils par defaut** (configurable dans `hook.sh`) :
- **Warning** : 10 000 lignes lues
- **Alert** : 20 000 lignes lues

**Fichiers generes** :
- `.claude/context-usage.txt` — compteur cumule
- `.claude/context-usage.log` — detail de chaque lecture

---

## 9. session-recap

> Maintient un resume temps reel de toutes les actions de la session.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PostToolUse` |
| **Matcher** | `Edit\|Write\|Bash` |
| **Action** | Silencieux — ecrit dans `.claude/session-recap.md` |

**Exemple de sortie** :

```markdown
# Session Recap - 2024-03-15

## Actions

- `14:30:22` **Created/Wrote** `src/utils/helper.ts`
- `14:30:25` **Edited** `src/index.ts` — `old code` → `new code`
- `14:31:01` **Ran** `git commit -m "feat: add helper"`
```

---

## 10. change-logger

> Journalise toutes les modifications faites par Claude.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PostToolUse` |
| **Matcher** | `Edit\|Write\|Bash` |
| **Action** | Silencieux — ecrit dans `.claude/changelog.log` |

Format : `[timestamp] ToolName: file_or_command`. Auto-tronque a 500 lignes quand depasse 1000.

---

## 11. large-file-guard

> Avertit avant de lire des fichiers volumineux.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PreToolUse` |
| **Matcher** | `Read` |
| **Action** | Demande confirmation si fichier > seuil |

**Seuil par defaut** : **1 MB** — modifier dans `hook.sh` : `MAX_SIZE_KB=2048`

---

# Qualite de Code

## 12. commit-convention

> Valide les messages de commit au format [Conventional Commits](https://www.conventionalcommits.org/).

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PreToolUse` |
| **Matcher** | `Bash` |
| **Action** | Demande confirmation si non conforme |

**Format** : `type(scope): description`

**Types** : `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`

---

## 13. architecture-boundary

> Enforce les frontieres entre couches architecturales.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PreToolUse` |
| **Matcher** | `Edit\|Write` |
| **Action** | Demande confirmation si import cross-layer |

**Architectures supportees** (configurable dans `boundary_rules.txt`) :
- **Clean Architecture** : `domain/` ne peut pas importer `infrastructure/`
- **Hexagonal** : `core/`/`ports/` ne peuvent pas importer `adapters/`
- **DDD** : `entities/` ne peut pas importer `services/`
- **Frontend** : `components/` ne peut pas importer directement `api/`

**Format** : `SOURCE_LAYER -> FORBIDDEN_IMPORT_PATTERN`

---

## 14. complexity-guard

> Alerte quand la complexite du code depasse les seuils.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PostToolUse` |
| **Matcher** | `Edit\|Write` |
| **Action** | Notification si seuils depasses |

**Seuils par defaut** (configurable dans `hook.sh`) :

| Metrique | Seuil |
|----------|-------|
| Longueur de fonction | 50 lignes |
| Profondeur d'imbrication | 4 niveaux |
| Nombre de parametres | 5 |

---

## 15. import-validator

> Detecte les imports interdits et patterns de code dangereux.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PreToolUse` |
| **Matcher** | `Edit\|Write` |
| **Action** | Demande confirmation si pattern detecte |

**Patterns detectes** (configurable dans `forbidden_imports.txt`) :
- **Execution unsafe** : `eval()`, `exec()`, `subprocess.call(shell=True)`, `os.system()`
- **Deserialisation** : `pickle.loads()`, `yaml.load()` sans Loader
- **Injection SQL** : f-strings avec `SELECT`, `INSERT`, `DELETE`
- **Debug residuel** : `debugger;`, `breakpoint()`, `import pdb`

---

## 16. naming-convention

> Verifie les conventions de nommage du projet.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PostToolUse` |
| **Matcher** | `Edit\|Write` |
| **Action** | Notification si violations detectees |

**Regles par defaut** (configurable dans `naming_rules.txt`) :

| Langage | Fonctions | Classes | Interfaces | Constantes |
|---------|-----------|---------|------------|------------|
| TS/JS | camelCase | — | `I` prefix | UPPER_SNAKE |
| Python | snake_case | PascalCase | — | UPPER_SNAKE |
| C# | PascalCase | — | `I` prefix | — |
| Go | PascalCase | — | — | — |

---

# DevOps & Infrastructure

## 17. env-guard

> Previent le melange d'environnements (dev/staging/prod).

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PreToolUse` |
| **Matcher** | `Edit\|Write\|Read` |
| **Action** | Demande confirmation si cross-contamination |

**Detecte** (configurable dans `env_rules.txt`) :
- URL de production dans `.env.development`
- `localhost` dans `.env.production`
- URLs d'environnement hardcodees dans le code source
- Mots de passe en dur dans `docker-compose.yml`

---

## 18. infra-cost-estimator

> Avertit avant l'execution de commandes de provisioning cloud.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PreToolUse` |
| **Matcher** | `Bash` |
| **Action** | Demande confirmation avant provisioning |

**Commandes interceptees** :
`terraform apply/destroy`, `pulumi up/destroy`, `cloudformation deploy/delete-stack`, `cdk deploy`, `gcloud * create`, `az * create`, `helm install/upgrade`

---

## 19. docker-best-practices

> Verifie les bonnes pratiques dans les Dockerfiles.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PostToolUse` |
| **Matcher** | `Edit\|Write` |
| **Action** | Notification si anti-patterns detectes |

**Verifications** : tag `:latest`, execution root, `apt-get` sans `--no-install-recommends`, cache non nettoye, `COPY . .` avant deps, `.dockerignore` absent, `ADD` vs `COPY`

---

# Informatique Industrielle

## 20. plc-safety-guard

> Detecte les patterns dangereux dans le code automate PLC.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PreToolUse` |
| **Matcher** | `Edit\|Write` |
| **Action** | Demande confirmation si pattern unsafe |

**Extensions** : `.st`, `.scl`, `.pou`, `.exp`, `.xml`, `.tmc`, `.plcproj`, `.gsd`, `.aml`

**Detecte** (configurable dans `plc_unsafe_patterns.txt`) :
- Ecriture sur `%Q` sans interlock de securite
- `WHILE TRUE DO` sans watchdog/timeout
- `TON`/`TOF` sans limite de temps
- Commande moteur/vanne sans rampe
- Blocs communication sans gestion d'erreur
- `REAL_TO_INT` sur valeurs de consigne
- `FUNCTION_BLOCK` sans gestion E-Stop

---

## 21. protocol-validator

> Valide les configurations de protocoles industriels.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PreToolUse` |
| **Matcher** | `Edit\|Write` |
| **Action** | Demande confirmation si configuration invalide |

| Protocole | Verifications |
|-----------|---------------|
| **Modbus** | Adresses registres (0-65535), function codes valides, unit ID (0-247) |
| **OPC-UA** | SecurityMode != None, pas d'auth anonyme, ports non privilegies |
| **MQTT** | QoS 0 interdit pour alarmes, pas de wildcard root, TLS obligatoire |
| **BACnet** | Object instance (0-4194303) |

---

## 22. network-segmentation

> Previent les violations de segmentation IT/OT (ISA/IEC 62443).

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PreToolUse` |
| **Matcher** | `Edit\|Write\|Bash` |
| **Action** | Demande confirmation si cross-zone |

**Zones** (configurable dans `network_zones.txt`) :

| Zone | Niveau | Description |
|------|--------|-------------|
| **IT** | SL1 | Reseau d'entreprise |
| **DMZ** | SL2 | Zone demilitarisee |
| **OT** | SL3 | Reseau industriel |
| **SAFETY** | SL4 | Systemes instrumentes de securite |

**Violations** : IPs IT et OT dans le meme contexte, acces direct IT → SAFETY, code referencant la zone SAFETY.

---

## 23. realtime-constraint

> Detecte les patterns qui cassent le determinisme temps reel.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PreToolUse` |
| **Matcher** | `Edit\|Write` |
| **Action** | Demande confirmation si violation |

**Extensions** : `.c`, `.h`, `.cpp`, `.hpp`, `.rs`, `.ino`

**Violations** (configurable dans `realtime_violations.txt`) :
- **Allocation dynamique** : `malloc`, `free`, `new`, `std::vector`, `std::string`
- **I/O bloquantes** : `printf`, `scanf`, `fopen`, `std::cout`
- **Non borne** : `sleep()`, `while(1)` sans timeout
- **Exceptions** : `throw`, `try/catch`
- **Fonctions virtuelles** : indirection vtable
- **Threads sans priorite** : `pthread_create` sans `SCHED_FIFO`
- **Float en ISR** : calculs flottants dans handlers d'interruption
- **Appels systeme en section critique**

---

## 24. firmware-changelog

> Maintient un changelog firmware avec peripheriques affectes.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PostToolUse` |
| **Matcher** | `Edit\|Write` |
| **Action** | Silencieux — ecrit dans `.claude/firmware-changelog.md` |

**Tags auto-detectes** : `GPIO`, `UART`, `SPI`, `I2C`, `TIMER`, `ADC`, `DAC`, `DMA`, `CAN`, `ETH`, `USB`, `RTC`, `WATCHDOG`, `FLASH`, `IRQ`, `CLOCK`, `REGISTERS`, `MMIO`, `LINKER`, `MEMORY_MAP`

**Exemple** :

```markdown
## 2024-03-15

- `14:30:22` **src/drivers/gpio.c** [GPIO,IRQ,REGISTERS]
- `14:35:01` **src/hal/timer.c** [TIMER,DMA,IRQ]
- `14:40:15` **linker/STM32F4.ld** [LINKER,MEMORY_MAP]
```

---

## 25. safety-standard-check

> Verifie la conformite aux normes de surete industrielle.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PreToolUse` |
| **Matcher** | `Edit\|Write` |
| **Action** | Demande confirmation si violation de norme |

**Extensions** : `.c`, `.h`, `.cpp`, `.hpp`, `.rs`, `.ada`, `.adb`, `.ads`

| Norme | Domaine | Exemples de regles |
|-------|---------|-------------------|
| **IEC 61508** | Securite fonctionnelle | `goto` interdit (SIL 2+), comparaison float directe, unions |
| **MISRA C** | Fiabilite automobile | Pas de recursion, pas d'allocation dynamique, pas d'I/O standard |
| **DO-178C** | Aeronautique | Pas de casts implicites (DAL A/B), pas de signaux |
| **ISO 26262** | Automobile (ASIL) | `goto` interdit (ASIL B+), `#pragma` justifie |
| **IEC 62443** | Cybersecurite industrielle | Pas de credentials hardcodes, pas de telnet/FTP, pas de MD5 |

---

## 26. hardware-register-guard

> Protege contre l'ecriture accidentelle dans des registres hardware critiques.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PreToolUse` |
| **Matcher** | `Edit\|Write` |
| **Action** | Demande confirmation avant ecriture |

**Registres proteges** (configurable dans `protected_registers.txt`) :

| Categorie | Registres |
|-----------|-----------|
| **Reset** | `SCB->AIRCR`, `NVIC_SystemReset`, `RCC->*RST` |
| **Watchdog** | `IWDG->KR/PR/RLR`, `WWDG->CR` |
| **Flash** | `FLASH->CR` (erase/program), `FLASH->KEYR`, `HAL_FLASH_*` |
| **Power** | `PWR->CR`, `SCB->SCR` (deep sleep), `__WFI()`, `__WFE()` |
| **Clock** | `RCC->CFGR/CR/PLLCFGR`, `SystemClock_Config` |
| **MPU** | `MPU->*`, `SCB->SHCSR` |
| **Boot** | `FLASH->OPTKEYR/OPTR`, `OB_RDP` |

---

# Combinaisons recommandees

| Objectif | Hooks |
|----------|-------|
| **Securite minimale** | `check-sensitive` + `dangerous-command-guard` + `no-secret-commit` |
| **Protection complete** | Tous les hooks Securite (1-6) |
| **Qualite de code** | `architecture-boundary` + `complexity-guard` + `import-validator` + `commit-convention` |
| **Workflow equipe** | `branch-protection` + `commit-convention` + `session-recap` + `change-logger` |
| **DevOps securise** | `env-guard` + `infra-cost-estimator` + `docker-best-practices` + `no-secret-commit` |
| **Projet embarque** | `realtime-constraint` + `hardware-register-guard` + `firmware-changelog` + `safety-standard-check` |
| **Automatisme / PLC** | `plc-safety-guard` + `protocol-validator` + `network-segmentation` + `safety-standard-check` |
| **Solo avec filet** | `auto-backup` + `dangerous-command-guard` + `auto-test-runner` + `large-file-guard` |

---

# Pre-requis

- **bash** (Cygwin, Git Bash, WSL, ou Linux/macOS natif)
- **python3** (utilise a la place de `jq` pour le parsing JSON)
- **git** (pour les hooks utilisant l'historique ou les branches)

## Fichiers generes (a ajouter au `.gitignore`)

```
.claude/backups/
.claude/changelog.log
.claude/session-recap.md
.claude/firmware-changelog.md
.claude/context-usage.*
.claude/test-results.log
```

## Conseils

- Combiner les hooks avec des regles dans `CLAUDE.md` pour une protection contextuelle
- Les hooks ne ralentissent pas le workflow : timeout de 5-10s, `exit 0` si aucun match
- Les patterns sont case-insensitive (`grep -iE`) sauf indication contraire
- Tous les fichiers de config (patterns, rules, zones) sont editables apres installation
