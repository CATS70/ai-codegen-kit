# claude-code-kit

Kit de génération de code assisté par IA, production-ready et réutilisable sur tout nouveau projet Python / TypeScript.

---

> **V1 — base de travail.** Testé sur des projets Python/FastAPI. La couverture TypeScript est partielle. Les contributions et adaptations sont bienvenues.

## Contexte

Ce kit accompagne la série LinkedIn *"Après le vibe coding"* :
→ Article 1 — [Après le vibe coding : comment structurer la génération de code avec Claude Code](https://www.linkedin.com/pulse/apr%C3%A8s-le-vibe-coding-comment-structurer-la-g%C3%A9n%C3%A9ration-felix-ldfpf/)
→ Article 2 — [CLAUDE.md, skills, blueprints : externaliser le contexte de génération](https://www.linkedin.com/posts/cfelixdevia_encoder-les-conventions-d%C3%A9quipe-pour-que-activity-7466039804313460736-07Ub)
→ Article 3 — [Hooks et commandes : la couche déterministe qui manquait](https://www.linkedin.com/pulse/hooks-et-commandes-la-couche-d%C3%A9terministe-qui-manquait-felix-llgne/)
→ Article 4 — [Ce qu'on a vraiment appris — et ce que ça dit du rôle d'architecte](https://www.linkedin.com/pulse/ce-quon-vraiment-appris-et-que-%C3%A7a-dit-du-r%C3%B4le-christophe-felix-vscfe)

---

## Le problème que ça résout

Sans contexte encodé, chaque session Claude Code repart de zéro. Conventions oubliées, patterns réinventés, architecture incohérente d'une session à l'autre. On finit à corriger le code généré autant qu'à l'écrire soi-même.

Ce kit encode le contexte une fois — conventions, blueprints, contraintes de sécurité — pour qu'il soit disponible automatiquement à chaque génération.

---

## Structure

```
.claude/
├── CLAUDE.md              # Contrat de génération — lu automatiquement par Claude
├── AGENTS.md              # Portabilité multi-agents (Cursor, Windsurf, Copilot…)
├── settings.json          # Hooks automatiques
├── hooks/
│   ├── security-check.sh  # PreToolUse — bloque les secrets avant l'écriture
│   └── lint.sh            # PostToolUse — lance ruff + bandit après chaque fichier
├── architectures/         # Blueprints métier : structure + skills à charger
├── commands/              # Commandes /spec /implement /fix /add /test /doc /security-audit
└── skills/                # Conventions techniques par domaine (FastAPI, SQLAlchemy, auth…)
```

---

## Prérequis

- [Claude Code CLI](https://claude.ai/code)
- Python 3.11+ avec `ruff` et `bandit` installés globalement (`pip install ruff bandit`)
- Node.js 18+ + `pnpm` si stack TypeScript / Next.js
- Docker (optionnel — pour les blueprints qui incluent le skill `docker`)

---

## Démarrage rapide sur un nouveau projet

**1. Copier le kit**

```bash
cp -r path/to/claude-code-kit/.claude /chemin/vers/mon-projet/.claude
```

**2. Créer une description initiale**

Créer `spec.md` à la racine du projet avec une description libre de ce que vous voulez construire. Quelques phrases suffisent.

**3. Lancer Claude Code**

```bash
cd /chemin/vers/mon-projet
claude
```

**4. Exécuter le workflow**

```
/spec            → 5 questions de clarification → génère spec-final.md
/implement       → identifie le blueprint, charge les skills, code
/test            → lance les tests
/security-audit  → audit OWASP (à la demande)
```

Les hooks lint et sécurité s'exécutent automatiquement lors de `/implement`. Aucune action manuelle requise.

---

## Commandes disponibles

| Commande          | Rôle                                                      |
|-------------------|-----------------------------------------------------------|
| `/spec`           | Clarifie la spec en 5 questions max → génère `spec-final.md` |
| `/implement`      | Lit `spec-final.md`, identifie le blueprint, code         |
| `/fix`            | Corrige un bug ciblé sans refactorer                      |
| `/add`            | Ajoute une fonctionnalité en mode delta                   |
| `/test`           | Lance les tests du projet                                 |
| `/doc`            | Génère la documentation technique (API, README)           |
| `/documentation`  | Produit une documentation orientée humains et/ou agents IA |
| `/security-audit` | Audit OWASP sur le code produit                           |

---

## Les hooks : ce qui s'exécute automatiquement

Les hooks sont configurés dans `settings.json` et s'activent automatiquement lors de chaque session Claude Code dans le projet.

**`security-check.sh`** (avant chaque écriture) — bloque si :
- Une clé API Anthropic, OpenAI ou Stripe est détectée dans le contenu
- Une tentative d'écriture dans `.env` est faite

**`lint.sh`** (après chaque fichier écrit) — lance :
- Python : `ruff check` + `ruff format --check` + `bandit`
- TypeScript : `tsc --noEmit`

Si des erreurs sont détectées, Claude les reçoit comme feedback et corrige dans la même session.

**Dépendances des hooks :** `ruff` et `bandit` doivent être accessibles dans le PATH. Si absents, les vérifications sont ignorées avec un message d'information (pas de blocage).

### Log des hooks

Par défaut, les hooks ne loggent rien. Pour activer le log, définir `CLAUDE_HOOK_LOG` dans `.claude/settings.json` :

```json
"env": { "CLAUDE_HOOK_LOG": "~/.claude/hooks.log" }
```

Chaque entrée inclut l'heure, le nom du projet, le hook concerné et le résultat :

```
[14:32:01] [mon-projet] [security] START file=/mon-projet/app/main.py
[14:32:01] [mon-projet] [security] END result=OK
[14:32:02] [mon-projet] [lint] START file=/mon-projet/app/main.py
[14:32:02] [mon-projet] [lint] ruff check: OK
[14:32:02] [mon-projet] [lint] bandit: OK
[14:32:02] [mon-projet] [lint] END result=OK
```

Pour désactiver : remettre `CLAUDE_HOOK_LOG` à `""` dans `settings.json`.

---

## Les blueprints : le cœur du kit

Un blueprint est plus qu'un template de sélection — c'est **l'endroit où encoder vos propres décisions d'architecture**. Il définit la structure de fichiers, les composants attendus, les contraintes métier, et les skills à charger. C'est là que vivent les choix qui font que votre projet ressemble à votre projet, et pas à une API générique sortie d'un tutoriel.

Chaque blueprint livré dans ce kit est un point de départ. Il est conçu pour être **modifié** : ajoutez vos contraintes spécifiques, retirez les composants non pertinents, adaptez la structure de fichiers à vos conventions d'équipe. Un blueprint adapté à votre contexte vaut mieux qu'un blueprint générique appliqué tel quel.

`/implement` identifie automatiquement le blueprint à partir de `spec-final.md`. Le champ "Blueprint identifié" dans `spec-final.md` (généré par `/spec`) peut le préciser explicitement.

| Blueprint              | Cas d'usage                                        |
|------------------------|----------------------------------------------------|
| `auth`                 | SSO, JWT, RBAC, refresh tokens                     |
| `rag-chatbot`          | Chatbot avec mémoire et recherche RAG              |
| `saas-multitenant`     | Organisations, isolation données, rôles            |
| `ecommerce`            | Catalogue, panier, paiement                        |
| `crm`                  | Contacts, pipeline, activités                      |
| `email-ai`             | Traitement et génération d'emails par IA           |
| `document-processing`  | Extraction, transformation de documents            |
| `customer-support`     | Tickets, chatbot, base de connaissance             |
| `data-pipeline`        | Ingestion, transformation, stockage                |
| `dashboard-reporting`  | Visualisation, rapports, exports                   |
| `content-generation`   | Génération de contenu par IA                       |
| `notifications`        | Email, push, in-app, retry, préférences            |

Plusieurs blueprints peuvent être combinés : `/spec` peut indiquer `saas-multitenant + rag-chatbot`.

---

## Les skills : conventions techniques encodées

Chaque skill est un fichier `SKILL.md` qui décrit les conventions d'un domaine. Ils sont chargés par `/implement` selon le blueprint.

`skills/security/` est **toujours chargé**, quel que soit le blueprint.

Les skills `caching` et `observability` sont chargés selon le volume défini dans la spec :
- `low` (< 100 users simultanés) : ni l'un ni l'autre
- `medium` (100–10k) : `caching` activé
- `high` (> 10k) : `caching` + `observability` activés

---

## Adapter le kit à votre projet

Tout est modifiable — c'est l'intention. Ce kit n'est pas à utiliser tel quel : c'est une base de départ à s'approprier.

**`CLAUDE.md`** — remplacer les conventions génériques par celles de votre équipe. Garder sous 200 lignes : au-delà, l'attention de l'agent se dilue. Les détails techniques n'ont pas leur place ici — ils vont dans les skills.

**Blueprints** — modifier la structure de fichiers, les contraintes, les composants pour refléter vos choix d'architecture. Ajouter un blueprint pour un cas d'usage qui n'existe pas encore dans le kit.

**Skills** — enrichir les skills existants avec les conventions propres à votre équipe (patterns d'injection, règles de nommage, librairies imposées). Créer de nouveaux skills pour des domaines non couverts.

**Hooks** — ajuster les linters dans `lint.sh` selon votre stack. Ajouter des vérifications dans `security-check.sh` pour des patterns dangereux spécifiques à votre contexte.

**Commandes** — modifier `/implement` pour qu'il reflète votre workflow. Ajouter des commandes pour des étapes récurrentes dans votre équipe.

---

## Limites connues

**Specs ambiguës** — Le kit ne compense pas une spec floue. `/spec` aide à clarifier, mais c'est un outil, pas un substitut au travail de spécification.

**Taille du contexte** — Charger trop de skills dégrade la qualité de génération. Les règles les plus récentes prennent le dessus sur les plus anciennes. `/implement` charge uniquement les skills du blueprint identifié, pas tous les skills.

**Effort d'initialisation** — Configurer le kit pour un nouveau projet (adapter `CLAUDE.md`, sélectionner les blueprints pertinents) prend du temps. C'est un investissement justifié pour un projet qui durera, pas pour un prototype jetable.

**Méta-maintenance** — Le contexte encodé dérive si les conventions d'équipe évoluent sans mise à jour des skills. Traiter la maintenance du kit comme un travail d'équipe, pas comme une tâche ponctuelle.

---

## Utiliser avec un autre agent que Claude Code

Voir `AGENTS.md`. Le kit fonctionne avec Cursor, Windsurf, Copilot ou n'importe quel LLM — les hooks automatiques ne sont pas disponibles, mais les blueprints et skills restent utilisables manuellement.
