---
name: git
description: Conventions Git pour commits, branches et workflow. Conventional commits, nommage des branches, messages clairs, gitignore, workflow feature branch.
---

# Conventions Git

## Conventional Commits

Format obligatoire : `<type>(<scope>): <description>`

```
feat(auth): add JWT refresh token endpoint
fix(orders): prevent double charge on webhook retry
docs(api): update pagination examples
refactor(cart): extract price calculation to service
test(payment): add Stripe webhook signature tests
chore(deps): bump anthropic to 0.40
```

**Types** :

| Type | Quand |
|---|---|
| `feat` | Nouvelle fonctionnalité |
| `fix` | Correction de bug |
| `docs` | Documentation uniquement |
| `refactor` | Refactoring sans changement de comportement |
| `test` | Ajout ou correction de tests |
| `chore` | Maintenance (deps, config, CI) |
| `perf` | Amélioration de performance |

**Scope** : composant concerné (`auth`, `orders`, `cart`, `api`, `db`...).

**Description** : impératif présent, sans majuscule, sans point final.

## Nommage des branches

```
feat/add-stripe-webhook
fix/order-double-charge
refactor/extract-cart-service
chore/update-dependencies
```

Format : `<type>/<description-courte-en-kebab-case>`

## Workflow

```bash
# 1. Créer la branche depuis main à jour
git checkout main && git pull
git checkout -b feat/user-profile-api

# 2. Commits atomiques pendant le développement
git add app/api/users.py app/services/user_service.py
git commit -m "feat(users): add profile update endpoint"

git add tests/test_users.py
git commit -m "test(users): add profile update coverage"

# 3. Rebase avant PR (historique propre)
git fetch origin
git rebase origin/main

# 4. Push et PR
git push -u origin feat/user-profile-api
```

## Commits atomiques — règle

Un commit = une intention. Ne pas mélanger :

```bash
# ❌ commit fourre-tout
git commit -m "fix stuff and add feature and update deps"

# ✅ commits séparés
git commit -m "fix(auth): handle expired token gracefully"
git commit -m "feat(users): add avatar upload endpoint"
git commit -m "chore(deps): bump pydantic to 2.10"
```

## Messages de commit — structure complète

Pour les changements significatifs, ajouter un body :

```
feat(payment): add idempotency key to Stripe intents

Without idempotency keys, network retries could create duplicate
charges. Keys are generated from order_id + attempt number to
ensure stable retries without double billing.

Closes #142
```

## .gitignore Python/TypeScript

```gitignore
# Python
__pycache__/
*.pyc
.venv/
venv/
*.egg-info/
dist/
.pytest_cache/
.coverage
htmlcov/
.mypy_cache/

# Secrets
.env
.env.*
!.env.example

# Node
node_modules/
.next/
dist/
*.log

# IDE
.vscode/
.idea/
*.swp

# OS
.DS_Store
Thumbs.db

# Docker
*.tar
```

## .env.example — toujours présent

Committer un `.env.example` avec toutes les variables nécessaires (valeurs fictives) :

```bash
# .env.example
DATABASE_URL=postgresql+asyncpg://user:password@localhost:5432/dbname
JWT_SECRET=change-me-in-production
ANTHROPIC_API_KEY=sk-ant-...
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
LLM_PROVIDER=anthropic
```

## Règles

- Ne jamais committer `.env` — uniquement `.env.example`
- Ne jamais committer des clés API, tokens ou mots de passe
- Ne jamais force-push sur `main` ou `develop`
- Chaque PR vise `main` — pas de longues branches de feature (> 1 semaine)
- Un PR = une fonctionnalité ou un fix — pas de PR fourre-tout
- Tests verts avant merge — jamais de `# noqa` ou `# type: ignore` sans commentaire
