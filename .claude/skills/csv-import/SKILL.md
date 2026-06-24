---
name: csv-import
description: Import de données en masse depuis un fichier CSV pour FastAPI. Mapping de colonnes configurable, délimiteur configurable, validation ligne par ligne, dédoublonnage (upsert/reject), rapport d'erreurs, traitement synchrone/asynchrone selon le volume.
---

# Conventions Import CSV

## Principe fondamental

Toute logique d'import passe par un `ImportJob` persisté — jamais de traitement "fire and forget" sans trace. L'utilisateur doit toujours pouvoir consulter le résultat (lignes importées, rejetées, raison).

```
route (upload) → import_service.start() → ImportJob (PENDING)
                                          → traitement sync ou async selon le volume
                                          → ImportJob (DONE/FAILED) + ImportRowError[]
```

## Modèles

```python
# models/import_job.py
class ImportEntityType(StrEnum):
    ENTREPRISE = "entreprise"
    PERSONNE = "personne"
    # ajouter une valeur par entité important réellement du CSV dans le projet

class ImportStatus(StrEnum):
    PENDING    = "pending"
    PROCESSING = "processing"
    DONE       = "done"
    FAILED     = "failed"

class ImportJob(Base):
    __tablename__ = "import_jobs"

    id:             Mapped[int]            = mapped_column(primary_key=True)
    entity_type:    Mapped[ImportEntityType]
    status:         Mapped[ImportStatus]    = mapped_column(default=ImportStatus.PENDING)
    delimiter:      Mapped[str]             = mapped_column(String(1), default=",")
    column_mapping: Mapped[dict]            = mapped_column(JSON)   # {"colonne_csv": "champ_cible"}
    total_rows:     Mapped[int]             = mapped_column(default=0)
    success_count:  Mapped[int]             = mapped_column(default=0)
    error_count:    Mapped[int]             = mapped_column(default=0)
    created_by_id:  Mapped[int]             = mapped_column(ForeignKey("users.id"))
    created_at:     Mapped[datetime]        = mapped_column(default=func.now())
    finished_at:    Mapped[datetime | None]

# models/import_row_error.py
class ImportRowError(Base):
    __tablename__ = "import_row_errors"

    id:            Mapped[int]      = mapped_column(primary_key=True)
    import_job_id: Mapped[int]      = mapped_column(ForeignKey("import_jobs.id"), index=True)
    row_number:    Mapped[int]                          # numéro de ligne dans le fichier source (1-indexed, hors header)
    raw_data:      Mapped[dict]     = mapped_column(JSON)
    reason:        Mapped[str]      = mapped_column(String(255))   # "validation" | "doublon" | "ligne malformée"
```

## Délimiteur — toujours configurable par import, jamais figé en dur

Les fichiers CSV exportés depuis Excel en France utilisent très souvent `;` (le `,` étant le séparateur décimal), alors qu'un export US ou un outil SaaS utilise `,`. Le délimiteur dépend du fichier source de l'utilisateur, pas du projet — c'est un paramètre fourni à chaque import, jamais une constante codée en dur ni une seule valeur par défaut implicite sans possibilité de l'écraser.

```python
# schemas/import_job.py
class ImportRequest(BaseModel):
    mapping: dict[str, str]
    delimiter: str = ","   # override possible : ";", "\t", "|"...

    @field_validator("delimiter")
    @classmethod
    def delimiter_must_be_one_char(cls, v: str) -> str:
        if len(v) != 1:
            raise ValueError("Le délimiteur doit être un seul caractère")
        return v
```

## Lecture en streaming — jamais charger tout le fichier en mémoire

```python
# services/csv_import_service.py
import csv
import io

async def parse_csv_rows(file: UploadFile, delimiter: str = ",") -> Iterator[dict[str, str]]:
    """Lit le CSV ligne par ligne sans charger tout le fichier en mémoire."""
    wrapper = io.TextIOWrapper(file.file, encoding="utf-8-sig")  # utf-8-sig : tolère le BOM Excel
    reader = csv.DictReader(wrapper, delimiter=delimiter)
    for row in reader:
        yield row
```

`utf-8-sig` est nécessaire : Excel ajoute un BOM (`﻿`) en tête de fichier lors d'un export CSV — sans ce décodage, la première colonne mappée échoue silencieusement.

**Optionnel — détection automatique en aide à la saisie** (jamais comme seule source de vérité) :

