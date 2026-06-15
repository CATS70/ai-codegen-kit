---
name: database-design
description: Conception de schéma PostgreSQL production-ready. Conventions de nommage, contraintes d'intégrité, stratégie d'index, données sensibles au repos, permissions DB, soft delete, audit trail.
---

# Conventions Database Design

## Nommage

| Élément         | Convention               | Exemple                          |
|-----------------|--------------------------|----------------------------------|
| Tables          | `snake_case` pluriel     | `user_roles`, `order_items`      |
| Colonnes        | `snake_case`             | `created_at`, `is_active`        |
| Clés étrangères | `{table_sg}_id`          | `user_id`, `order_id`            |
| Index           | `ix_{table}_{colonnes}`  | `ix_users_email`                 |
| Contraintes     | `uq_{table}_{colonnes}`  | `uq_users_email`                 |
| Enum PG         | `snake_case` singulier   | `order_status`, `user_role`      |

Noms explicites, sans abréviations — `created_at` pas `crt_at`.

## IDs publics — règle obligatoire

**Ne jamais exposer l'`id` séquentiel dans les URLs ou les réponses API.** Utiliser un `public_id` UUID.

Raison : les IDs séquentiels révèlent le volume de données et permettent l'énumération.

```python
# SQLAlchemy — pattern dual-ID obligatoire pour toute entité exposée dans une URL
import uuid
from sqlalchemy import UUID

class Order(Base, TimestampMixin):
    __tablename__ = "orders"

    id:        Mapped[int]       = mapped_column(primary_key=True)
    public_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), default=uuid.uuid4, unique=True, index=True, nullable=False
    )
    user_id:   Mapped[int]       = mapped_column(ForeignKey("users.id"))
```

```python
# Route FastAPI — public_id dans l'URL, jamais id
@router.get("/orders/{order_id}", response_model=OrderResponse)
async def get_order(order_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    order = await db.scalar(select(Order).where(Order.public_id == order_id))
    if not order:
        raise HTTPException(status_code=404)
    return order

# Schéma Pydantic — ne jamais inclure id: int
class OrderResponse(BaseModel):
    id: uuid.UUID = Field(validation_alias="public_id")
    status: OrderStatus
    total: Decimal
```

Appliquer à : toute table dont les enregistrements sont accessibles via une URL (`/orders/{id}`, `/users/{id}`, `/cart/items/{id}`). Les tables pivot et de logs sans URL dédiée peuvent garder uniquement l'`id` séquentiel.

## Types de colonnes — règles

```sql
-- Identifiants
id          SERIAL PRIMARY KEY              -- entier séquentiel pour JOINs et FK internes
public_id   UUID DEFAULT gen_random_uuid() -- UUID exposé dans les URLs (jamais l'id interne)

-- Texte
email       VARCHAR(255)               -- longueur bornée, jamais TEXT pour les champs indexés
content     TEXT                       -- TEXT pour les contenus libres non indexés

-- Montants financiers
amount      NUMERIC(12, 2)             -- jamais FLOAT pour l'argent (imprécision flottante)

-- Dates
created_at  TIMESTAMPTZ DEFAULT NOW()  -- toujours WITH TIME ZONE
expires_at  TIMESTAMPTZ                -- idem

-- Booléens
is_active   BOOLEAN NOT NULL DEFAULT TRUE
```

## Contraintes — discipline NOT NULL

Toute colonne qui ne peut pas être nulle **doit** avoir `NOT NULL`. Les nulls masquent les bugs.

```python
# SQLAlchemy — bon usage
class User(Base):
    id:         Mapped[int]      = mapped_column(primary_key=True)
    email:      Mapped[str]      = mapped_column(String(255), unique=True)  # NOT NULL implicite
    name:       Mapped[str]      = mapped_column(String(100))
    role:       Mapped[UserRole] = mapped_column(default=UserRole.MEMBER)
    deleted_at: Mapped[datetime | None]  # None explicite = nullable voulu
```

## Contraintes d'intégrité

