# Blueprint : Content Generation

## Cas d'usage
Génération de contenu textuel par IA (articles, descriptions, copies marketing, rapports). Adapté aux outils de production de contenu avec templates, variantes et historique.

## Composants

- Authentification et autorisation          ← skill associé : `auth`
- API REST génération / historique          ← skill associé : `fastapi`
- Génération de contenu par LLM (streaming) ← skill associé : `claude-api`
- Validation des prompts et paramètres      ← skill associé : `pydantic`
- Persistance générations et templates      ← skill associé : `sqlalchemy`
- Frontend interface de génération          ← skill associé : `nextjs`
- Tests API et qualité de génération        ← skill associé : `testing`

## Contraintes

- Le streaming SSE est obligatoire pour les générations (pas de réponse bloquante)
- Les templates sont versionnés (modification → nouvelle version, pas d'écrasement)
- Toutes les générations sont tracées (template utilisé, paramètres, coût tokens)
- Le rate limiting LLM est géré dans `llm_service` (retry exponentiel)
- Configuration exclusivement via `core/settings.py` (Pydantic BaseSettings)
- Les services doivent être testables sans dépendance externe (LLM mocké)

## Flux : génération de contenu

1. Sélection du template (ou saisie libre)
2. Paramétrage (tone, longueur, variables du template)
3. Validation des paramètres par schéma Pydantic
4. Construction du prompt final
5. Appel LLM avec streaming SSE
6. Affichage token par token côté frontend
7. À la fin du stream → sauvegarde de la génération complète en base
8. Génération disponible dans l'historique

## Structure de fichiers recommandée

```
backend/
├── app/
│   ├── main.py
│   ├── core/
│   │   ├── settings.py           # Pydantic BaseSettings (LLM keys, modèles...)
│   │   └── logging.py
│   ├── api/
│   │   ├── auth.py
│   │   ├── generate.py           # endpoint génération (streaming SSE)
│   │   ├── templates.py          # CRUD templates versionnés
│   │   └── history.py            # historique des générations
│   ├── models/
│   │   ├── user.py
│   │   ├── generation.py         # résultat + métadonnées (tokens, coût)
│   │   └── template.py           # versioning intégré
│   ├── schemas/
│   │   ├── generation.py
│   │   └── template.py
│   ├── services/
│   │   ├── auth_service.py
│   │   ├── generation_service.py # construction prompt + sauvegarde
│   │   └── llm_service.py        # abstraction LLM + retry + streaming
│   └── db.py
├── migrations/
└── tests/
    ├── test_auth.py
    ├── test_generate.py
    └── test_templates.py

frontend/
├── app/
│   ├── page.tsx
│   ├── generate/
│   └── history/
├── components/
│   ├── PromptForm.tsx
│   ├── StreamingOutput.tsx       # affichage token par token (SSE)
│   └── TemplateSelector.tsx
└── lib/
    ├── api.ts
    └── stream.ts                 # gestion SSE
```
