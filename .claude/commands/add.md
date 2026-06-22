# /add — Ajout d'une fonctionnalité sur du code existant

## Objectif

Ajouter une fonctionnalité à un projet existant en mode **delta** : identifier précisément ce qui doit être créé ou modifié, présenter ce plan à l'utilisateur, puis implémenter uniquement ce delta. Ne jamais toucher ce qui n'est pas dans le périmètre.

## Processus

### Étape 1 — Lire la demande

Lire la description de la fonctionnalité fournie par l'utilisateur.

Si le périmètre est flou, poser **au maximum 3 questions** avant de continuer :
1. Quel est le comportement attendu ?
2. Quels utilisateurs / rôles sont concernés ?
3. Y a-t-il des contraintes techniques imposées ?

### Étape 2 — Lire l'existant

1. Lire `spec-final.md` pour comprendre le périmètre déjà implémenté, et relever le plus grand identifiant existant pour chaque préfixe (FR-xxx, NFR-xxx, AC-xxx, EC-xxx)
2. Lire la structure du projet (répertoires et fichiers)
3. Lire les fichiers les plus susceptibles d'être impactés
4. Identifier les conventions en place : nommage, patterns, style

L'objectif est de comprendre **comment le projet est structuré** pour s'y intégrer sans rupture de cohérence.

### Étape 3 — Définir le delta

Lister explicitement avant d'implémenter :

```
Fichiers à créer :
- services/xxx_service.py
- api/xxx.py
- tests/test_xxx.py

Fichiers à modifier :
- main.py  (ajouter le router)
- models/user.py  (ajouter le champ xxx)
- migrations/  (nouvelle migration Alembic)

Fichiers à ne pas toucher :
- [tout le reste]
```

**Présenter ce delta à l'utilisateur et attendre confirmation avant d'implémenter.**

Si une modification "incidente" semble nécessaire sur un fichier hors delta (ex : corriger un bug découvert en chemin), la signaler et demander confirmation séparément — ne pas la faire silencieusement.

### Étape 4 — Charger les skills

Charger uniquement les skills pertinents pour le delta identifié. Toujours charger `skills/security/`.

Si la fonctionnalité à ajouter utilise une stack différente de l'existant (ex : ajout d'un agent LangGraph dans une API FastAPI pure), charger les skills correspondants et signaler la dépendance nouvelle.

### Étape 5 — Implémenter le delta

Créer et modifier uniquement les fichiers listés à l'étape 3, dans cet ordre :

1. Modèles (si nouveau champ ou table)
2. Migration Alembic (si changement de schéma)
3. Schémas Pydantic
4. Service(s)
5. Routes API
6. Enregistrement du router dans `main.py`
7. Tests

Respecter le style du code existant — ne pas imposer les conventions des skills si elles divergent de ce qui est déjà en place. La cohérence avec l'existant prime sur la pureté des conventions.

### Étape 6 — Finaliser

1. Créer les tests pour le code ajouté, dérivés des nouveaux AC-xxx/EC-xxx (voir étape 3 ci-dessous)
2. Mettre à jour `spec-final.md` :
   - Ajouter les nouvelles exigences dans "Exigences fonctionnelles" en continuant la numérotation FR-xxx (jamais de réutilisation ou de redémarrage à FR-001)
   - Ajouter les nouvelles exigences non-fonctionnelles dans "Exigences non-fonctionnelles" en continuant NFR-xxx, si le delta en introduit
   - Ajouter les nouveaux scénarios dans "Scénarios d'acceptation" (AC-xxx) et les nouveaux cas limites dans "Edge cases" (EC-xxx), même règle de numérotation continue
   - Ajouter les nouvelles entités dans "Entités métier"
3. Mettre à jour `.env.example` si de nouvelles variables d'environnement ont été ajoutées

## Règles

- Ne jamais modifier un fichier hors du delta validé sans confirmation
- Ne pas ajouter de dépendances sans signaler l'impact sur `pyproject.toml` / `package.json`
- Les identifiants FR-xxx, NFR-xxx, AC-xxx, EC-xxx sont permanents : ne jamais réutiliser un numéro déjà attribué, même si l'exigence correspondante a été retirée entre-temps
- Un ajout multi-tenant doit systématiquement inclure `org_id` sur les nouvelles tables et `get_current_tenant` sur les nouvelles routes
- Si la fonctionnalité demandée chevauche une fonctionnalité existante, signaler le risque de duplication avant d'implémenter
