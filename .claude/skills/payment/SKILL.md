---
name: payment
description: Intégration Stripe pour paiements Python. Payment intents, webhooks avec vérification de signature, idempotence, remboursements, gestion d'erreurs.
---

# Conventions Payment — Stripe

## Dépendances

```toml
stripe = "^10.0"
```

## Configuration

```python
# core/settings.py
class Settings(BaseSettings):
    stripe_secret_key: str          # sk_test_... ou sk_live_...
    stripe_webhook_secret: str      # whsec_...
    stripe_currency: str = "eur"
```

```python
# services/payment_service.py
import stripe
from core.settings import settings

stripe.api_key = settings.stripe_secret_key
```

## Flux Payment Intent

```python
# services/payment_service.py

async def create_payment_intent(
    amount_cents: int,
    order_id: int,
    idempotency_key: str,
) -> stripe.PaymentIntent:
    """
    Crée un payment intent Stripe.
    amount_cents : montant en centimes (ex: 1999 pour 19.99€)
    idempotency_key : clé unique par tentative (ex: f"order-{order_id}-{attempt}")
    """
    return stripe.PaymentIntent.create(
        amount=amount_cents,
        currency=settings.stripe_currency,
        metadata={"order_id": str(order_id)},
        idempotency_key=idempotency_key,
    )

async def confirm_payment_intent(payment_intent_id: str) -> stripe.PaymentIntent:
    return stripe.PaymentIntent.retrieve(payment_intent_id)
```

## Idempotence — règle absolue

Toute opération de paiement doit avoir une `idempotency_key` unique et stable :

```python
# La clé doit être déterministe : même input → même clé
# Cela permet de réessayer sans créer de double débit

idempotency_key = f"order-{order_id}-attempt-{attempt_number}"

intent = stripe.PaymentIntent.create(
    amount=amount_cents,
    currency="eur",
    idempotency_key=idempotency_key,
)
```

## Webhooks — traitement des événements

```python
# api/webhooks.py
router = APIRouter(prefix="/webhooks", tags=["webhooks"])

@router.post("/stripe", status_code=200)
async def stripe_webhook(
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """
    Reçoit les événements Stripe. Vérifie la signature avant tout traitement.
    Configuré dans le dashboard Stripe : endpoint → sélectionner les événements.
    """
    payload = await request.body()
    sig_header = request.headers.get("stripe-signature")

    try:
        event = stripe.Webhook.construct_event(
            payload, sig_header, settings.stripe_webhook_secret
        )
    except stripe.error.SignatureVerificationError:
        raise HTTPException(status_code=400, detail="Invalid signature")

    await _handle_event(db, event)
    return {"received": True}

async def _handle_event(db: AsyncSession, event: stripe.Event) -> None:
    match event["type"]:
        case "payment_intent.succeeded":
            await _on_payment_succeeded(db, event["data"]["object"])
        case "payment_intent.payment_failed":
            await _on_payment_failed(db, event["data"]["object"])
        case "charge.refunded":
            await _on_refund(db, event["data"]["object"])
        case _:
            pass  # événements non gérés ignorés silencieusement

async def _on_payment_succeeded(db: AsyncSession, intent: dict) -> None:
    order_id = int(intent["metadata"]["order_id"])
    async with db.begin():
        order = await db.get(Order, order_id, with_for_update=True)
        if not order or order.status != OrderStatus.PENDING:
            return  # idempotence : déjà traité
        order.status = OrderStatus.PAID
        order.stripe_payment_intent_id = intent["id"]
```

## Remboursements

```python
async def create_refund(
    payment_intent_id: str,
    amount_cents: int | None = None,  # None = remboursement total
    reason: str = "requested_by_customer",
) -> stripe.Refund:
    """
    Crée un remboursement.
    reason : requested_by_customer | fraudulent | duplicate
    """
    params = {
        "payment_intent": payment_intent_id,
        "reason": reason,
    }
    if amount_cents:
        params["amount"] = amount_cents  # remboursement partiel

    return stripe.Refund.create(**params)
```

## Gestion des erreurs Stripe

```python
async def safe_create_intent(amount_cents: int, order_id: int) -> stripe.PaymentIntent:
    try:
        return await create_payment_intent(amount_cents, order_id, f"order-{order_id}")
    except stripe.error.CardError as e:
        # Carte refusée — erreur côté utilisateur
        raise HTTPException(status_code=402, detail=e.user_message)
    except stripe.error.RateLimitError:
        raise HTTPException(status_code=429, detail="Payment service temporarily unavailable")
    except stripe.error.InvalidRequestError as e:
        logger.error("Stripe invalid request", extra={"error": str(e), "order_id": order_id})
        raise HTTPException(status_code=400, detail="Invalid payment request")
    except stripe.error.StripeError as e:
        logger.error("Stripe error", exc_info=e, extra={"order_id": order_id})
        raise HTTPException(status_code=502, detail="Payment provider error")
```

## Tests

```python
# Utiliser les clés test Stripe (sk_test_...)
# Cartes de test : 4242424242424242 (succès), 4000000000000002 (refusée)

async def test_payment_intent_created(client: AsyncClient, auth_headers: dict):
    with patch("stripe.PaymentIntent.create") as mock_create:
        mock_create.return_value = {"id": "pi_test_123", "client_secret": "secret"}
        response = await client.post("/payments/intent", json={"order_id": 1}, headers=auth_headers)
        assert response.status_code == 201
        mock_create.assert_called_once()

async def test_webhook_invalid_signature(client: AsyncClient):
    response = await client.post("/webhooks/stripe", content=b"payload", headers={"stripe-signature": "bad"})
    assert response.status_code == 400
```

## Règles de sécurité

- **Jamais** de clé secrète Stripe côté frontend — uniquement le `client_secret` du payment intent
- Toujours vérifier la signature webhook avant de traiter l'événement
- Idempotence sur tous les handlers webhook (un événement peut arriver plusieurs fois)
- Montants toujours en **centimes** (entiers) — jamais de float pour l'argent
- Logger les erreurs Stripe avec `order_id` mais sans données de carte
