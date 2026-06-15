---
name: saas-multitenant
description: Isolation multi-tenant pour SaaS Python/FastAPI. Tenant_id sur toutes les tables, dépendances d'injection, RBAC par organisation, invitations, onboarding.
---

# Conventions SaaS Multi-tenant

## Principe d'isolation — règle absolue

Toute table de données métier porte une colonne `tenant_id`. Aucune requête SQL ne s'exécute sans filtre sur `tenant_id`. La dépendance `get_current_tenant` est obligatoire sur toutes les routes métier.

```
requête HTTP → get_current_user → get_current_tenant → service métier(tenant_id=org.id)
```

## Modèles

```python
# models/organization.py
class Organization(Base):
    __tablename__ = "organizations"

    id:         Mapped[int]      = mapped_column(primary_key=True)
    slug:       Mapped[str]      = mapped_column(String(64), unique=True, index=True)
    name:       Mapped[str]      = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(default=func.now())

# models/membership.py
class OrgRole(StrEnum):
    OWNER  = "owner"
    ADMIN  = "admin"
    MEMBER = "member"

class Membership(Base):
    __tablename__ = "memberships"

    user_id: Mapped[int]     = mapped_column(ForeignKey("users.id"), primary_key=True)
    org_id:  Mapped[int]     = mapped_column(ForeignKey("organizations.id"), primary_key=True)
    role:    Mapped[OrgRole] = mapped_column(default=OrgRole.MEMBER)
    joined_at: Mapped[datetime] = mapped_column(default=func.now())

# models/invitation.py
class InvitationStatus(StrEnum):
    PENDING  = "pending"
    ACCEPTED = "accepted"
    EXPIRED  = "expired"
    REVOKED  = "revoked"

class Invitation(Base):
    __tablename__ = "invitations"

    id:         Mapped[int]              = mapped_column(primary_key=True)
    org_id:     Mapped[int]              = mapped_column(ForeignKey("organizations.id"), index=True)
    email:      Mapped[str]              = mapped_column(String(255), index=True)
    role:       Mapped[OrgRole]          = mapped_column(default=OrgRole.MEMBER)
    token_hash: Mapped[str]              = mapped_column(String(128), unique=True)
    status:     Mapped[InvitationStatus] = mapped_column(default=InvitationStatus.PENDING)
    expires_at: Mapped[datetime]
    created_at: Mapped[datetime]         = mapped_column(default=func.now())
```

## Patron pour tables métier

Toute table de données appartenant à un tenant hérite de ce patron :

```python
# models/project.py  (exemple de ressource métier)
class Project(Base):
    __tablename__ = "projects"

    id:         Mapped[int] = mapped_column(primary_key=True)
    org_id:     Mapped[int] = mapped_column(ForeignKey("organizations.id"), index=True)  # tenant_id
    name:       Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(default=func.now())

    __table_args__ = (
        Index("ix_projects_org_id_name", "org_id", "name"),
    )
```

## Dépendances — get_current_tenant et require_org_role

```python
# dependencies/tenant.py
async def get_current_tenant(
    org_slug: str,                              # paramètre de path /orgs/{org_slug}/...
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> tuple[Organization, Membership]:
    """Vérifie que l'utilisateur est membre de l'organisation et retourne (org, membership)."""
    org = await db.scalar(
        select(Organization).where(Organization.slug == org_slug)
    )
    if not org:
        raise HTTPException(status_code=404, detail="Organization not found")

    membership = await db.scalar(
        select(Membership).where(
            Membership.user_id == current_user.id,
            Membership.org_id == org.id,
        )
    )
    if not membership:
        raise HTTPException(status_code=403, detail="Not a member of this organization")

    return org, membership


def require_org_role(*roles: OrgRole):
    """Fabrique de dépendance : vérifie le rôle dans l'organisation courante."""
    async def check(
        tenant: tuple[Organization, Membership] = Depends(get_current_tenant),
    ) -> tuple[Organization, Membership]:
        org, membership = tenant
        if membership.role not in roles:
            raise HTTPException(status_code=403, detail="Insufficient role in organization")
        return org, membership
    return check
```

## Routes — structure type

