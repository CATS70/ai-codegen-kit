---
name: mcp
description: Conventions FastMCP (framework tiers PrefectHQ, gofastmcp.com) pour serveurs MCP Python — composition, proxying, génération OpenAPI. Définition d'outils, ressources, auth, exposition d'APIs FastAPI via MCP, client Claude Code. Pour le SDK officiel Anthropic (contrôle protocole bas niveau), voir le skill mcp-sdk-2.0.
---

# Conventions MCP — FastMCP

> **Note** : `fastmcp` est un framework tiers (PrefectHQ/Jeremiah Lowin, gofastmcp.com), distinct du SDK officiel Anthropic (`mcp` sur PyPI). C'est le choix par défaut de ce kit pour sa productivité (moins de code, composition, proxying, génération d'outils depuis OpenAPI). Pour un contrôle bas niveau du protocole ou pour rester strictement sur l'outillage Anthropic, utiliser le skill `mcp-sdk-2.0`.

## Installation

```toml
fastmcp = "^3.0"
```

## Serveur MCP minimal

```python
# mcp_server.py
from fastmcp import FastMCP
from core.settings import settings

mcp = FastMCP(
    name=settings.app_name,
    version=settings.app_version,
)
```

## Définition d'outils

Les outils sont des fonctions async décorées. La docstring est lue par le modèle pour décider quand utiliser l'outil.

```python
from fastmcp import FastMCP
from pydantic import BaseModel

mcp = FastMCP("My API")

@mcp.tool()
async def search_products(query: str, limit: int = 10) -> list[dict]:
    """
    Recherche des produits par nom ou description.
    Retourne une liste de produits avec id, nom et prix.
    """
    products = await product_service.search(query, limit)
    return [{"id": p.id, "name": p.name, "price": float(p.price)} for p in products]

@mcp.tool()
async def create_order(user_id: int, product_id: int, quantity: int) -> dict:
    """
    Crée une commande pour un utilisateur.
    Retourne l'id de la commande créée et son statut initial.
    """
    order = await order_service.create(user_id=user_id, product_id=product_id, quantity=quantity)
    return {"order_id": order.id, "status": order.status}
```

## Ressources (données contextuelles)

Les ressources exposent des données statiques ou dynamiques lisibles par le modèle.

```python
@mcp.resource("config://app")
async def get_app_config() -> str:
    """Configuration publique de l'application."""
    return f"App: {settings.app_name} v{settings.app_version}\nEnvironment: {settings.env}"

@mcp.resource("schema://orders")
async def get_order_schema() -> str:
    """Schéma JSON des commandes pour guider la création."""
    return OrderCreate.model_json_schema().__str__()
```

## Exposition d'une API FastAPI existante via MCP

```python
# mcp_server.py — wrapper sur les services existants
from app.services import product_service, order_service, user_service
from app.db import async_session_factory

async def get_db_session():
    async with async_session_factory() as session:
        return session

@mcp.tool()
async def list_users(page: int = 1, size: int = 20) -> dict:
    """Liste les utilisateurs actifs avec pagination."""
    db = await get_db_session()
    users, total = await user_service.list_users(db, page=page, size=size)
    return {
        "items": [{"id": u.id, "email": u.email, "name": u.name} for u in users],
        "total": total,
        "page": page,
    }
```

## Sécurité des outils

```python
# Opérations destructives : exiger une confirmation explicite
@mcp.tool()
async def delete_user(user_id: int, confirm: bool = False) -> dict:
    """
    Supprime un utilisateur. confirm doit être True pour exécuter.
    Utiliser uniquement après confirmation explicite de l'utilisateur.
    """
    if not confirm:
        return {"status": "pending", "message": f"Confirmer la suppression de l'utilisateur {user_id} ?"}
    await user_service.delete(user_id)
    return {"status": "deleted", "user_id": user_id}

# Jamais d'opérations irréversibles sans garde
# Jamais de secrets dans les retours d'outils
# Valider les paramètres d'entrée avant toute opération
```

## Gestion des erreurs

Par défaut, une exception Python non interceptée dans un outil est convertie par fastmcp en un message générique côté client ("Error calling tool") — le modèle, et l'utilisateur derrière lui, n'ont rien d'exploitable. Deux leviers, à utiliser ensemble :

**Masquer les détails internes, mais logger avec un identifiant traçable**

```python
mcp = FastMCP(
    name=settings.app_name,
    version=settings.app_version,
    mask_error_details=True,   # aucune stack trace/détail interne ne fuite vers le client
)
```

```python
# core/errors.py
import logging
import uuid

logger = logging.getLogger(__name__)

def log_error(exc: Exception, **context) -> str:
    """Logge l'exception avec un error_id court, à inclure dans le ToolError renvoyé au modèle."""
    error_id = uuid.uuid4().hex[:8]
    logger.error("Tool error", exc_info=exc, extra={"error_id": error_id, **context})
    return error_id
```

**`ToolError` pour tout ce qui doit atteindre le modèle**

`mask_error_details=True` empêche une exception non interceptée de fuiter une stack trace — mais sans relève explicite en `ToolError`, l'appelant ne voit qu'un message générique inexploitable. Toujours intercepter et re-lever, jamais laisser fastmcp masquer silencieusement une panne réelle.

```python
from fastmcp.exceptions import ToolError
from app.core.errors import log_error

@mcp.tool()
async def search_products(query: str, limit: int = 10) -> list[dict]:
    """Recherche des produits par nom ou description."""
    if not query.strip():
        # Erreur de saisie — le modèle comprend directement, pas besoin de référence
        raise ToolError("Le paramètre query ne peut pas être vide.")

    try:
        products = await product_service.search(query, limit)
    except ProductServiceUnavailable as e:
        # Panne système, hors contrôle du modèle — la référence permet de retrouver le log
        error_id = log_error(e, query=query)
        raise ToolError(f"Service de recherche indisponible (réf. {error_id}).")

    return [{"id": p.id, "name": p.name, "price": float(p.price)} for p in products]
```

## Lancement du serveur

```python
# mcp_server.py
if __name__ == "__main__":
    mcp.run(transport="stdio")   # pour Claude Code (stdio)
    # ou mcp.run(transport="sse")  # pour accès réseau — port via FASTMCP_PORT (env), défaut 8000
    # NB : depuis fastmcp 3.0, port n'est plus un kwarg de run(). Pour fixer le port en code
    # plutôt qu'en env, utiliser mcp.run_http_async(transport="sse", port=8000).
```

## Configuration dans Claude Code

```json
// .claude/settings.json
{
  "mcpServers": {
    "my-api": {
      "command": "python",
      "args": ["mcp_server.py"],
      "env": {
        "DATABASE_URL": "${DATABASE_URL}",
        "ANTHROPIC_API_KEY": "${ANTHROPIC_API_KEY}"
      }
    }
  }
}
```

## Règles

- Docstring claire sur chaque outil — le modèle en dépend pour décider quand l'appeler
- Retours en types simples (dict, list, str) — pas d'objets SQLAlchemy
- Opérations destructives avec paramètre `confirm: bool = False`
- Jamais de secrets dans les retours d'outils
- Un serveur MCP par domaine métier (pas de serveur monolithique)
- Tester les outils unitairement avant intégration avec Claude Code
- `mask_error_details=True` sur le serveur — aucune stack trace ne doit fuiter vers le modèle
- Erreur inattendue (panne système, dépendance externe) → catch, logger avec un `error_id`, relever en `ToolError` incluant cette référence ; erreur de saisie → `ToolError` direct, sans référence
