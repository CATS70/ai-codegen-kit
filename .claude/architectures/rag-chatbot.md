# Blueprint : RAG Chatbot

## Cas d'usage
Chatbot conversationnel avec mémoire persistée et recherche dans une base de connaissance (RAG). Adapté aux assistants IA qui doivent répondre à partir de documents internes, FAQ ou contenus propriétaires tout en gardant le contexte de la conversation.

## Composants

- Authentification et autorisation               ← skill associé : `auth`
- API REST chat + ingestion documents            ← skill associé : `fastapi`
- Agent conversationnel avec mémoire             ← skill associé : `langgraph`
- Génération et embeddings via LLM               ← skill associé : `claude-api`
- Conception schéma et index vectoriels           ← skill associé : `database-design`
- Modèles et persistance                         ← skill associé : `sqlalchemy`
- Validation des données                         ← skill associé : `pydantic`
- Frontend interface chat                        ← skill associé : `nextjs`
- Tests agent et API                             ← skill associé : `testing`
- Règles OWASP transversales                     ← skill associé : `security`

## Contraintes

- La mémoire de conversation est persistée en base, jamais en mémoire vive (scalabilité)
- Les embeddings sont générés une seule fois à l'ingestion — pas à chaque requête
- Le contexte RAG injecté dans le prompt est limité en tokens (top-K chunks, K configurable via env)
- La recherche hybride (sémantique + lexicale) est préférable à la recherche sémantique seule
- Les sources citées dans les réponses sont traçables (chunk_id + document_id)
- Les réponses en streaming sont supportées (SSE ou WebSocket) pour l'UX
- Configuration exclusivement via `core/settings.py` (Pydantic BaseSettings)
- Les coûts LLM sont loggés par session (tokens input/output, modèle utilisé)
- **Séparer le service d'embedding de l'API FastAPI** si `sentence-transformers` ou `torch` est utilisé — du calcul tensoriel dans le même process qu'une API async bloque la boucle d'événements et empêche les autres requêtes de répondre pendant l'inférence. Utiliser un worker ARQ/Celery dédié ou un microservice séparé pour l'ingestion.

## Flux : message utilisateur

1. Réception du message et chargement de l'historique de session
2. Génération de l'embedding de la question (`embedding_service`)
3. Recherche hybride dans le vector store (top-K chunks)
4. Construction du prompt : historique + chunks + question
5. Appel LLM en streaming
6. Persistance du message utilisateur + réponse + chunks utilisés
7. Retour de la réponse au client (streaming)

## Flux : ingestion de document

1. Upload du document (PDF, Markdown, texte)
2. Extraction du texte (`parser_service`)
3. Découpage en chunks avec overlap configurable
4. Génération des embeddings pour chaque chunk
5. Stockage en vector store (pgvector ou sqlite-vss)
6. Enregistrement du document + métadonnées en base

## Structure de fichiers recommandée

```
backend/
├── app/
│   ├── main.py
│   ├── core/
│   │   ├── settings.py           # ANTHROPIC_API_KEY, EMBEDDING_MODEL, CHAT_MODEL
│   │   │                         # RAG_TOP_K, CHUNK_SIZE, CHUNK_OVERLAP (env)
│   │   └── logging.py
│   ├── api/
│   │   ├── auth.py
│   │   ├── chat.py               # POST /chat/sessions, POST /chat/sessions/{id}/messages (streaming)
│   │   └── documents.py          # POST /documents (upload), GET /documents
│   ├── agents/
│   │   ├── chat_agent.py         # agent ReAct LangGraph avec mémoire persistée
│   │   └── tools/
│   │       └── search_kb.py      # recherche hybride, retourne chunks + scores
│   ├── models/
│   │   ├── user.py
│   │   ├── session.py            # id, user_id, title, created_at
│   │   ├── message.py            # session_id, role, content, tokens_used, created_at
│   │   ├── document.py           # id, title, source_url, status, created_at
│   │   └── chunk.py              # document_id, content, embedding (vector), metadata
│   ├── schemas/
│   │   ├── chat.py               # MessageRequest, MessageResponse, SessionRead
│   │   └── document.py           # DocumentUpload, DocumentRead
│   ├── services/
│   │   ├── auth_service.py
│   │   ├── chat_service.py       # orchestration session + agent + persistance
│   │   ├── embedding_service.py  # génération embeddings, batch
│   │   ├── parser_service.py     # extraction texte PDF/MD/TXT
│   │   ├── chunking_service.py   # découpage avec overlap, nettoyage
│   │   └── search_service.py     # recherche hybride (vecteur + FTS)
│   └── db.py                     # pgvector extension ou sqlite-vss
├── migrations/
└── tests/
    ├── test_chat.py              # session, messages, streaming mocké
    ├── test_rag.py               # recherche, chunks retournés, sources citées
    ├── test_ingestion.py         # upload, parsing, chunking, embeddings mockés
    └── test_agent.py             # agent mocké, mémoire persistée

frontend/
├── app/
│   ├── page.tsx
│   └── chat/
│       └── [sessionId]/
│           └── page.tsx
├── components/
│   ├── ChatWindow.tsx            # streaming SSE, affichage sources
│   ├── MessageBubble.tsx
│   └── DocumentUpload.tsx
└── lib/
    └── api.ts
```