```python
# CHECK — valider en base, pas seulement en application
class Product(Base):
    price: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    stock: Mapped[int]     = mapped_column(default=0)

    __table_args__ = (
        CheckConstraint("price >= 0",  name="ck_products_price_positive"),
        CheckConstraint("stock >= 0",  name="ck_products_stock_positive"),
    )

# UNIQUE composite
class Membership(Base):
    __table_args__ = (
        UniqueConstraint("user_id", "org_id", name="uq_memberships_user_org"),
    )

# FK avec cascade explicite
class OrderItem(Base):
    order_id: Mapped[int] = mapped_column(
        ForeignKey("orders.id", ondelete="CASCADE"),  # suppression en cascade
    )
    product_id: Mapped[int] = mapped_column(
        ForeignKey("products.id", ondelete="RESTRICT"),  # interdit si référencé
    )
```

## Stratégie d'index

### Règle de base

Indexer les colonnes qui apparaissent dans `WHERE`, `JOIN ON`, `ORDER BY` sur des tables > 10 000 lignes.

```python
class User(Base):
    email:      Mapped[str] = mapped_column(String(255), index=True)   # B-tree, lookup exact
    created_at: Mapped[datetime]                                        # index si filtré souvent

class Notification(Base):
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    status:  Mapped[str]  # pas d'index si peu de valeurs distinctes (faible cardinalité)

    __table_args__ = (
        # Index composite — ordre important : colonne la plus sélective en premier
        Index("ix_notifications_user_status", "user_id", "status"),
        # Index partiel — n'indexe que les lignes PENDING (évite les lignes SENT/FAILED)
        Index(
            "ix_notifications_pending",
            "user_id",
            postgresql_where=text("status = 'pending'"),
        ),
    )
```

### Types d'index PostgreSQL

| Type    | Quand l'utiliser                                      |
|---------|-------------------------------------------------------|
| B-tree  | Égalité, plages (`=`, `<`, `>`, `BETWEEN`)            |
| GIN     | Colonnes JSON, tableaux, full-text search             |
| GiST    | Données géographiques, intervalles temporels          |
| BRIN    | Tables très volumineuses avec données ordonnées (logs)|

```python
# GIN pour jsonb
class Event(Base):
    metadata: Mapped[dict] = mapped_column(JSONB)

    __table_args__ = (
        Index("ix_events_metadata", "metadata", postgresql_using="gin"),
    )
```

### Ce qu'il ne faut pas faire

```python
# ❌ Index inutile — faible cardinalité (3 valeurs possibles)
Index("ix_orders_status", "status")

# ❌ Index sur une colonne transformée — non utilisé par PostgreSQL
# WHERE LOWER(email) = ...  → indexer lower(email) ou normaliser à l'insertion

# ❌ Trop d'index — ralentit les INSERT/UPDATE
# Viser max 3-4 index par table en dehors de la PK
```

## Données sensibles au repos

### Mots de passe — toujours bcrypt

Ne jamais stocker en clair, MD5, SHA-1 ou SHA-256. Seul bcrypt (ou argon2) est acceptable.

```python
from passlib.context import CryptContext
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto", bcrypt__rounds=12)
```

### PII et données confidentielles

Les données personnelles (numéros de téléphone, adresses, données de santé) qui ne sont pas utilisées pour des recherches doivent être chiffrées au repos.

```python
# Chiffrement symétrique avec Fernet (AES-128-CBC + HMAC)
from cryptography.fernet import Fernet

class EncryptedField:
    """Chiffre/déchiffre à la lecture/écriture. La clé vient de settings."""

    def __init__(self):
        self._fernet = Fernet(settings.encryption_key.encode())

    def encrypt(self, value: str) -> str:
        return self._fernet.encrypt(value.encode()).decode()

    def decrypt(self, token: str) -> str:
        return self._fernet.decrypt(token.encode()).decode()

# En base : colonne TEXT contenant le token chiffré
# En mémoire : valeur en clair uniquement le temps de traitement
```

