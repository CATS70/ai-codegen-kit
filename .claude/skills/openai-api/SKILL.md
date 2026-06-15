---
name: openai-api
description: Conventions OpenAI SDK Python. Completion, streaming, function calling, structured outputs, gestion d'erreurs, sélection de modèle.
---

# Conventions OpenAI API

## Installation et configuration

```toml
openai = "^1.50"
```

```python
# services/llm_service.py
from openai import AsyncOpenAI
from core.settings import settings

client = AsyncOpenAI(api_key=settings.openai_api_key)
```

## Modèles disponibles

| Modèle | Usage recommandé |
|---|---|
| `gpt-4o` | Tâches complexes, vision, agents |
| `gpt-4o-mini` | Équilibre performance/coût (défaut) |
| `o1-mini` | Raisonnement mathématique / logique |

```python
# core/settings.py
class Settings(BaseSettings):
    openai_api_key: str
    openai_model: str = "gpt-4o-mini"   # configurable par env
```

## Completion simple

```python
async def complete(prompt: str, system: str | None = None) -> str:
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})

    response = await client.chat.completions.create(
        model=settings.openai_model,
        messages=messages,
        max_tokens=1024,
    )
    return response.choices[0].message.content or ""
```

## Streaming

```python
async def stream_completion(prompt: str, system: str | None = None) -> AsyncIterator[str]:
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})

    stream = await client.chat.completions.create(
        model=settings.openai_model,
        messages=messages,
        max_tokens=2048,
        stream=True,
    )
    async for chunk in stream:
        delta = chunk.choices[0].delta.content
        if delta:
            yield delta
```

## Function Calling

```python
tools = [
    {
        "type": "function",
        "function": {
            "name": "search_knowledge_base",
            "description": "Recherche dans la base de connaissance interne",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string"},
                    "limit": {"type": "integer", "default": 5},
                },
                "required": ["query"],
            },
        },
    }
]

async def agent_with_tools(user_message: str) -> str:
    messages = [{"role": "user", "content": user_message}]

    while True:
        response = await client.chat.completions.create(
            model=settings.openai_model,
            messages=messages,
            tools=tools,
            tool_choice="auto",
        )
        message = response.choices[0].message

        if message.tool_calls:
            messages.append(message)
            for call in message.tool_calls:
                result = await execute_tool(call.function.name, call.function.arguments)
                messages.append({
                    "role": "tool",
                    "tool_call_id": call.id,
                    "content": result,
                })
        else:
            return message.content or ""
```

## Structured Outputs

```python
from pydantic import BaseModel

class ExtractedData(BaseModel):
    name: str
    amount: float
    date: str
    category: str

async def extract_structured(text: str) -> ExtractedData:
    """Extraction garantie dans le schéma Pydantic — pas de parsing manuel."""
    response = await client.beta.chat.completions.parse(
        model="gpt-4o-mini",
        messages=[
            {"role": "system", "content": "Extrais les informations structurées du texte."},
            {"role": "user", "content": text},
        ],
        response_format=ExtractedData,
    )
    return response.choices[0].message.parsed
```

## Tracking des coûts

```python
def log_usage(response, operation: str) -> None:
    logger.info(
        "LLM usage",
        extra={
            "operation": operation,
            "model": response.model,
            "input_tokens": response.usage.prompt_tokens,
            "output_tokens": response.usage.completion_tokens,
            "total_tokens": response.usage.total_tokens,
        },
    )
```

## Gestion des erreurs et retry

```python
import openai
from tenacity import retry, stop_after_attempt, wait_exponential

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=2, max=10),
    reraise=True,
)
async def resilient_complete(prompt: str) -> str:
    try:
        return await complete(prompt)
    except openai.RateLimitError:
        raise   # tenacity va retry
    except openai.APIStatusError as e:
        logger.error("OpenAI API error", extra={"status": e.status_code})
        raise
```

## Règles

- Modèle configurable via `settings.openai_model` — jamais hardcodé
- `max_tokens` toujours explicite
- Logger les usages (tokens) pour suivre les coûts
- Structured Outputs préféré à JSON mode pour les extractions typées
- Streaming obligatoire pour les réponses longues
