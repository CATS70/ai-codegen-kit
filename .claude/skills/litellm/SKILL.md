---
name: litellm
description: Abstraction LLM multi-provider clé en main via LiteLLM. Compatible 100+ providers (Anthropic, OpenAI, Mistral, Gemini…), drop-in replacement, streaming, fallback, tracking coûts.
---

# Conventions LiteLLM

## Quand utiliser LiteLLM vs llm-router

| Critère | `litellm` | `llm-router` |
|---|---|---|
| Nombre de providers cibles | 3+ | 1-2 |
| Fonctionnalités avancées (fallback, retry, load balancing) | Oui | Non |
| Dépendance externe acceptée | Oui | Non |
| Contrôle total sur l'implémentation | Non | Oui |

## Installation

```toml
litellm = "^1.50"
```

## Configuration

```python
# core/settings.py
class Settings(BaseSettings):
    llm_provider: str = "anthropic"           # anthropic | openai | mistral | gemini
    llm_model: str = "claude-sonnet-4-6"      # modèle complet ou alias LiteLLM
    anthropic_api_key: str | None = None
    openai_api_key: str | None = None
    mistral_api_key: str | None = None
```

```python
# services/llm_service.py
import litellm
from core.settings import settings

# LiteLLM lit les clés depuis les variables d'environnement standard
# ANTHROPIC_API_KEY, OPENAI_API_KEY, MISTRAL_API_KEY...
litellm.set_verbose = settings.debug
```

## Completion — API unifiée

```python
from litellm import acompletion

async def complete(
    prompt: str,
    system: str | None = None,
    model: str | None = None,
) -> str:
    """
    Interface unifiée pour tous les providers.
    Le format de messages est identique quel que soit le provider.
    """
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})

    response = await acompletion(
        model=model or settings.llm_model,
        messages=messages,
        max_tokens=1024,
    )
    return response.choices[0].message.content or ""
```

## Streaming

```python
from litellm import acompletion

async def stream_completion(prompt: str, system: str | None = None) -> AsyncIterator[str]:
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})

    response = await acompletion(
        model=settings.llm_model,
        messages=messages,
        max_tokens=2048,
        stream=True,
    )
    async for chunk in response:
        delta = chunk.choices[0].delta.content
        if delta:
            yield delta
```

## Fallback automatique

```python
from litellm import acompletion

async def complete_with_fallback(prompt: str) -> str:
    """Bascule automatiquement vers le provider de secours si le principal échoue."""
    response = await acompletion(
        model=settings.llm_model,
        messages=[{"role": "user", "content": prompt}],
        fallbacks=["gpt-4o-mini", "mistral/mistral-small"],  # tentés dans l'ordre
        max_tokens=1024,
    )
    return response.choices[0].message.content or ""
```

## Tracking des coûts

```python
import litellm

# Activer le tracking global
litellm.success_callback = ["langfuse"]   # optionnel : envoi vers observabilité

def log_usage(response, operation: str) -> None:
    cost = litellm.completion_cost(completion_response=response)
    logger.info(
        "LLM usage",
        extra={
            "operation": operation,
            "model": response.model,
            "input_tokens": response.usage.prompt_tokens,
            "output_tokens": response.usage.completion_tokens,
            "cost_usd": round(cost, 6),
        },
    )
```

## Intégration LangGraph

```python
from langchain_community.chat_models.litellm import ChatLiteLLM

def get_langchain_model():
    """LiteLLM comme backend LangChain — compatible LangGraph."""
    return ChatLiteLLM(
        model=settings.llm_model,
        max_tokens=2048,
    )

# Dans le graphe LangGraph
model = get_langchain_model()
model_with_tools = model.bind_tools(tools)
```

## Noms de modèles LiteLLM

| Provider | Format du modèle |
|---|---|
| Anthropic | `claude-sonnet-4-6` |
| OpenAI | `gpt-4o-mini` |
| Mistral | `mistral/mistral-small` |
| Google Gemini | `gemini/gemini-1.5-flash` |
| Azure OpenAI | `azure/gpt-4o` |

## Tests

```python
# Mock LiteLLM en test — pas d'appel réseau
from unittest.mock import patch, AsyncMock

async def test_complete(monkeypatch):
    mock_response = MagicMock()
    mock_response.choices[0].message.content = "Réponse de test"

    with patch("litellm.acompletion", new_callable=AsyncMock, return_value=mock_response):
        result = await complete("Bonjour")
        assert result == "Réponse de test"
```

## Règles

- Modèle configurable via `settings.llm_model` — jamais hardcodé
- Les clés API passent par les variables d'environnement standard (LiteLLM les lit automatiquement)
- Logger le coût USD à chaque appel pour suivre la consommation
- Utiliser `fallbacks` pour les endpoints critiques (support, paiement)
- Streaming obligatoire pour les réponses longues (UX)
