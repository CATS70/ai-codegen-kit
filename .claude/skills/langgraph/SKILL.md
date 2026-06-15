---
name: langgraph
description: Conventions LangGraph pour agents ReAct Python. StateGraph, nœuds, edges conditionnels, checkpointing SQLite, human-in-the-loop, streaming.
---

# Conventions LangGraph

## Installation

```toml
langgraph = "^0.2"
langchain-anthropic = "^0.2"   # ou langchain-openai
```

## Pattern ReAct — structure de base

```python
# agents/support_agent.py
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.sqlite.aio import AsyncSqliteSaver
from langchain_anthropic import ChatAnthropic
from langchain_core.messages import HumanMessage, SystemMessage
from typing import TypedDict, Annotated
import operator

# 1. Définir l'état
class AgentState(TypedDict):
    messages: Annotated[list, operator.add]   # accumulation des messages
    user_id: int
    iteration: int                             # protection contre les boucles infinies

# 2. Initialiser le modèle
model = ChatAnthropic(
    model=settings.claude_model,
    api_key=settings.anthropic_api_key,
)
model_with_tools = model.bind_tools(tools)

# 3. Nœuds
async def call_model(state: AgentState) -> dict:
    response = await model_with_tools.ainvoke(state["messages"])
    return {"messages": [response], "iteration": state["iteration"] + 1}

async def call_tools(state: AgentState) -> dict:
    last_message = state["messages"][-1]
    # Appels parallèles — évite d'exécuter N outils en séquence quand ils sont indépendants
    tasks = [execute_tool(tc["name"], tc["args"]) for tc in last_message.tool_calls]
    raw_results = await asyncio.gather(*tasks, return_exceptions=True)
    results = [
        ToolMessage(
            content=str(r) if not isinstance(r, Exception) else f"Erreur : {r}",
            tool_call_id=tc["id"],
        )
        for r, tc in zip(raw_results, last_message.tool_calls)
    ]
    return {"messages": results}

# 4. Routing conditionnel
def should_continue(state: AgentState) -> str:
    last_message = state["messages"][-1]
    if state["iteration"] >= 10:
        return "end"                           # protection boucle infinie
    if hasattr(last_message, "tool_calls") and last_message.tool_calls:
        return "tools"
    return "end"

# 5. Construction du graphe
def build_agent() -> StateGraph:
    graph = StateGraph(AgentState)

    graph.add_node("agent", call_model)
    graph.add_node("tools", call_tools)

    graph.set_entry_point("agent")
    graph.add_conditional_edges("agent", should_continue, {"tools": "tools", "end": END})
    graph.add_edge("tools", "agent")   # retour au modèle après les outils

    return graph
```

## Checkpointing — persistance de l'état

```python
# Persistance SQLite (simple, pas de dépendances externes)
async def create_agent_with_memory(db_path: str = "checkpoints.db"):
    async with AsyncSqliteSaver.from_conn_string(db_path) as checkpointer:
        graph = build_agent()
        app = graph.compile(checkpointer=checkpointer)
        return app

# Utilisation avec thread_id (= session de conversation)
async def chat(agent, user_message: str, thread_id: str, user_id: int) -> str:
    config = {"configurable": {"thread_id": thread_id}}
    initial_state = {
        "messages": [HumanMessage(content=user_message)],
        "user_id": user_id,
        "iteration": 0,
    }
    result = await agent.ainvoke(initial_state, config=config)
    return result["messages"][-1].content
```

## Outils (Tools)

```python
from langchain_core.tools import tool

@tool
async def search_knowledge_base(query: str, limit: int = 5) -> str:
    """
    Recherche dans la base de connaissance.
    Retourner une chaîne vide si aucun résultat.
    """
    results = await kb_service.search(query, limit)
    if not results:
        return "Aucun résultat trouvé."
    return "\n".join(f"- {r.title}: {r.content[:200]}" for r in results)

@tool
async def create_ticket(title: str, description: str, priority: str = "medium") -> str:
    """
    Crée un ticket de support.
    priority: low | medium | high | critical
    """
    ticket = await ticket_service.create(title=title, description=description, priority=priority)
    return f"Ticket #{ticket.id} créé avec succès."

tools = [search_knowledge_base, create_ticket]
```

## Human-in-the-Loop

```python
from langgraph.graph import interrupt

async def review_node(state: AgentState) -> dict:
    """Interrompt l'exécution pour validation humaine."""
    last_message = state["messages"][-1]
    human_decision = interrupt({
        "message": "L'agent veut effectuer cette action. Approuver ?",
        "proposed_action": last_message.content,
    })
    if human_decision == "approve":
        return state
    return {"messages": [HumanMessage(content="Action annulée par l'utilisateur.")]}

# Reprise après approbation
async def resume_agent(agent, thread_id: str, decision: str):
    config = {"configurable": {"thread_id": thread_id}}
    return await agent.ainvoke(Command(resume=decision), config=config)
```

## Streaming

```python
async def stream_agent(agent, user_message: str, thread_id: str) -> AsyncIterator[str]:
    config = {"configurable": {"thread_id": thread_id}}
    state = {"messages": [HumanMessage(content=user_message)], "iteration": 0}

    async for event in agent.astream_events(state, config=config, version="v2"):
        if event["event"] == "on_chat_model_stream":
            chunk = event["data"]["chunk"]
            if chunk.content:
                yield chunk.content
```

## Contraintes

- `iteration` dans l'état + vérification dans le routing — évite les boucles infinies
- Outils avec docstrings claires — le modèle lit la description pour décider
- `thread_id` = identifiant de session — un thread par conversation utilisateur
- Checkpointing toujours activé en production (reprise après erreur)
- Tester les nœuds isolément avant de tester le graphe complet
- **SQLite uniquement pour dev/single-instance** — sur infra distribuée (plusieurs workers/pods), utiliser `AsyncPostgresSaver` (`langgraph-checkpoint-postgres`) : SQLite n'est pas partageable entre processus distincts et n'est pas recommandé par LangGraph pour la production
- **Fenêtre de contexte** — surveiller la longueur de `messages` ; au-delà de ~40 échanges, résumer ou tronquer avec `trim_messages` (langchain_core) avant `call_model` pour éviter un dépassement de contexte
- **Bug asyncio.gather + interrupt()** (déc. 2025, issue #6624) — les tool calls parallèles via `asyncio.gather` génèrent des IDs d'interruption identiques, cassant les workflows human-in-the-loop. Éviter les appels parallèles dans les graphes avec des `interrupt()` ; utiliser l'API `Send` pour le parallélisme contrôlé (map-reduce sur sous-graphes)
