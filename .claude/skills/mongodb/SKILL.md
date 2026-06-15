---
name: mongodb
description: Conventions MongoDB async pour Python/FastAPI. Beanie ODM (Motor + Pydantic v2), design de documents, index, agrégation, transactions, sécurité.
---

# Conventions MongoDB

## Dépendances

```toml
# pyproject.toml
motor   = "^3.4"    # driver async officiel MongoDB
beanie  = "^1.26"   # ODM async (Motor + Pydantic v2)
```

Beanie est l'ODM retenu : il repose sur Motor (async) et s'intègre nativement avec Pydantic v2, qui est déjà utilisé pour la validation des routes FastAPI.

## Configuration et connexion

```python
# core/settings.py
class Settings(BaseSettings):
    mongodb_url:  str = "mongodb://localhost:27017"
    mongodb_name: str = "myapp"

# db.py
from beanie import init_beanie
from motor.motor_asyncio import AsyncIOMotorClient
from core.settings import settings

async def init_db(document_models: list) -> None:
    client = AsyncIOMotorClient(settings.mongodb_url)
    await init_beanie(database=client[settings.mongodb_name], document_models=document_models)

# main.py
@app.on_event("startup")
async def on_startup() -> None:
    from models.user import User
    from models.order import Order
    await init_db([User, Order])
```

## Modèles — Beanie Document

```python
# models/user.py
from beanie import Document, Indexed
from pydantic import EmailStr, Field
from datetime import datetime, timezone
import uuid

class User(Document):
    public_id:  str      = Field(default_factory=lambda: str(uuid.uuid4()))
    email:      Indexed(EmailStr, unique=True)  # index unique déclaré inline
    name:       str
    role:       str      = "member"
    is_active:  bool     = True
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    class Settings:
        name = "users"          # nom de la collection
        use_revision = True     # détection de conflits sur update concurrent
```

L'`_id` MongoDB (ObjectId) est géré automatiquement par Beanie. Exposer un `public_id` UUID dans l'API — ne jamais exposer l'ObjectId directement.

## Design de documents : embedding vs referencing

### Règle de décision

| Critère | Embedding | Referencing |
|---|---|---|
| Données lues ensemble systématiquement | ✅ | ❌ |
| Cardinalité de la relation | 1-à-peu (≤ 50) | 1-à-beaucoup |
| Les données enfants existent seules | ❌ | ✅ |
| Mises à jour fréquentes des enfants | ❌ | ✅ |

### Embedding — quand les données sont toujours lues ensemble

```python
# models/order.py
class OrderItem(BaseModel):          # BaseModel, pas Document — pas de collection propre
    product_id: str
    name:       str
    quantity:   int
    unit_price: float

class Order(Document):
    user_id:    str                  # référence vers User (ObjectId sous forme de str)
    items:      list[OrderItem]      # embedded — toujours lus avec la commande
    total:      float
    status:     str = "pending"
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    class Settings:
        name = "orders"
```

### Referencing — quand les données ont une vie propre

```python
# models/article.py
from beanie import Link

class Article(Document):
    title:      str
    author:     Link[User]          # référence résolue à la lecture (1 requête supplémentaire)
    tags:       list[str] = []
    content:    str

    class Settings:
        name = "articles"

# Lecture avec résolution de la référence
article = await Article.find_one(Article.id == article_id, fetch_links=True)
print(article.author.name)          # User chargé
```

## Index

```python
# models/notification.py
from beanie import Document, Indexed
from pymongo import IndexModel, ASCENDING, DESCENDING, TEXT

class Notification(Document):
    user_id:    Indexed(str)                    # index simple
    status:     str
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    class Settings:
        name = "notifications"
        indexes = [
            # Index composé — requêtes filtrées par user + status
            IndexModel([("user_id", ASCENDING), ("status", ASCENDING)]),
            # Index TTL — suppression automatique après 30 jours
            IndexModel([("created_at", ASCENDING)], expireAfterSeconds=30 * 24 * 3600),
            # Index partiel — uniquement les notifications PENDING
            IndexModel(
                [("user_id", ASCENDING)],
                name="ix_notifications_user_pending",
                partialFilterExpression={"status": "pending"},
            ),
        ]

# Recherche full-text
class Article(Document):
    title:   str
    content: str

    class Settings:
        name = "articles"
        indexes = [
            IndexModel([("title", TEXT), ("content", TEXT)], default_language="french"),
        ]

# Requête full-text
results = await Article.find({"$text": {"$search": "intelligence artificielle"}}).to_list()
```

## Requêtes courantes

```python
# Lecture
user = await User.get(user_id)                          # par ObjectId
user = await User.find_one(User.email == email)
users = await User.find(User.is_active == True).to_list()

# Pagination
users = await (
    User.find(User.is_active == True)
    .sort(-User.created_at)
    .skip(offset)
    .limit(limit)
    .to_list()
)
total = await User.find(User.is_active == True).count()

# Création
user = User(email=email, name=name)
await user.insert()

# Update — modifier un champ
await user.set({User.name: new_name})

# Update — opérateurs MongoDB
await Order.find_one(Order.id == order_id).update(
    {"$push": {"items": item.model_dump()}}
)

# Soft delete
await user.set({User.deleted_at: datetime.now(timezone.utc)})

# Delete physique
await user.delete()
```

