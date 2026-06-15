# Blueprint : CRM

## Cas d'usage
Gestion de contacts, suivi de pipeline commercial et historique d'activités. Adapté aux outils internes de gestion de relation client.

## Composants

- Authentification et autorisation          ← skill associé : `auth`
- API REST contacts / pipeline / activités  ← skill associé : `fastapi`
- Modèles et accès base de données          ← skill associé : `sqlalchemy`
- Validation des entrées et schémas         ← skill associé : `pydantic`
- Frontend tableau de bord CRM              ← skill associé : `nextjs`
- Tests API et E2E                          ← skill associé : `testing`

## Contraintes

- Toute logique métier dans `services/` — les routes API font max 20 lignes
- Les transitions de statut des deals passent par la machine à états de `domain/`
- Les activités sont immuables une fois créées (append-only)
- Configuration exclusivement via `core/settings.py` (Pydantic BaseSettings)
- Les services doivent être testables sans dépendance externe

## Flux : qualification d'un lead

1. Créer le contact avec les informations de base
2. Créer un deal associé (`status=LEAD`)
3. Enregistrer la première activité (appel, email, réunion)
4. Mettre à jour le statut du deal selon l'avancement (`QUALIFIED`, `PROPOSAL`, `WON/LOST`)
5. Chaque changement de statut génère une activité automatique

## Structure de fichiers recommandée

```
backend/
├── app/
│   ├── main.py
│   ├── core/
│   │   ├── settings.py           # Pydantic BaseSettings
│   │   └── logging.py
│   ├── api/
│   │   ├── auth.py
│   │   ├── contacts.py           # CRUD + recherche + pagination
│   │   ├── deals.py              # pipeline + transitions de statut
│   │   └── activities.py         # historique (append-only)
│   ├── domain/
│   │   └── enums/
│   │       └── deal_status.py    # LEAD, QUALIFIED, PROPOSAL, WON, LOST
│   ├── models/
│   │   ├── user.py
│   │   ├── contact.py
│   │   ├── deal.py
│   │   └── activity.py
│   ├── schemas/
│   │   ├── contact.py
│   │   ├── deal.py
│   │   └── activity.py
│   ├── services/
│   │   ├── auth_service.py
│   │   ├── contact_service.py
│   │   └── pipeline_service.py   # transitions de statut + activités automatiques
│   └── db.py
├── migrations/
└── tests/
    ├── test_auth.py
    ├── test_contacts.py
    ├── test_deals.py
    └── test_activities.py

frontend/
├── app/
│   ├── page.tsx
│   ├── contacts/
│   ├── pipeline/
│   └── activities/
├── components/
│   ├── ContactCard.tsx
│   ├── PipelineBoard.tsx
│   └── ActivityFeed.tsx
└── lib/
    └── api.ts
```
