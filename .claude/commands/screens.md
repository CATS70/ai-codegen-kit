# /screens — Description des écrans de l'application

## Objectif

Décomposer `spec-final.md` en une liste concrète des écrans de l'application (un écran = un ou plusieurs FR-xxx pour un rôle humain donné), la présenter à l'utilisateur pour validation explicite et correction, puis générer `screens-final.md` — le contrat que `/implement` DOIT suivre pour construire le frontend, et la référence utilisée pour vérifier après coup que rien n'a été oublié.

Contrairement à `/spec` (boucle de questions sur des zones d'ombre), `/screens` part d'une spec déjà validée et complète — il n'y a pas d'ambiguïté à résoudre, seulement un découpage à proposer puis à faire valider ou corriger par l'utilisateur.

## Processus

### Étape 1 — Lire la spec

Lire `spec-final.md`. Si absent, stopper et demander d'exécuter `/spec` d'abord.

### Étape 2 — Identifier les FR-xxx nécessitant un écran

Reprendre la classification par acteur de `## Utilisateurs et rôles` (la même que celle qu'utilise `/implement`, étape 4 — "Couverture frontend par FR-xxx") :

- **Acteur = rôle humain** (Utilisateur, Admin...) : nécessite un écran.
- **Acteur = système externe** (API tierce, client externe type extension navigateur) : aucun écran à prévoir, exclu de la suite.

Si une FR-xxx énumère plusieurs cibles (cf règle d'atomicité de `/spec`), elle a normalement déjà été scindée en plusieurs FR-xxx distinctes à ce stade — si ce n'est pas le cas (spec antérieure à cette règle), traiter chaque cible séparément ici malgré tout.

### Étape 3 — Regrouper les FR-xxx en écrans

Un écran peut couvrir plusieurs FR-xxx (ex: une page "Objectifs" couvre la création, la liste et le tableau de bord). Une FR-xxx peut nécessiter plusieurs écrans (ex: liste + détail). Décrire ce découpage explicitement, pour chaque écran :

| Champ | Contenu |
|---|---|
| Écran | Nom convivial (ex: "Tableau de bord d'un objectif") |
| Route | Chemin frontend (ex: `/objectifs/[id]`) |
| Rôle(s) | Qui y a accès |
| FR-xxx couvertes | Liste des identifiants |
| Objectif | Une phrase |
| Éléments clés | Formulaires, tableaux triables/filtrables (avec leurs colonnes), boutons d'action, modales... |
| Navigation | D'où on y arrive, vers où on peut aller depuis cet écran |
| États particuliers | Vide / chargement / erreur, uniquement si un AC-xxx ou EC-xxx de la spec l'exige explicitement — sinon "standard" |

### Étape 4 — Présenter pour validation

Afficher le tableau complet des écrans à l'utilisateur et demander explicitement :

> "Validez-vous ce découpage en écrans, ou souhaitez-vous des corrections (ajout, suppression, fusion ou découpage d'un écran, ajustement des éléments listés) ?"

Itérer sans limite de tours tant que l'utilisateur demande des corrections — ce n'est pas une boucle de questions sur des inconnues comme `/spec`, mais une boucle de relecture/correction d'un document déjà complet. Ne jamais générer `screens-final.md` sans validation explicite ("oui"/"valide"/"ok" ou équivalent) — pas d'auto-validation silencieuse ici, contrairement à l'auto-validation de `/spec` : c'est un choix délibéré, l'utilisateur veut un vrai point d'arrêt humain sur ce document avant que `/implement` ne s'en empare comme contrat.

### Étape 5 — Générer screens-final.md

Une fois validé, écrire `screens-final.md` :

```markdown
# Écrans — [Nom du projet]

## [Nom de l'écran]
- Route : `/chemin/[param]`
- Rôle(s) : ...
- FR-xxx couvertes : FR-00X, FR-00Y
- Objectif : ...
- Éléments clés : ...
- Navigation : ...
- États particuliers : ...

## ...

## Couverture FR-xxx
| FR-xxx | Écran(s) | Couvert |
|---|---|---|
| FR-00X | Nom de l'écran | ✅ |
```

### Étape 6 — Rapport de complétion

Rapporter à l'utilisateur :
- Chemin de `screens-final.md`
- Nombre d'écrans générés
- Toute FR-xxx à acteur humain qui n'apparaît dans aucun écran — cas bloquant, à corriger avant de continuer (jamais de FR-xxx humaine orpheline dans ce document)

## Règles

- `screens-final.md` n'est généré qu'après validation humaine explicite — jamais par auto-validation silencieuse
- Chaque écran référence au moins une FR-xxx ; chaque FR-xxx à acteur humain de `spec-final.md` doit apparaître dans au moins un écran
- Ne jamais inclure les FR-xxx dont l'acteur est un système externe — ces FR-xxx n'ont pas d'écran par définition
- `/implement` lit ce fichier s'il existe et construit le frontend en suivant exactement les écrans décrits — voir la règle correspondante dans `implement.md`
