---
name: fastapi
description: Conventions FastAPI pour APIs REST Python. Routeurs, injection de dépendances, modèles de réponse, pagination, gestion d'erreurs, async.
---

# Conventions FastAPI

## Structure des routeurs

Un fichier par domaine dans `api/`. Chaque routeur déclare son préfixe et ses tags.

```python
# api/users.py
router = APIRouter(prefix="/users", tags=["users"])
```

Enregistrement dans `main.py` :
```python
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(products.router)
```

## Règle des 20 lignes par route

Les routes orchestrent, elles ne contiennent pas de logique métier.

```python
@router.post("/", response_model=UserResponse, status_code=201)
async def create_user(data: UserCreate, db: DB, _: CurrentUser) -> UserResponse:
    return await user_service.create_user(db, data)
```

## Response model — toujours déclaré

- Toujours `response_model` sur chaque route
- Séparer schémas d'entrée (`UserCreate`, `UserUpdate`) et de sortie (`UserResponse`)
- Ne jamais retourner un modèle SQLAlchemy directement

## Injection de dépendances — pattern `Annotated` (obligatoire)

FastAPI 0.95+ impose le pattern `Annotated` pour les dépendances. L'ancien `= Depends(X)` est déprécié et déclenche des violations SonarQube (S8410).

```python
from typing import Annotated

# db/session.py
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_factory() as session:
        yield session

# Alias réutilisables (bonne pratique)
DB = Annotated[AsyncSession, Depends(get_db)]
CurrentUser = Annotated[User, Depends(get_current_user)]

# api/deps.py
async def get_current_user(
    token: Annotated[str, Depends(oauth2_scheme)],
    db: DB,
) -> User:
    ...

# api/users.py — utilisation dans les routes
@router.get("/{user_id}", response_model=UserResponse)
async def get_user(user_id: int, db: DB, current_user: CurrentUser) -> UserResponse:
    return await user_service.get_user_or_404(db, user_id)
```

**Ne jamais écrire** `param: Type = Depends(X)` — toujours `param: Annotated[Type, Depends(X)]`.

## Pagination — pattern standard

```python
# schemas/pagination.py
class PaginationParams:
    def __init__(
        self,
        page: int = Query(1, ge=1),
        size: int = Query(20, ge=1, le=100),
    ):
        self.offset = (page - 1) * size
        self.limit = size

class PaginatedResponse(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    size: int
    pages: int
```

Toutes les routes retournant une liste utilisent `PaginationParams`.

## Codes HTTP

| Situation | Code |
|---|---|
| Création réussie | 201 |
| Succès sans contenu retourné | 204 |
| Ressource non trouvée | 404 |
| Non authentifié | 401 |
| Non autorisé (authentifié mais interdit) | 403 |
| Validation Pydantic échouée | 422 |
| Conflit / doublon | 409 |

## Documentation des codes d'erreur dans les routes

Chaque `HTTPException` levée dans une route doit être déclarée dans le paramètre `responses`. SonarQube (S8415) le vérifie.

```python
@router.post(
    "/login",
    response_model=TokenResponse,
    responses={
        401: {"description": "Invalid credentials"},
        409: {"description": "Email already registered"},
    },
)
async def login(data: LoginRequest, db: DB) -> TokenResponse:
    ...
```

## Gestion des erreurs

```python
# Erreur métier connue
raise HTTPException(status_code=404, detail="User not found")

# Handler global pour erreurs inattendues — dans main.py
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error("Unexpected error", exc_info=exc)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"},
    )
```

**Exceptions typées par couche :**

Un `Exception` générique dans le handler masque les erreurs métier derrière un 500 opaque. Définir des exceptions typées permet de les attraper sélectivement et de retourner les bons codes HTTP.