```python
# api/members.py
router = APIRouter(prefix="/orgs/{org_slug}", tags=["members"])

@router.get("/members", response_model=list[MemberRead])
async def list_members(
    tenant: tuple[Organization, Membership] = Depends(get_current_tenant),
    db: AsyncSession = Depends(get_db),
):
    """Retourne les membres de l'organisation."""
    org, _ = tenant
    return await membership_service.list_members(db, org.id)

@router.delete("/members/{user_id}", status_code=204)
async def remove_member(
    user_id: int,
    tenant: tuple[Organization, Membership] = Depends(require_org_role(OrgRole.OWNER, OrgRole.ADMIN)),
    db: AsyncSession = Depends(get_db),
):
    """Retire un membre. Réservé aux OWNER et ADMIN."""
    org, _ = tenant
    await membership_service.remove_member(db, org.id, user_id)
```

## TenantRepository — filtre automatique par org_id

Toute ressource métier multi-tenant doit étendre `TenantRepository`. Le filtre `org_id` est injecté une seule fois dans `_base_query` et s'applique automatiquement à toutes les méthodes. L'IA utilise les méthodes du repository — elle n'écrit jamais le filtre manuellement.

```python
# repositories/base.py
from typing import Generic, TypeVar, Type, Any
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import HTTPException

ModelT = TypeVar("ModelT")

class TenantRepository(Generic[ModelT]):
    """Base repository avec isolation tenant automatique.
    
    Toute requête passe par _base_query() qui filtre sur org_id.
    Ne jamais contourner cette méthode pour accéder aux données.
    """
    model: Type[ModelT]

    def __init__(self, db: AsyncSession, org_id: int) -> None:
        self.db = db
        self.org_id = org_id

    def _base_query(self):
        return select(self.model).where(self.model.org_id == self.org_id)

    async def list(self, limit: int = 50, offset: int = 0) -> list[ModelT]:
        result = await self.db.scalars(
            self._base_query()
            .order_by(self.model.created_at.desc())
            .limit(limit)
            .offset(offset)
        )
        return list(result)

    async def get_or_404(self, resource_id: int) -> ModelT:
        obj = await self.db.scalar(
            self._base_query().where(self.model.id == resource_id)
        )
        if not obj:
            raise HTTPException(status_code=404, detail=f"{self.model.__name__} not found")
        return obj

    async def create(self, data: dict[str, Any]) -> ModelT:
        obj = self.model(org_id=self.org_id, **data)
        self.db.add(obj)
        await self.db.commit()
        await self.db.refresh(obj)
        return obj

    async def delete(self, resource_id: int) -> None:
        obj = await self.get_or_404(resource_id)
        await self.db.delete(obj)
        await self.db.commit()
```

Usage — un repository concret par ressource :

```python
# repositories/project_repository.py
from .base import TenantRepository
from models.project import Project

class ProjectRepository(TenantRepository[Project]):
    model = Project

    async def find_by_name(self, name: str) -> Project | None:
        """Recherche dans le scope du tenant courant uniquement."""
        return await self.db.scalar(
            self._base_query().where(Project.name == name)
        )
```

Usage dans une route — l'instanciation passe `org.id`, le reste est automatique :

```python
# api/projects.py
@router.get("/projects", response_model=PaginatedResponse[ProjectRead])
async def list_projects(
    pagination: PaginationParams = Depends(),
    tenant: tuple[Organization, Membership] = Depends(get_current_tenant),
    db: AsyncSession = Depends(get_db),
):
    org, _ = tenant
    repo = ProjectRepository(db, org.id)
    return await repo.list(limit=pagination.limit, offset=pagination.offset)

@router.delete("/projects/{project_id}", status_code=204)
async def delete_project(
    project_id: int,
    tenant: tuple[Organization, Membership] = Depends(require_org_role(OrgRole.OWNER, OrgRole.ADMIN)),
    db: AsyncSession = Depends(get_db),
):
    org, _ = tenant
    repo = ProjectRepository(db, org.id)
    await repo.delete(project_id)  # lève 404 si hors du tenant
```

## Services — logique métier complexe

Pour la logique qui dépasse le CRUD (transactions multi-tables, appels externes), écrire un service qui reçoit le repository en paramètre :

```python
# services/project_service.py
async def archive_project_with_tasks(
    repo: ProjectRepository,
    task_repo: TaskRepository,
    project_id: int,
) -> Project:
    """Archive un projet et toutes ses tâches dans une transaction unique."""
    project = await repo.get_or_404(project_id)
    tasks = await task_repo.list_by_project(project_id)

    async with repo.db.begin():
        for task in tasks:
            task.status = TaskStatus.ARCHIVED
        project.status = ProjectStatus.ARCHIVED
    return project
```

