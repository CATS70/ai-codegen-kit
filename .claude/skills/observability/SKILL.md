---
name: observability
description: Observabilité pour FastAPI Python. Logging structuré avec masquage de données sensibles, métriques Prometheus, health checks. Charger si volume high (>10k users simultanés).
---

# Conventions observabilité

## Quand charger ce skill

Charger uniquement si le volume est **high** (>10k users simultanés). Pour medium/low, le logging structuré suffit.

## Logging structuré

Configurer le logging une seule fois au démarrage. Masquer systématiquement les champs sensibles.

```python
# core/logging.py
import logging
import sys

_SENSITIVE_FIELDS = {"password", "password_hash", "token", "secret", "card_number", "cvv"}


class SensitiveDataFilter(logging.Filter):
    """Masque les champs sensibles dans les messages de log."""

    def filter(self, record: logging.LogRecord) -> bool:
        if isinstance(record.args, dict):
            record.args = {
                k: "***" if k in _SENSITIVE_FIELDS else v
                for k, v in record.args.items()
            }
        return True


def setup_logging(debug: bool = False) -> None:
    level = logging.DEBUG if debug else logging.INFO
    handler = logging.StreamHandler(sys.stdout)
    handler.addFilter(SensitiveDataFilter())

    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        handlers=[handler],
    )

    # Réduire le bruit des libs tierces
    logging.getLogger("sqlalchemy.engine").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
```

```python
# main.py
from app.core.logging import setup_logging
from app.core.settings import settings

setup_logging(debug=settings.debug)
app = FastAPI(...)
```

Usage dans les services :
```python
import logging

logger = logging.getLogger(__name__)

async def create_order(db: AsyncSession, data: OrderCreate) -> Order:
    logger.info("Creating order user_id=%s items=%d", data.user_id, len(data.items))
    # ...
    logger.info("Order created order_id=%s total=%s", order.id, order.total)
    return order
```

## Health check

Route `/health` obligatoire — vérifier la connectivité DB, pas seulement le process.

```python
# api/health.py
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
from app.db import get_db

router = APIRouter()


class HealthResponse(BaseModel):
    status: str
    database: str


@router.get("/health", response_model=HealthResponse)
async def health_check(db: AsyncSession = Depends(get_db)):
    try:
        await db.execute(text("SELECT 1"))
        db_status = "ok"
    except Exception:
        db_status = "error"

    return HealthResponse(
        status="ok" if db_status == "ok" else "degraded",
        database=db_status,
    )
```

## Métriques Prometheus

Installer `prometheus-fastapi-instrumentator` — zéro configuration pour les métriques HTTP standard.

```toml
# pyproject.toml
dependencies = [
    "prometheus-fastapi-instrumentator>=6.1",
]
```

```python
# main.py
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI(...)
Instrumentator().instrument(app).expose(app, endpoint="/metrics")
```

Métriques exposées automatiquement :
- `http_requests_total` — compteur par route, méthode, status
- `http_request_duration_seconds` — histogramme de latence
- `http_requests_in_progress` — requêtes en cours

## Métriques métier personnalisées

```python
# core/metrics.py
from prometheus_client import Counter, Histogram

orders_created = Counter(
    "orders_created_total",
    "Nombre de commandes créées",
    ["status"],
)

payment_duration = Histogram(
    "payment_processing_seconds",
    "Durée de traitement des paiements",
    buckets=[0.1, 0.5, 1.0, 2.0, 5.0],
)
```

```python
# services/order_service.py
from app.core.metrics import orders_created, payment_duration
import time

async def create_order(db: AsyncSession, data: OrderCreate) -> Order:
    # ...
    orders_created.labels(status="pending").inc()

    start = time.monotonic()
    await payment_service.create_intent(order)
    payment_duration.observe(time.monotonic() - start)

    return order
```

## docker-compose

```yaml
services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"
```

```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: api
    static_configs:
      - targets: ["backend:8000"]
    metrics_path: /metrics
```

## Middleware de logging des requêtes

```python
# main.py
import time
import logging

logger = logging.getLogger("api.access")

@app.middleware("http")
async def log_requests(request: Request, call_next):
    start = time.monotonic()
    response = await call_next(request)
    duration = time.monotonic() - start

    logger.info(
        "method=%s path=%s status=%d duration=%.3fs",
        request.method,
        request.url.path,
        response.status_code,
        duration,
    )
    return response
```

## Anti-patterns

```python
# ❌ Logger des données sensibles
logger.info("User login email=%s password=%s", email, password)

# ❌ print() en production — non capturé par les agrégateurs de logs
print("Order created")

# ❌ Health check sans vérification réelle
@app.get("/health")
async def health():
    return {"status": "ok"}  # ne détecte pas une DB hors service

# ✅ Logger le contexte utile sans données sensibles
logger.info("User login email=%s", email)
logger.info("Order created order_id=%s user_id=%s", order.id, user.id)
```