```python
def detect_delimiter(header_line: str, candidates: str = ",;\t|") -> str:
    """Suggestion d'UI uniquement — l'utilisateur garde la main pour corriger avant de lancer l'import.

    Ne PAS utiliser csv.Sniffer() sur un échantillon multi-lignes : son heuristique se trompe dès qu'une
    valeur de texte libre contient une virgule non protégée par des guillemets ailleurs dans le fichier
    (ex: un champ "secteur d'activité" du type "Administration générale, économique et sociale" sur un
    export INSEE réel a fait détecter "," au lieu du ";" réellement utilisé). La ligne d'en-tête seule
    ne contient jamais de texte libre — compter la fréquence de chaque délimiteur candidat dessus suffit
    et est sans ambiguïté en pratique.
    """
    counts = {c: header_line.count(c) for c in candidates}
    best = max(counts, key=counts.get)
    return best if counts[best] > 0 else ","
```

## Mapping de colonnes — toujours explicite, jamais déduit par position

```python
def apply_mapping(raw_row: dict[str, str], mapping: dict[str, str]) -> dict[str, str]:
    return {
        target_field: raw_row.get(source_column, "").strip()
        for source_column, target_field in mapping.items()
    }
```

Ne jamais supposer que la colonne N du fichier correspond toujours au même champ — l'ordre des colonnes varie selon l'export source de l'utilisateur, le mapping doit être fourni à chaque import (ou rechargé depuis un mapping sauvegardé si la spec le prévoit explicitement).

## Validation ligne par ligne + rapport d'erreurs

```python
async def process_row(
    db: AsyncSession,
    row_number: int,
    mapped_row: dict[str, str],
    job_id: int,
    dedup_strategy: Literal["upsert", "reject"],
) -> bool:
    """Retourne True si la ligne a été importée avec succès, False si rejetée."""
    try:
        validated = EntrepriseCreate.model_validate(mapped_row)
    except ValidationError as e:
        await _record_error(db, job_id, row_number, mapped_row, reason=f"validation: {e.errors()[0]['msg']}")
        return False

    existing = await db.scalar(select(Entreprise).where(Entreprise.siren == validated.siren))
    if existing:
        if dedup_strategy == "reject":
            await _record_error(db, job_id, row_number, mapped_row, reason="doublon (SIREN déjà existant)")
            return False
        # dedup_strategy == "upsert"
        for field, value in validated.model_dump(exclude_unset=True).items():
            setattr(existing, field, value)
    else:
        db.add(Entreprise(**validated.model_dump()))

    return True

async def _record_error(db: AsyncSession, job_id: int, row_number: int, raw_data: dict, reason: str) -> None:
    db.add(ImportRowError(import_job_id=job_id, row_number=row_number, raw_data=raw_data, reason=reason))
```

**`dedup_strategy` (upsert vs reject) n'est jamais un choix par défaut du code — c'est une décision métier qui doit venir de `spec-final.md` (FR-xxx explicite)**. Les deux stratégies sont légitimes selon le projet ; ne pas en coder une au hasard faute de précision dans la spec — si la spec ne le précise pas, signaler l'ambiguïté plutôt que de trancher silencieusement.

## Traitement synchrone vs asynchrone selon le volume

```python
# core/settings.py
class Settings(BaseSettings):
    csv_async_threshold_rows: int = 2000   # au-delà, traitement en BackgroundTask

# services/csv_import_service.py
async def start_import(
    db: AsyncSession,
    background_tasks: BackgroundTasks,
    file: UploadFile,
    entity_type: ImportEntityType,
    mapping: dict[str, str],
    delimiter: str,
    dedup_strategy: Literal["upsert", "reject"],
    user_id: int,
) -> ImportJob:
    job = ImportJob(entity_type=entity_type, column_mapping=mapping, delimiter=delimiter, created_by_id=user_id)
    db.add(job)
    await db.commit()
    await db.refresh(job)

    content = await file.read()
    row_count = content.count(b"\n")
    await file.seek(0)

    if row_count > settings.csv_async_threshold_rows:
        background_tasks.add_task(_process_import, job.id, file, mapping, delimiter, dedup_strategy)
    else:
        await _process_import(job.id, file, mapping, delimiter, dedup_strategy, db=db)

    return job
```

Le seuil (`csv_async_threshold_rows`) est une variable d'environnement, pas une valeur en dur — il dépend du temps de traitement par ligne propre à chaque projet (appels externes par ligne, complexité de validation...).

## Commit par lot — pas un commit par ligne

```python
BATCH_SIZE = 500

async def _process_import(job_id: int, rows: Iterator[dict], mapping: dict, delimiter: str, dedup_strategy: str, db: AsyncSession) -> None:
    success = errors = 0
    for i, raw_row in enumerate(rows, start=1):
        mapped = apply_mapping(raw_row, mapping)
        ok = await process_row(db, i, mapped, job_id, dedup_strategy)
        success += ok
        errors += not ok
        if i % BATCH_SIZE == 0:
            await db.commit()   # libère la mémoire de session SQLAlchemy périodiquement

    await db.commit()
    job = await db.get(ImportJob, job_id)
    job.status = ImportStatus.DONE
    job.total_rows, job.success_count, job.error_count = i, success, errors
    job.finished_at = datetime.now(timezone.utc)
    await db.commit()
```

