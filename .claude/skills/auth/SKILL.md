---
name: auth
description: Authentification JWT et OAuth2 pour FastAPI. Hashing passwords, génération/validation tokens, refresh, RBAC, dépendances d'injection.
---

# Conventions Auth — JWT + OAuth2

## Dépendances

```toml
# pyproject.toml
PyJWT = "^2.8"
pwdlib = {extras = ["argon2"], version = "^0.2"}
```

## Hashing des mots de passe

```python
# services/auth_service.py
from pwdlib import PasswordHash

# Argon2id — recommandation OWASP 2024, résistant GPU/ASIC
# Créé par François Voron (auteur fastapi-users) pour remplacer passlib
pwd_context = PasswordHash.recommended()

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)
```

## Génération et validation JWT

```python
import jwt
from jwt import InvalidTokenError
from datetime import datetime, timedelta, timezone
from core.settings import settings

def create_access_token(user_id: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.jwt_expire_minutes)
    payload = {"sub": user_id, "exp": expire, "type": "access"}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)

def create_refresh_token(user_id: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(days=settings.jwt_refresh_days)
    payload = {"sub": user_id, "exp": expire, "type": "refresh"}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)

def decode_token(token: str, expected_type: str = "access") -> str:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        if payload.get("type") != expected_type:
            raise InvalidTokenError("Invalid token type")
        return payload["sub"]  # str — int ou UUID selon le modèle User
    except InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
```

## Dépendance get_current_user

```python
# api/deps.py
from fastapi.security import OAuth2PasswordBearer

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")

async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    user_id = decode_token(token)  # str
    user = await db.get(User, user_id)
    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="User not found or inactive")
    return user

async def get_current_active_user(
    current_user: User = Depends(get_current_user),
) -> User:
    return current_user
```

## Routes auth

```python
# api/auth.py
router = APIRouter(prefix="/auth", tags=["auth"])

@router.post("/login", response_model=TokenResponse)
async def login(
    form: OAuth2PasswordRequestForm = Depends(),
    db: AsyncSession = Depends(get_db),
):
    """Authentification par email/password, retourne access + refresh tokens."""
    user = await auth_service.authenticate(db, form.username, form.password)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    return TokenResponse(
        access_token=create_access_token(str(user.id)),
        refresh_token=create_refresh_token(str(user.id)),
        token_type="bearer",
    )

@router.post("/refresh", response_model=TokenResponse)
async def refresh(body: RefreshRequest, db: AsyncSession = Depends(get_db)):
    """Renouvelle l'access token depuis un refresh token valide."""
    user_id = decode_token(body.refresh_token, expected_type="refresh")
    user = await db.get(User, user_id)
    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="Invalid refresh token")
    return TokenResponse(
        access_token=create_access_token(str(user.id)),
        refresh_token=create_refresh_token(str(user.id)),
        token_type="bearer",
    )

@router.post("/register", response_model=UserResponse, status_code=201)
async def register(data: UserCreate, db: AsyncSession = Depends(get_db)):
    """Création de compte. Retourne 409 si l'email est déjà utilisé."""
    if await auth_service.email_exists(db, data.email):
        raise HTTPException(status_code=409, detail="Email already registered")
    user = await auth_service.create_user(db, data)
    return user
```

## Schémas

```python
class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"

class RefreshRequest(BaseModel):
    refresh_token: str
    model_config = ConfigDict(extra="forbid")
```

## RBAC — contrôle d'accès par rôle

```python
# models/user.py
class UserRole(StrEnum):
    USER  = "user"
    ADMIN = "admin"

class User(Base):
    role: Mapped[UserRole] = mapped_column(default=UserRole.USER)

# api/deps.py
def require_role(*roles: UserRole):
    async def check(current_user: User = Depends(get_current_user)) -> User:
        if current_user.role not in roles:
            raise HTTPException(status_code=403, detail="Insufficient permissions")
        return current_user
    return check

# Usage dans une route admin
@router.delete("/{user_id}", status_code=204)
async def delete_user(
    user_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_role(UserRole.ADMIN)),
):
    await user_service.delete_user(db, user_id)
```

## OAuth2 — Authorization Code Flow (login social)

Le skill couvre deux mécanismes distincts :
- **Password grant** (sections ci-dessus) : email/password → JWT interne
- **Authorization Code Flow** (ci-dessous) : Google/GitHub/etc. → JWT interne

Ne pas confondre `OAuth2PasswordBearer` de FastAPI (simple scheme Bearer) avec l'Authorization Code Flow.

