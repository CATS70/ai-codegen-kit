# /sonar-reset — Réinitialisation des règles SonarQube injectées

## Objectif

Repartir de zéro sur l'intégration SonarQube : retirer toutes les règles injectées par `/sonar-to-skills` dans les skills, supprimer les fichiers de détail et le manifest. Le prochain `/sonar-to-skills` traitera alors tout le diff comme "nouveau".

**Action destructive — ne jamais l'exécuter sans confirmation explicite de l'utilisateur.**

## Processus

### Étape 1 — Inventorier ce qui sera supprimé

1. Lister les skills contenant les marqueurs :
   ```bash
   grep -rl "SONARQUBE:START" .claude/skills/
   ```
2. Lister le contenu de `.claude/sonar-rules/` (fichiers de détail + `manifest.json`), s'il existe.
3. Vérifier l'existence de `CHANGELOG_skills.md`.

Si rien n'est trouvé (aucun skill marqué, pas de dossier `.claude/sonar-rules/`), le signaler et stopper : rien à réinitialiser.

### Étape 2 — Présenter et confirmer

Afficher la liste précise (skills concernés, nombre de fichiers de détail) et demander confirmation explicite avant de continuer. Préciser que `CHANGELOG_skills.md` est conservé par défaut (historique), sauf si l'utilisateur demande aussi de le vider.

### Étape 3 — Exécuter (seulement après confirmation)

1. Pour chaque skill listé à l'étape 1, retirer uniquement le bloc entre les marqueurs (marqueurs inclus) :
   ```bash
   sed -i '/<!-- SONARQUBE:START -->/,/<!-- SONARQUBE:END -->/d' <fichier>
   ```
2. Supprimer le dossier des fichiers de détail et du manifest :
   ```bash
   rm -rf .claude/sonar-rules/
   ```
3. Si l'utilisateur a explicitement demandé de vider aussi l'historique : supprimer `CHANGELOG_skills.md`.

### Étape 4 — Confirmer le résultat

Résumer ce qui a été retiré (skills nettoyés, nombre de fichiers de détail supprimés, manifest réinitialisé).

## Règles

- Ne jamais supprimer sans confirmation explicite de l'utilisateur (voir étape 2)
- Ne jamais toucher au contenu d'un skill en dehors des marqueurs `SONARQUBE:START`/`END`
- Conserver `CHANGELOG_skills.md` par défaut — ne le supprimer que sur demande explicite