## Agrégation pipeline

Pour les calculs, regroupements et jointures entre collections.

```python
from beanie.odm.operators.find.comparison import GT

# Exemple : total des ventes par statut
pipeline = [
    {"$match": {"status": {"$in": ["paid", "shipped"]}}},
    {"$group": {
        "_id": "$status",
        "total":       {"$sum": "$total"},
        "order_count": {"$count": {}},
    }},
    {"$sort": {"total": -1}},
]
results = await Order.aggregate(pipeline).to_list()

# Jointure ($lookup) — équivalent d'un JOIN SQL
pipeline = [
    {"$match": {"user_id": str(user_id)}},
    {"$lookup": {
        "from":         "users",
        "localField":   "user_id",
        "foreignField": "public_id",
        "as":           "user",
    }},
    {"$unwind": "$user"},
    {"$project": {"items": 1, "total": 1, "user.name": 1, "user.email": 1}},
]
```

## Transactions

Les transactions multi-documents nécessitent un replica set (même en dev — utiliser `mongod --replSet rs0`).

```python
from motor.motor_asyncio import AsyncIOMotorClient

async def transfer_credits(
    from_user_id: str, to_user_id: str, amount: float
) -> None:
    client = AsyncIOMotorClient(settings.mongodb_url)
    async with await client.start_session() as session:
        async with session.start_transaction():
            sender = await User.find_one(User.public_id == from_user_id, session=session)
            if not sender or sender.credits < amount:
                raise ValueError("Solde insuffisant")

            await sender.set({User.credits: sender.credits - amount}, session=session)
            await User.find_one(User.public_id == to_user_id).update(
                {"$inc": {"credits": amount}}, session=session
            )
        # commit automatique à la sortie du bloc — rollback si exception
```

## Sécurité

### Utilisateur applicatif avec droits minimaux

```javascript
// MongoDB shell — à exécuter une seule fois
db.createUser({
  user: "app_user",
  pwd:  "<mot de passe depuis env>",
  roles: [{ role: "readWrite", db: "myapp" }]
  // Jamais dbAdmin, clusterAdmin, root
})
```

```python
class Settings(BaseSettings):
    mongodb_url:  str  # mongodb://app_user:<pwd>@host:27017/myapp
    # Jamais l'URL root dans l'application
```

### Validation côté MongoDB (JSON Schema)

En complément de Pydantic, le schéma est appliqué en base pour rejeter les insertions malformées depuis n'importe quel client.

```python
class User(Document):
    class Settings:
        name = "users"
        # Validation MongoDB : appliquée même hors Beanie (scripts, mongo shell)
        bson_encoders = {}
        validate_on_save = True   # active la validation Pydantic avant insert/update
```

### Données sensibles

Mêmes règles que `database-design` :
- Mots de passe : bcrypt, jamais en clair
- Tokens : stocker le hash SHA-256, pas le token brut
- PII : chiffrement Fernet avant stockage dans le document

```python
class User(Document):
    email:         str
    password_hash: str           # bcrypt
    phone_hash:    str | None    # SHA-256 du numéro (pour lookup exact uniquement)
    phone_enc:     str | None    # Fernet (pour affichage — déchiffrable)
```

### Injection NoSQL

Beanie utilise des requêtes typées — pas de concaténation de requêtes.

```python
# ❌ INTERDIT — injection possible si email contient {"$gt": ""}
collection.find({"email": request_body["email"]})

# ✅ Beanie — requête typée
await User.find_one(User.email == email)

# ✅ Si requête brute nécessaire — valider le type avant
if not isinstance(email, str):
    raise ValueError("Invalid email")
await User.find_one({"email": email})
```

## Intégration FastAPI

```python
# api/users.py
router = APIRouter(prefix="/users", tags=["users"])

@router.get("/{public_id}", response_model=UserRead)
async def get_user(
    public_id: str,
    current_user: User = Depends(get_current_user),
):
    """Récupère un utilisateur par son public_id."""
    user = await User.find_one(User.public_id == public_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return UserRead.model_validate(user.model_dump())
```

## Anti-patterns

```python
# ❌ Charger tous les documents sans limite
users = await User.find_all().to_list()

# ✅ Toujours paginer
users = await User.find().skip(offset).limit(limit).to_list()

# ❌ Document trop profond (nesting > 3 niveaux) — difficile à requêter et indexer
class Order(Document):
    customer: dict   # contient address: {city: {zip: ...}}

# ❌ Tableau sans borne — peut dépasser la limite de document MongoDB (16 Mo)
class User(Document):
    activity_log: list[dict]  # grandit sans fin

# ✅ Collection séparée pour les données non bornées
class ActivityLog(Document):
    user_id: str
    event:   str
    ...
```

## Règles

- Ne jamais exposer l'ObjectId `_id` dans l'API — utiliser `public_id` UUID
- Les tableaux embedded sont bornés (commentaires d'un post : OK) — pas les logs ou historiques
- Décision embedding vs referencing basée sur le pattern de lecture, pas sur la structure relationnelle
- `validate_on_save = True` activé sur tous les Documents — la validation Pydantic s'applique avant chaque insert/update
- Index TTL pour les données temporaires (tokens, sessions, OTP) — pas de cron de nettoyage manuel
- Replica set obligatoire en production — même single-node — pour activer les transactions et le oplog