### Dépendance supplémentaire

```toml
authlib = "^1.6.5"   # >= 1.6.5 pour le patch CVE-2025-61920
httpx = "^0.27"
```

### Modèle oauth_accounts

```python
# models/oauth_account.py
class OAuthAccount(Base, TimestampMixin):
    __tablename__ = "oauth_accounts"

    id:               Mapped[int] = mapped_column(primary_key=True)
    user_id:          Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    provider:         Mapped[str] = mapped_column(String(32))         # "google", "github"
    provider_user_id: Mapped[str] = mapped_column(String(255))        # ID chez le provider
    access_token:     Mapped[str] = mapped_column(Text)

    user: Mapped["User"] = relationship(back_populates="oauth_accounts")

    __table_args__ = (
        UniqueConstraint("provider", "provider_user_id", name="uq_oauth_provider_user"),
    )
```

### Configuration des providers

```python
# core/oauth.py
OAUTH_PROVIDERS: dict[str, dict] = {
    "google": {
        "authorize_url": "https://accounts.google.com/o/oauth2/auth",
        "token_url":     "https://oauth2.googleapis.com/token",
        "userinfo_url":  "https://www.googleapis.com/oauth2/v3/userinfo",
        "scopes":        ["openid", "email", "profile"],
    },
    "github": {
        "authorize_url": "https://github.com/login/oauth/authorize",
        "token_url":     "https://github.com/login/oauth/access_token",
        "userinfo_url":  "https://api.github.com/user",
        "scopes":        ["user:email"],
    },
}
```

### Protection CSRF — state signé HMAC

```python
# core/oauth.py
import hmac, hashlib, secrets

def generate_oauth_state() -> str:
    """State = nonce + signature HMAC. Aucun stockage serveur nécessaire."""
    nonce = secrets.token_urlsafe(16)
    sig = hmac.new(
        settings.oauth_state_secret.encode(), nonce.encode(), hashlib.sha256
    ).hexdigest()
    return f"{nonce}.{sig}"

def verify_oauth_state(state: str) -> bool:
    try:
        nonce, sig = state.rsplit(".", 1)
        expected = hmac.new(
            settings.oauth_state_secret.encode(), nonce.encode(), hashlib.sha256
        ).hexdigest()
        return hmac.compare_digest(sig, expected)
    except ValueError:
        return False
```

### Routes OAuth

```python
# api/auth.py
from authlib.integrations.httpx_client import AsyncOAuth2Client
from core.oauth import OAUTH_PROVIDERS, generate_oauth_state, verify_oauth_state

@router.get("/{provider}/login")
async def oauth_login(provider: str) -> RedirectResponse:
    """Redirige vers le provider OAuth. Génère un state CSRF signé."""
    if provider not in OAUTH_PROVIDERS:
        raise HTTPException(status_code=404, detail="Provider not supported")

    cfg = OAUTH_PROVIDERS[provider]
    state = generate_oauth_state()

    async with AsyncOAuth2Client(
        client_id=settings.oauth_client_id(provider),
        redirect_uri=settings.oauth_redirect_uri(provider),
        scope=" ".join(cfg["scopes"]),
    ) as client:
        url, _ = client.create_authorization_url(cfg["authorize_url"], state=state)

    return RedirectResponse(url)


@router.get("/{provider}/callback", response_model=TokenResponse)
async def oauth_callback(
    provider: str,
    code: str,
    state: str,
    db: AsyncSession = Depends(get_db),
) -> TokenResponse:
    """Reçoit le code, l'échange contre un token, trouve ou crée l'utilisateur."""
    if not verify_oauth_state(state):
        raise HTTPException(status_code=400, detail="Invalid OAuth state — possible CSRF")

    cfg = OAUTH_PROVIDERS[provider]

    async with AsyncOAuth2Client(
        client_id=settings.oauth_client_id(provider),
        client_secret=settings.oauth_client_secret(provider),
        redirect_uri=settings.oauth_redirect_uri(provider),
    ) as client:
        token_data = await client.fetch_token(cfg["token_url"], code=code)
        client.token = token_data
        resp = await client.get(cfg["userinfo_url"])
        resp.raise_for_status()
        userinfo = resp.json()

    user = await oauth_service.find_or_create(db, provider, userinfo, token_data["access_token"])

    return TokenResponse(
        access_token=create_access_token(str(user.id)),
        refresh_token=create_refresh_token(str(user.id)),
        token_type="bearer",
    )
```

### Service find_or_create

