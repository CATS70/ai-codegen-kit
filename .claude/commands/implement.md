# /implement — Implémentation à partir de spec-final.md

## Objectif

Lire `spec-final.md`, identifier le blueprint, charger les skills associés, créer la structure et implémenter le code en respectant les conventions.

## Processus

### Étape 1 — Lire la spec

Lire `spec-final.md`. Si le fichier est absent, stopper et demander d'exécuter `/spec` d'abord.

### Étape 2 — Identifier le blueprint

Lire le champ "Blueprint identifié" dans `spec-final.md`. Si renseigné, utiliser ce blueprint directement.

Sinon, analyser les fonctionnalités et choisir le blueprint le plus proche dans `.claude/architectures/` :

| Mots-clés dans la spec | Blueprint |
|---|---|
| catalogue, panier, commande, paiement | `ecommerce` |
| contacts, pipeline, activités, CRM | `crm` |
| email, classification, réponse automatique | `email-ai` |
| PDF, extraction, document, OCR | `document-processing` |
| ticket, chatbot, support, base de connaissance | `customer-support` |
| ETL, ingestion, pipeline, transformation | `data-pipeline` |
| dashboard, KPI, rapport, visualisation | `dashboard-reporting` |
| génération, contenu, rédaction, LLM | `content-generation` |

**Combinaisons fréquentes** — plusieurs blueprints peuvent coexister :

| Combinaison | Blueprints à charger |
|---|---|
| SaaS avec assistant IA | `saas-multitenant` + `rag-chatbot` |
| Support client avec IA | `customer-support` + `rag-chatbot` |
| Ecommerce avec recommandations | `ecommerce` + `content-generation` |

Quand plusieurs blueprints sont identifiés : fusionner les structures de fichiers (pas de doublons), charger tous les skills listés.

Si aucun blueprint ne correspond, construire la structure à partir des composants identifiés dans la spec.

### Étape 3 — Charger les skills

Lire le blueprint identifié et extraire la liste des skills associés à chaque composant.

**Toujours charger `skills/security/` en premier**, quel que soit le blueprint.

Charger ensuite les skills du blueprint dans cet ordre :
1. `security` (systématique)
2. `auth` (si le blueprint liste un composant auth)
3. Skills backend (`fastapi`, `sqlalchemy`, `pydantic`)
4. Skills IA si présents — règle de sélection :
   - Provider imposé par la spec → skill provider-spécifique (`claude-api` ou `openai-api`)
   - Plusieurs providers possibles ou non précisé → `litellm` (abstraction multi-provider)
   - Agent avec graph d'état → `langgraph` + skill provider choisi ci-dessus
   - Ne jamais charger `llm-router` ET `litellm` ensemble — choisir l'un ou l'autre
5. Skills frontend (`nextjs`, `typescript`)
6. Skills transverses (`testing`, `docker`, `git`)
7. **Skills de charge — selon `## Niveau de charge` dans `spec-final.md` :**

   | Niveau | Skills à charger | Ajustements |
   |--------|-----------------|-------------|
   | FAIBLE | `observability` (logging + health check uniquement) | `db_pool_size=5` (défaut) |
   | MOYEN  | `observability` (Prometheus activé) + `caching` | `db_pool_size=20` ; Redis dans docker-compose |
   | ÉLEVÉ  | `observability` (OpenTelemetry activé) + `caching` (ARQ activé) | `db_pool_size=5` + PgBouncer recommandé ; Redis + worker dans docker-compose |

   Si `## Niveau de charge` est absent de `spec-final.md`, traiter comme **FAIBLE** et signaler l'omission.

### Étape 3b — Vérifier l'environnement

Lire `## Configuration environnement` dans `spec-final.md`.

**Venv Python :** Si le chemin du venv est fourni, vérifier qu'il existe (`ls <venv>/bin/python`). Sinon chercher `.venv/` ou `venv/` à la racine. Si aucun venv n'est trouvé, demander à l'utilisateur avant de continuer — ne pas lancer de code sans venv identifié.

**Base de données :** Si une base existante est indiquée, utiliser ses credentials dans `core/settings.py` et `.env.example`. Ne pas supposer `localhost:5432` si l'utilisateur a précisé un autre port.

### Étape 4 — Créer la structure

Créer l'arborescence de fichiers définie dans le blueprint. Créer les fichiers dans cet ordre :

1. `core/settings.py` — configuration Pydantic BaseSettings avec toutes les variables nécessaires
2. `core/logging.py` — configuration des logs
3. `db.py` — session SQLAlchemy
4. `models/` — modèles SQLAlchemy (commencer par `user.py`)
5. `schemas/` — schémas Pydantic
6. `domain/enums/` — enums métier si le blueprint en définit
7. `services/` — logique métier
8. `api/auth.py` — routes auth en premier
9. `api/` — autres routes
10. `main.py` — application FastAPI
11. `tests/conftest.py` — fixtures de test (template PostgreSQL + NullPool du skill `testing`)
12. `tests/test_<domaine>.py` — tests HTTP d'intégration par module de route
13. `tests/test_services.py` — tests unitaires de service (voir règle ci-dessous)

