# /fix — Correction ciblée d'un bug

## Objectif

Localiser et corriger un bug dans le code existant. Ne pas refactorer, ne pas ajouter de fonctionnalités — un fix = une cause racine = une correction minimale.

## Processus

### Étape 1 — Lire la description

L'utilisateur fournit : message d'erreur, stack trace, ou description du comportement incorrect.

Si la description est trop vague pour localiser le problème, poser **une seule question** :
> "Dans quel fichier / quelle route / quelle action le bug se produit-il ?"

Ne pas poser plusieurs questions — inférer ce qui peut l'être.

### Étape 2 — Localiser

1. Identifier les fichiers concernés à partir de la description ou du stack trace
2. Lire ces fichiers entièrement
3. Remonter la chaîne d'appel si nécessaire : route → service → repository → modèle
4. Lire les tests existants liés à la zone concernée

### Étape 3 — Identifier la cause racine

Avant toute modification, formuler en une phrase :
> "Le bug vient de X parce que Y."

Si le fix impacte d'autres fichiers que celui identifié initialement, les lister avant de continuer.

Si le bug révèle un problème de design plus profond (ex : mauvaise architecture, dette technique significative) : le signaler sans le corriger dans cette passe. Ouvrir une issue séparée.

### Étape 4 — Corriger

Appliquer la correction **minimale** qui résout le bug :

- Modifier uniquement ce qui est strictement nécessaire
- Ne pas refactorer le code environnant, même s'il pourrait être amélioré
- Respecter le style et les conventions du code existant
- Respecter les règles de sécurité — un fix ne doit pas introduire de nouvelle vulnérabilité

### Étape 5 — Vérifier

1. Relire le diff final pour s'assurer qu'aucun effet de bord n'a été introduit
2. Lancer les tests existants sur les fichiers modifiés via `/test`
3. Si aucun test ne couvre le bug : créer un test minimal qui aurait détecté le problème avant le fix

## Règles

- Ne jamais "améliorer" le code pendant un fix — le signaler et le traiter séparément
- Si le stack trace pointe vers une dépendance externe, vérifier d'abord si c'est une version connue pour un bug avant de modifier le code applicatif
- Un fix sur du code multi-tenant doit vérifier que l'isolation `org_id` n'est pas affectée
- Toujours vérifier qu'aucun secret n'est introduit dans le code lors de la correction
