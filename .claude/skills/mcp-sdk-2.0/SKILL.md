---
name: mcp-sdk-2.0
description: Conventions SDK MCP officiel Anthropic (package `mcp`, ligne v2.0, classe MCPServer) pour serveurs MCP Python. Contrôle protocole bas niveau, transports stdio/streamable-http/sse, gestion d'erreurs ToolError/MCPError. Alternative au framework tiers fastmcp — voir le skill mcp.
---

# Conventions MCP — SDK officiel Anthropic (v2.0)

> **Quand utiliser ce skill plutôt que `mcp`** : quand on veut rester strictement sur l'outillage Anthropic (`modelcontextprotocol/python-sdk`), ou qu'on a besoin d'un contrôle protocole bas niveau (transport custom, capacités non standard). Pour la productivité (composition de serveurs, proxying, génération d'outils depuis OpenAPI), préférer le skill `mcp` (framework tiers `fastmcp`).
>
> Le SDK officiel v2.0 (30/06/2026) a renommé sa classe interne `FastMCP` en `MCPServer` et refondu ses internes (pipeline dispatcher/runner). L'ancien import `from mcp.server.fastmcp import FastMCP` (v1.x) n'existe plus — utiliser `from mcp.server import MCPServer`. La branche v1.x reste en maintenance sécurité seule ; ne pas cibler de nouveau code dessus sauf contrainte explicite.

## Installation

```toml
mcp = { version = "^2.0", extras = ["cli"] }
```

L'extra `cli` active les commandes `mcp dev` (Inspector, développement) et `mcp run`. Sans lui, seul le runtime programmatique (`mcp.run(...)` dans le code) est disponible.

## Serveur MCP minimal

```python
# mcp_server.py
from mcp.server import MCPServer
from core.settings import settings

mcp = MCPServer(settings.app_name)
```

## Définition d'outils

Les outils sont des fonctions décorées. Le docstring est lu par le modèle pour décider quand utiliser l'outil ; les annotations de type suffisent à générer le schéma (pas de JSON Schema manuel).

```python
from mcp.server import MCPServer

mcp = MCPServer("My API")

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

Un outil qui fait de l'I/O (DB, appel réseau, fichier) doit être déclaré `async def` et `await` à l'intérieur — le SDK l'attend nativement. Un outil `def` synchrone fonctionne aussi (exécuté dans un thread séparé) mais réserver ce cas au calcul pur, sans I/O.

## Ressources (données contextuelles)

Les ressources exposent des données statiques ou dynamiques lisibles par le modèle, via un URI (éventuellement templaté).

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
from mcp.server import MCPServer
from app.services import product_service, order_service, user_service
from app.db import async_session_factory

mcp = MCPServer("My API")

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

## Gestion des erreurs dans les outils

Le SDK distingue deux familles d'erreurs — le critère de choix : *« un modèle plus intelligent aurait-il pu éviter cette erreur ? »*

- **Oui** → `ToolError` : erreur d'exécution/validation que le modèle peut corriger. Le message est retourné au modèle, qui peut réessayer avec de meilleures données.
- **Non** → `MCPError` : erreur au niveau protocole (requête invalide, service indisponible). Pas de message destiné au modèle ; l'appel échoue au niveau JSON-RPC.

Pour une `MCPError` (panne système, hors contrôle du modèle), un `message` générique ("Fournisseur catalogue indisponible") ne suffit pas : sans identifiant commun avec le log serveur, personne — ni l'humain derrière le client MCP, ni le support — ne peut retrouver la cause. Le champ `data` de `ErrorData` (JSON-RPC 2.0, valeur libre définie par le serveur) est fait pour ça.

```python
# core/errors.py
import logging
import uuid

logger = logging.getLogger(__name__)

def log_error(exc: Exception, **context) -> str:
    """Logge l'exception avec un error_id court, à inclure dans la MCPError renvoyée au client."""
    error_id = uuid.uuid4().hex[:8]
    logger.error("MCP tool error", exc_info=exc, extra={"error_id": error_id, **context})
    return error_id
```

```python
from mcp.server import MCPServer
from mcp.server.mcpserver.exceptions import ToolError
from mcp import MCPError
from mcp.types import INVALID_PARAMS
from app.core.errors import log_error

mcp = MCPServer("Catalog")

@mcp.tool()
async def get_author(title: str) -> str:
    """Recherche l'auteur d'un livre dans le catalogue."""
    book = await catalog_service.find_by_title(title)
    if book is None:
        # Le modèle peut corriger le titre → ToolError, pas besoin d'error_id, cas déjà clair
        raise ToolError(f"Aucun livre nommé {title!r} dans le catalogue.")
    return book.author

@mcp.tool()
async def sync_catalog() -> dict:
    """Synchronise le catalogue depuis le fournisseur externe."""
    try:
        return await catalog_service.sync()
    except CatalogProviderUnavailable as e:
        # Erreur serveur, hors contrôle du modèle → MCPError avec error_id traçable dans les logs
        error_id = log_error(e)
        raise MCPError(
            code=INVALID_PARAMS,
            message="Fournisseur catalogue indisponible",
            data={"error_id": error_id},
        )
```

Sur le transport `streamable-http` (contrairement à `stdio`, qui n'a pas de couche HTTP), le serveur tourne sur ASGI — réutiliser directement `CorrelationIdMiddleware` (skill `security`) plutôt que générer un `error_id` séparé : `correlation_id.get()` donne la même valeur que celle déjà loggée par le reste de la stack HTTP.

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
# Valider les paramètres d'entrée avant toute opération (lever ToolError si invalides)
```

## Lancement du serveur

Trois transports standard ; sans argument, `stdio` par défaut.

```python
# mcp_server.py
if __name__ == "__main__":
    mcp.run()  # stdio — pour Claude Code (le host lance le fichier en sous-processus)

    # ou, pour un accès réseau (nouvelles intégrations — recommandé sur SSE) :
    # mcp.run(transport="streamable-http", host="127.0.0.1", port=8000)

    # ou, transport hérité (compatibilité descendante uniquement) :
    # mcp.run(transport="sse", host="127.0.0.1", port=8000)
```

Host/port sont configurables — ne jamais les coder en dur en dehors d'un défaut raisonnable ; passer par variables d'environnement (`MCP_HOST`, `MCP_PORT`) comme pour tout autre service réseau du kit.

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
- `ToolError` pour les erreurs récupérables par le modèle, `MCPError` pour les erreurs protocole/serveur — jamais d'exception brute non interceptée
- Toute `MCPError` liée à une panne système (pas une erreur de saisie) porte un `error_id` dans `data`, identique dans les logs serveur
- Opérations destructives avec paramètre `confirm: bool = False`
- Jamais de secrets dans les retours d'outils
- Un serveur MCP par domaine métier (pas de serveur monolithique)
- Tester les outils unitairement avant intégration avec Claude Code
- `mcp>=2.0,<3.0` explicite dans `pyproject.toml` si migration non souhaitée depuis la v1.x (le simple `pip install mcp` installe désormais la v2 par défaut)
