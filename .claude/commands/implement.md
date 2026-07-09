# /implement — Implémentation à partir de spec-final.md

## Objectif

Lire `spec-final.md`, identifier le blueprint, charger les skills associés, créer la structure et implémenter le code en respectant les conventions.

## Processus

### Étape 1 — Lire la spec

Lire `spec-final.md`. Si le fichier est absent, stopper et demander d'exécuter `/spec` d'abord.

**Si `## Utilisateurs et rôles` contient au moins un rôle humain** (Utilisateur, Admin...) avec des FR-xxx associées, `screens-final.md` est **obligatoire** : le chercher dans le répertoire courant. S'il est absent, stopper et demander d'exécuter `/screens` d'abord — ne jamais construire le frontend sans ce contrat dès qu'un humain interagit avec l'application. Si tous les acteurs de la spec sont des systèmes externes (API pure, aucun rôle humain), `screens-final.md` n'est pas requis.

### Étape 1b — Vérifier la cohérence transversale des entités

Avant d'identifier le blueprint, croiser les exigences qui portent sur une même entité métier :

1. Pour chaque entité listée dans `## Entités métier`, relever tous les FR-xxx qui la manipulent (création, import, export, recherche, rapport, API publique...).
2. Vérifier que les champs de l'entité sont traités de façon cohérente par ces FR-xxx. Un champ défini dans un FR de création mais absent du mapping d'un FR d'import/export n'est pas forcément une erreur — `spec-final.md` peut l'exclure volontairement — mais toute incohérence apparente doit être signalée à l'utilisateur avant de coder, jamais résolue par supposition silencieuse (cohérent avec la règle de fin de fichier sur les inconnues techniques).
3. Si une incohérence est trouvée, la lister dans un message avant de poursuivre. Ne bloquer l'implémentation que si l'ambiguïté empêche réellement de choisir une structure de données ; sinon, avancer avec l'interprétation la plus cohérente et la mentionner dans le rapport de l'étape 8.

### Étape 2 — Identifier le blueprint

`spec-final.md` ne propose jamais de nom de blueprint — ce choix est entièrement à la charge de `/implement`. Analyser les exigences fonctionnelles (FR-xxx) et choisir le blueprint le plus proche dans `.claude/architectures/` :

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
7. **Skills de charge — selon la NFR taguée "Charge" dans `## Exigences non-fonctionnelles` de `spec-final.md` :**

   | Niveau | Skills à charger | Ajustements |
   |--------|-----------------|-------------|
   | FAIBLE | `observability` (logging + health check uniquement) | `db_pool_size=5` (défaut) |
   | MOYEN  | `observability` (Prometheus activé) + `caching` | `db_pool_size=20` ; Redis dans docker-compose |
   | ÉLEVÉ  | `observability` (OpenTelemetry activé) + `caching` (ARQ activé) | `db_pool_size=5` + PgBouncer recommandé ; Redis + worker dans docker-compose |

   Si aucune NFR "Charge" n'est trouvée dans `spec-final.md`, traiter comme **FAIBLE** et signaler l'omission — cette spec a été générée avant que `/spec` ne rende cette NFR obligatoire.

8. **Autres NFR — chaque exigence non-fonctionnelle de `spec-final.md` (hors Charge) DOIT se traduire par une action identifiable**, selon le signal détecté dans son texte :

   | NFR catégorie | Signal détecté dans le texte de la NFR | Action |
   |---|---|---|
   | Sécurité | "limiter la fréquence", "anti-abus", "rate limiting" | Charger `caching` (rate limiter Redis) même si la NFR-Charge est FAIBLE |
   | Sécurité | "chiffrement au repos", "donnée sensible" | Appliquer le chiffrement de colonne du skill `database-design` |
   | Sécurité | "audit", "traçabilité", "historique des actions" | Appliquer le pattern audit trail du skill `database-design` |
   | Performance | seuil de temps de réponse explicite (ex: "< 2s", "quasi instantané") | Charger `caching` (cache-aside) même si la NFR-Charge est FAIBLE ; vérifier les index sur les colonnes filtrées avec le skill `database-design` |
   | Disponibilité | "ne doit jamais bloquer", "résilient à une panne", SLA explicite | Charger `observability` (health checks) même si la NFR-Charge est FAIBLE ; appliquer un retry/backoff sur les appels externes concernés (pattern du skill `notifications`, réutilisable hors notifications) |
   | Conformité | RGPD, suppression/anonymisation de données | Appliquer cascade delete et/ou soft-delete du skill `database-design` |
   | Conformité | PCI-DSS (paiement) | Vérifier que le skill `payment` déjà chargé ne stocke aucune donnée de carte (délégué à Stripe) |
   | Contrainte externe | Système d'authentification externe imposé (LDAP/SAML/SSO tiers) | Aucun skill du kit ne couvre ce cas — **signaler explicitement à l'utilisateur avant de continuer**, ne pas improviser une intégration |
   | Contrainte externe | Hébergement imposé avec contrainte technique (ex: serverless, on-premise) | Signaler l'impact sur `Dockerfile`/`docker-compose.yml`, adapter si possible sinon signaler la limite |

   Ces skills s'**ajoutent** à ceux déjà chargés par la table de charge (point 7) — ne jamais retirer un skill déjà chargé pour ce motif.

   Si une NFR ne correspond à aucune ligne de cette table mais implique manifestement un changement de skill ou de configuration, appliquer la solution la plus simple avec les skills déjà chargés et documenter le choix en commentaire. Si aucune solution raisonnable n'existe avec les skills disponibles, signaler la limite à l'utilisateur plutôt que d'improviser (cohérent avec la règle générale "signaler à l'utilisateur si une contrainte du blueprint ne peut pas être respectée").

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

