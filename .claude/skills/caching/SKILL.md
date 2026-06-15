---
name: caching
description: Caching Redis pour FastAPI Python. Cache-aside, TTL, invalidation, sessions, catalogue produits. Charger quand volume medium ou high (>100 users simultanés).
---

# Conventions caching — Redis

## Quand charger ce skill

Charger uniquement si le volume est **medium** (100–10k users) ou **high** (>10k). Pour les projets low-volume, un dict Python ou aucun cache suffit.

## Configuration

```python
# core/settings.py
class Settings(BaseSettings):
    redis_url: str = "redis://localhost:6379/0"
    cache_ttl_seconds: int = 300  # 5 min par défaut
```

```python
# core/cache.py
import json
from typing import Any
import redis.asyncio as redis
from app.core.settings import settings

_pool: redis.ConnectionPool | None = None


def get_redis_pool() -> redis.ConnectionPool:
    global _pool
    if _pool is None:
        _pool = redis.ConnectionPool.from_url(settings.redis_url, decode_responses=True)
    return _pool


async def get_cache() -> redis.Redis:
    return redis.Redis(connection_pool=get_redis_pool())
```

## Pattern cache-aside

Le pattern de base : lire le cache, retourner si présent, sinon interroger la DB et mettre en cache.

```python
# services/product_service.py
import json
from app.core.cache import get_cache
from app.core.settings import settings

async def get_product(db: AsyncSession, product_id: int) -> Product | None:
    cache = await get_cache()
    key = f"product:{product_id}"

    cached = await cache.get(key)
    if cached:
        return Product(**json.loads(cached))

    product = await db.get(Product, product_id)
    if product:
        await cache.setex(key, settings.cache_ttl_seconds, json.dumps(product_to_dict(product)))
    return product
```

## Invalidation

Invalider le cache à chaque mutation. Préférer des clés structurées pour faciliter l'invalidation par préfixe.

```python
async def update_product(db: AsyncSession, product_id: int, data: ProductUpdate) -> Product:
    product = await db.get(Product, product_id, with_for_update=True)
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(product, field, value)
    await db.commit()

    # Invalider les entrées affectées
    cache = await get_cache()
    await cache.delete(f"product:{product_id}")
    await cache.delete("products:list")   # liste paginée
    return product
```

## Cache de liste avec pagination

Les listes paginées sont invalidées entièrement à chaque mutation — acceptable si les mutations sont rares.

```python
async def list_products(
    db: AsyncSession, page: int = 1, limit: int = 20
) -> tuple[list[Product], int]:
    cache = await get_cache()
    key = f"products:list:p{page}:l{limit}"

    cached = await cache.get(key)
    if cached:
        data = json.loads(cached)
        return data["items"], data["total"]

    stmt = select(Product).where(Product.is_active == True).offset((page - 1) * limit).limit(limit)
    products = (await db.execute(stmt)).scalars().all()
    total_stmt = select(func.count()).select_from(Product).where(Product.is_active == True)
    total = (await db.execute(total_stmt)).scalar()

    payload = {"items": [p.model_dump() for p in products], "total": total}
    await cache.setex(key, settings.cache_ttl_seconds, json.dumps(payload))
    return products, total
```

## Sessions utilisateur

Utiliser Redis pour les sessions stateless (alternative aux JWT ou complément).

```python
import secrets

async def create_session(user_id: int) -> str:
    cache = await get_cache()
    session_id = secrets.token_urlsafe(32)
    await cache.setex(f"session:{session_id}", 3600, str(user_id))
    return session_id

async def get_session_user_id(session_id: str) -> int | None:
    cache = await get_cache()
    value = await cache.get(f"session:{session_id}")
    return int(value) if value else None

async def delete_session(session_id: str) -> None:
    cache = await get_cache()
    await cache.delete(f"session:{session_id}")
```

## Injection dans FastAPI

```python
# api/deps.py
from app.core.cache import get_cache
import redis.asyncio as redis

async def get_cache_dep() -> redis.Redis:
    return await get_cache()

# api/products.py
@router.get("/products/")
async def list_products_route(
    page: int = 1,
    db: AsyncSession = Depends(get_db),
    cache: redis.Redis = Depends(get_cache_dep),
):
    return await list_products(db, cache, page)
```

## docker-compose

```yaml
services:
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    command: redis-server --appendonly yes  # persistance AOF

volumes:
  redis_data:
```

## TTL recommandés par type de données

| Données | TTL | Raison |
|---------|-----|--------|
| Catalogue produit | 5 min | Mise à jour rare |
| Profil utilisateur | 15 min | Donnée stable |
| Panier anonyme | 24h | Durée de session typique |
| Session auth | 1h | Expire avec le JWT |
| Résultats de recherche | 2 min | Fraîcheur attendue |

## Anti-patterns

```python
# ❌ Mettre en cache des données sensibles (mots de passe, tokens)
await cache.set("user:1:password_hash", hash)  # jamais

# ❌ TTL infini — les données deviennent obsolètes
await cache.set("products:list", data)  # manque setex

# ❌ Clés sans namespace — collision entre environnements
await cache.set("products", data)   # trop générique

# ✅ Namespace explicite
await cache.setex("myapp:prod:products:list:p1", 300, data)
```
