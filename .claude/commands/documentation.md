# /documentation — Documentation pour humains et assistants IA

## Objectif

Produire une documentation à deux niveaux :
- **Niveau humain** : vue d'ensemble, architecture, décisions
- **Niveau IA** : contrats locaux, types, comportements attendus — pour que tout assistant de code comprenne le projet sans lire chaque implémentation

## Processus

### Étape 1 — Analyser le projet

Lire :
- `spec-final.md` si présent
- `core/settings.py` — variables de configuration
- `app/main.py` — structure de l'application
- Tous les fichiers `api/` — routes et contrats
- Tous les fichiers `services/` — logique métier
- Tous les fichiers `models/` — entités

### Étape 2 — CODEBASE.md (documentation IA)

Générer `CODEBASE.md` à la racine. Ce fichier est conçu pour être chargé en contexte par un assistant de code qui découvre le projet.

```markdown
# Carte du projet — [Nom]

## Architecture en une phrase
[Ex: API FastAPI + PostgreSQL exposant une boutique e-commerce avec paiement Stripe]

## Modules principaux

| Module | Rôle | Fichiers clés |
|---|---|---|
| `app/api/` | Routes HTTP — orchestration uniquement, max 20 lignes par route | `auth.py`, `orders.py` |
| `app/services/` | Logique métier — toute décision ici, jamais dans les routes | `order_service.py` |
| `app/models/` | Tables SQLAlchemy | `user.py`, `order.py` |
| `app/schemas/` | Contrats Pydantic entrée/sortie | `order.py` (Create/Update/Response) |
| `core/settings.py` | Configuration centralisée (BaseSettings) | — |

## Entités et relations
[Diagramme texte ou liste des relations clés]
User → Order (1-N)
Order → OrderItem (1-N)
Product → OrderItem (1-N)

## Flux métier critiques
[Reprendre les flux du blueprint — ex: création commande en 8 étapes]

## Patterns à respecter

- Routes : `Depends(get_current_user)` sur toutes les routes authentifiées
- Services : retournent des objets métier, lèvent `HTTPException` pour les erreurs connues
- Config : toute valeur configurable dans `core/settings.py`, jamais hardcodée
- Tests : chaque test est isolé, rollback DB après chaque test

## Variables d'environnement requises
[Tableau: Variable | Type | Requis | Usage]
```

### Étape 3 — FILE_LINKS.md (cartographie des liens entre fichiers)

Générer `FILE_LINKS.md` à la racine : une cartographie de tous les liens entre fichiers **du code applicatif** (le périmètre du projet, pas de ses dépendances), quelle que soit la nature du lien.

**Exclusion explicite** : ne jamais lister de fichier appartenant à une librairie externe (`node_modules/`, `.venv/`/`site-packages/`, packages installés via `pyproject.toml`/`package.json`). Seuls les fichiers écrits pour ce projet apparaissent dans la cartographie ; un appel vers une librairie externe reste implicite dans le lien (ex: "appelle Stripe SDK"), sans créer d'entrée pour les fichiers de la librairie elle-même.

**Liens directs** — un fichier appelle/importe explicitement un autre fichier du projet dans le code (import Python/TS, appel de fonction, extends/implements, injection de dépendance).

**Liens indirects** — deux fichiers du projet sont couplés sans s'appeler directement dans le code :
- Route backend ↔ appel frontend (ex: route `POST /orders` dans `api/orders.py` ↔ page qui la fetch dans `frontend/app/orders/page.tsx`) — c'est le lien principal entre backend et frontend
- Composant partagé (ex: plusieurs pages qui utilisent le même composant)
- Schéma/type partagé (ex: un schéma Pydantic dont la forme est dupliquée côté frontend dans un type TypeScript)
- Table/entité de données partagée entre plusieurs services (ex: deux services qui lisent/écrivent la même table sans s'appeler entre eux)
- Événement/webhook (ex: un service déclenche un événement consommé par un autre)
- Job planifié ou script qui touche un fichier sans en dépendre dans le flux principal

Format :

```markdown
# Cartographie des liens — [Nom du projet]

## Liens directs

| Fichier source | Fichier cible | Nature du lien |
|---|---|---|
| `api/orders.py` | `services/order_service.py` | appelle `create_order()` |
| `services/order_service.py` | `models/order.py` | manipule le modèle `Order` |

## Liens indirects

| Fichier A | Fichier B | Nature du lien |
|---|---|---|
| `api/orders.py` (`POST /orders`) | `frontend/app/orders/page.tsx` | route consommée par cette page |
| `frontend/components/OrderTable.tsx` | `frontend/app/orders/page.tsx`, `frontend/app/admin/orders/page.tsx` | composant partagé |
| `schemas/order.py` (`OrderResponse`) | `frontend/types/order.ts` | contrat de donnée dupliqué |
| `services/order_service.py` | `services/report_service.py` | table `orders` partagée |
```

Ne pas viser l'exhaustivité au fichier près pour les fichiers du projet sans logique propre (config vide, `__init__.py` vide) — se concentrer sur les liens dont la rupture aurait un impact réel.

Ce fichier est ensuite utilisé comme point de départ par `/add` et `/fix` pour repérer les impacts indirects d'une modification (voir ces commandes) — le tenir à jour lui donne de la valeur dans la durée, un fichier obsolète est pire qu'absent.

### Étape 4 — Docstrings des fonctions publiques

Parcourir tous les fichiers `services/` et `api/`. Pour chaque fonction publique sans docstring :

Ajouter une docstring décrivant :
1. Ce que la fonction fait (une phrase)
2. Les paramètres non évidents (type + signification)
3. Ce qu'elle retourne
4. Les exceptions qu'elle peut lever

```python
async def create_order(db: AsyncSession, data: OrderCreate, user: User) -> Order:
    """
    Crée une commande, réserve le stock et initie le paiement.

    Lève ValueError si le stock est insuffisant.
    Lève HTTPException(402) si Stripe refuse le paiement.
    """
```

### Étape 5 — README.md (documentation humaine)

Générer ou compléter `README.md` orienté développeur humain :
- Contexte et objectif du projet
- Guide d'installation en 5 minutes
- Architecture de haut niveau
- Comment lancer les tests
- Comment contribuer

Voir `/doc` pour le format détaillé du README.

### Étape 6 — Rapport

À la fin, afficher :
```
CODEBASE.md    créé (XX lignes) — pour assistants IA
FILE_LINKS.md  créé (XX liens directs, XX liens indirects)
README.md      créé/mis à jour
Docstrings ajoutées : XX fonctions dans services/
Docstrings manquantes restantes : XX (optionnel)
```

## Différence avec /doc

| `/doc` | `/documentation` |
|---|---|
| README + API reference | README + CODEBASE.md + FILE_LINKS.md + docstrings |
| Orienté utilisateur final | Orienté développeur + assistant IA |
| Rapide | Plus exhaustif |
