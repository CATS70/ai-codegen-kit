---
name: testing
description: Conventions de test pour stack Python/TypeScript. pytest async pour FastAPI, fixtures, mocking, couverture 85%, Playwright pour E2E.
---

# Conventions de test

## Structure des tests

```
tests/
├── conftest.py          # fixtures partagées
├── test_auth.py
├── test_users.py
├── test_orders.py
└── e2e/
    └── test_checkout.py # Playwright
```

Un fichier de test par fichier de route. Les tests miroir la structure `api/`.

## Configuration pytest

```toml
# pyproject.toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]
addopts = "--cov=app --cov-report=term-missing --cov-report=xml --cov-fail-under=85"
```

Le `--cov-report=xml` génère `coverage.xml` nécessaire pour que SonarQube comptabilise la couverture (`sonar.python.coverage.reportPaths=coverage.xml`).

## Pré-requis : base de données de test

**Ne pas utiliser SQLite** : incompatible avec asyncpg (`pool_size`, `max_overflow`, types PostgreSQL).

Créer un fichier `.env.test` à la racine du backend :

```ini
# .env.test
TEST_DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/myapp_test
```

La base de test doit exister avant de lancer pytest :
```bash
createdb myapp_test   # ou via psql / docker exec
```

## Fixtures de base

```python
# tests/conftest.py
import asyncio
import os
from collections.abc import AsyncGenerator

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.pool import NullPool
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.main import app
from app.db import get_db
from app.models import Base

TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+asyncpg://postgres:postgres@localhost:5432/myapp_test",
)

# NullPool : connexion fraîche par checkout — évite les conflits asyncpg entre tests
_test_engine = create_async_engine(TEST_DATABASE_URL, echo=False, poolclass=NullPool)
_session_factory = async_sessionmaker(_test_engine, expire_on_commit=False)


def _run_sync(coro):
    """Exécute un coroutine de façon synchrone (pour hooks pytest sync)."""
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


@pytest.fixture(scope="session", autouse=True)
def setup_schema():
    """Crée le schéma une fois pour toute la session (fixture synchrone)."""
    async def _create():
        async with _test_engine.begin() as conn:
            await conn.run_sync(Base.metadata.drop_all)
            await conn.run_sync(Base.metadata.create_all)

    async def _drop():
        async with _test_engine.begin() as conn:
            await conn.run_sync(Base.metadata.drop_all)
        await _test_engine.dispose()

    _run_sync(_create())
    yield
    _run_sync(_drop())


@pytest.fixture(autouse=True)
async def clean_tables():
    """Vide toutes les tables après chaque test (isolation sans rollback imbriqué)."""
    yield
    async with _test_engine.begin() as conn:
        for table in reversed(Base.metadata.sorted_tables):
            await conn.execute(table.delete())


@pytest.fixture
async def db() -> AsyncGenerator[AsyncSession, None]:
    async with _session_factory() as session:
        yield session


@pytest.fixture
async def client(db: AsyncSession) -> AsyncGenerator[AsyncClient, None]:
    app.dependency_overrides[get_db] = lambda: db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture
async def user(db: AsyncSession) -> User:
    u = User(email="test@example.com", password_hash=hash_password("password123"))
    db.add(u)
    await db.commit()
    await db.refresh(u)
    return u


@pytest.fixture
async def auth_client(client: AsyncClient, user: User) -> AsyncClient:
    """Client avec cookie/header d'authentification."""
    response = await client.post(
        "/auth/login", json={"email": "test@example.com", "password": "password123"}
    )
    assert response.status_code == 200
    return client
```

> **Pourquoi `clean_tables` plutôt que `rollback` ?**
> Les transactions imbriquées (SAVEPOINT) sont fragiles avec asyncpg. Supprimer les données après chaque test est plus fiable et presque aussi rapide.

## Coverage et ASGI — piège connu

`coverage.py` **ne trace pas** les appels qui transitent par le transport ASGI de httpx (`ASGITransport`). Une route testée via `client.get(...)` peut apparaître comme non couverte.

**Solution** : compléter les tests HTTP avec des tests unitaires directs des services :

```python
# Test HTTP (couverture partielle)
async def test_list_products_api(client: AsyncClient):
    response = await client.get("/products/")
    assert response.status_code == 200

# Test unitaire service (couverture complète)
async def test_list_products_service(db: AsyncSession):
    products, total = await list_products(db, pagination=PaginationParams())
    assert total == 0
```

