# Blueprint : Customer Support

## Cas d'usage
Gestion de tickets, chatbot de support conversationnel et base de connaissance consultable. Adapté aux outils de support client augmentés par IA.

## Composants

- Authentification et autorisation          ← skill associé : `auth`
- API REST tickets / conversations          ← skill associé : `fastapi`
- Agent conversationnel avec mémoire        ← skill associé : `langgraph`
- Génération de réponses par LLM            ← skill associé : `claude-api`
- Validation des entrées et schémas         ← skill associé : `pydantic`
- Persistance tickets et historique         ← skill associé : `sqlalchemy`
- Frontend interface support                ← skill associé : `nextjs`
- Tests API, agent et E2E                   ← skill associé : `testing`

## Contraintes

- Toute logique métier dans `services/` — les routes API font max 20 lignes
- La mémoire de conversation est persistée en base (pas en mémoire vive)
- Les conditions d'escalade humaine sont explicitement définies dans l'agent
- Les réponses LLM sont limitées en tokens pour maîtriser les coûts
- Configuration exclusivement via `core/settings.py` (Pydantic BaseSettings)
- Les services doivent être testables sans dépendance externe (agent mocké)

## Flux : traitement d'un message utilisateur

1. Réception du message (canal : chat, email, API)
2. Chargement de l'historique de conversation
3. Recherche dans la base de connaissance (`search_kb`)
4. Génération de la réponse par l'agent
5. Si score de confiance < seuil → escalade humaine + création ticket
6. Sinon → envoi de la réponse + mise à jour de l'historique
7. Clôture ou continuation de la conversation

## Structure de fichiers recommandée

```
backend/
├── app/
│   ├── main.py
│   ├── core/
│   │   ├── settings.py           # Pydantic BaseSettings (LLM, seuils escalade...)
│   │   └── logging.py
│   ├── api/
│   │   ├── auth.py
│   │   ├── tickets.py            # CRUD tickets + statuts
│   │   └── chat.py               # endpoint conversation (streaming)
│   ├── agents/
│   │   ├── support_agent.py      # agent ReAct avec mémoire persistée
│   │   └── tools/
│   │       ├── search_kb.py      # recherche base de connaissance
│   │       └── create_ticket.py  # création ticket lors d'escalade
│   ├── domain/
│   │   └── enums/
│   │       └── ticket_status.py  # OPEN, IN_PROGRESS, ESCALATED, CLOSED
│   ├── models/
│   │   ├── user.py
│   │   ├── ticket.py
│   │   ├── conversation.py
│   │   └── kb_article.py
│   ├── schemas/
│   │   ├── ticket.py
│   │   └── chat.py
│   ├── services/
│   │   ├── auth_service.py
│   │   ├── ticket_service.py
│   │   └── kb_service.py
│   └── db.py
├── migrations/
└── tests/
    ├── test_auth.py
    ├── test_tickets.py
    └── test_agent.py

frontend/
├── app/
│   ├── page.tsx
│   ├── tickets/
│   └── chat/
├── components/
│   ├── ChatWindow.tsx
│   ├── TicketList.tsx
│   └── MessageBubble.tsx
└── lib/
    └── api.ts
```