```python
class Settings(BaseSettings):
    encryption_key: str   # Fernet.generate_key() — stocker dans .env, rotation planifiée
```

### Tokens et secrets — toujours hashés

Un token en base est toujours stocké hashé. Le token brut est envoyé une seule fois (email, réponse API).

```python
import hashlib, secrets

raw_token   = secrets.token_urlsafe(32)
token_hash  = hashlib.sha256(raw_token.encode()).hexdigest()
# → stocker token_hash en base, envoyer raw_token par email
```

### Données à ne jamais persister

- Numéros de carte bancaire (déléguer à Stripe/Adyen — PCI DSS)
- Tokens OAuth2 des providers externes (stocker seulement l'`external_id`)
- Mots de passe en clair, même temporairement

## Permissions de l'utilisateur de base de données

L'application ne doit jamais se connecter avec un superuser. Créer un rôle applicatif avec les droits minimaux.

```sql
-- Créer le rôle applicatif
CREATE ROLE app_user WITH LOGIN PASSWORD '...';

-- Accorder les droits sur les tables uniquement
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;

-- INTERDIT pour app_user
-- DROP TABLE, CREATE TABLE, TRUNCATE, ALTER TABLE
-- → réservés au rôle de migration (alembic_user) exécuté séparément
```

```python
class Settings(BaseSettings):
    database_url:           str   # URL du rôle applicatif (droits limités)
    database_migration_url: str   # URL du rôle migration (droits DDL) — utilisé par Alembic
```

## Soft delete

Préférer le soft delete pour les données métier ayant une valeur d'audit (commandes, utilisateurs, factures).

```python
class SoftDeleteMixin:
    deleted_at: Mapped[datetime | None] = mapped_column(default=None)

    @property
    def is_deleted(self) -> bool:
        return self.deleted_at is not None

class Order(Base, SoftDeleteMixin):
    ...

# Dans les services — filtre systématique
async def list_orders(db: AsyncSession) -> list[Order]:
    return list(await db.scalars(
        select(Order).where(Order.deleted_at.is_(None))
    ))

async def soft_delete_order(db: AsyncSession, order_id: int) -> None:
    order = await db.get(Order, order_id)
    order.deleted_at = datetime.now(timezone.utc)
    await db.commit()
```

Ne pas utiliser le soft delete pour : sessions, logs, tokens — supprimer physiquement.

## Audit trail

Pour les tables dont l'historique des modifications est critique (contrats, paiements, données médicales) :

```python
class AuditLog(Base):
    __tablename__ = "audit_logs"

    id:          Mapped[int]       = mapped_column(primary_key=True)
    table_name:  Mapped[str]       = mapped_column(String(64))
    record_id:   Mapped[int]
    action:      Mapped[str]       = mapped_column(String(16))   # INSERT, UPDATE, DELETE
    changed_by:  Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    old_values:  Mapped[dict | None] = mapped_column(JSONB)
    new_values:  Mapped[dict | None] = mapped_column(JSONB)
    created_at:  Mapped[datetime]  = mapped_column(default=func.now())
```

L'audit log ne doit jamais être modifié ou supprimé par l'application (permissions `INSERT` only pour `app_user`).

## Checklist schema avant migration

- [ ] Toutes les colonnes non nullables ont `NOT NULL`
- [ ] Les montants financiers en `NUMERIC`, jamais `FLOAT`
- [ ] Les dates en `TIMESTAMPTZ`, jamais `TIMESTAMP`
- [ ] Les URLs publiques utilisent UUID, pas l'id séquentiel
- [ ] Les FKs ont une stratégie `ondelete` explicite (CASCADE ou RESTRICT)
- [ ] Les index couvrent les colonnes de `WHERE` et `JOIN` fréquents
- [ ] Les tokens et mots de passe sont hashés avant stockage
- [ ] Les PII chiffrables sont chiffrées (`encryption_key` en env)
- [ ] L'utilisateur applicatif n'a pas de droits DDL
