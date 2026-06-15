# Blueprint : Dashboard & Reporting

## Cas d'usage
Visualisation de données, génération de rapports et exports. Adapté aux outils internes de pilotage, tableaux de bord analytiques et reporting périodique.

## Composants

- Authentification et autorisation          ← skill associé : `auth`
- API REST données / agrégats / exports     ← skill associé : `fastapi`
- Modèles et requêtes analytiques           ← skill associé : `sqlalchemy`
- Validation des filtres et paramètres      ← skill associé : `pydantic`
- Frontend tableaux de bord et graphiques   ← skill associé : `nextjs`
- Tests API et E2E                          ← skill associé : `testing`

## Contraintes

- Les agrégats coûteux sont mis en cache (TTL configuré dans `core/settings.py`)
- Toutes les requêtes analytiques sont paginées (pas de retour full-scan)
- Les exports volumineux sont générés de façon asynchrone (job + download)
- Les filtres sont validés par schéma Pydantic avant toute requête SQL
- Configuration exclusivement via `core/settings.py` (Pydantic BaseSettings)
- Les services analytiques sont testables avec des fixtures SQL déterministes

## Flux : génération d'un rapport exporté

1. Requête avec filtres (période, dimensions, format)
2. Validation des filtres par schéma Pydantic
3. Vérification du cache (TTL)
4. Si cache miss → exécution des requêtes analytiques
5. Mise en cache du résultat
6. Si export → création du job asynchrone
7. Génération du fichier (CSV, PDF)
8. Mise à disposition via URL de téléchargement

## Structure de fichiers recommandée

```
backend/
├── app/
│   ├── main.py
│   ├── core/
│   │   ├── settings.py           # Pydantic BaseSettings (cache TTL, formats...)
│   │   └── logging.py
│   ├── api/
│   │   ├── auth.py
│   │   ├── metrics.py            # agrégats et KPIs (paginés)
│   │   ├── reports.py            # création jobs export
│   │   └── exports.py            # téléchargement des fichiers générés
│   ├── models/
│   │   ├── user.py
│   │   ├── metric.py
│   │   └── export_job.py
│   ├── schemas/
│   │   ├── filters.py            # validation des paramètres de filtrage
│   │   ├── metric.py
│   │   └── report.py
│   ├── services/
│   │   ├── auth_service.py
│   │   ├── analytics_service.py  # requêtes + cache
│   │   └── export_service.py     # génération CSV/PDF
│   └── db.py
├── migrations/
└── tests/
    ├── test_auth.py
    ├── test_metrics.py
    └── test_reports.py

frontend/
├── app/
│   ├── page.tsx
│   ├── dashboards/
│   └── reports/
├── components/
│   ├── Chart.tsx
│   ├── KpiCard.tsx
│   ├── DataTable.tsx
│   └── FilterBar.tsx
└── lib/
    ├── api.ts
    └── formatters.ts
```
