> Créé par Aurélien Moote - Moo - 2026. Logiciel libre (licence MIT) :
> réutilisable à condition de conserver la mention de l'auteur.

# Claude Code Hooks

Collection de 26 hooks [Claude Code](https://docs.anthropic.com/en/docs/claude-code) pour securiser, automatiser et ameliorer les sessions de developpement avec un LLM — de l'informatique pure a l'informatique industrielle.

## Arborescence

```
claude-hooks/
├── install.sh                          # Installateur generique (auto-decouverte)
├── _common.sh                          # Bibliotheque partagee par tous les hooks
├── _dispatch.sh                        # Dispatcher : un seul processus par appel d'outil
├── tests/run-tests.sh                  # Suite de tests (bac a sable git jetable)
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
- Copie la bibliotheque partagee `_common.sh` et le dispatcher `_dispatch.sh` a cote des hooks
- Enregistre **un dispatcher par evenement** (`PreToolUse`, `PostToolUse`) dans `settings.json` ; la liste des hooks qu'il execute est ecrite dans `.claude/hooks/_hooks.conf`. Les hooks asynchrones (`auto-test-runner`) gardent leur propre entree.
- **Merge** la config si `settings.json` existe deja (preserve les autres cles)
- **Idempotent** : relancer met a jour les scripts et leur entree `settings.json`, sans jamais ecraser les fichiers de config utilisateur (`*.txt`)

> Les seuils definis en tete de certains scripts (`MAX_SIZE_KB`, `WARN_LINES`, ...) vivent dans le script installe : ils sont a reappliquer apres une reinstallation.

### Mode autonome (un enregistrement par hook)

```bash
bash install.sh --standalone /chemin/vers/mon-projet                  # tous les hooks
bash install.sh --standalone /chemin/vers/mon-projet check-sensitive  # un seul
```

Chaque hook recoit alors sa propre entree `settings.json`, avec son matcher et son timeout : un processus par hook a chaque appel d'outil (plus lent), utile pour isoler ou deboguer un hook. Les deux modes se melangent et se changent en relancant l'installateur ; chaque script reste executable seul (`bash .claude/hooks/<hook>.sh < entree.json`).

Pour ne faire tourner qu'un hook a travers le dispatcher : `CLAUDE_HOOKS_ONLY=<hook> bash .claude/hooks/_dispatch.sh PreToolUse < entree.json`.

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

**Ce qui est scanne** :

| Appel | Contenu scanne |
|-------|----------------|
| Read / Edit / Write, Grep sur un fichier | Le fichier |
| Grep sur un dossier, mode `content` | Les lignes que la recherche renverrait a Claude. Si le motif ne peut pas etre reproduit fidelement avec `grep` (`\d`, `(?...)`, multiligne...), tous les fichiers parcourus sont scannes |
| Grep sur un dossier, autres modes | Rien : seuls des noms de fichiers ou des compteurs sont renvoyes (la lecture ulterieure de ces fichiers repasse par le hook) |

Les dossiers `.git`, `node_modules` et `.claude` sont ignores. Le scan d'un dossier est borne a `SCAN_TIMEOUT` (3 s) : au-dela, le hook demande confirmation au lieu de laisser passer.

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

**Cas detectes** :
- `git commit` / `git push` quand la branche courante est protegee (y compris `git -C dir commit`, `git -c cle=valeur commit`)
- `git push` nommant explicitement une branche protegee depuis une autre branche (`git push origin HEAD:main`)

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

Les chemins sont compares sous forme canonique : `..` resolus (pas de contournement par `projet/../../.ssh`), comparaison par dossier entier (`/projet-bis` n'est pas sous `/projet`), et sous Windows `C:\dossier`, `/c/dossier` et la casse sont unifies.

**Configuration** — editer `allowed_paths.txt` :

```
$PROJECT_DIR
/home/user/shared-libs
/tmp
```

---

## 5. no-secret-commit

> Scanne ce qui va etre commite pour detecter des secrets avant un git commit.

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

**Contenu analyse** (lignes ajoutees uniquement, fichiers binaires ignores) :

| Commande | Contenu scanne |
|----------|----------------|
| `git commit ...` | Le diff stage |
| `git commit -a` / `-am ...` | Diff stage + modifications non stagees des fichiers suivis |
| `git add ... && git commit ...` | Idem + fichiers non suivis (hors `.gitignore`), car rien n'est encore stage quand le hook s'execute |

Le scan est un unique pipeline `git diff | sed | grep`, quel que soit le nombre de fichiers.

---

## 6. auto-backup

> Cree une copie de sauvegarde de chaque fichier avant modification.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PreToolUse` |
| **Matcher** | `Edit\|Write` |
| **Action** | Silencieux — copie dans `.claude/backups/` |

- Sauvegarde dans `.claude/backups/<nom_fichier>.<timestamp>.bak`
- Conserve les **20 derniers backups** par fichier (nettoyage auto, `MAX_BACKUPS` dans `hook.sh`)
- Plusieurs modifications dans la meme seconde : chaque etat est conserve (suffixe `_1`, `_2`...)
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
| **Execution** | Asynchrone (`"async": true`) : les tests tournent en arriere-plan sans bloquer Claude |
| **Action** | Log dans `.claude/test-results.log` ; silencieux si les tests passent, **echec signale a Claude** (et a l'utilisateur) avec les dernieres lignes de la sortie des tests |

**Frameworks supportes** :
- **JavaScript/TypeScript** : Vitest ou Jest, selon le binaire present dans le `node_modules/.bin` le plus proche (detecte `*.test.ts`, `*.spec.js`, `__tests__/`) ; aucun telechargement via `npx` si aucun n'est installe
- **Python** : Pytest (detecte `test_*.py`, `*_test.py`, `tests/`)
- **Go** : `go test` (detecte `*_test.go`)
- **C#** : xUnit/NUnit (detecte `*Tests.cs`, `*Test.cs`)

**Fonctionnement** : quand `src/utils/helper.ts` est modifie, le hook cherche `src/utils/helper.test.ts` ou `__tests__/helper.test.ts` et le lance. Le statut PASS/FAIL est le vrai code de sortie du lanceur de tests ; une execution est interrompue apres `TEST_TIMEOUT` (120 s, si `timeout` GNU est disponible).

---

## 8. context-usage-monitor

> Suit le volume de donnees lues par Claude et alerte a l'approche des limites.

| Propriete | Valeur |
|-----------|--------|
| **Event** | `PostToolUse` |
| **Matcher** | `Read\|Grep` |
| **Action** | Notification au franchissement de chaque seuil |

**Seuils par defaut** (configurable dans `hook.sh`) :
- **Warning** : 10 000 lignes lues
- **Alert** : 20 000 lignes lues

**Comptage** : lignes reellement lues (parametre `limit` de Read, 2000 lignes par defaut). Le compteur repart de zero a chaque nouvelle session (`session_id`) et chaque seuil n'est signale qu'une fois, au moment ou il est franchi.

**Fichiers generes** :
- `.claude/context-usage.txt` — compteur cumule de la session
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

**Format** : `type(scope): description` (un `!` avant `:` signale un breaking change : `feat(api)!: ...`)

**Types** : `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`

**Formes reconnues** : `-m "msg"`, `-m 'msg'`, `-am "msg"`, `--message="msg"` et les messages en heredoc (`git commit -m "$(cat <<'EOF' ... EOF)"`, la forme utilisee par Claude Code). `--amend` et les commits sans message en ligne sont ignores.

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

Analyse heuristique : indentation pour Python/Ruby, accolades pour la famille C (TS/JS, Go, C#, Java, C/C++, Rust, PHP). L'imbrication compte les structures de controle (`if`/`for`/`while`/`try`...) reellement emboitees dans une meme fonction ; les parametres sont comptes sur les declarations, pas sur les appels.

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
| Go | camelCase / PascalCase | — | — | — |

Controles effectivement appliques : `function_case` (declarations `def` / `function` / `func`), `class_case` et `interface_prefix`. Les types `constant_case`, `variable_case` et `class_prefix` sont acceptes dans `naming_rules.txt` mais pas encore verifies. Plusieurs casses peuvent etre autorisees avec `/` (`camelCase/PascalCase`).

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

Quand des plages se recouvrent, une adresse appartient a la zone la plus specifique : avec IT = `10.0.0.0/8` et OT = `10.135.0.0/16`, `10.135.1.1` est OT uniquement.

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

- **bash** >= 3.2 (Cygwin, Git Bash, WSL, ou Linux/macOS natif) avec `grep` et `sed`
- **python3** pour l'installateur et pour les hooks qui analysent du contenu : `architecture-boundary`, `import-validator`, `env-guard`, `complexity-guard`, `naming-convention`, `docker-best-practices`, `plc-safety-guard`, `protocol-validator`, `network-segmentation`, `realtime-constraint`, `firmware-changelog`, `safety-standard-check`, `hardware-register-guard`. Les 13 autres hooks n'utilisent que bash.
- **git** (pour les hooks utilisant l'historique ou les branches)

## Fonctionnement & performances

Les hooks s'executent a **chaque** appel d'outil : leur cout se paie donc en permanence. Sous Windows, demarrer bash coute ~70 ms, un `fork` ~20 ms et python jusqu'a 300 ms ; tout est concu pour en lancer le moins possible.

- **Un processus par appel d'outil** : `_dispatch.sh` lit le JSON une fois, puis execute dans son propre processus, l'un apres l'autre, tous les hooks concernes par l'outil (~3 ms par hook en bash pur). Il fusionne leurs reponses en un seul document : en `PreToolUse`, `deny` l'emporte sur `ask` et les motifs sont joints ; en `PostToolUse`, les avertissements sont concatenes.
- **Extraction JSON en bash pur** : `_common.sh` extrait les champs simples (`tool_name`, `file_path`, `command`...) avec les seules primitives de bash.
- **Un seul python, seulement si necessaire** : un hook ne demande une analyse python que si elle est utile (extension concernee, regle applicable au fichier, mot-cle ou adresse IP present). Les analyses demandees par les hooks d'un meme appel sont mises en file puis executees par un unique interpreteur.
- **`grep` evite quand c'est prouvable** : pour les commandes Bash, le moteur de regex de bash verifie d'abord un sur-ensemble des motifs dangereux ; `grep` n'est lance que s'il subsiste un doute (verdict identique a `grep -iE`, verifie par les tests).
- Les reponses JSON sont construites par echappement (`json_escape` / `json.dumps`), jamais en inserant du texte (contenu de fichier, commande, chemin) dans du code.
- Les avertissements PostToolUse sont emis dans `systemMessage` (affiche a l'utilisateur) et `additionalContext` (transmis a Claude).

Duree du traitement de tous les hooks pour un appel d'outil, mesuree sous Windows / Git Bash avec les 26 hooks installes :

| Appel d'outil | Version d'origine | Mode autonome | Dispatcher (defaut) |
|---------------|-------------------|---------------|---------------------|
| Edit d'un `.py` (avant / apres) | 3,5 s / 2,3 s | 0,66 s / 0,60 s | 0,53 s / 0,54 s |
| Edit d'un `.md` (avant / apres) | 3,3 s / 3,1 s | 0,48 s / 0,25 s | 0,23 s / 0,18 s |
| Commande Bash (avant / apres) | 1,6 s / 1,3 s | 0,26 s / 0,13 s | 0,17 s / 0,13 s |
| Read d'un `.py` (avant / apres) | 1,3 s / 0,7 s | 0,52 s / 0,18 s | 0,51 s / 0,18 s |

Le plancher restant est le demarrage de bash (~70 ms) et, quand une analyse de contenu est requise, celui de python. Installation complete : 73 s → 1 s.

### Ecrire ou modifier un hook

Pour pouvoir partager le processus du dispatcher, un hook respecte quatre regles (verifiees par la suite de tests) :

1. son corps est une fonction `main()`, appelee en derniere ligne du fichier ;
2. toute variable qu'il affecte est declaree `local` (seules les constantes de configuration sont definies en tete de fichier) ;
3. il se termine par `return 0`, jamais par `exit` (qui interromprait les hooks suivants) ;
4. `run_py`, s'il est utilise, est sa derniere action.

## Tests

```bash
bash tests/run-tests.sh               # -v pour le detail
bash tests/run-tests.sh --standalone  # execute chaque script directement, sans dispatcher
```

Installe tous les hooks dans un depot git jetable, puis envoie a chaque hook le JSON que Claude Code lui fournirait et verifie la decision (`ask` / `deny` / avertissement / silence), les journaux produits et la validite du JSON emis. La suite couvre aussi l'installateur (idempotence, changement de mode), la fusion des reponses par le dispatcher, l'absence de fuite d'etat entre hooks et l'equivalence du pre-filtre avec `grep -iE`.

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
- N'installer que les hooks utiles au projet : moins de confirmations inutiles, et en mode autonome un processus de moins a chaque appel d'outil
- Syntaxe des patterns : `grep -iE` (insensible a la casse) pour `sensitive_patterns.txt`, `dangerous_patterns.txt` et `secret_patterns.txt` ; expressions regulieres Python (lookaheads `(?!...)` acceptes) pour tous les autres fichiers, insensibles a la casse sauf `realtime_violations.txt`, `safety_rules.txt` et `protected_registers.txt`
- Une expression reguliere invalide est signalee (message a l'utilisateur ou sur stderr) au lieu de desactiver silencieusement le hook
- Tous les fichiers de config (patterns, rules, zones) sont editables apres installation

---

## Auteur & licence

Créé par **Aurélien Moote - Moo - 2026**.
Logiciel libre distribué sous [licence MIT](LICENSE) : réutilisable à condition de conserver la mention de l'auteur.

Copyright (c) 2026 Aurélien Moote ("Moo") — https://github.com/auremoo/claude_hooks
