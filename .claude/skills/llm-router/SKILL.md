---
name: llm-router
description: Pattern adaptateur provider-agnostique pour LLM. Interface commune, implémentations Anthropic/OpenAI, sélection via variable d'environnement. Compatible LangGraph et FastAPI.
---

# LLM Router — Pattern Adaptateur

## Principe

Définir une interface commune pour tous les providers LLM. Le code applicatif dépend de l'interface, pas d'un SDK spécifique. Le provider est sélectionné via `LLM_PROVIDER` dans l'environnement.

## Interface commune

```python
# services/llm_router.py
from typing import Protocol, AsyncIterator, runtime_checkable

@runtime_checkable
class LLMProvider(Protocol):
    async def complete(
        self,
        messages: list[dict],
        system: str | None = None,
        max_tokens: int = 1024,
    ) -> str:
        """Retourne la réponse complète."""
        ...

    async def stream(
        self,
        messages: list[dict],
        system: str | None = None,
        max_tokens: int = 2048,
    ) -> AsyncIterator[str]:
        """Génère les tokens au fur et à mesure."""
        ...
```

## Implémentation Anthropic

```python
# services/providers/anthropic_provider.py
from anthropic import AsyncAnthropic
from core.settings import settings

class AnthropicProvider:
    def __init__(self):
        self._client = AsyncAnthropic(api_key=settings.anthropic_api_key)
        self._model = settings.claude_model  # ex: "claude-sonnet-4-6"

    async def complete(self, messages, system=None, max_tokens=1024) -> str:
        kwargs = {"model": self._model, "max_tokens": max_tokens, "messages": messages}
        if system:
            kwargs["system"] = system
        response = await self._client.messages.create(**kwargs)
        return response.content[0].text

    async def stream(self, messages, system=None, max_tokens=2048) -> AsyncIterator[str]:
        async with self._client.messages.stream(
            model=self._model,
            max_tokens=max_tokens,
            system=system or "",
            messages=messages,
        ) as s:
            async for text in s.text_stream:
                yield text
```

## Implémentation OpenAI

```python
# services/providers/openai_provider.py
from openai import AsyncOpenAI
from core.settings import settings

class OpenAIProvider:
    def __init__(self):
        self._client = AsyncOpenAI(api_key=settings.openai_api_key)
        self._model = settings.openai_model  # ex: "gpt-4o-mini"

    async def complete(self, messages, system=None, max_tokens=1024) -> str:
        all_messages = []
        if system:
            all_messages.append({"role": "system", "content": system})
        all_messages.extend(messages)
        response = await self._client.chat.completions.create(
            model=self._model, messages=all_messages, max_tokens=max_tokens
        )
        return response.choices[0].message.content or ""

    async def stream(self, messages, system=None, max_tokens=2048) -> AsyncIterator[str]:
        all_messages = []
        if system:
            all_messages.append({"role": "system", "content": system})
        all_messages.extend(messages)
        stream = await self._client.chat.completions.create(
            model=self._model, messages=all_messages, max_tokens=max_tokens, stream=True
        )
        async for chunk in stream:
            delta = chunk.choices[0].delta.content
            if delta:
                yield delta
```

## Factory — sélection par env var

```python
# services/llm_router.py (suite)
from core.settings import settings

_providers: dict[str, type] = {
    "anthropic": AnthropicProvider,
    "openai":    OpenAIProvider,
}

def get_llm_provider() -> LLMProvider:
    """
    Retourne le provider configuré via LLM_PROVIDER.
    Défaut : anthropic.
    """
    name = settings.llm_provider
    if name not in _providers:
        raise ValueError(f"Unknown LLM provider: {name}. Available: {list(_providers)}")
    return _providers[name]()
```

```python
# core/settings.py
class Settings(BaseSettings):
    llm_provider: str = "anthropic"   # anthropic | openai
    # Clés optionnelles selon le provider actif
    anthropic_api_key: str | None = None
    openai_api_key: str | None = None
    claude_model: str = "claude-sonnet-4-6"
    openai_model: str = "gpt-4o-mini"
```

## Usage dans les services

```python
# services/generation_service.py
from services.llm_router import get_llm_provider

async def generate_content(prompt: str, system: str) -> str:
    provider = get_llm_provider()   # résolution à l'appel
    return await provider.complete(
        messages=[{"role": "user", "content": prompt}],
        system=system,
    )

async def stream_content(prompt: str, system: str) -> AsyncIterator[str]:
    provider = get_llm_provider()
    async for chunk in provider.stream(
        messages=[{"role": "user", "content": prompt}],
        system=system,
    ):
        yield chunk
```

## Intégration LangGraph

```python
# LangGraph accepte n'importe quel modèle LangChain
# Wrapper pour rendre le router compatible avec LangGraph

from langchain_core.language_models import BaseChatModel

def get_langchain_model() -> BaseChatModel:
    """Retourne le modèle LangChain correspondant au provider configuré."""
    match settings.llm_provider:
        case "anthropic":
            from langchain_anthropic import ChatAnthropic
            return ChatAnthropic(model=settings.claude_model, api_key=settings.anthropic_api_key)
        case "openai":
            from langchain_openai import ChatOpenAI
            return ChatOpenAI(model=settings.openai_model, api_key=settings.openai_api_key)
        case _:
            raise ValueError(f"Unknown provider: {settings.llm_provider}")
```

## Provider de test (mock)

```python
# tests/providers/mock_provider.py
class MockProvider:
    def __init__(self, response: str = "Mock response"):
        self._response = response

    async def complete(self, messages, system=None, max_tokens=1024) -> str:
        return self._response

    async def stream(self, messages, system=None, max_tokens=2048) -> AsyncIterator[str]:
        for word in self._response.split():
            yield word + " "

# Dans les tests
def override_provider(monkeypatch, response="Test response"):
    monkeypatch.setattr("services.llm_router.get_llm_provider", lambda: MockProvider(response))
```

## Ajouter un nouveau provider

1. Créer `services/providers/mistral_provider.py` qui implémente `LLMProvider`
2. Ajouter `"mistral": MistralProvider` dans `_providers`
3. Ajouter `mistral_api_key` et `mistral_model` dans `Settings`
4. Changer `LLM_PROVIDER=mistral` dans `.env`

Aucun autre fichier à modifier.
