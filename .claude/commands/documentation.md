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

### Étape 3 — Docstrings des fonctions publiques

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

### Étape 4 — README.md (documentation humaine)

Générer ou compléter `README.md` orienté développeur humain :
- Contexte et objectif du projet
- Guide d'installation en 5 minutes
- Architecture de haut niveau
- Comment lancer les tests
- Comment contribuer

Voir `/doc` pour le format détaillé du README.

### Étape 5 — Rapport

À la fin, afficher :
```
CODEBASE.md         créé (XX lignes) — pour assistants IA
README.md           créé/mis à jour
Docstrings ajoutées : XX fonctions dans services/
Docstrings manquantes restantes : XX (optionnel)
```

## Différence avec /doc

| `/doc` | `/documentation` |
|---|---|
| README + API reference | README + CODEBASE.md + docstrings |
| Orienté utilisateur final | Orienté développeur + assistant IA |
| Rapide | Plus exhaustif |
