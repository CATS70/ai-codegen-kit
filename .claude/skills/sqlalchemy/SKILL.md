---
name: sqlalchemy
description: Conventions SQLAlchemy 2.0 async pour Python. Modèles, sessions, requêtes, transactions, N+1, migrations Alembic.
---

# Conventions SQLAlchemy 2.0 (Async)

## Configuration de la session

```python
# db.py
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from core.settings import settings

engine = create_async_engine(
    settings.database_url,
    pool_size=settings.db_pool_size,
    max_overflow=settings.db_max_overflow,
    echo=settings.debug,
)

async_session_factory = async_sessionmaker(engine, expire_on_commit=False)

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_factory() as session:
        yield session
```

## Modèles — conventions

```python
# models/base.py
from sqlalchemy.orm import DeclarativeBase, mapped_column, Mapped
from sqlalchemy import func
from datetime import datetime

class Base(DeclarativeBase):
    pass

class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        server_default=func.now(), onupdate=func.now()
    )

# models/user.py
class User(Base, TimestampMixin):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(unique=True, index=True)
    name: Mapped[str] = mapped_column(String(100))
    is_active: Mapped[bool] = mapped_column(default=True)

    orders: Mapped[list["Order"]] = relationship(back_populates="user")
```

## Requêtes — syntaxe 2.0

```python
from sqlalchemy import select, update, delete

# SELECT avec filtre
stmt = select(User).where(User.email == email, User.is_active == True)
result = await db.execute(stmt)
user = result.scalar_one_or_none()

# SELECT avec jointure (évite N+1)
stmt = (
    select(Order)
    .options(selectinload(Order.items))   # charge les relations en 1 requête
    .where(Order.user_id == user_id)
    .order_by(Order.created_at.desc())
)

# INSERT
db.add(User(email=email, name=name))
await db.commit()

# UPDATE
stmt = update(User).where(User.id == user_id).values(name=new_name)
await db.execute(stmt)
await db.commit()

# DELETE
stmt = delete(User).where(User.id == user_id)
await db.execute(stmt)
await db.commit()
```

## Transactions

```python
async def transfer_stock(db: AsyncSession, from_id: int, to_id: int, qty: int):
    async with db.begin():  # rollback automatique si exception
        source = await db.get(Product, from_id, with_for_update=True)
        dest = await db.get(Product, to_id, with_for_update=True)

        if source.stock < qty:
            raise ValueError("Stock insuffisant")

        source.stock -= qty
        dest.stock += qty
    # commit automatique à la sortie du bloc
```

## Prévention N+1

```python
from sqlalchemy.orm import selectinload, joinedload

# ❌ N+1 — charge orders.items en N requêtes
orders = (await db.execute(select(Order))).scalars().all()
for order in orders:
    print(order.items)  # requête SQL par itération

# ✅ selectinload — 2 requêtes au total
stmt = select(Order).options(selectinload(Order.items))
orders = (await db.execute(stmt)).scalars().all()

# joinedload pour relations to-one
stmt = select(Order).options(joinedload(Order.user))
```

## Pattern repository dans les services

```python
# services/user_service.py
async def get_user_or_404(db: AsyncSession, user_id: int) -> User:
    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user

async def list_users(
    db: AsyncSession, pagination: PaginationParams
) -> tuple[list[User], int]:
    count_stmt = select(func.count()).select_from(User).where(User.is_active == True)
    total = (await db.execute(count_stmt)).scalar()

    stmt = (
        select(User)
        .where(User.is_active == True)
        .offset(pagination.offset)
        .limit(pagination.limit)
        .order_by(User.created_at.desc())
    )
    users = (await db.execute(stmt)).scalars().all()
    return users, total
```

## Migrations Alembic (async)

Initialisation — **utiliser le flag `-t async`** qui génère un `env.py` correct pour SQLAlchemy async :
```bash
alembic init -t async migrations
```

`migrations/env.py` généré — adapter uniquement les imports :
```python
import asyncio
from logging.config import fileConfig
from sqlalchemy import pool
from sqlalchemy.ext.asyncio import async_engine_from_config
from alembic import context
from app.models import Base   # ← importer TOUS les modèles ici (sinon autogenerate génère vide)
from core.settings import settings

config = context.config
fileConfig(config.config_file_name)
target_metadata = Base.metadata

def do_run_migrations(connection):
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()

async def run_async_migrations() -> None:
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()

def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())

if context.is_offline_mode():
    # mode offline simplifié — URL depuis alembic.ini
    context.configure(url=settings.database_url, target_metadata=target_metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()
else:
    run_migrations_online()
```