```python
# core/exceptions.py
class AppError(Exception):
    """Base pour toutes les erreurs applicatives typées."""
    status_code: int = 500
    detail: str = "Internal server error"

class NotFoundError(AppError):
    status_code = 404
    def __init__(self, resource: str):
        self.detail = f"{resource} not found"

class ConflictError(AppError):
    status_code = 409

class UnauthorizedError(AppError):
    status_code = 401
    detail = "Authentication required"

# main.py — handler dédié aux erreurs applicatives
@app.exception_handler(AppError)
async def app_error_handler(request: Request, exc: AppError):
    logger.warning("Application error", extra={"status": exc.status_code, "detail": exc.detail})
    return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})

# services/user_service.py — usage dans un service
async def get_user_or_404(db: AsyncSession, user_id: int) -> User:
    user = await db.get(User, user_id)
    if not user:
        raise NotFoundError("User")   # propagé jusqu'au handler, retourne 404
    return user
```

## Configuration de l'application

```python
# main.py
app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    docs_url="/docs" if settings.debug else None,  # swagger désactivé en prod
    redoc_url=None,
)
```

## Async — règles

- Toutes les routes en `async def`
- `AsyncSession` SQLAlchemy (pas `Session` synchrone)
- Opérations CPU-intensives → `asyncio.run_in_executor`
- **Jamais `open()` synchrone dans une fonction `async`** — utiliser `aiofiles.open()` (S7493). Ajouter `aiofiles` aux dépendances si lecture/écriture de fichiers nécessaire.

```python
# ❌
async def process_file(path: str) -> str:
    with open(path) as f:          # bloque la boucle d'événements
        return f.read()

# ✅
import aiofiles

async def process_file(path: str) -> str:
    async with aiofiles.open(path) as f:
        return await f.read()
```

## Background tasks

Pour les opérations non bloquantes après réponse (emails, notifications) :

```python
@router.post("/orders/", response_model=OrderResponse, status_code=201)
async def create_order(
    data: OrderCreate,
    background_tasks: BackgroundTasks,
    db: DB,
    current_user: CurrentUser,
):
    order = await order_service.create_order(db, data, current_user)
    background_tasks.add_task(notification_service.send_confirmation, order)
    return order
```

**Anti-pattern BackgroundTasks + session DB :**

Si la tâche en background a besoin d'accès à la base de données, ne pas réutiliser la session de la requête (elle sera fermée) ni importer `async_session_factory` à l'intérieur de la route.

```python
# ❌ — casse l'injection de dépendances, crée un couplage fort
from app.db import async_session_factory   # import au milieu de la logique métier

async def create_order(...):
    order = await order_service.create_order(db, data)
    async def _notify():
        async with async_session_factory() as new_db:   # session manuelle bricolée
            await notification_service.send(new_db, order.id)
    background_tasks.add_task(_notify)

# ✅ — passer les données primitives, la tâche gère sa propre session
async def create_order(data: OrderCreate, background_tasks: BackgroundTasks, db: DB, ...):
    order = await order_service.create_order(db, data)
    background_tasks.add_task(send_confirmation_email, order_id=order.id)  # ID, pas l'objet
    return order

# services/notification_service.py
async def send_confirmation_email(order_id: int) -> None:
    async with get_async_session() as db:   # session propre, gérée localement
        order = await db.get(Order, order_id)
        ...
```

La session SQLAlchemy de la requête est fermée dès que la dépendance est libérée. Passer l'objet entier à la tâche en background provoque une `DetachedInstanceError` au premier accès lazy.

## Middleware

Ordre d'enregistrement dans `main.py` (dernier ajouté = exécuté en premier) :

```python
app.add_middleware(CORSMiddleware, ...)      # 1er exécuté
app.add_middleware(GZipMiddleware, ...)
# auth gérée via Depends, pas middleware global
```

## Documentation des routes

Docstring courte sur chaque route publique — elle apparaît dans Swagger :

```python
@router.get("/{user_id}", response_model=UserResponse)
async def get_user(user_id: int, db: AsyncSession = Depends(get_db)):
    """Récupère un utilisateur par son identifiant."""
    return await user_service.get_user_or_404(db, user_id)
```
