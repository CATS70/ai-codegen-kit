# /retro-doc — Rétro-documentation d'un codebase existant

## Objectif

Partir d'un codebase déjà écrit (avec une documentation partielle, obsolète, ou totalement absente), la comparer à l'état réel du code, **mettre à jour** ce qui a dérivé et **générer** ce qui manque — pour que la chaîne du kit (`/add`, `/fix`, `/check-spec`, `/security-audit`, et un futur `/implement` en extension) dispose des mêmes fichiers de référence que si le projet était né avec `/spec` → `/screens` → `/implement`.

`/retro-doc` ne modifie jamais le code — lecture seule sur le code applicatif, écriture uniquement sur les fichiers de documentation.

## Quand l'utiliser

- Codebase repris tel quel (legacy, généré hors du kit, ou dont la doc n'a jamais été maintenue)
- Documentation existante mais code qui a dérivé depuis (fonctionnalités ajoutées sans mise à jour de `spec-final.md`, écrans modifiés sans repasser par `/screens`)
- Avant d'utiliser `/add`, `/fix`, `/check-spec` ou `/security-audit` sur un projet qui n'a pas cette base
- Codebase qui ne suit **pas** l'arborescence type FastAPI/Next.js du kit (autre framework, autre convention de dossiers, monorepo atypique) — voir étape 0

## Processus

### Étape 0 — Découvrir la structure réelle du projet

Ne jamais présupposer une arborescence (`app/`, `services/`, `frontend/app/`...) avant de l'avoir observée : le kit cible Python/TypeScript mais le codebase repris peut suivre d'autres conventions (Django, Express, monorepo, autre langage). Scanner d'abord, proposer ensuite.

1. Identifier le ou les langages/frameworks présents via leurs fichiers manifestes : `pyproject.toml`/`requirements.txt` (+ `manage.py` → Django, présence de `fastapi`/`flask` dans les dépendances), `package.json` (+ `next.config.*` → Next.js, sinon React/Express/autre), `go.mod`, `Gemfile`, etc.
2. Repérer par sondage (pas d'hypothèse de nom de dossier) où vivent réellement : les points d'entrée HTTP/routes, la logique métier, les modèles/entités de données, les pages/vues frontend si un frontend existe, les tests, les fichiers de configuration/variables d'environnement. S'appuyer sur le contenu (imports, décorateurs de route, définitions de classes de modèle) plutôt que sur des noms de dossier attendus.
3. Si `FILE_LINKS.md` ou `CODEBASE.md` existent déjà (voir étape 1), les utiliser comme point de départ de cette découverte plutôt que de repartir de zéro.
4. Présenter le mapping détecté à l'utilisateur avant de continuer :

```markdown
## Structure détectée

| Rôle | Emplacement(s) trouvé(s) | Confiance |
|---|---|---|
| Routes / API | `src/routes/*.js` | Haute |
| Logique métier | `src/controllers/*.js` | Moyenne — mélangée aux routes par endroits |
| Modèles de données | `src/models/*.js` (Mongoose) | Haute |
| Frontend | (aucun détecté) | — |
| Tests | `test/*.spec.js` | Haute |
| Configuration | `.env`, `src/config.js` | Haute |

Ce mapping vous semble-t-il correct, ou faut-il le corriger avant de continuer ?
```

Ne jamais passer à l'étape 2 sans confirmation explicite sur ce mapping — une mauvaise cartographie de départ fausse silencieusement tout ce qui suit (FR-xxx manquantes parce qu'un dossier de routes n'a pas été repéré, etc.). Si l'utilisateur corrige, réutiliser sa correction pour toute la suite de la commande, y compris un futur `/add`/`/fix` qui pourrait s'appuyer sur `FILE_LINKS.md` généré ici.

### Étape 1 — Inventaire de la documentation existante

Chercher à la racine du projet (et dans les emplacements usuels si absents à la racine du projet) : `spec.md`, `spec-final.md`, `screens-final.md`, `CODEBASE.md`, `FILE_LINKS.md`, `README.md`, `API.md`, un fichier d'exemple de variables d'environnement (`.env.example` ou équivalent détecté à l'étape 0).

Pour chaque fichier trouvé, relever sa dernière modification (`git log -1 --format=%ad -- <fichier>`) et la comparer à la dernière modification du code applicatif (emplacements validés à l'étape 0). Un signal de fraîcheur brut, pas une preuve : un fichier récent peut être obsolète si le code a changé sans que la doc suive.

### Étape 2 — Cartographier le codebase réel

En s'appuyant sur le mapping validé à l'étape 0 :

- **Routes/points d'entrée** : chemin, méthode, fonction/handler
- **Logique métier** : modules identifiés, quelle que soit leur convention de nommage locale
- **Modèles/entités de données**
- **Tâches planifiées / jobs asynchrones** si détectés (recherche par contenu : bibliothèques de queue/cron/scheduler utilisées, quel que soit le langage)
- **Frontend** (si détecté à l'étape 0) : pages/vues, composants partagés référencés depuis plusieurs pages
- **Tests** : noms de fonctions/cas, identifiants `AC-`/`EC-`/`NFR-` déjà présents en commentaire le cas échéant (un codebase legacy n'en a généralement aucun)
- **Configuration réelle** : variables lues effectivement par le code (recherche par contenu : accès à l'environnement, quel que soit le mécanisme du langage/framework) — comparer à l'exemple de configuration s'il existe
- **Intégrations externes détectées** : imports de SDK/bibliothèques tierces, appels vers un domaine externe en dur — chaque intégration détectée est un candidat direct à une entrée `## Intégrations externes` de `spec-final.md`

Ce recensement est la matière première de toutes les étapes suivantes — ne pas le refaire à chaque étape, le réutiliser.

### Étape 3 — Reconstruire ou mettre à jour `spec-final.md`

**Cas A — absent.** Générer un brouillon à partir du seul code (étape 2) :
- Une FR-xxx par route/cas d'usage identifié dans le code (regrouper les routes CRUD d'une même ressource sous des FR-xxx distinctes par action si leur comportement diverge, sinon une FR-xxx par ressource)
- Un AC-xxx par test qui passe et couvre un flux nominal ; un EC-xxx par test qui couvre une erreur/un rejet
- `## Entités métier` déduites des modèles
- `## Intégrations externes` déduites des SDK détectés

**Cas B — présent.** Lire le fichier en entier, puis appliquer la logique de `/check-spec` étape 3 (couverture FR-xxx) en sens inverse — un diff entre le texte existant et l'état réel du code, jamais un écrasement direct :
- FR-xxx documentée mais introuvable dans le code → ne jamais supprimer l'entrée ; la marquer `[Retirée]` en fin de ligne et demander confirmation à l'utilisateur avant de la considérer close
- Code (route/service) sans FR-xxx correspondante → proposer une nouvelle FR-xxx avec un **nouvel identifiant** (jamais réutiliser un numéro existant, même retiré — même règle que `/spec`/`/add`)
- FR-xxx existante dont le comportement code a divergé du texte → signaler l'écart, ne jamais réécrire silencieusement le texte de la FR-xxx sans le signaler dans le rapport final
- FR-xxx existante toujours conforme au code → laissée telle quelle

**Dans les deux cas, ce qui n'est jamais déduit du code** (même règle que `/spec` catégories 1, 4 et 9 — voir `spec.md`) reste posé à l'utilisateur, une question à la fois :
- Les rôles humains réels (le code peut révéler des routes protégées par rôle, mais pas l'intention produit derrière)
- Les NFR — charge attendue, exigences de sécurité/conformité au-delà de ce qui est déjà codé, disponibilité visée
- `## Hors périmètre` — ne peut jamais être déduit du code, qui ne montre que ce qui existe
- `## Configuration environnement` — venv/runtime, base de données

Ce qui **peut** être proposé comme hypothèse par défaut à valider (pas de question bloquante) : une NFR "reflet" quand une mesure technique est déjà présente dans le code (ex: hashing de mot de passe trouvé dans le module d'authentification → proposer `NFR-xxx: Sécurité — mots de passe hashés` déjà "acquise", à confirmer plutôt qu'à décider).

Tant que les questions ci-dessus n'ont pas de réponse, `spec-final.md` porte l'en-tête :
```
> ⚠️ Généré par `/retro-doc` à partir du code existant le [date] — NFR/rôles/hors-périmètre non confirmés, ne pas encore utiliser comme entrée de `/implement` ou `/check-spec`.
```
Retirer cet en-tête uniquement une fois toutes les questions bloquantes résolues.

### Étape 4 — Reconstruire ou mettre à jour `screens-final.md`

Ne s'applique que si `## Utilisateurs et rôles` de l'étape 3 contient au moins un rôle humain **et** qu'un frontend a été détecté à l'étape 0.

**Cas A — absent.** Parcourir les pages/vues réelles (emplacement validé à l'étape 0) :
- Layout(s) déduits des éléments de mise en page partagés trouvés (header, navigation — lire le contenu réel, ne jamais deviner ce qui n'est pas présent)
- Un écran par page, route = chemin réel, éléments clés = ce qui est effectivement rendu (tableaux, colonnes, boutons d'action, formulaires)
- FR-xxx couvertes = croisement avec les appels API faits depuis la page et la table de l'étape 3
- Système de design : lire les variables/tokens de style globaux s'ils existent (feuille de style globale, thème) et les reporter tels quels — ne jamais en inventer si aucun n'est défini, signaler l'absence à la place

**Cas B — présent.** Lire le fichier en entier, puis même logique que `/check-spec` étape 6 : pour chaque écran documenté, vérifier route/éléments clés/layout contre la page réelle, signaler tout écart. Pour chaque page réelle sans entrée dans `screens-final.md`, proposer un ajout.

Comme `/screens`, **ne jamais écrire la version finale de `screens-final.md` sans validation explicite de l'utilisateur** — présenter le brouillon (ou le diff si le fichier existait déjà) et attendre "oui"/"valide" ou des corrections, en boucle sans limite de tours.

### Étape 5 — Mettre à jour `CODEBASE.md` et `FILE_LINKS.md`

Réutiliser la logique de `/documentation` étapes 2 et 3, en mode diff plutôt qu'en génération pure :
- Si absents : générer comme le ferait `/documentation`, en s'appuyant sur la structure validée à l'étape 0
- Si présents : lire l'existant en entier avant toute écriture. Régénérer les tableaux pilotés par le scan (modules, liens directs/indirects) à partir de l'étape 2 ; conserver telle quelle toute prose écrite à la main qui n'est pas dérivable du scan (ex: "Architecture en une phrase", "Flux métier critiques") sauf si elle référence un fichier qui n'existe plus, auquel cas le signaler dans le rapport plutôt que de la supprimer silencieusement
- Retirer de `FILE_LINKS.md` les entrées dont le fichier source ou cible n'existe plus, en le signalant dans le rapport ; ajouter les liens détectés à l'étape 2 absents du fichier
- Mêmes règles d'exclusion que `/documentation` : jamais de fichier de dépendance externe (dossiers de dépendances installées, quel que soit le gestionnaire de paquets)

### Étape 6 — Mettre à jour `README.md`, `API.md`, exemple de configuration

Réutiliser la logique de `/doc` en mode diff :
- `README.md` : lire l'existant avant d'écraser (règle déjà en place dans `/doc`) ; mettre à jour uniquement les sections factuelles dérivables du code (stack, structure du projet, variables d'environnement) ; ne jamais toucher aux sections narratives (contexte, contribution) sans le signaler
- `API.md` : régénérer la liste des routes à partir de l'étape 2 si le fichier existe déjà et diverge du code
- Exemple de configuration (`.env.example` ou équivalent détecté à l'étape 0) : ajouter toute variable trouvée dans le code et absente du fichier ; signaler (sans le retirer automatiquement) toute variable présente dans le fichier mais plus référencée nulle part dans le code

### Étape 7 — Rapport de rétro-documentation

```
RÉTRO-DOCUMENTATION
====================

Structure détectée (étape 0) : [confirmée par l'utilisateur | corrigée — voir détail]

spec-final.md      [créé | mis à jour | déjà à jour]  — X FR-xxx nouvelles, Y retirées (à confirmer), Z inchangées
screens-final.md    [créé | mis à jour | déjà à jour | non applicable]  — X écrans nouveaux, Y en écart
CODEBASE.md         [créé | mis à jour | déjà à jour]
FILE_LINKS.md       [créé | mis à jour | déjà à jour]  — X liens ajoutés, Y retirés (fichier disparu)
README.md           [créé | mis à jour | déjà à jour]
API.md               [créé | mis à jour | déjà à jour | absent, non généré]
Config exemple        [mis à jour | déjà à jour]  — X variables ajoutées, Y orphelines signalées

QUESTIONS EN SUSPENS (bloquent la validation finale de spec-final.md)
----------------------------------------------------------------------
- Rôles humains à confirmer : ...
- NFR à préciser : Charge, Sécurité, ...
- Hors périmètre à définir

Statut : spec-final.md [prêt pour /implement, /check-spec | encore provisoire — voir questions ci-dessus]
```

Si aucune question ne reste en suspens et que `spec-final.md` (et `screens-final.md` s'il existe) ont été explicitement validés par l'utilisateur, retirer l'en-tête d'avertissement de l'étape 3 et le confirmer dans le rapport.

## Règles

- Ne jamais présupposer une arborescence de dossiers avant de l'avoir observée et fait valider à l'étape 0 — le kit cible Python/TypeScript mais un codebase repris peut suivre d'autres conventions
- Lecture seule sur le code applicatif — `/retro-doc` ne modifie jamais le code, quel que soit son emplacement
- Jamais de suppression silencieuse d'un identifiant FR-xxx/AC-xxx/EC-xxx/NFR-xxx existant : marquage `[Retirée]` avec confirmation utilisateur, jamais une simple disparition de la ligne
- Un identifiant retiré n'est jamais réattribué à une FR-xxx nouvellement détectée — toujours un numéro inédit, même règle que `/spec`/`/add`
- Les catégories jamais déduites de `/spec` (rôles humains, NFR, hors périmètre, configuration environnement) restent jamais déduites ici : poser la question à l'utilisateur plutôt que d'inférer une valeur plausible depuis le code — le code montre ce qui existe, jamais l'intention produit ni les limites voulues
- `screens-final.md` n'est finalisé qu'après validation humaine explicite, comme dans `/screens` — jamais d'auto-validation silencieuse
- Toujours lire un fichier de documentation existant en entier avant de le modifier ; ne jamais écraser une section de prose écrite à la main sans le signaler dans le rapport
- `spec-final.md`/`screens-final.md` générés ou mis à jour par `/retro-doc` portent l'en-tête d'avertissement tant que les questions bloquantes ne sont pas résolues — les autres commandes du kit ne doivent pas les traiter comme fiables avant cette validation
- Si le codebase est vide ou trivial (aucune route, aucun modèle détecté à l'étape 0), le signaler et recommander `/spec` directement plutôt que `/retro-doc`