**Si le skill `nextjs` est chargé**, créer également :
- `frontend/package.json` — avec toutes les dépendances Next.js (ne pas laisser ce fichier à générer par l'utilisateur)
- `frontend/public/.gitkeep` — Next.js attend ce répertoire ; sans lui, le build Docker échoue

**Règle des deux niveaux de tests** (obligatoire pour atteindre 80% de couverture) :

- `tests/test_<domaine>.py` : teste le comportement HTTP externe (status codes, payloads, auth)
- `tests/test_services.py` : appelle les fonctions de service directement, via la fixture `db`

Coverage.py ne trace pas fiablement le code exécuté dans le processus ASGI d'httpx avec pytest-asyncio.
Les branches internes des services (ex: merge de panier, annulation, erreurs métier) doivent être
testées directement pour être comptabilisées.

### Étape 5 — Implémenter

Implémenter chaque fichier en respectant strictement les conventions des skills chargés :

- Routes API : max 20 lignes, `response_model` toujours déclaré
- Services : logique métier isolée, injectable et testable
- Modèles : `TimestampMixin` sur toutes les entités
- Schémas : séparation Create / Update / Response
- Configuration : toutes les valeurs variables dans `core/settings.py`
- Secrets : jamais dans le code, toujours via `Settings`

Respecter les **Contraintes** et les **Flux métier** définis dans le blueprint.

### Étape 5b — Vérifier la compatibilité des librairies

Avant d'écrire du code qui appelle une librairie, vérifier que l'API utilisée existe dans la version épinglée dans `pyproject.toml`. En cas de doute sur une méthode ou un paramètre, rechercher dans la documentation officielle de la librairie ou vérifier le fichier source dans le venv.

**Anti-pattern à éviter** : générer du code qui appelle une fonction dépréciée ou renommée. Si une incertitude existe sur l'API exacte d'une librairie, utiliser la fonction la plus basique et documenter l'incertitude en commentaire plutôt que d'inventer une signature.

### Étape 6 — Générer les fichiers de configuration

**`pyproject.toml`** — agréger toutes les dépendances déclarées dans les sections `## Dépendances` de chaque skill chargé, plus les dépendances de base FastAPI :

```toml
[project]
name = "<nom-du-projet>"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = [
    # Base FastAPI — toujours présent
    "fastapi>=0.115",
    "uvicorn[standard]>=0.30",
    "python-multipart>=0.0.9",   # requis pour les forms OAuth2
    "httpx>=0.27",               # client HTTP async
    # + dépendances collectées depuis chaque skill chargé
]

[tool.ruff]
target-version = "py311"
line-length = 100

[tool.ruff.lint]
select = ["E", "F", "I", "UP", "S"]  # S = bandit rules via ruff

[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]
addopts = "--cov=app --cov-report=term-missing --cov-fail-under=80"
```

Ajouter dans `dependencies` uniquement les packages des skills effectivement chargés — ne pas copier les dépendances de skills non utilisés.

Créer également à la racine :
- `.env.example` avec toutes les variables de `core/settings.py` (valeurs fictives)
- `.env.test.example` avec `TEST_DATABASE_URL=postgresql+asyncpg://...`, `DATABASE_URL=...`, `JWT_SECRET=...`
- `alembic.ini` + migrations initialisées via `alembic init -t async migrations` si SQLAlchemy est utilisé
- `Dockerfile` si le blueprint inclut le skill `docker`
- `docker-compose.yml` si le blueprint inclut le skill `docker`
- `entrypoint.sh` si SQLAlchemy est chargé — script qui applique `alembic upgrade head` avant de démarrer uvicorn (voir skill `docker`)
- `sonar-project.properties` à la racine du projet :

```properties
sonar.projectKey=<nom-du-projet>
sonar.projectName=<Nom du projet>
sonar.sources=backend/app,frontend
sonar.exclusions=**/node_modules/**,**/__pycache__/**,**/migrations/**
sonar.python.version=3.11
sonar.python.coverage.reportPaths=backend/coverage.xml
sonar.typescript.lcov.reportPaths=frontend/coverage/lcov.info

# S2068 dans les tests = faux positif (credentials de fixture, pas des vrais secrets)
sonar.issue.ignore.multicriteria=e1
sonar.issue.ignore.multicriteria.e1.ruleKey=python:S2068
sonar.issue.ignore.multicriteria.e1.resourceKey=**/tests/**
```

Ce fichier est nécessaire pour que SonarQube comptabilise la couverture des tests. Sans lui, SonarQube affiche 0 % de couverture et le Quality Gate échoue systématiquement.

**Si le skill `nextjs` est chargé**, créer dans `frontend/` :
- `package.json` — dépendances Next.js complètes (next, react, react-dom, typescript, tailwindcss…)
- `pnpm-lock.yaml` ou demander à l'utilisateur de lancer `pnpm install` — documenter cette étape dans le README
- `public/.gitkeep` — répertoire vide attendu par Next.js et le Dockerfile

### Étape 7 — Vérification

Avant de terminer, vérifier :
- [ ] Toutes les variables de configuration sont dans `core/settings.py`
- [ ] Pas de secrets dans le code
- [ ] Toutes les routes sensibles ont `Depends(get_current_user)`
- [ ] `response_model` déclaré sur toutes les routes
- [ ] `conftest.py` avec les fixtures PostgreSQL + NullPool créé (template du skill `testing`)
- [ ] `.env.example` et `.env.test.example` créés avec toutes les variables
- [ ] `tests/test_services.py` créé avec au moins un test direct par service
- [ ] `entrypoint.sh` créé si SQLAlchemy est chargé (migrations avant démarrage)
- [ ] `frontend/package.json` créé si nextjs est chargé
- [ ] `frontend/public/.gitkeep` créé si nextjs est chargé
- [ ] `sonar-project.properties` créé avec `sonar.python.coverage.reportPaths=backend/coverage.xml`

## Règles

- Ne jamais implémenter au-delà du périmètre défini dans `spec-final.md`
- Si une décision technique n'est pas couverte par les skills, choisir la solution la plus simple
- Signaler à l'utilisateur si une contrainte du blueprint ne peut pas être respectée