```python
# services/oauth_service.py
async def find_or_create(
    db: AsyncSession,
    provider: str,
    userinfo: dict,
    access_token: str,
) -> User:
    """
    Trouve l'utilisateur lié à ce compte social, ou crée le compte si premier login.
    Lève HTTPException 400 si les données userinfo sont incomplètes.
    """
    provider_user_id = str(userinfo.get("sub") or userinfo.get("id"))
    email = userinfo.get("email")
    if not provider_user_id or not email:
        raise HTTPException(status_code=400, detail="Incomplete user info from provider")

    # 1. Compte OAuth existant → retourner l'utilisateur lié
    oauth_account = await db.scalar(
        select(OAuthAccount).where(
            OAuthAccount.provider == provider,
            OAuthAccount.provider_user_id == provider_user_id,
        )
    )
    if oauth_account:
        oauth_account.access_token = access_token
        await db.commit()
        return await db.get(User, oauth_account.user_id)

    # 2. Email déjà connu → lier le compte social à l'utilisateur existant
    user = await db.scalar(select(User).where(User.email == email))
    if not user:
        # 3. Nouvel utilisateur — pas de mot de passe (login social uniquement)
        user = User(email=email, name=userinfo.get("name", email), is_active=True)
        db.add(user)
        await db.flush()

    oauth_account = OAuthAccount(
        user_id=user.id,
        provider=provider,
        provider_user_id=provider_user_id,
        access_token=access_token,
    )
    db.add(oauth_account)
    await db.commit()
    return user
```

### Settings requises (OAuth)

```python
class Settings(BaseSettings):
    # JWT (inchangé)
    jwt_secret: str
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60
    jwt_refresh_days: int = 30

    # OAuth CSRF
    oauth_state_secret: str           # min 32 caractères, distinct de jwt_secret

    # Credentials par provider (préfixe dynamique)
    google_client_id: str = ""
    google_client_secret: str = ""
    github_client_id: str = ""
    github_client_secret: str = ""

    # URL de base pour construire les redirect_uri
    api_base_url: str = "http://localhost:8000"

    def oauth_client_id(self, provider: str) -> str:
        return getattr(self, f"{provider}_client_id")

    def oauth_client_secret(self, provider: str) -> str:
        return getattr(self, f"{provider}_client_secret")

    def oauth_redirect_uri(self, provider: str) -> str:
        return f"{self.api_base_url}/auth/{provider}/callback"
```

## Settings requises (résumé)

```python
class Settings(BaseSettings):
    jwt_secret: str              # min 32 caractères
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60
    jwt_refresh_days: int = 30
    oauth_state_secret: str      # min 32 caractères, distinct de jwt_secret
    # + credentials par provider (voir section OAuth ci-dessus)
```

## Logout — invalidation du refresh token

Sans invalidation, un refresh token volé reste valide jusqu'à son expiration.

```python
# models/user.py — colonne pour stocker le token valide courant
class User(Base):
    refresh_token_hash: Mapped[str | None] = mapped_column(nullable=True)
```

```python
# services/auth_service.py
import hashlib

def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()

async def save_refresh_token(db: AsyncSession, user_id: int, token: str) -> None:
    await db.execute(
        update(User).where(User.id == user_id).values(refresh_token_hash=_hash_token(token))
    )
    await db.commit()

async def invalidate_refresh_token(db: AsyncSession, user_id: int) -> None:
    await db.execute(
        update(User).where(User.id == user_id).values(refresh_token_hash=None)
    )
    await db.commit()

async def verify_refresh_token_valid(db: AsyncSession, user_id: int, token: str) -> bool:
    user = await db.get(User, user_id)
    if not user or not user.refresh_token_hash:
        return False
    return hmac.compare_digest(user.refresh_token_hash, _hash_token(token))
```

```python
# api/auth.py
@router.post("/logout", status_code=204)
async def logout(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await auth_service.invalidate_refresh_token(db, current_user.id)
```

Appeler `save_refresh_token()` à chaque `/login` et `/refresh`. Le `/refresh` vérifie `verify_refresh_token_valid()` avant d'émettre un nouveau token.

## Règles de sécurité

- Ne jamais stocker le mot de passe en clair — toujours `hash_password()` avant `db.add()`
- Ne jamais retourner le hash de mot de passe dans les réponses API
- Tokens avec expiration courte (`access`) + longue (`refresh`) — ne pas mélanger les types
- Sur logout : invalider le refresh token en base (pattern ci-dessus)
- Comparer les mots de passe avec `verify_password()` uniquement — jamais `==`