Un commit par ligne sur un fichier de plusieurs milliers de lignes dégrade fortement les performances et sature les connexions ; un commit unique en fin de traitement fait perdre toute progression en cas de crash à mi-parcours.

## Routes API

```python
# api/imports.py
router = APIRouter(prefix="/imports", tags=["imports"])

@router.post("/{entity_type}", response_model=ImportJobRead, status_code=202)
async def create_import(
    entity_type: ImportEntityType,
    file: UploadFile,
    request: ImportRequest,
    dedup_strategy: Literal["upsert", "reject"],
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Démarre un import CSV. Retourne immédiatement l'ImportJob (en cours ou terminé selon le volume)."""
    if file.content_type not in ("text/csv", "application/vnd.ms-excel"):
        raise HTTPException(422, "Le fichier doit être un CSV")
    return await csv_import_service.start_import(
        db, background_tasks, file, entity_type, request.mapping, request.delimiter, dedup_strategy, current_user.id
    )

@router.get("/{job_id}", response_model=ImportJobRead)
async def get_import_status(job_id: int, db: AsyncSession = Depends(get_db)):
    """Consulte le statut et le résumé d'un import (succès/erreurs)."""
    ...

@router.get("/{job_id}/errors", response_model=PaginatedResponse[ImportRowErrorRead])
async def list_import_errors(job_id: int, db: AsyncSession = Depends(get_db)):
    """Liste détaillée des lignes rejetées avec leur raison."""
    ...
```

## Sécurité — injection de formule CSV (CSV/Excel injection)

Une cellule commençant par `=`, `+`, `-` ou `@` est interprétée comme une formule par Excel/LibreOffice si le contenu est un jour ré-exporté en CSV et ouvert tel quel — un champ texte libre importé (ex: "nom d'entreprise") peut contenir une formule malveillante (`=cmd|'/c calc'!A1`) qui s'exécute à l'ouverture chez un autre utilisateur.

```python
def sanitize_for_export(value: str) -> str:
    """Neutralise les formules avant un export CSV — préfixer d'une quote bloque l'interprétation Excel."""
    if value and value[0] in ("=", "+", "-", "@"):
        return f"'{value}"
    return value
```

Appliquer cette neutralisation à l'**export**, pas à l'import — les données doivent rester fidèles en base ; le risque n'existe qu'au moment où elles ressortent dans un fichier ouvert par un tableur.

## Anti-patterns

```python
# ❌ — charge tout le fichier en mémoire, plante sur un gros CSV
content = await file.read()
rows = content.decode().splitlines()

# ✅ — streaming ligne par ligne
async for row in parse_csv_rows(file, delimiter):
    ...

# ❌ — délimiteur figé en dur, casse sur tout fichier exporté avec un autre séparateur
reader = csv.DictReader(wrapper)   # délimiteur par défaut "," non négociable

# ❌ — mapping par position de colonne, cassé dès que l'ordre change
nom = row[0]
siren = row[1]

# ❌ — dédoublonnage codé en dur sans vérifier la spec
existing = await db.scalar(select(Entreprise).where(Entreprise.siren == siren))
if existing:
    return  # silencieusement ignoré — upsert ou reject ? jamais précisé

# ❌ — commit à chaque ligne
for row in rows:
    db.add(Entreprise(**row))
    await db.commit()   # lent, et perd toute transaction de lot
```

## Règles

- Le délimiteur est toujours un paramètre fourni à chaque import (défaut raisonnable `,`, jamais figé en dur) — un export Excel français utilise typiquement `;`
- Le mapping de colonnes est toujours explicite (fourni par l'utilisateur ou un template sauvegardé) — jamais déduit de la position ou de l'ordre des colonnes
- La stratégie de dédoublonnage (`upsert` vs `reject`) vient de `spec-final.md` — ne jamais la choisir par défaut sans qu'elle soit explicite dans une FR-xxx
- Toujours streamer la lecture du fichier — ne jamais le charger intégralement en mémoire
- Toujours produire un rapport d'erreurs ligne par ligne (numéro + raison), jamais un échec global silencieux
- Le seuil sync/async est une variable d'environnement (`csv_async_threshold_rows`), jamais une valeur en dur
- Neutraliser les formules (`=`,`+`,`-`,`@`) à l'export, pas à l'import — préserver la donnée brute en base
