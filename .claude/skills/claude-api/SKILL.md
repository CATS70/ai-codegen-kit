---
name: claude-api
description: Conventions Anthropic SDK Python. Completion, streaming, tool use, prompt caching, gestion d'erreurs, sélection de modèle.
---

# Conventions Claude API — Anthropic SDK

## Installation et configuration

```toml
anthropic = "^0.40"
```

```python
# services/llm_service.py
from anthropic import AsyncAnthropic
from core.settings import settings

client = AsyncAnthropic(api_key=settings.anthropic_api_key)
```

## Modèles disponibles

| Modèle | Usage recommandé |
|---|---|
| `claude-opus-4-7` | Tâches complexes, raisonnement, agents |
| `claude-sonnet-4-6` | Équilibre performance/coût (défaut) |
| `claude-haiku-4-5-20251001` | Tâches simples, faible latence, coût minimal |

```python
# core/settings.py
class Settings(BaseSettings):
    anthropic_api_key: str
    claude_model: str = "claude-sonnet-4-6"   # configurable par env
```

## Completion simple

```python
async def complete(prompt: str, system: str | None = None) -> str:
    """Appel simple sans streaming."""
    messages = [{"role": "user", "content": prompt}]
    kwargs = {"model": settings.claude_model, "max_tokens": 1024, "messages": messages}
    if system:
        kwargs["system"] = system

    response = await client.messages.create(**kwargs)
    return response.content[0].text
```

## Streaming

```python
from fastapi.responses import StreamingResponse

async def stream_completion(prompt: str, system: str | None = None) -> AsyncIterator[str]:
    """Génère les tokens au fur et à mesure."""
    async with client.messages.stream(
        model=settings.claude_model,
        max_tokens=2048,
        system=system or "",
        messages=[{"role": "user", "content": prompt}],
    ) as stream:
        async for text in stream.text_stream:
            yield text

# Route FastAPI avec SSE
@router.post("/generate")
async def generate(data: GenerateRequest):
    async def event_generator():
        async for chunk in stream_completion(data.prompt, data.system):
            yield f"data: {chunk}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")
```

## Tool Use (Function Calling)

```python
tools = [
    {
        "name": "search_knowledge_base",
        "description": "Recherche dans la base de connaissance interne",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Requête de recherche"},
                "limit": {"type": "integer", "description": "Nombre de résultats", "default": 5},
            },
            "required": ["query"],
        },
    }
]

async def agent_with_tools(user_message: str) -> str:
    messages = [{"role": "user", "content": user_message}]

    while True:
        response = await client.messages.create(
            model=settings.claude_model,
            max_tokens=2048,
            tools=tools,
            messages=messages,
        )

        if response.stop_reason == "end_turn":
            return response.content[0].text

        if response.stop_reason == "tool_use":
            tool_use = next(b for b in response.content if b.type == "tool_use")
            tool_result = await execute_tool(tool_use.name, tool_use.input)

            messages.append({"role": "assistant", "content": response.content})
            messages.append({
                "role": "user",
                "content": [{"type": "tool_result", "tool_use_id": tool_use.id, "content": tool_result}],
            })
```

## Prompt Caching

Réduit les coûts sur les prompts système longs ou les documents répétés.

```python
response = await client.messages.create(
    model=settings.claude_model,
    max_tokens=1024,
    system=[
        {
            "type": "text",
            "text": long_system_prompt,
            "cache_control": {"type": "ephemeral"},   # cache 5 min
        }
    ],
    messages=[{"role": "user", "content": user_message}],
)

# Vérifier l'utilisation du cache
usage = response.usage
print(f"Cache hit: {usage.cache_read_input_tokens} tokens")
print(f"Cache miss: {usage.cache_creation_input_tokens} tokens")
```

## Tracking des coûts

```python
def log_usage(response, operation: str) -> None:
    logger.info(
        "LLM usage",
        extra={
            "operation": operation,
            "model": response.model,
            "input_tokens": response.usage.input_tokens,
            "output_tokens": response.usage.output_tokens,
            "cache_read_tokens": getattr(response.usage, "cache_read_input_tokens", 0),
        },
    )
```

## Gestion des erreurs et retry

```python
import anthropic
from tenacity import retry, stop_after_attempt, wait_exponential

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=2, max=10),
    reraise=True,
)
async def resilient_complete(prompt: str) -> str:
    try:
        return await complete(prompt)
    except anthropic.RateLimitError:
        raise   # tenacity va retry
    except anthropic.APIStatusError as e:
        logger.error("Anthropic API error", extra={"status": e.status_code, "message": str(e)})
        raise
```

## Règles

- Modèle configurable via `settings.claude_model` — jamais hardcodé
- `max_tokens` toujours explicite — pas de valeur par défaut silencieuse
- Logger les usages (tokens) pour suivre les coûts
- Streaming obligatoire pour les réponses longues (UX)
- Prompt caching sur les system prompts > 1000 tokens
