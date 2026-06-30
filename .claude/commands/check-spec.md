# /check-spec — Vérification de conformité à spec-final.md et screens-final.md

## Objectif

Vérifier que le code produit couvre bien toutes les exigences de `spec-final.md` et tous les écrans de `screens-final.md`. Produire un rapport de conformité — sans modifier le code.

## Processus

### Étape 1 — Lire les specs de référence

Lire `spec-final.md`. Si absent, stopper :
> "`spec-final.md` introuvable. Exécuter `/spec` d'abord."

Extraire :
- **Acteurs et rôles** : liste des rôles humains et des acteurs externes
- **FR-xxx** : identifiant, acteur, cible, texte court
- **AC-xxx** : identifiant, FR-xxx parent, description
- **EC-xxx** : identifiant, FR-xxx parent, description
- **NFR-xxx** : identifiant, catégorie (Sécurité, Performance, Conformité, Disponibilité, Contrainte externe), texte

Si `spec-final.md` contient au moins un rôle humain, chercher `screens-final.md`. Si absent, le signaler (non bloquant — continuer la vérification FR-xxx sans ce fichier, mais noter l'absence dans le rapport).

Si `screens-final.md` est présent, extraire :
- **Layouts** : nom, header, navigation, footer
- **Écrans** : nom, route, FR-xxx couvertes, éléments clés listés

### Étape 2 — Cartographier le code existant

#### 2a — Backend

Chercher les routes API :
```bash
find . -path "*/api/*.py" -not -path "*/node_modules/*" -not -path "*/__pycache__/*"
```

Pour chaque fichier route, relever les décorateurs (`@router.get`, `@router.post`, `@router.put`, `@router.delete`, `@router.patch`) et les noms de fonctions.

Chercher les services :
```bash
find . -path "*/services/*.py" -not -path "*/node_modules/*" -not -path "*/__pycache__/*"
```

Chercher les tests :
```bash
find . -path "*/tests/test_*.py" -not -path "*/node_modules/*"
```

Pour chaque fichier de test, relever les noms de fonctions — ceux qui contiennent `AC-` ou `EC-` sont les tests d'acceptation formels.

#### 2b — Frontend (si rôle humain dans la spec)

Chercher les pages Next.js :
```bash
find . -path "*/app/**/page.tsx" -not -path "*/node_modules/*"
```

Chercher les layouts :
```bash
find . -name "layout.tsx" -not -path "*/node_modules/*"
```

### Étape 3 — Vérifier la couverture FR-xxx

Pour chaque FR-xxx de `spec-final.md` :

**Si l'acteur est un système externe (API pure) :**
- Backend : route correspondante dans `api/` ? (grep sur le chemin ou le nom de ressource)
- Tests : au moins un test référençant les AC-xxx/EC-xxx de cette FR-xxx ?
- Frontend : non applicable

**Si l'acteur est un rôle humain :**
- Backend : route API correspondante dans `api/` ?
- Frontend : page correspondante dans `frontend/app/` ? (route issue de `screens-final.md` si disponible, sinon inférer depuis le nom de la FR-xxx)
- Tests : au moins un test ?

**FR-xxx composée** (plusieurs cibles distinctes dans son texte) : vérifier chaque cible séparément — une FR-xxx n'est Complet que si *toutes* ses cibles sont couvertes. Ne jamais cocher Complet sur la base des seuls tests passants ; relire le code lui-même pour chaque cible.

Statuts :
- ✅ **Complet** — backend + frontend (si humain) + test tous présents
- ⚠️ **Partiel** — certains éléments présents, d'autres manquants (préciser)
- ❌ **Absent** — aucune implémentation trouvée

### Étape 4 — Vérifier la couverture AC-xxx / EC-xxx

Pour chaque AC-xxx et EC-xxx de `spec-final.md`, chercher dans les fichiers de test une fonction dont le nom ou un commentaire inline contient l'identifiant :

```bash
grep -rn "AC-[0-9]\+\|EC-[0-9]\+" tests/
```

Statut par identifiant : ✅ couvert / ❌ absent.

Si un AC-xxx ou EC-xxx ne peut pas être testé directement (dépendance externe non mockable, scénario UI pur), vérifier s'il est couvert par un test Playwright dans `tests/e2e/` ou documenté explicitement en commentaire dans le test le plus proche.

### Étape 5 — Vérifier les NFR-xxx

Pour chaque NFR-xxx, appliquer la règle selon sa catégorie :

| Catégorie | Ce qu'on vérifie | Résultat attendu |
|---|---|---|
| Sécurité / Conformité | Présence d'un test direct référençant la NFR-xxx | Test trouvé ✅ ou absent ❌ |
| Performance | Application d'une mesure technique (index dans les migrations, clé Redis dans le service) — pas de timing dans les tests | Mesure présente ✅ ou absente ❌ |
| Disponibilité | Un EC-xxx couvrant la panne correspondante a un test (issu de l'étape 4) | Couvert ✅ par EC-xxx ou test de résilience dédié, sinon ❌ |
| Contrainte externe | Signalée ou implémentée — chercher dans les commentaires, le README, ou le code | Signalée/implémentée ✅ ou sans trace ❌ |

```bash
grep -rn "NFR-[0-9]\+" tests/ app/ backend/
```

Signaler si des assertions de timing (`assert elapsed`, `time.time()`) existent dans les tests pour couvrir une NFR Performance — ce pattern est invalide (flaky en CI) et doit être signalé.

### Étape 6 — Vérifier la conformité des écrans (si screens-final.md)

Pour chaque écran décrit dans `screens-final.md` :

1. **Route existe ?** — chercher `frontend/app/<route>/page.tsx` (ou l'équivalent selon la structure du projet)
2. **Éléments clés présents ?** — pour chaque élément listé (formulaire, tableau, bouton, modale...), grep sur les mots-clés attendus dans le composant ou la page
3. **Layout appliqué ?** — vérifier que le `layout.tsx` parent de la route correspond au layout décrit

Exemple pour un écran "Tableau des objectifs" avec les éléments clés "tableau trié par statut, bouton Créer" :
```bash
grep -n "statut\|Créer\|DataTable\|<table" frontend/app/objectifs/page.tsx
```

Ne jamais déclarer un écran conforme si la page est vide ou ne contient que le squelette (`return null`, `// TODO`).

### Étape 7 — Rapport de conformité

Produire les tableaux suivants, puis la synthèse.

#### Tableau FR-xxx

Même format que le rapport de `/implement` étape 8 — pour pouvoir comparer directement.

| FR-xxx | Cible | Acteur | Backend | Frontend | Tests AC/EC | Statut |
|---|---|---|---|---|---|---|
| FR-001 | — | Utilisateur | ✅ `api/users.py` | ✅ `app/users/page.tsx` | ✅ AC-001, EC-002 | Complet |
| FR-003 | Entreprises | Admin | ✅ `api/companies.py` | ❌ absent | ⚠️ AC-007 absent | **Incomplet** |
| FR-005 | — | Système externe | ✅ `api/webhooks.py` | — (non applicable) | ✅ AC-010 | Complet |

#### Tableau des écrans (si screens-final.md)

| Écran | Route attendue | Fichier | Éléments clés | Statut |
|---|---|---|---|---|
| Tableau de bord | `/dashboard` | ✅ `app/dashboard/page.tsx` | ✅ tous présents | Conforme |
| Import CSV | `/import` | ❌ absent | — | **Absent** |
| Détail objectif | `/objectifs/[id]` | ✅ présent | ⚠️ bouton "Archiver" absent | **Non conforme** |

#### Synthèse

```
RAPPORT DE CONFORMITÉ
=====================

FR-xxx  : X/Y complètes  (Z partielles, W absentes)
Tests   : X/Y AC-xxx couverts  |  X/Y EC-xxx couverts
NFR     : X/Y Sécurité/Conformité avec test direct
Écrans  : X/Y conformes  (si screens-final.md présent)

ACTIONS REQUISES
----------------
- FR-00X [cible Tâches] : service absent de services/tasks.py
- AC-0XX : aucun test trouvé dans tests/
- Écran [Import CSV] : fichier app/import/page.tsx manquant
- NFR-00X [Sécurité] : aucun test direct trouvé
```

Si tout est conforme, le confirmer explicitement :
> "L'implémentation couvre l'intégralité de `spec-final.md` [et `screens-final.md`]. Aucune action requise."

## Règles

- **Lecture seule** — ne jamais modifier le code lors de cette vérification
- Une FR-xxx n'est **Complet** que si backend + frontend (si acteur humain) + au moins un test sont tous présents
- Une FR-xxx composée (plusieurs cibles dans son texte) est vérifiée cible par cible — jamais globalement
- Un test passant ne prouve pas qu'une cible est implémentée : lire le code lui-même pour chaque cible
- Si `screens-final.md` est absent alors que des rôles humains existent dans la spec : signaler l'absence dans le rapport, ne pas bloquer
- Les assertions de timing dans les tests (`assert elapsed < 2`) ne couvrent pas une NFR Performance — les signaler comme anti-pattern si elles existent
- Utiliser le même format de rapport que `/implement` étape 8 pour permettre la comparaison directe