**Couverture frontend par FR-xxx** :
- **Si `screens-final.md` existe** (obligatoire dès qu'un rôle humain est présent, voir étape 1) : c'est la source de vérité. Construire d'abord le(s) layout(s) qu'il décrit (`app/layout.tsx` et layouts imbriqués — header, navigation avec visibilité par rôle, footer), puis exactement les écrans qu'il décrit — mêmes routes, mêmes éléments clés par écran, rattachés au layout indiqué. Une route API testée ne suffit jamais : tant que l'écran correspondant n'existe pas dans le frontend, la FR-xxx qu'il couvre n'est **pas** considérée comme implémentée. Si un écran ou le layout de `screens-final.md` s'avère impossible à construire tel que décrit, le signaler explicitement à l'utilisateur plutôt que de s'en écarter silencieusement.
- **Si `screens-final.md` n'existe pas** (aucun rôle humain dans la spec — cas API pure) : aucune UI n'est attendue, le backend seul suffit.

**Règle des deux niveaux de tests** (obligatoire pour atteindre 80% de couverture) :

- `tests/test_<domaine>.py` : teste le comportement HTTP externe (status codes, payloads, auth)
- `tests/test_services.py` : appelle les fonctions de service directement, via la fixture `db`

Coverage.py ne trace pas fiablement le code exécuté dans le processus ASGI d'httpx avec pytest-asyncio.
Les branches internes des services (ex: merge de panier, annulation, erreurs métier) doivent être
testées directement pour être comptabilisées.

**Dériver les tests des AC-xxx et EC-xxx de `spec-final.md`** : avant d'écrire les tests d'un domaine, relire les sections "Scénarios d'acceptation" et "Edge cases" de `spec-final.md` et identifier celles qui concernent ce domaine.

- Chaque scénario AC-xxx devient au moins un test, nommé pour référencer son identifiant (ex: `test_create_order_succeeds_with_valid_payment  # AC-003`)
- Chaque edge case EC-xxx devient au moins un test d'erreur (ex: `test_create_order_rejects_invalid_card  # EC-005`)
- Si un AC-xxx ou un EC-xxx ne peut pas être traduit en test direct (dépendance externe non mockable, scénario UI pur), le couvrir via Playwright (skill `nextjs`/`testing`) ou documenter explicitement pourquoi dans un commentaire
- À la fin de l'étape 5, vérifier qu'aucun AC-xxx ou EC-xxx n'est resté sans test correspondant — le signaler à l'utilisateur si c'est le cas

**Dériver les tests des NFR-xxx (hors Charge)** : contrairement aux AC-xxx/EC-xxx, toutes les catégories de NFR ne sont pas testables de la même façon en pytest — appliquer la règle selon la catégorie :

- **Sécurité** et **Conformité** : DOIVENT avoir un test direct, comme un AC-xxx (ex: `test_dirigeants_refresh_is_rate_limited  # NFR-005`, `test_deleting_user_cascades_to_entities  # NFR-003`). Ce sont des comportements déterministes, donc testables de façon fiable.
- **Disponibilité** : généralement déjà couverte par un EC-xxx décrivant la panne externe correspondante (ex: EC-003 couvre déjà NFR-004 dans l'exemple ReachMyGoals) — vérifier qu'un tel EC-xxx existe avant d'écrire un test redondant ; sinon écrire un test de résilience dédié (mock de l'échec externe, assertion que l'application ne plante pas).
- **Performance** : **ne jamais** écrire d'assertion de timing dans la suite pytest standard (`assert elapsed < 2` est flaky — dépend de la machine, source de faux échecs en CI). L'action attendue est l'application de la mesure technique elle-même (cache, index — voir étape 3 point 8), pas un test qui mesure le temps. Documenter dans le rapport de fin d'implémentation que la validation du seuil chiffré nécessite un outil de charge dédié, hors périmètre des tests automatisés, sauf demande explicite de l'utilisateur (ex: `pytest-benchmark`).
- **Contrainte externe** : pas de test attendu si elle a été traitée comme une limite signalée à l'utilisateur (étape 3 point 8) plutôt que comme du code.

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

**Librairie non couverte par un skill** : la spec ou l'utilisateur peut demander une librairie qui n'est couverte par aucun skill chargé. Ne jamais improviser son usage par supposition — appliquer la règle générale ci-dessous (voir Règles).

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
- `eslint.config.mjs` — flat config (jamais `.eslintrc.json`, voir skill `nextjs`)
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
- [ ] Chaque AC-xxx et EC-xxx de `spec-final.md` a au moins un test correspondant
- [ ] Chaque NFR-xxx Sécurité/Conformité de `spec-final.md` a un test direct correspondant
- [ ] Chaque NFR-xxx Disponibilité est couverte par un EC-xxx existant ou un test de résilience dédié
- [ ] Chaque NFR-xxx Performance a déclenché l'application d'une mesure technique (cache/index), sans assertion de timing dans pytest
- [ ] Chaque NFR-xxx Contrainte externe non couvrable par les skills a été signalée à l'utilisateur
- [ ] `entrypoint.sh` créé si SQLAlchemy est chargé (migrations avant démarrage)
- [ ] `frontend/package.json` créé si nextjs est chargé
- [ ] `frontend/eslint.config.mjs` créé si nextjs est chargé (jamais `.eslintrc.json`)
- [ ] `frontend/public/.gitkeep` créé si nextjs est chargé
- [ ] `sonar-project.properties` créé avec `sonar.python.coverage.reportPaths=backend/coverage.xml`
- [ ] Si nextjs est chargé : chaque FR-xxx dont l'acteur est un rôle humain a un point d'entrée fonctionnel dans le frontend (pas seulement une route API testée)

### Étape 8 — Rapport de complétion

**Avant de remplir le tableau, décomposer toute FR-xxx composée** : si le texte d'une FR-xxx énumère plusieurs cibles distinctes (plusieurs entités, plusieurs tables, "X, Y et Z"), la traiter comme autant de lignes à vérifier séparément dans le tableau ci-dessous — jamais comme une seule case à cocher globale. Une FR-xxx composée n'est Backend ✅ que si **chacune** de ses cibles a été vérifiée individuellement dans le code, pas seulement parce qu'un test associé à cette FR passe (un test peut n'avoir été écrit que pour le sous-ensemble déjà implémenté, et passer malgré tout — ce n'est pas une preuve de complétude, relire le code lui-même pour chaque cible).

**Si `screens-final.md` existe, vérifier aussi sa conformité** : pour chaque écran qu'il décrit, confirmer que la route existe, que les éléments clés listés sont bien présents (pas seulement une page vide), et que les FR-xxx qu'il couvre y sont effectivement accessibles. Ajouter ce tableau au rapport :

| Écran (screens-final.md) | Route | Construit | Conforme | Statut |
|---|---|---|---|---|
| Tableau de bord d'un objectif | `/objectifs/[id]` | ✅ | ✅ tous les éléments clés présents | Complet |
| Import CSV entreprises | `/entreprises/import` | ❌ | — | **Incomplet** |

Toute ligne **Incomplet** ou **non conforme** (route existe mais élément clé manquant) doit être signalée avec sa raison, au même titre que les FR-xxx incomplètes.

Produire un tableau de couverture FR-xxx — sur le même principe que le rapport de `/spec` — et le présenter à l'utilisateur, pas seulement en cas de question :

| FR-xxx | Cible | Acteur | Backend | Frontend | Statut |
|---|---|---|---|---|---|
| FR-001 | — | Utilisateur | ✅ testé | ✅ page/composant | Complet |
| FR-00X | — | Service externe | ✅ testé | — (non applicable) | Complet |
| FR-018 | Entreprises | Utilisateur | ✅ vérifié dans le code | ✅ | Complet |
| FR-018 | Tâches | Utilisateur | ❌ absent du code | ❌ | **Incomplet** |

Toute ligne **Incomplet** doit être signalée explicitement avec sa raison (oubli, hors périmètre temporaire, dépendance bloquante) — ne jamais laisser une FR-xxx ou une cible orpheline sans la nommer dans ce rapport.

## Règles

- Ne jamais implémenter au-delà du périmètre défini dans `spec-final.md`
- Si une décision technique n'est pas couverte par les skills, choisir la solution la plus simple
- Signaler à l'utilisateur si une contrainte du blueprint ne peut pas être respectée
- Une FR-xxx n'est complète que si son acteur humain peut réellement l'exécuter depuis l'interface — un backend testé sans UI correspondante reste une FR-xxx incomplète, à signaler dans le rapport de l'étape 8
- Ne jamais supposer face à une inconnue technique (ex: librairie non couverte par un skill) : demander à l'utilisateur si le doute a un impact réel sur l'implémentation, et au besoin chercher l'information (documentation officielle, recherche internet) avant d'écrire le code — jamais deviner silencieusement
- Une entité manipulée par plusieurs FR-xxx (création, import, export, recherche, rapport...) doit être traitée de façon cohérente entre ces FR-xxx ; toute incohérence de champs entre elles est signalée à l'utilisateur, jamais tranchée silencieusement (voir étape 1b)
