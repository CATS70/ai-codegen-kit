---
name: notifications
description: Système de notifications multi-canal pour FastAPI. Email (SMTP), push (FCM), in-app, préférences utilisateur, idempotence, retry avec backoff exponentiel.
---

# Conventions Notifications

## Dépendances

```toml
# pyproject.toml
aiosmtplib = "^3.0"       # SMTP async
httpx = "^0.27"            # appels FCM REST API
jinja2 = "^3.1"            # templates email HTML
```

## Principe fondamental

Toute notification transite par un service d'orchestration — jamais d'envoi direct depuis une route API.

```
route → notification_service.enqueue() → BackgroundTask → provider
```

L'envoi est toujours async et non-bloquant pour la requête HTTP appelante.

## Modèles

```python
# models/notification.py
class NotificationChannel(StrEnum):
    EMAIL  = "email"
    PUSH   = "push"
    IN_APP = "in_app"

class NotificationStatus(StrEnum):
    PENDING = "pending"
    SENT    = "sent"
    FAILED  = "failed"
    SKIPPED = "skipped"

class Notification(Base):
    __tablename__ = "notifications"

    id:               Mapped[int]                  = mapped_column(primary_key=True)
    user_id:          Mapped[int]                  = mapped_column(ForeignKey("users.id"), index=True)
    channel:          Mapped[NotificationChannel]
    type:             Mapped[str]                  = mapped_column(String(64))
    payload:          Mapped[dict]                 = mapped_column(JSON)
    status:           Mapped[NotificationStatus]   = mapped_column(default=NotificationStatus.PENDING)
    idempotency_key:  Mapped[str]                  = mapped_column(String(128), unique=True)
    attempt_count:    Mapped[int]                  = mapped_column(default=0)
    error_message:    Mapped[str | None]
    sent_at:          Mapped[datetime | None]
    created_at:       Mapped[datetime]             = mapped_column(default=func.now())

# models/notification_preference.py
class NotificationPreference(Base):
    __tablename__ = "notification_preferences"

    user_id:  Mapped[int] = mapped_column(ForeignKey("users.id"), primary_key=True)
    channel:  Mapped[NotificationChannel]          = mapped_column(primary_key=True)
    type:     Mapped[str] = mapped_column(String(64), primary_key=True)
    enabled:  Mapped[bool] = mapped_column(default=True)
```

## Idempotence — règle absolue

Chaque événement métier produit un `idempotency_key` déterministe. Si la notification existe déjà, on skip silencieusement.

```python
# services/notification_service.py
import hashlib

def _idempotency_key(user_id: int, notification_type: str, context_id: int) -> str:
    raw = f"{user_id}:{notification_type}:{context_id}"
    return hashlib.sha256(raw.encode()).hexdigest()[:64]
```

## NotificationService — orchestration

```python
# services/notification_service.py
class NotificationService:

    async def enqueue(
        self,
        db: AsyncSession,
        background_tasks: BackgroundTasks,
        user_id: int,
        channel: NotificationChannel,
        notification_type: str,
        payload: dict,
        idempotency_key: str,
    ) -> None:
        # 1. Vérifier idempotence
        existing = await db.scalar(
            select(Notification).where(Notification.idempotency_key == idempotency_key)
        )
        if existing:
            return

        # 2. Vérifier préférences utilisateur
        pref = await db.scalar(
            select(NotificationPreference).where(
                NotificationPreference.user_id == user_id,
                NotificationPreference.channel == channel,
                NotificationPreference.type == notification_type,
            )
        )
        if pref and not pref.enabled:
            notification = Notification(
                user_id=user_id, channel=channel, type=notification_type,
                payload=payload, idempotency_key=idempotency_key,
                status=NotificationStatus.SKIPPED,
            )
            db.add(notification)
            await db.commit()
            return

        # 3. Persister en PENDING et déléguer à un background task
        notification = Notification(
            user_id=user_id, channel=channel, type=notification_type,
            payload=payload, idempotency_key=idempotency_key,
        )
        db.add(notification)
        await db.commit()
        await db.refresh(notification)

        background_tasks.add_task(self._dispatch, notification.id)

    async def _dispatch(self, notification_id: int) -> None:
        """Récupère la notification et tente l'envoi avec retry."""
        async with async_session_factory() as db:
            notification = await db.get(Notification, notification_id)
            await self._send_with_retry(db, notification)
```

## Retry avec backoff exponentiel

