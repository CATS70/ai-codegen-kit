# Blueprint : Auth avancée

## Cas d'usage
Authentification complète pour applications SaaS : email/password, SSO OAuth2 (Google, GitHub), gestion des rôles (RBAC) et rotation des refresh tokens. À utiliser comme socle de sécurité pour tout projet nécessitant une gestion d'identité robuste.

## Composants

- Authentification JWT + refresh tokens             ← skill associé : `auth`
- API REST endpoints auth                           ← skill associé : `fastapi`
- Modèles et persistance utilisateurs/rôles         ← skill associé : `sqlalchemy`
- Validation des données d'entrée                   ← skill associé : `pydantic`
- Règles OWASP transversales                        ← skill associé : `security`
- Tests unitaires et d'intégration                  ← skill associé : `testing`
- Conteneurisation                                  ← skill associé : `docker`

## Contraintes

- Les mots de passe sont hashés avec bcrypt (cost factor ≥ 12) — jamais en clair ni MD5/SHA1
- Les refresh tokens sont à usage unique : chaque refresh génère une nouvelle paire (rotation)
- Les refresh tokens révoqués sont stockés en base jusqu'à leur expiration naturelle
- Le RBAC est vérifié via des dépendances FastAPI injectées (`require_role`, `require_permission`)
- L'OAuth2 (Google, GitHub) ne crée jamais de compte dupliqué : lookup par email d'abord
- Les tokens OAuth2 externes ne sont jamais persistés — seul l'`external_id` du provider est stocké
- Toute tentative de login échoué génère le même message d'erreur (pas d'énumération d'emails)
- Configuration exclusivement via `core/settings.py` (Pydantic BaseSettings)

## Flux : login email/password

1. Réception des credentials (email + password)
2. Lookup utilisateur par email (résultat identique si inexistant — anti-énumération)
3. Vérification bcrypt du mot de passe
4. Génération access token (15 min) + refresh token (30 jours)
5. Stockage du refresh token hashé en base
6. Retour des deux tokens au client

## Flux : refresh token

1. Réception du refresh token
2. Lookup en base (token hashé)
3. Vérification expiration + non-révocation
4. Révoquer l'ancien token (invalider en base)
5. Générer une nouvelle paire access + refresh
6. Retourner la nouvelle paire

## Flux : OAuth2 (Google / GitHub)

1. Redirect vers le provider avec `state` aléatoire (CSRF)
2. Réception du callback avec `code`
3. Vérification du `state`
4. Échange du `code` contre un token provider
5. Récupération du profil utilisateur (email, `external_id`)
6. Lookup ou création du compte local (jamais de doublon par email)
7. Génération de la paire JWT interne

## Structure de fichiers recommandée

```
backend/
├── app/
│   ├── main.py
│   ├── core/
│   │   ├── settings.py           # JWT_SECRET, ACCESS_TOKEN_TTL, REFRESH_TOKEN_TTL
│   │   │                         # GOOGLE_CLIENT_ID/SECRET, GITHUB_CLIENT_ID/SECRET
│   │   └── logging.py
│   ├── api/
│   │   ├── auth.py               # POST /login, /refresh, /logout, /register
│   │   └── oauth.py              # GET /oauth/{provider}/redirect, /oauth/{provider}/callback
│   ├── models/
│   │   ├── user.py               # id, email, password_hash, is_active, created_at
│   │   ├── role.py               # id, name, permissions (JSON)
│   │   ├── user_role.py          # many-to-many user ↔ role
│   │   └── refresh_token.py      # token_hash, user_id, expires_at, revoked_at
│   ├── schemas/
│   │   ├── auth.py               # LoginRequest, TokenResponse, RefreshRequest
│   │   └── user.py               # UserCreate, UserRead
│   ├── services/
│   │   ├── auth_service.py       # hash, verify, generate tokens, rotation
│   │   ├── oauth_service.py      # échange code → profil, upsert utilisateur
│   │   └── rbac_service.py       # vérification rôles / permissions
│   ├── dependencies/
│   │   ├── auth.py               # get_current_user, require_role("admin"), require_permission("read:reports")
│   │   └── oauth.py              # vérification state CSRF
│   └── db.py
├── migrations/
└── tests/
    ├── test_login.py             # credentials valides, invalides, compte inexistant
    ├── test_refresh.py           # rotation, token révoqué, token expiré
    ├── test_oauth.py             # mock provider, compte existant, doublon email
    └── test_rbac.py              # accès autorisé, refusé, rôle manquant
```
