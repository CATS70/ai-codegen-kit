# /spec — Clarification interactive et spécification structurée

## Objectif

Scanner la demande par catégorie pour ne laisser aucune zone d'ombre, poser une question à la fois avec une recommandation argumentée, produire des exigences **testables et non ambiguës** (fonctionnelles et non-fonctionnelles), valider la qualité de la spécification, puis générer `spec-final.md` prêt à être consommé par `/implement`.

## Processus

### Étape 1 — Lire ce qui existe

Chercher dans le répertoire courant :
- `spec.md` — description initiale de l'utilisateur
- `spec-final.md` — spec existante à mettre à jour

Si `spec.md` n'existe pas, demander à l'utilisateur de décrire sa demande avant de continuer.

### Étape 2 — Identification des acteurs, cas d'usage et scan par taxonomie

**2a. Identifier les acteurs**

Recenser exhaustivement, avant toute autre analyse :
- Les **rôles utilisateurs humains** — jamais déduit : si `spec.md` ne les énumère pas explicitement (même s'il n'y a vraisemblablement qu'un seul rôle), le confirmer par une question avant de poursuivre. Une mauvaise supposition implicite ici coûte bien plus qu'une question.
- Les **acteurs externes** : tout service tiers consommé par le système, et tout client externe (y compris hors périmètre, ex: une extension navigateur) qui consomme une API exposée par le système.

**2b. Énumérer les cas d'usage par acteur**

Pour chaque acteur identifié, lister ses cas d'usage dans un format structuré — pensé pour être vérifié systématiquement par un agent IA plutôt que décrit en prose libre, où un point peut être omis sans qu'on s'en rende compte :

| Acteur | Cas d'usage | Déclencheur | Donnée(s) échangée(s) | Cible identifiée comment ? | Comportement en cas d'échec |
|---|---|---|---|---|---|

- Pour un rôle humain via une interface graphique, les deux dernières colonnes sont souvent triviales — les laisser vides si non pertinentes.
- Pour un acteur externe (consommateur ou producteur d'une API), ces deux colonnes sont **obligatoires** : on doit pouvoir répondre précisément à "comment cet appelant désigne la ressource visée" et "que se passe-t-il si l'appel échoue ou que la ressource n'existe pas" — sans cela la ligne reste Manquant. C'est exactement le type de trou qu'une description en prose laisse passer (ex: une API qui reçoit une donnée sans jamais préciser comment l'appelant désigne la fiche cible).

Cette énumération est la matière première du scan par taxonomie ci-dessous : chaque case vide ou ambiguë devient un statut Partiel/Manquant pour la catégorie correspondante (1 pour les rôles, 5 pour les acteurs externes, 6 pour le comportement en cas d'échec).

**2c. Scan par taxonomie**

Passer la demande, enrichie par l'énumération ci-dessus, au crible de **toutes** les catégories suivantes. Pour chacune, déterminer un statut : **Clair** (suffisamment précis pour implémenter), **Partiel** (direction connue mais détail manquant), **Manquant** (rien n'indique la réponse).

| # | Catégorie | Ce qu'on vérifie |
|---|---|---|
| 1 | Périmètre fonctionnel | Rôles/personas explicitement identifiés *(jamais déduit — voir note ci-dessous)*, cas d'usage par rôle (issus de 2b), objectifs utilisateur, hors-périmètre explicite |
| 2 | Modèle de données | Entités, attributs, relations, règles d'unicité, cycle de vie |
| 3 | Flux UX et interaction | Parcours critiques, états d'erreur/vide/chargement |
| 4 | Exigences non-fonctionnelles | Performance, scalabilité, charge/volume d'utilisateurs simultanés, disponibilité, observabilité, sécurité/confidentialité, conformité, contraintes externes imposées (hébergement, intégration obligatoire avec un système existant) *(jamais déduit — voir note ci-dessous)* |
| 5 | Intégrations externes | Cas d'usage par acteur externe (issus de 2b) — APIs/services tiers utilisés, modes d'échec, formats d'import/export, **contrat d'identification de la cible pour tout appelant externe** |
| 6 | Edge cases et erreurs | Scénarios négatifs, rate limiting, conflits concurrents, accès non autorisé, comportement en cas d'échec pour chaque cas d'usage de 2b |
| 7 | Terminologie | Vocabulaire métier cohérent, pas de synonymes flottants pour la même notion |
| 8 | Signaux de complétion | Les critères d'acceptation sont-ils déjà testables en l'état ? |
| 9 | Configuration d'exécution | Base de données existante, chemin du venv Python *(jamais déduit)* |

Les catégories 1 (volet rôles), 4 et 9 ne peuvent jamais être classées Clair par déduction — aucune question n'est faite l'économie tant que la réponse n'est pas écrite noir sur blanc dans `spec.md`.

- **Catégorie 1 (rôles)** : un rôle utilisateur non explicitement énuméré dans `spec.md` ne doit jamais être supposé implicitement, même s'il n'y a vraisemblablement qu'un seul rôle — voir 2a. Le reste de la catégorie 1 (objectifs, hors-périmètre) suit la règle normale Partiel/Manquant avec hypothèses possibles.
- **Catégorie 9** : ce sont des faits propres à l'environnement de l'utilisateur (pas des choix de conception), impossibles à deviner par nature.
- **Catégorie 4** : chaque exigence non-fonctionnelle (sécurité, performance, charge, disponibilité, conformité, contrainte externe) est potentiellement très structurante pour l'architecture que choisira `/implement`, et **`/implement` ne vérifie ni n'enrichit ces points lui-même** — toute hypothèse silencieuse à ce niveau devient une décision d'architecture jamais validée par l'utilisateur. Ne jamais faire d'hypothèse ici : poser la question, même si une recommandation évidente l'accompagne (l'utilisateur n'a alors qu'à répondre "oui"). *Si `/implement` est un jour modifié pour vérifier lui-même certains aspects NFR, cette règle pourra être assouplie pour ces aspects spécifiquement — pas avant.*

Pour les catégories 1, 2, 3, 5 et 6 marquées Partiel ou Manquant, ne générer une question que si la clarification change réellement l'architecture, la sécurité ou l'expérience utilisateur — sinon faire une hypothèse raisonnable et la documenter dans la section "Hypothèses" de `spec-final.md` (étape 4).

### Étape 3 — Boucle de questions séquentielle

Construire la liste des questions à partir des catégories Partiel/Manquant, triée par priorité (périmètre > sécurité > UX > technique). Pas de plafond fixe — la rigueur prime sur la rapidité — mais ne jamais poser une question dont la réponse n'aurait aucun impact réel sur l'implémentation.

**Poser une seule question à la fois** et attendre la réponse avant de poser la suivante :

- **Si plusieurs réponses raisonnables existent** : analyser le contexte (standards du domaine, bonnes pratiques, réduction des risques de sécurité/performance) et afficher une recommandation explicite en tête, puis les options en tableau :

```markdown
## Question [N] : [Sujet]

**Contexte** : [citer la partie concernée de la demande]

**Recommandé : Option [X]** — [1-2 phrases expliquant pourquoi c'est le meilleur choix ici]

| Option | Réponse | Implications |
|--------|---------|---------------|
| A | [réponse 1] | [conséquence] |
| B | [réponse 2] | [conséquence] |
| Personnalisé | Réponse libre | — |

*Répondre "oui"/"recommandé" pour accepter, ou choisir une autre option, ou répondre librement.*
```

- **Si la question est un fait propre à l'utilisateur** (volume réel, DB existante, chemin du venv, contraintes de conformité) : pas de recommandation pertinente, garder le format simple question + défaut raisonnable si l'utilisateur ne sait pas :
> "Combien d'utilisateurs simultanés ? (si incertain, défaut : faible <100)"

Après chaque réponse, l'intégrer immédiatement à la compréhension de la spec avant de poser la question suivante (ne pas attendre la fin de la boucle pour en tenir compte — une réponse peut rendre une question suivante obsolète, dans ce cas la retirer de la liste).

**Arrêter la boucle** dès que :
- Toutes les questions à fort impact restantes deviennent inutiles (réponses précédentes les ont déjà résolues), ou
- L'utilisateur signale l'arrêt ("stop", "ça suffit", "continue comme ça"), ou
- Toutes les questions de la liste ont été posées.

Si l'utilisateur arrête alors que des catégories à fort impact restent Partiel/Manquant, le signaler explicitement avant de continuer à l'étape 4 et documenter ces zones comme hypothèses.

### Étape 4 — Générer spec-final.md

Une fois les réponses obtenues, générer `spec-final.md` avec ce format :

```markdown
# Spec — [Nom du projet]

## Résumé
[2-3 phrases décrivant ce que fait le système]

## Exigences fonctionnelles
- FR-001: Le système DOIT [action vérifiable et non ambiguë]
- FR-002: Le système DOIT [action vérifiable et non ambiguë]
- ...

## Exigences non-fonctionnelles
- NFR-001: Charge — [FAIBLE | MOYEN | ÉLEVÉ] ([justification basée sur le volume d'utilisateurs simultanés, ex: "< 100 utilisateurs simultanés"])
- NFR-002: [Sécurité | Performance | Disponibilité | Conformité | Contrainte externe] — [exigence mesurable, ex: "Les mots de passe sont hashés avec bcrypt, jamais stockés en clair"]
- NFR-003: ...

## Utilisateurs et rôles
- [Rôle] : [ce qu'il peut faire]

## Scénarios d'acceptation
- AC-001: Given [contexte], When [action], Then [résultat attendu]
- AC-002: ...

## Edge cases
- EC-001: Que se passe-t-il si [cas limite, y compris cas d'erreur et accès non autorisé] ?
- EC-002: ...

## Critères de succès
- [Mesurable et vérifiable du point de vue utilisateur/métier — pas de détail d'implémentation, ex: "95% des requêtes traitées en moins de 2s", "L'utilisateur termine le paiement en moins de 3 minutes"]

## Entités métier
- [Entité] : [champs clés et relations]

## Intégrations externes
- [Service] : [usage, mode d'échec attendu]

## Hors périmètre
- [Ce qui n'est PAS inclus dans cette implémentation]

## Hypothèses
- [Défaut pris sans confirmation explicite de l'utilisateur, et pourquoi ce choix est raisonnable]

## Configuration environnement
- Venv Python : [chemin du virtualenv, ex: .venv]
- Base de données : [new | existing — host:port/dbname user/password]

## Checklist qualité
- [ ] Chaque rôle utilisateur est explicitement identifié et confirmé (jamais déduit)
- [ ] Chaque acteur externe (consommateur ou producteur d'API) précise comment il identifie sa cible et le comportement en cas d'échec
- [ ] Aucun détail d'implémentation dans les Critères de succès
- [ ] Chaque exigence fonctionnelle (FR-xxx) est testable et non ambiguë
- [ ] Chaque exigence non-fonctionnelle (NFR-xxx) est mesurable, y compris la NFR-Charge
- [ ] Les scénarios d'acceptation couvrent les flux principaux
- [ ] Les edge cases couvrent les cas d'erreur et les accès non autorisés
- [ ] Le périmètre est clairement borné (Hors périmètre rempli)
- [ ] Chaque hypothèse non confirmée par l'utilisateur est documentée

## Couverture par catégorie
| Catégorie | Statut |
|---|---|
| Périmètre fonctionnel | Résolu / Clair / Différé / En suspens |
| Modèle de données | ... |
| Flux UX et interaction | ... |
| Exigences non-fonctionnelles | ... |
| Intégrations externes | ... |
| Edge cases et erreurs | ... |
| Terminologie | ... |
| Signaux de complétion | ... |
| Configuration d'exécution | ... |
```

### Étape 5 — Auto-validation

Relire `spec-final.md` généré contre la "Checklist qualité" :

1. Pour chaque item, déterminer s'il passe ou échoue, en citant la partie concernée de la spec
2. **Si un item échoue** (manque de précision, exigence non testable, critère de succès qui mentionne une techno, edge case manquant sur un flux sensible...) : corriger directement la spec et recocher l'item — pas besoin de revalider avec l'utilisateur pour ce type de correction
3. **Si une vraie ambiguïté bloquante subsiste** (impossible de corriger sans information de l'utilisateur) : reprendre la boucle séquentielle de l'étape 3 pour les questions manquantes uniquement
4. Recommencer la validation après correction — **maximum 3 itérations** au total
5. Si des items restent en échec après 3 itérations, les laisser non cochés et documenter la raison dans une note sous la checklist — ne pas bloquer indéfiniment la génération
6. Mettre à jour le tableau "Couverture par catégorie" : **Résolu** (était Partiel/Manquant, traité par une question), **Clair** (déjà suffisant dès le scan initial), **Différé** (non traité pour rester focalisé, faible impact, hypothèse documentée à la place), **En suspens** (zone à fort impact toujours non résolue après 3 itérations — à signaler explicitement à l'utilisateur)

Cocher tous les items résolus dans la "Checklist qualité" du fichier final.

### Étape 6 — Rapport de complétion

Rapporter à l'utilisateur :
- Chemin du fichier `spec-final.md`
- Nombre de questions posées et résolues
- Résultat de la checklist qualité (items cochés / en échec avec raison)
- Tableau "Couverture par catégorie" — signaler explicitement toute catégorie **En suspens**
- Confirmation que la spec est prête pour `/implement`

## Règles

- Ne jamais générer `spec-final.md` sans avoir obtenu les informations minimales (rôles utilisateurs, charge, DB, venv, exigences non-fonctionnelles)
- Les rôles utilisateurs, la catégorie "Exigences non-fonctionnelles" (charge, sécurité, performance, disponibilité, conformité, contraintes externes) et la catégorie "Configuration d'exécution" sont toujours posés s'ils ne sont pas déjà écrits explicitement dans `spec.md` — jamais déduits, voir étape 2
- Pour chaque acteur externe (service consommé ou client consommateur, même hors périmètre), le contrat d'identification de la cible et le comportement en cas d'échec sont toujours vérifiés explicitement — voir étape 2b
- Les questions se posent **une à la fois**, jamais groupées — chaque réponse peut invalider une question suivante
- Chaque exigence (FR-xxx, NFR-xxx) et chaque scénario/edge case (AC-xxx, EC-xxx) a un identifiant unique qui doit être préservé et jamais réutilisé — `/add` continue la numérotation, ne la réinitialise jamais
- Le champ "Hors périmètre" est obligatoire — il prévient le scope creep pendant `/implement`
- Le champ "Hypothèses" est obligatoire dès qu'un défaut a été pris sans confirmation explicite
- `/spec` ne propose et ne devine jamais de nom de blueprint (`.claude/architectures/`) — ce matching est entièrement de la responsabilité de `/implement`, qui dispose du tableau de correspondance complet ; lui faire porter cette décision depuis `/spec` exposerait à la variabilité non déterministe d'un LLM sans second regard
- La NFR-Charge décide si `/implement` doit charger les skills `caching` et `observability` (voir table ci-dessous)
- Les critères de succès ne doivent jamais mentionner une techno, un framework ou un détail d'implémentation — reformuler du point de vue utilisateur/métier
- Les scénarios d'acceptation (AC-xxx) et edge cases (EC-xxx) sont la matière première des tests générés par `/implement` — les rédiger avec une granularité testable (un scénario = un test)
- Une recommandation n'est jamais imposée silencieusement : elle doit toujours être présentée à l'utilisateur avec sa justification, qui choisit de l'accepter ou non
- L'auto-validation a une limite claire (3 itérations) pour rester actionnable, mais le but est la rigueur, pas la vitesse — ne pas couper les coins ronds pour finir plus vite

## Règle charge → architecture

| NFR-Charge | Volume | Conséquence sur `/implement` |
|-------------------|--------|------------------------------|
| **FAIBLE** | < 100 users simultanés | Architecture standard — pas de caching, pas de queue |
| **MOYEN** | 100–10k | Ajouter skill `caching` — cache catalogue, sessions |
| **ÉLEVÉ** | > 10k | Ajouter skills `caching` + `observability` — Redis obligatoire, metrics, queue pour tâches lourdes |