```python
    RETRY_DELAYS = [60, 300, 1800]  # secondes : 1 min, 5 min, 30 min

    async def _send_with_retry(self, db: AsyncSession, notification: Notification) -> None:
        provider = self._get_provider(notification.channel)

        for attempt, delay in enumerate(self.RETRY_DELAYS):
            try:
                await provider.send(notification)
                notification.status = NotificationStatus.SENT
                notification.sent_at = datetime.now(timezone.utc)
                notification.attempt_count = attempt + 1
                await db.commit()
                return
            except Exception as e:
                notification.attempt_count = attempt + 1
                notification.error_message = str(e)
                if attempt < len(self.RETRY_DELAYS) - 1:
                    await asyncio.sleep(delay)

        notification.status = NotificationStatus.FAILED
        await db.commit()
        logger.error("Notification %d failed after %d attempts", notification.id, len(self.RETRY_DELAYS))
```

## Provider email (SMTP async)

```python
# services/providers/email_provider.py
import aiosmtplib
from jinja2 import Environment, FileSystemLoader

jinja_env = Environment(loader=FileSystemLoader("templates/emails"))

class EmailProvider:

    async def send(self, notification: Notification) -> None:
        template = jinja_env.get_template(f"{notification.type}.html")
        html_content = template.render(**notification.payload)

        message = MIMEMultipart("alternative")
        message["From"]    = settings.smtp_from
        message["To"]      = notification.payload["email"]
        message["Subject"] = notification.payload.get("subject", "")
        message.attach(MIMEText(html_content, "html"))

        await aiosmtplib.send(
            message,
            hostname=settings.smtp_host,
            port=settings.smtp_port,
            username=settings.smtp_user,
            password=settings.smtp_password,
            use_tls=True,
        )
```

## Provider push (FCM)

```python
# services/providers/push_provider.py
import httpx

FCM_ENDPOINT = "https://fcm.googleapis.com/v1/projects/{project}/messages:send"

class PushProvider:

    async def send(self, notification: Notification) -> None:
        token = notification.payload.get("device_token")
        if not token:
            return

        async with httpx.AsyncClient() as client:
            response = await client.post(
                FCM_ENDPOINT.format(project=settings.fcm_project_id),
                headers={"Authorization": f"Bearer {settings.fcm_api_key}"},
                json={
                    "message": {
                        "token": token,
                        "notification": {
                            "title": notification.payload["title"],
                            "body":  notification.payload["body"],
                        },
                    }
                },
                timeout=10,
            )

        if response.status_code == 404:
            # Token expiré ou invalide : supprimer pour éviter les envois futurs
            await self._revoke_push_token(token)
            raise ValueError("Push token invalid, revoked")

        response.raise_for_status()
```

## Provider in-app

```python
# services/providers/inapp_provider.py
class InAppProvider:

    async def send(self, notification: Notification) -> None:
        # Déjà persisté en base via Notification — rien à faire d'autre
        # La lecture se fait via GET /notifications
        pass
```

## Routes API

```python
# api/notifications.py
router = APIRouter(prefix="/notifications", tags=["notifications"])

@router.get("/", response_model=PaginatedResponse[NotificationRead])
async def list_notifications(
    pagination: PaginationParams = Depends(),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Retourne les notifications in-app non lues de l'utilisateur."""
    ...

@router.patch("/{notification_id}/read", status_code=204)
async def mark_as_read(
    notification_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Marque une notification in-app comme lue."""
    ...

# api/preferences.py
@router.get("/me/notification-preferences", response_model=list[PreferenceRead])
async def get_preferences(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Retourne les préférences de notification de l'utilisateur."""
    ...

@router.patch("/me/notification-preferences", response_model=list[PreferenceRead])
async def update_preferences(
    data: list[PreferenceUpdate],
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Met à jour les préférences de notification."""
    ...
```

## Usage depuis un service métier

```python
# services/order_service.py
async def confirm_order(
    db: AsyncSession,
    background_tasks: BackgroundTasks,
    order: Order,
) -> None:
    # ... logique métier ...

    await notification_service.enqueue(
        db=db,
        background_tasks=background_tasks,
        user_id=order.user_id,
        channel=NotificationChannel.EMAIL,
        notification_type="order_confirmed",
        payload={"email": order.user.email, "order_id": order.id, "subject": "Commande confirmée"},
        idempotency_key=_idempotency_key(order.user_id, "order_confirmed", order.id),
    )
```

## Settings requises

```python
class Settings(BaseSettings):
    # SMTP
    smtp_host:     str
    smtp_port:     int = 587
    smtp_user:     str
    smtp_password: str
    smtp_from:     str

    # Push (FCM)
    fcm_project_id: str = ""
    fcm_api_key:    str = ""

    # Retry
    max_retry_attempts: int = 3
```

## Règles

- `idempotency_key` toujours déterministe depuis les données métier — jamais aléatoire
- Ne jamais envoyer de notification depuis une route directement — passer par `notification_service.enqueue()`
- Toujours vérifier les préférences avant d'envoyer, même si la préférence n'existe pas encore (défaut : `True`)
- Purger les push tokens invalides au premier échec FCM 404 — pas de retry sur un token mort
- Les templates email sont dans `templates/emails/{notification_type}.html`
