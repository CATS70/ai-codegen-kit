---
name: docker
description: Conventions Docker pour Python FastAPI et Next.js. Dockerfile multi-stage, docker-compose dev/prod, sécurité non-root, health checks, variables d'environnement.
---

# Conventions Docker

## Dockerfile Python (FastAPI) — multi-stage

```dockerfile
# Dockerfile (backend)
FROM python:3.12-slim AS base

WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Stage builder — installation des dépendances
FROM base AS builder

RUN pip install uv
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-editable

# Stage final — image minimale
FROM base AS runtime

# Utilisateur non-root (sécurité)
RUN useradd --create-home appuser
USER appuser

COPY --from=builder --chown=appuser /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"

COPY --chown=appuser . .

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import httpx; httpx.get('http://localhost:8000/health').raise_for_status()"

COPY --chown=appuser entrypoint.sh ./entrypoint.sh
RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

## Dockerfile Next.js — multi-stage

```dockerfile
# Dockerfile (frontend)
FROM node:20-alpine AS base

WORKDIR /app

# Stage deps
FROM base AS deps
COPY package.json pnpm-lock.yaml ./
RUN corepack enable pnpm && pnpm install --frozen-lockfile

# Stage builder
FROM base AS builder
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN pnpm build

# Stage runtime — image minimale Next.js
FROM node:20-alpine AS runtime

WORKDIR /app
ENV NODE_ENV=production

RUN addgroup --system nodejs && adduser --system --ingroup nodejs nextjs
USER nextjs

COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD wget -qO- http://localhost:3000/api/health || exit 1

CMD ["node", "server.js"]
```

## Entrypoint — migrations Alembic au démarrage

Le serveur ne doit démarrer qu'après que les migrations sont appliquées.

```bash
#!/bin/sh
# entrypoint.sh
set -e

echo "Applying database migrations..."
alembic upgrade head

echo "Starting server..."
exec "$@"
```

Ce fichier doit être dans le répertoire racine du backend, copié dans l'image avec `--chown=appuser`, et rendu exécutable via `RUN chmod +x`.

> **Pourquoi un entrypoint plutôt qu'un CMD combiné** : `exec "$@"` préserve les signaux système (SIGTERM) vers uvicorn, ce qu'un `CMD sh -c "alembic upgrade head && uvicorn ..."` ne fait pas.

## Permissions volumes — utilisateur non-root

Quand un volume est monté (`./data:/app/data`), il appartient par défaut à `root`. Si le conteneur tourne en `appuser`, les écritures échouent.

```dockerfile
# Créer le dossier ET lui donner les permissions avant de passer à appuser
RUN mkdir -p /app/data && chown -R appuser:appuser /app/data
USER appuser
```

Ne jamais monter un volume sans avoir créé le répertoire cible avec les bonnes permissions dans le Dockerfile.

## docker-compose — développement

```yaml
# docker-compose.yml
services:
  backend:
    build:
      context: ./backend
      target: builder          # stage avec devtools
    volumes:
      - ./backend:/app         # hot reload
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql+asyncpg://postgres:postgres@db:5432/appdb
      - DEBUG=true
    env_file: ./backend/.env
    depends_on:
      db:
        condition: service_healthy
    command: uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

  frontend:
    build:
      context: ./frontend
      target: deps
    volumes:
      - ./frontend:/app
      - /app/node_modules       # évite l'écrasement par le volume
    ports:
      - "3000:3000"
    environment:
      - API_URL=http://backend:8000
    command: pnpm dev

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: appdb
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
```

## docker-compose — production

```yaml
# docker-compose.prod.yml
services:
  backend:
    build:
      context: ./backend
      target: runtime          # image minimale sans devtools
    restart: unless-stopped
    env_file: .env.prod
    depends_on:
      db:
        condition: service_healthy

  frontend:
    build:
      context: ./frontend
      target: runtime
    restart: unless-stopped
    env_file: .env.prod

  db:
    image: postgres:16-alpine
    restart: unless-stopped
    env_file: .env.prod
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

## .dockerignore

```
# .dockerignore (backend)
.git
.env
.env.*
__pycache__
*.pyc
.pytest_cache
.coverage
htmlcov
.venv
venv
*.egg-info
```

```
# .dockerignore (frontend)
.git
.env
.env.*
node_modules
.next
*.log
```

## Route de health check

```python
# app/api/health.py
@router.get("/health")
async def health_check(db: AsyncSession = Depends(get_db)):
    """Vérifie que l'application et la base de données sont opérationnelles."""
    try:
        await db.execute(text("SELECT 1"))
        return {"status": "ok"}
    except Exception:
        raise HTTPException(status_code=503, detail="Database unavailable")
```

## uv — gestionnaire de paquets Python (remplace pip + virtualenv)

Le Dockerfile utilise `uv sync` — le même outil s'utilise en développement local pour cohérence.

**Installation :**
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

**Workflow quotidien :**
```bash
uv sync                        # crée le venv + installe les dépendances depuis pyproject.toml
uv sync --dev                  # inclut les dépendances de développement (pytest, ruff…)
uv add fastapi                 # ajoute une dépendance → met à jour pyproject.toml + uv.lock
uv add --dev pytest pytest-asyncio  # dépendance dev uniquement
uv run uvicorn app.main:app --reload  # lance sans activer le venv manuellement
uv run pytest                  # idem pour les tests
uv lock                        # regénère uv.lock sans installer
```

**`uv.lock`** — committer ce fichier. Il garantit que Docker et tous les développeurs installent exactement les mêmes versions. Équivalent de `package-lock.json` pour Node.

```toml
# pyproject.toml — dépendances dev séparées
[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-asyncio>=0.23",
    "httpx>=0.27",    # client de test FastAPI
    "ruff>=0.4",
]
```

```bash
uv sync --extra dev    # installe les dépendances dev
```

## Règles

- Toujours un utilisateur non-root dans l'image finale
- Multi-stage obligatoire — jamais d'outils de build dans l'image de production
- `HEALTHCHECK` sur chaque service
- Secrets via `env_file` ou secrets Docker — jamais dans le `Dockerfile`
- `.dockerignore` présent dans chaque contexte de build
- `--frozen` dans le Dockerfile pour garantir la reproductibilité des builds
- `uv.lock` committé dans le dépôt — jamais dans `.gitignore`
- **`COPY` ne supporte pas les opérateurs shell** (`||`, `2>/dev/null`, `&&`). Pour une copie conditionnelle, utiliser `RUN` avec shell ou créer le répertoire avant : `RUN mkdir -p public && COPY public ./public`
- **Next.js — répertoire `public/` obligatoire** : créer `public/.gitkeep` dans le code source ; le Dockerfile doit copier `./public ./public`. Sans ce répertoire, le build échoue silencieusement
