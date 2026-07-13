# /fix — Correction ciblée d'un bug

## Objectif

Localiser et corriger un bug dans le code existant. Ne pas refactorer, ne pas ajouter de fonctionnalités — un fix = une cause racine = une correction minimale.

Deux chemins selon l'ambiguïté du bug : un **chemin rapide** quand la cause est vérifiable par simple lecture du code, une **investigation complète** quand plusieurs causes restent plausibles ou que la cause dépend d'un état runtime observable seulement à l'exécution. Ne jamais corriger sur une hypothèse non vérifiée — au moindre doute sur la cause, basculer sur l'investigation complète plutôt que de deviner.

## Processus

### Étape 1 — Recueillir symptôme et comportement attendu

L'utilisateur fournit : message d'erreur, stack trace, ou description du comportement incorrect. Deux éléments sont nécessaires avant de continuer :
- **Le symptôme** : ce qui se passe concrètement
- **Le comportement attendu** : ce qui devrait se passer à la place

Si l'un des deux manque, poser **une seule question** pour l'obtenir (ex : "Dans quel fichier / quelle route / quelle action le bug se produit-il ?" ou "Qu'est-ce qui devrait se passer à la place ?"). Ne pas poser plusieurs questions — inférer ce qui peut l'être.

### Étape 2 — Localiser et reproduire

1. Identifier les fichiers concernés à partir de la description ou du stack trace
2. Lire ces fichiers entièrement
3. Remonter la chaîne d'appel si nécessaire : route → service → repository → modèle
4. Lire les tests existants liés à la zone concernée
5. Si `FILE_LINKS.md` existe (généré par `/documentation`), le consulter pour repérer d'éventuels liens indirects vers la zone concernée (route ↔ frontend, composant partagé, table partagée)
6. Décrire en 3 lignes le scénario minimal qui reproduit le bug à coup sûr. Si la reproduction n'est pas fiable, le dire et proposer un plan pour y arriver avant de continuer.

### Étape 3 — Trier : cause évidente ou ambiguë ?

Après lecture du code, déterminer laquelle des deux situations s'applique :

- **Cause évidente** : une seule explication couvre le symptôme, vérifiable par simple lecture du code, sans avoir besoin d'observer l'état runtime (faute de frappe, opérateur inversé, `await` manquant, mauvais nom de variable, off-by-one...). → **Étape 4a**.
- **Cause ambiguë** : plusieurs causes restent plausibles après lecture, ou la cause dépend de données/état runtime pour trancher (comportement intermittent, dépendant des données, concurrence, plusieurs zones candidates de l'étape 2). → **Étape 4b**.

Au moindre doute, traiter comme ambiguë — le coût d'une investigation complète inutile est bien plus faible que celui d'un fix posé sur la mauvaise cause.

### Étape 4a — Chemin rapide (cause évidente)

Formuler en une phrase : "Le bug vient de X parce que Y." Puis passer directement à l'étape 5.

### Étape 4b — Investigation complète (cause ambiguë)

Dérouler ces deux phases dans l'ordre. **S'arrêter à la fin de chacune et attendre validation explicite de l'utilisateur** avant de continuer — ne jamais proposer de fix pendant ces phases.

**Phase 1 — 3 hypothèses classées sur la cause racine.** Proposer 3 hypothèses sur la cause racine (pas le symptôme), classées de la plus probable à la moins probable. Pour chacune : l'hypothèse en 1 phrase, puis une prédiction falsifiable — "si cette hypothèse est vraie, on observerait `<observation précise>` ; si on observe l'inverse, on l'élimine."

**Phase 2 — Tester l'hypothèse #1.** Ajouter des logs ciblés pour vérifier l'hypothèse #1, préfixés par un tag `[DEBUG-xxxx]` (4 caractères aléatoires, pour un nettoyage en masse ensuite). Ne pas proposer de fix à cette phase. Dire précisément ce que l'utilisateur doit observer pour confirmer ou infirmer.

Si l'hypothèse #1 est infirmée, répéter la Phase 2 sur l'hypothèse #2, puis #3 si nécessaire.

**Règle des 3 strikes** : si les 3 hypothèses tombent, arrêter — ne pas en inventer une 4e. Ce n'est probablement plus un bug de code isolé mais un problème d'architecture ou de conception plus profond. Le signaler explicitement à l'utilisateur et proposer d'ouvrir une discussion/issue séparée plutôt que de continuer à chercher.

Une fois une hypothèse confirmée, formuler la cause racine en une phrase puis passer à l'étape 5.

### Étape 5 — Vérifier les impacts avant de corriger

- Si le fix impacte d'autres fichiers que celui identifié initialement, les lister avant de continuer.
- Si le bug concerne un champ ou une donnée d'entité, vérifier si ce champ est dupliqué ailleurs dans le code (mapping d'import/export, sérialiseur, cache, filtre de recherche) — corriger un seul endroit peut laisser le même bug actif ailleurs. Lister ces duplications même si elles restent hors du fix minimal, et signaler explicitement celles qui ne sont pas corrigées dans cette passe.
- Si le bug révèle un problème de design plus profond (mauvaise architecture, dette technique significative) : le signaler sans le corriger dans cette passe. Ouvrir une issue séparée.

### Étape 6 — Corriger

Appliquer la correction **minimale** qui résout la cause racine confirmée :

- Modifier uniquement ce qui est strictement nécessaire
- Ne pas refactorer le code environnant, même s'il pourrait être amélioré — pas d'optimisation collatérale
- Respecter le style et les conventions du code existant
- Respecter les règles de sécurité — un fix ne doit pas introduire de nouvelle vulnérabilité
- Rédiger le message de commit en expliquant la cause racine, pas le symptôme

### Étape 7 — Vérifier

1. Relire le diff final pour s'assurer qu'aucun effet de bord n'a été introduit
2. Lancer les tests existants sur les fichiers modifiés via `/test`
3. Si aucun test ne couvre le bug : créer un test minimal qui aurait détecté le problème avant le fix
4. Si `FILE_LINKS.md` existe et que le fix a modifié un lien entre fichiers (nouveau champ dupliqué, appel supprimé/ajouté), le mettre à jour
5. Si des logs `[DEBUG-xxxx]` ont été ajoutés en étape 4b, les retirer

## Règles

- Le chemin rapide (étape 4a) est réservé aux causes vérifiables par simple lecture du code — au moindre doute, basculer sur l'investigation complète (étape 4b)
- Ne jamais proposer de fix pendant les phases d'hypothèse de l'investigation complète — seulement après confirmation d'une hypothèse
- Ne jamais "améliorer" le code pendant un fix — le signaler et le traiter séparément
- Si le stack trace pointe vers une dépendance externe, vérifier d'abord si c'est une version connue pour un bug avant de modifier le code applicatif
- Un fix sur du code multi-tenant doit vérifier que l'isolation `org_id` n'est pas affectée
- Toujours vérifier qu'aucun secret n'est introduit dans le code lors de la correction
- Un fix sur un champ/une donnée dupliquée ailleurs (import, export, cache, sérialiseur) doit signaler ces duplications, même si elles ne sont pas corrigées dans cette passe (voir étape 5)