`models/base.py` — naming convention pour contraintes autogénérées cohérentes :
```python
from sqlalchemy import MetaData
from sqlalchemy.orm import DeclarativeBase

NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}

class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)
```

`alembic.ini` :
```ini
sqlalchemy.url = %(DATABASE_URL)s
```

Workflow standard :
```bash
alembic revision --autogenerate -m "add users table"
alembic upgrade head
alembic downgrade -1   # rollback
```

Règles :
- Toujours relire la migration générée avant d'appliquer — `autogenerate` manque les contraintes CHECK et certains index personnalisés
- Sans `naming_convention` sur la `MetaData`, les noms de contraintes sont non-déterministes → migrations inconsistantes entre environnements
- Ne jamais modifier une migration déjà appliquée en production
- Chaque migration doit avoir un `downgrade` fonctionnel

### Piège : ENUM PostgreSQL réutilisé sur plusieurs tables

Quand un type `ENUM` est utilisé comme colonne sur plusieurs tables, `autogenerate` crée le type explicitement une fois puis le réutilise comme type de colonne dans les `create_table` suivants :

```python
def upgrade() -> None:
    job_status_enum = postgresql.ENUM("pending", "running", "done", name="job_status_enum")
    job_status_enum.create(bind=op.get_bind(), checkfirst=True)

    op.create_table(
        "jobs",
        sa.Column("status", job_status_enum, nullable=False),
        # ...
    )
    op.create_table(
        "job_logs",
        # ❌ create_type=True (défaut) → SQLAlchemy retente un CREATE TYPE au moment du create_table
        # → conflit avec le type déjà créé ci-dessus, dans la même transaction
        sa.Column("status", postgresql.ENUM("pending", "running", "done", name="job_status_enum"), nullable=False),
    )
```

- `postgresql.ENUM` a `create_type=True` par défaut : chaque fois qu'il est utilisé comme type de colonne dans un `create_table`, SQLAlchemy émet aussi un `CREATE TYPE`
- Si le type a déjà été créé explicitement (ou utilisé dans une table précédente), il faut `create_type=False` sur toutes les définitions suivantes du même type
- La migration étant transactionnelle, un échec ici fait un rollback complet — pas de nettoyage manuel nécessaire, mais la migration reste bloquée tant que le fix n'est pas appliqué

```python
job_status_enum = postgresql.ENUM("pending", "running", "done", name="job_status_enum", create_type=False)
```

## Fixtures de test — pattern NullPool

En test, ne jamais réutiliser l'engine de production (pool incompatible avec asyncpg dans un contexte multi-test).

```python
# tests/conftest.py
from sqlalchemy.pool import NullPool
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker

# NullPool : pas de réutilisation de connexion entre tests — isole chaque test
_test_engine = create_async_engine(TEST_DATABASE_URL, poolclass=NullPool)
_session_factory = async_sessionmaker(_test_engine, expire_on_commit=False)
```

> **Pourquoi NullPool ?** `asyncpg` maintient un état interne par connexion. Le pool standard réutilise les connexions entre tests, ce qui provoque des conflits d'event loop et des erreurs difficiles à diagnostiquer. `NullPool` crée une connexion fraîche à chaque checkout.

## expire_on_commit=False — piège collections

Avec `expire_on_commit=False`, les scalaires (id, name…) restent accessibles après commit. Mais les **collections** (relations one-to-many) chargées avant le commit peuvent rester vides (`[]`) si elles n'ont pas été explicitement chargées :

```python
# ❌ cart.items peut être [] après commit si pas chargé avant
cart = await db.get(Cart, cart_id)
await db.commit()
print(len(cart.items))  # → 0, pas d'erreur mais résultat faux

# ✅ refresh explicite sur la collection après commit
await db.refresh(cart, attribute_names=["items"])
print(len(cart.items))  # → correct
```

Utiliser `selectinload` dans la requête initiale est préférable quand on sait qu'on aura besoin de la collection.

## Anti-patterns

```python
# ❌ Session synchrone avec driver async
from sqlalchemy.orm import Session   # ne pas utiliser avec asyncpg

# ❌ expire_on_commit=True (défaut) avec async — accès après commit = erreur
async_session_factory = async_sessionmaker(engine)  # manque expire_on_commit=False

# ❌ Charger tous les résultats sans limite
users = (await db.execute(select(User))).scalars().all()  # full-scan dangereux

# ✅ Toujours paginer
users = (await db.execute(select(User).limit(100).offset(0))).scalars().all()
```
