# Blueprint : Data Pipeline

## Cas d'usage
Ingestion de données depuis des sources multiples, transformation et chargement vers une destination (ETL). Adapté aux pipelines batch ou streaming avec orchestration et monitoring.

## Composants

- Authentification et autorisation          ← skill associé : `auth`
- API REST déclenchement / statuts          ← skill associé : `fastapi`
- Orchestration des étapes du pipeline      ← skill associé : `langgraph`
- Validation et typage des données          ← skill associé : `pydantic`
- Persistance résultats et logs             ← skill associé : `sqlalchemy`
- Tests unitaires et d'intégration          ← skill associé : `testing`
- Conteneurisation et déploiement           ← skill associé : `docker`

## Contraintes

- Chaque nœud du pipeline est idempotent (re-exécutable sans effet de bord)
- L'état de chaque run est persisté en base à chaque étape (reprise possible)
- Les erreurs sont propagées et loggées avec contexte complet (source, ligne, valeur)
- La validation des données se fait à l'entrée ET à la sortie de chaque nœud
- Configuration exclusivement via `core/settings.py` (Pydantic BaseSettings)
- Les nœuds doivent être testables unitairement (entrée/sortie mockées)

## Flux : exécution d'un pipeline

1. Déclenchement (API, schedule ou événement)
2. Création du run (`status=RUNNING`)
3. Ingestion : lecture source + validation du schéma entrant
4. Transformation : nettoyage, enrichissement, normalisation
5. Validation du schéma sortant avant chargement
6. Chargement vers la destination
7. Mise à jour du run (`status=SUCCESS` ou `status=FAILED`)
8. Log du résumé (lignes traitées, erreurs, durée)

## Structure de fichiers recommandée

```
app/
├── main.py
├── core/
│   ├── settings.py               # Pydantic BaseSettings (sources, destinations...)
│   └── logging.py
├── api/
│   ├── auth.py
│   ├── pipeline.py               # trigger, statut, historique des runs
│   └── health.py
├── pipeline/
│   ├── graph.py                  # définition du graphe LangGraph
│   ├── state.py                  # état partagé entre les nœuds
│   └── nodes/
│       ├── ingest.py             # lecture source (fichier, API, DB)
│       ├── transform.py          # nettoyage, enrichissement
│       └── load.py               # écriture destination
├── domain/
│   └── enums/
│       └── run_status.py         # PENDING, RUNNING, SUCCESS, FAILED
├── models/
│   ├── user.py
│   ├── run.py                    # historique d'exécution
│   └── run_log.py                # logs par étape
├── schemas/
│   ├── pipeline.py
│   └── record.py                 # schéma des données transitant dans le pipeline
├── services/
│   ├── auth_service.py
│   └── pipeline_service.py
├── migrations/
└── db.py

tests/
├── test_auth.py
├── test_ingest.py
├── test_transform.py
├── test_load.py
└── test_pipeline_e2e.py

Dockerfile
docker-compose.yml
```
