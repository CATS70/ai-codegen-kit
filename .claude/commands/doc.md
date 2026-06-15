# /doc — Génération de documentation technique

## Objectif

Générer la documentation technique du projet : README principal, documentation des modules et référence API.

## Processus

### Étape 1 — Inventaire du projet

Analyser la structure du projet :
- Lire `spec-final.md` si présent (titre, résumé, fonctionnalités)
- Lister les modules principaux (`api/`, `services/`, `models/`)
- Détecter le framework (FastAPI, Next.js, ou les deux)

### Étape 2 — README.md principal

Générer ou mettre à jour `README.md` à la racine avec :

```markdown
# [Nom du projet]

[Résumé en 2-3 phrases]

## Fonctionnalités

- [Fonctionnalité 1]
- [Fonctionnalité 2]

## Stack technique

- Backend : FastAPI, SQLAlchemy, Pydantic
- Frontend : Next.js (si applicable)
- Base de données : PostgreSQL

## Installation

### Prérequis
- Python 3.12+
- PostgreSQL 16+
- Node.js 20+ (si frontend)

### Configuration

cp .env.example .env
# Remplir les variables dans .env

### Lancement en développement

docker-compose up
# ou
uvicorn app.main:app --reload

### Tests

pytest --cov=app

## Structure du projet

[Arborescence des dossiers clés avec une ligne d'explication par dossier]

## Variables d'environnement

[Tableau : Variable | Description | Requis | Défaut]
```

### Étape 3 — Documentation des modules

Pour chaque fichier dans `services/` :
- Vérifier que chaque fonction publique a une docstring
- Ajouter les docstrings manquantes (paramètres, retour, exceptions si non évidents)
- Ne pas paraphraser le code — documenter le contrat et l'intention

### Étape 4 — Référence API FastAPI

FastAPI génère automatiquement `/docs` (Swagger). Vérifier que :
- Chaque route a une docstring courte (elle apparaît dans Swagger)
- Les `response_model` sont déclarés sur toutes les routes
- Les tags sont cohérents (ils groupent les routes dans Swagger)

Si le projet n'est pas lancé, générer un fichier `API.md` avec le résumé des endpoints :

```markdown
# Référence API

## Auth
POST /auth/login       — Authentification, retourne access + refresh tokens
POST /auth/refresh     — Renouvelle l'access token
POST /auth/register    — Création de compte

## Users
GET  /users/           — Liste des utilisateurs (paginée)
GET  /users/{id}       — Détail d'un utilisateur
PUT  /users/{id}       — Mise à jour du profil
```

### Étape 5 — Variables d'environnement

Vérifier que `.env.example` est complet et à jour avec toutes les variables définies dans `core/settings.py`.

## Règles

- Ne jamais écraser un README existant sans lire son contenu d'abord
- Docstrings en français si le projet est en français, en anglais sinon — suivre la langue existante
- Ne pas documenter l'évident — documenter le contrat, pas l'implémentation
