---
name: pydantic
description: Conventions Pydantic v2 pour validation de données, schémas API et configuration. BaseModel, validators, BaseSettings, types stricts.
---

# Conventions Pydantic v2

## BaseModel — règles de base

```python
from pydantic import BaseModel, ConfigDict

class UserResponse(BaseModel):
    id: int
    email: str
    name: str
    created_at: datetime

    model_config = ConfigDict(
        from_attributes=True,   # lecture depuis objets SQLAlchemy
        extra="forbid",         # rejette les champs inconnus
    )
```

- `from_attributes=True` sur les schémas de réponse (conversion ORM → schema)
- `extra="forbid"` sur les schémas d'entrée (sécurité)

## Séparation des schémas

Un même concept a plusieurs schémas selon son usage :

```python
class UserCreate(BaseModel):       # entrée création
    email: EmailStr
    password: str = Field(min_length=8)
    name: str = Field(max_length=100)
    model_config = ConfigDict(extra="forbid")

class UserUpdate(BaseModel):       # entrée mise à jour (champs optionnels)
    name: str | None = None
    model_config = ConfigDict(extra="forbid")

class UserResponse(BaseModel):     # sortie API (jamais le mot de passe)
    id: int
    email: str
    name: str
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)
```

## Field — validation déclarative

```python
from pydantic import Field

class ProductCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    price: Decimal = Field(gt=0, decimal_places=2)
    stock: int = Field(ge=0)
    description: str | None = Field(None, max_length=2000)
```

## Validators

```python
from pydantic import field_validator, model_validator

class OrderCreate(BaseModel):
    quantity: int = Field(gt=0)
    unit_price: Decimal = Field(gt=0)
    discount: float = Field(ge=0, le=1)

    @field_validator("quantity")
    @classmethod
    def quantity_must_be_reasonable(cls, v: int) -> int:
        if v > 10_000:
            raise ValueError("Quantity exceeds maximum allowed")
        return v

    @model_validator(mode="after")
    def check_total_positive(self) -> "OrderCreate":
        total = self.quantity * self.unit_price * (1 - self.discount)
        if total <= 0:
            raise ValueError("Order total must be positive")
        return self
```

## BaseSettings — configuration

```python
# core/settings.py
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    # Application
    app_name: str = "My App"
    app_version: str = "0.1.0"
    debug: bool = False

    # Base de données
    database_url: str                    # requis, pas de défaut
    db_pool_size: int = 10
    db_max_overflow: int = 20

    # Sécurité
    jwt_secret: str                      # requis
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60

    # CORS
    allowed_origins: list[str] = ["http://localhost:3000"]

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

settings = Settings()  # singleton importé partout
```

## Types utiles

```python
from pydantic import EmailStr, HttpUrl, AnyUrl
from uuid import UUID
from decimal import Decimal

class UserCreate(BaseModel):
    email: EmailStr               # validation format email
    website: HttpUrl | None = None
    balance: Decimal = Decimal("0.00")
    external_id: UUID | None = None
```

## Réponses paginées

```python
from typing import Generic, TypeVar
T = TypeVar("T")

class PaginatedResponse(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    size: int
    pages: int

    @classmethod
    def create(cls, items: list[T], total: int, page: int, size: int):
        return cls(
            items=items,
            total=total,
            page=page,
            size=size,
            pages=(total + size - 1) // size,
        )
```

## Enums dans les schémas

```python
from enum import StrEnum  # Python 3.11+

class OrderStatus(StrEnum):
    PENDING   = "pending"
    PAID      = "paid"
    SHIPPED   = "shipped"
    CANCELLED = "cancelled"

class OrderResponse(BaseModel):
    id: int
    status: OrderStatus   # sérialisé comme string, validé à la désérialisation
```

## Anti-patterns à éviter

```python
# ❌ model_construct() contourne la validation
user = UserCreate.model_construct(email="not-an-email")

# ❌ dict() est déprécié en v2
data = user.dict()

# ✅ utiliser model_dump()
data = user.model_dump()
data = user.model_dump(exclude={"password"})
data = user.model_dump(include={"id", "email"})

# ❌ Optional sans valeur par défaut explicite — SonarQube S8396
class Schema(BaseModel):
    field: Optional[str]       # interdit : ambigu, déclenche S8396

# ✅ Toujours une valeur par défaut explicite
class Schema(BaseModel):
    field: Optional[str] = None          # explicite
    field2: str | None = None            # syntaxe alternative (préférer celle-ci en Python 3.10+)

# ❌ Optional[X] sans import explicite — utiliser X | None en Python 3.10+
from typing import Optional
field: Optional[str] = None

# ✅ préférer la syntaxe union native
field: str | None = None
```
