# Blueprint : Email AI

## Cas d'usage
Traitement automatisé d'emails entrants (classification, extraction d'infos, réponse générée) et génération d'emails sortants par IA. Adapté aux workflows de support ou de prospection augmentés par IA.

## Composants

- Authentification et autorisation          ← skill associé : `auth`
- API REST réception / envoi / statuts      ← skill associé : `fastapi`
- Agent de traitement et classification     ← skill associé : `langgraph`
- Génération de contenu par LLM             ← skill associé : `claude-api`
- Validation des entrées et schémas         ← skill associé : `pydantic`
- Persistance emails et historique          ← skill associé : `sqlalchemy`
- Tests API et agents                       ← skill associé : `testing`

## Contraintes

- Le traitement des emails entrants est idempotent (même email traité deux fois → même résultat)
- Les agents retournent des outputs structurés validés par Pydantic
- Aucune donnée personnelle (PII) n'est loggée en clair
- Configuration exclusivement via `core/settings.py` (Pydantic BaseSettings)
- Les services doivent être testables sans dépendance externe (LLM mocké)

## Flux : traitement d'un email entrant

1. Réception de l'email (webhook ou polling)
2. Déduplication (hash du message-id)
3. Classification par l'agent (intention + priorité + catégorie)
4. Extraction des entités clés (nom, date, demande, contact)
5. Génération de la réponse par LLM
6. Validation de la réponse (ton, longueur, cohérence)
7. Envoi ou mise en attente de validation humaine selon le score de confiance

## Structure de fichiers recommandée

```
app/
├── main.py
├── core/
│   ├── settings.py               # Pydantic BaseSettings (LLM keys, SMTP...)
│   └── logging.py                # logs sans PII
├── api/
│   ├── auth.py
│   ├── inbound.py                # webhook réception + déduplication
│   └── outbound.py               # envoi + statuts
├── agents/
│   ├── classifier.py             # classification intention / priorité
│   ├── extractor.py              # extraction entités structurées
│   └── responder.py              # génération de réponse
├── models/
│   ├── user.py
│   ├── email.py
│   └── thread.py
├── schemas/
│   ├── email.py
│   └── agent.py                  # outputs structurés des agents
├── services/
│   ├── auth_service.py
│   ├── email_service.py
│   └── llm_service.py            # abstraction LLM + retry
├── migrations/
└── db.py

tests/
├── test_auth.py
├── test_inbound.py
├── test_classifier.py
└── test_responder.py
```
