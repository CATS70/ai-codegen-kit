# Blueprint : SaaS Multi-tenant

## Cas d'usage
Application SaaS avec gestion d'organisations, isolation stricte des données entre tenants, rôles par organisation et onboarding d'équipes. Adapté à tout produit B2B où plusieurs clients partagent la même infrastructure avec des données cloisonnées.

## Composants

- Authentification et autorisation               ← skill associé : `auth`
- API REST organisations / membres / invitations ← skill associé : `fastapi`
- Conception schéma et isolation des données     ← skill associé : `database-design`
- Modèles et accès base de données               ← skill associé : `sqlalchemy`
- Validation des données                         ← skill associé : `pydantic`
- Frontend espace organisation                   ← skill associé : `nextjs`
- Tests isolation et permissions                 ← skill associé : `testing`
- Règles OWASP transversales                     ← skill associé : `security`
- Conteneurisation                               ← skill associé : `docker`

## Contraintes

- **Isolation par `tenant_id`** : toute table de données métier porte une colonne `tenant_id` — jamais de requête sans filtre tenant
- La dépendance FastAPI `get_current_tenant` est obligatoire sur toutes les routes métier — aucune route ne passe outre
- Un utilisateur peut appartenir à plusieurs organisations avec des rôles différents (`OWNER`, `ADMIN`, `MEMBER`)
- Les invitations sont envoyées par email avec un token temporaire (TTL configurable via env)
- Un token d'invitation ne peut être utilisé qu'une seule fois — révocation après acceptation
- Le `tenant_id` n'est jamais exposé dans les URLs publiques (utiliser `slug` ou `uuid`)
- Les endpoints super-admin (cross-tenant) sont sur un router séparé avec middleware dédié
- Configuration exclusivement via `core/settings.py` (Pydantic BaseSettings)

## Flux : onboarding d'une organisation

1. Utilisateur crée un compte (ou se connecte)
2. Crée une organisation → devient automatiquement `OWNER`
3. Invite des membres par email → token d'invitation généré
4. Le membre reçoit l'email, clique sur le lien
5. Si pas de compte → inscription + acceptation automatique
6. Si compte existant → acceptation de l'invitation
7. Création du `Membership` (user_id, org_id, role=MEMBER)

## Flux : requête métier

1. Requête HTTP avec JWT
2. Dépendance `get_current_user` → user
3. Dépendance `get_current_tenant(org_slug)` → vérifie membership + retourne org
4. Dépendance `require_org_role("ADMIN")` si besoin
5. Service métier appelé avec `tenant_id` explicite
6. Toutes les requêtes SQL filtrées sur `tenant_id`

## Structure de fichiers recommandée

```
backend/
├── app/
│   ├── main.py
│   ├── core/
│   │   ├── settings.py           # INVITATION_TTL_HOURS, SMTP_*, JWT_SECRET (env)
│   │   └── logging.py
│   ├── api/
│   │   ├── auth.py               # login, register, refresh
│   │   ├── organizations.py      # POST /orgs, GET /orgs (mes orgs)
│   │   ├── members.py            # GET/DELETE /orgs/{slug}/members
│   │   ├── invitations.py        # POST /orgs/{slug}/invitations, POST /invitations/{token}/accept
│   │   └── admin/
│   │       └── tenants.py        # super-admin uniquement (cross-tenant)
│   ├── domain/
│   │   └── enums/
│   │       ├── org_role.py        # OWNER, ADMIN, MEMBER
│   │       └── invitation_status.py # PENDING, ACCEPTED, EXPIRED, REVOKED
│   ├── models/
│   │   ├── user.py               # id, email, password_hash, is_active
│   │   ├── organization.py       # id, slug, name, created_at
│   │   ├── membership.py         # user_id, org_id, role, joined_at
│   │   └── invitation.py         # org_id, email, token_hash, role, expires_at, status
│   ├── schemas/
│   │   ├── organization.py       # OrgCreate, OrgRead
│   │   ├── membership.py         # MemberRead, RoleUpdate
│   │   └── invitation.py         # InvitationCreate, InvitationAccept
│   ├── repositories/
│   │   ├── base.py               # TenantRepository[T] — filtre org_id automatique
│   │   └── project_repository.py # exemple : étend TenantRepository[Project]
│   ├── services/
│   │   ├── auth_service.py
│   │   ├── org_service.py        # CRUD orgs, vérif slug unique
│   │   ├── membership_service.py # ajout/retrait membres, changement rôle
│   │   └── invitation_service.py # génération token, envoi email, acceptation, expiration
│   ├── dependencies/
│   │   ├── auth.py               # get_current_user
│   │   └── tenant.py             # get_current_tenant, require_org_role
│   └── db.py
├── migrations/
└── tests/
    ├── test_isolation.py          # un tenant ne voit pas les données d'un autre
    ├── test_membership.py         # rôles, accès autorisé/refusé
    ├── test_invitation.py         # token valide, expiré, déjà utilisé
    └── test_onboarding.py         # flux complet création org + invitation + acceptation

frontend/
├── app/
│   ├── page.tsx                   # liste des organisations
│   ├── orgs/
│   │   └── [slug]/
│   │       ├── page.tsx           # dashboard organisation
│   │       ├── members/
│   │       │   └── page.tsx       # gestion membres
│   │       └── settings/
│   │           └── page.tsx       # paramètres organisation
│   └── invitations/
│       └── [token]/
│           └── page.tsx           # acceptation invitation
├── components/
│   ├── OrgSwitcher.tsx            # changement d'organisation actuelle
│   ├── MemberList.tsx
│   └── InviteForm.tsx
└── lib/
    └── api.ts
```