Le `org_id` est toujours passé explicitement depuis la route — jamais lu depuis le contexte global.

## Invitations

```python
# services/invitation_service.py
import secrets
import hashlib

def _generate_token() -> tuple[str, str]:
    """Retourne (token_brut, token_hashé). Seul le hash est stocké en base."""
    raw = secrets.token_urlsafe(32)
    hashed = hashlib.sha256(raw.encode()).hexdigest()
    return raw, hashed

async def create_invitation(
    db: AsyncSession,
    org_id: int,
    email: str,
    role: OrgRole,
) -> tuple[Invitation, str]:
    # Vérifier que l'utilisateur n'est pas déjà membre
    user = await db.scalar(select(User).where(User.email == email))
    if user:
        membership = await db.scalar(
            select(Membership).where(Membership.user_id == user.id, Membership.org_id == org_id)
        )
        if membership:
            raise HTTPException(status_code=409, detail="User is already a member")

    # Révoquer les invitations PENDING existantes pour cet email dans cette org
    await db.execute(
        update(Invitation)
        .where(Invitation.org_id == org_id, Invitation.email == email, Invitation.status == InvitationStatus.PENDING)
        .values(status=InvitationStatus.REVOKED)
    )

    raw_token, token_hash = _generate_token()
    invitation = Invitation(
        org_id=org_id,
        email=email,
        role=role,
        token_hash=token_hash,
        expires_at=datetime.now(timezone.utc) + timedelta(hours=settings.invitation_ttl_hours),
    )
    db.add(invitation)
    await db.commit()
    return invitation, raw_token  # raw_token envoyé par email, jamais stocké


async def accept_invitation(db: AsyncSession, raw_token: str, user: User) -> Membership:
    token_hash = hashlib.sha256(raw_token.encode()).hexdigest()
    invitation = await db.scalar(
        select(Invitation).where(Invitation.token_hash == token_hash)
    )
    if not invitation:
        raise HTTPException(status_code=404, detail="Invitation not found")
    if invitation.status != InvitationStatus.PENDING:
        raise HTTPException(status_code=410, detail="Invitation already used or revoked")
    if invitation.expires_at < datetime.now(timezone.utc):
        invitation.status = InvitationStatus.EXPIRED
        await db.commit()
        raise HTTPException(status_code=410, detail="Invitation expired")

    invitation.status = InvitationStatus.ACCEPTED
    membership = Membership(user_id=user.id, org_id=invitation.org_id, role=invitation.role)
    db.add(membership)
    await db.commit()
    return membership
```

## Création d'organisation — flux onboarding

```python
# services/org_service.py
async def create_organization(db: AsyncSession, user: User, data: OrgCreate) -> Organization:
    # Vérifier unicité du slug
    existing = await db.scalar(select(Organization).where(Organization.slug == data.slug))
    if existing:
        raise HTTPException(status_code=409, detail="Slug already taken")

    org = Organization(slug=data.slug, name=data.name)
    db.add(org)
    await db.flush()  # obtenir org.id avant le commit

    # Le créateur devient OWNER automatiquement
    membership = Membership(user_id=user.id, org_id=org.id, role=OrgRole.OWNER)
    db.add(membership)
    await db.commit()
    await db.refresh(org)
    return org
```

## Ce qu'il ne faut jamais faire

```python
# INTERDIT — requête sans filtre tenant_id
projects = await db.scalars(select(Project))

# INTERDIT — org_id depuis une variable globale ou contexte implicite
current_org_id = request.state.org_id  # non

# INTERDIT — exposer l'org_id numérique dans les URLs
GET /orgs/42/projects   # non — utiliser le slug

# CORRECT
GET /orgs/my-startup/projects
```

## Settings requises

```python
class Settings(BaseSettings):
    invitation_ttl_hours: int = 72
```

## Règles

- Chaque service métier reçoit `org_id` en paramètre explicite — jamais via contexte global
- Le `slug` est la clé publique de l'organisation dans les URLs — `id` reste interne
- Un `OWNER` ne peut pas être retiré de son organisation (vérification dans `remove_member`)
- Le token d'invitation brut n'est jamais persisté — seul le hash SHA-256 est en base
- Les invitations expirées sont marquées `EXPIRED` à la première tentative d'acceptation (lazy expiration)
