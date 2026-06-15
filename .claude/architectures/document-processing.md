# Blueprint : Document Processing

## Cas d'usage
Ingestion, extraction et transformation de documents (PDF, Word, images). Adapté aux pipelines d'analyse documentaire, de structuration de données et d'archivage intelligent.

## Composants

- Authentification et autorisation          ← skill associé : `auth`
- API REST upload / extraction / export     ← skill associé : `fastapi`
- Extraction de contenu par LLM             ← skill associé : `claude-api`
- Validation des schémas extraits           ← skill associé : `pydantic`
- Persistance documents et résultats        ← skill associé : `sqlalchemy`
- Tests API et extraction                   ← skill associé : `testing`
- Conteneurisation                          ← skill associé : `docker`

## Contraintes

- Le traitement des documents est asynchrone (upload → job → résultat)
- Les extractions LLM sont validées par schéma Pydantic strict avant stockage
- Aucun contenu sensible n'est loggué (documents traités en mémoire)
- Le traitement est idempotent (même document soumis deux fois → même résultat)
- Configuration exclusivement via `core/settings.py` (Pydantic BaseSettings)
- Les services doivent être testables sans dépendance externe (LLM mocké)

## Flux : traitement d'un document

1. Upload du fichier (validation type + taille)
2. Stockage du fichier brut
3. Création du job de traitement (`status=PENDING`)
4. Extraction du texte selon le type (PDF, image OCR, Word)
5. Extraction structurée via LLM (selon le schéma cible)
6. Validation du résultat par schéma Pydantic
7. Stockage du résultat (`status=DONE`) ou erreur (`status=FAILED`)
8. Résultat disponible via l'API export

## Structure de fichiers recommandée

```
app/
├── main.py
├── core/
│   ├── settings.py               # Pydantic BaseSettings (storage, LLM keys...)
│   └── logging.py                # sans contenu sensible
├── api/
│   ├── auth.py
│   ├── upload.py                 # validation type/taille + création job
│   ├── jobs.py                   # statut des traitements
│   └── export.py                 # récupération des résultats
├── processors/
│   ├── pdf_processor.py          # extraction texte PDF
│   ├── image_processor.py        # OCR
│   └── extractor.py              # extraction structurée via LLM
├── domain/
│   └── enums/
│       └── job_status.py         # PENDING, PROCESSING, DONE, FAILED
├── models/
│   ├── user.py
│   ├── document.py
│   └── job.py
├── schemas/
│   ├── document.py
│   └── extraction.py             # schéma cible validé par Pydantic
├── services/
│   ├── auth_service.py
│   ├── storage_service.py        # lecture/écriture fichiers
│   └── llm_service.py            # abstraction LLM + retry
├── migrations/
└── db.py

tests/
├── test_auth.py
├── test_upload.py
├── test_extraction.py
└── fixtures/
    └── sample.pdf

Dockerfile
```