## Pattern de test — AAA

```python
async def test_create_user(client: AsyncClient):
    # Arrange
    data = {"email": "new@example.com", "name": "New User", "password": "secure123"}

    # Act
    response = await client.post("/users/", json=data)

    # Assert
    assert response.status_code == 201
    body = response.json()
    assert body["email"] == data["email"]
    assert "password" not in body        # le mot de passe ne doit jamais fuiter
    assert "id" in body
```

## Tester les cas d'erreur

```python
async def test_create_user_duplicate_email(client: AsyncClient, user: User):
    response = await client.post("/users/", json={
        "email": user.email,   # email déjà existant
        "name": "Other",
        "password": "password123",
    })
    assert response.status_code == 409

async def test_get_user_not_found(client: AsyncClient, auth_headers: dict):
    response = await client.get("/users/99999", headers=auth_headers)
    assert response.status_code == 404

async def test_protected_route_unauthorized(client: AsyncClient):
    response = await client.get("/users/1")  # sans auth
    assert response.status_code == 401
```

## Mocking

```python
from unittest.mock import AsyncMock, patch

async def test_create_order_sends_notification(client: AsyncClient, auth_headers: dict):
    with patch("app.services.notification_service.send_confirmation", new_callable=AsyncMock) as mock_notify:
        response = await client.post("/orders/", json={...}, headers=auth_headers)

        assert response.status_code == 201
        mock_notify.assert_called_once()

async def test_payment_stripe_error(client: AsyncClient, auth_headers: dict):
    with patch("app.services.payment_service.create_intent", side_effect=StripeError("card_declined")):
        response = await client.post("/payments/", json={...}, headers=auth_headers)
        assert response.status_code == 402
```

## Couverture — règles

- **Minimum 85%** de couverture sur `app/`
- Priorité : services/ > api/ > models/
- Ne pas chasser le % avec des tests vides — tester le comportement

```bash
pytest --cov=app --cov-report=html   # rapport HTML
pytest --cov=app --cov-fail-under=85 # CI gate
```

## Playwright — tests E2E

```python
# tests/e2e/test_checkout.py
from playwright.async_api import Page, expect

async def test_checkout_flow(page: Page, live_server_url: str):
    await page.goto(f"{live_server_url}/products")
    await page.click("[data-testid='add-to-cart-1']")
    await page.click("[data-testid='cart-icon']")

    await expect(page.locator("[data-testid='cart-count']")).to_have_text("1")

    await page.click("[data-testid='checkout-btn']")
    await page.fill("[name='card_number']", "4242424242424242")
    await page.click("[data-testid='pay-btn']")

    await expect(page.locator("[data-testid='success-message']")).to_be_visible()
```

Configuration Playwright :
```python
# conftest.py
@pytest.fixture(scope="session")
def playwright_browser_type():
    return "chromium"
```

## Credentials dans les tests — règle S2068

SonarQube (S2068) détecte les mots de passe hardcodés. Dans les fichiers de test, c'est un **faux positif** : un mot de passe de fixture n'est pas un credential réel. Ne pas contourner la règle en renommant des variables — cela masque le problème sans le résoudre.

La bonne réponse est d'annoter la ligne concernée :

```python
TEST_PASSWORD = "test_secret_1234!"  # NOSONAR S2068 — fixture de test, pas un credential réel
```

Ou, mieux, exclure les répertoires de test dans `sonar-project.properties` :

```properties
sonar.exclusions=**/tests/**,**/test_*.py
# ou cibler uniquement cette règle :
sonar.issue.ignore.multicriteria=e1
sonar.issue.ignore.multicriteria.e1.ruleKey=python:S2068
sonar.issue.ignore.multicriteria.e1.resourceKey=**/tests/**
```

## Règles de qualité

- Chaque test crée ses propres données — pas de dépendance entre tests
- Rollback de la DB après chaque test (fixture `db` ci-dessus)
- Pas de `sleep()` dans les tests — utiliser `expect().to_be_visible()` (Playwright) ou mocks
- Nommer clairement : `test_[action]_[condition]_[résultat_attendu]`
- Un seul comportement testé par test — séparer les assertions non liées
- **S2068 sur les tests = faux positif** — annoter avec `# NOSONAR S2068` ou exclure `tests/` dans `sonar-project.properties`, ne pas renommer les variables pour tromper l'outil
