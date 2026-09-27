# /sonar-to-skills — Injection des règles SonarQube dans les skills

## Objectif

Transformer le diff produit par `tools/sonarqube/extract_rules.py` (règles nouvelles / modifiées / dépréciées d'un Quality Profile SonarQube) en instructions condensées, injectées dans les skills du kit (`.claude/skills/*/SKILL.md`), pour que l'IA respecte ces règles **pendant** la génération de code.

Ceci reste de la **prévention à la source** : le scan SonarQube réel, lancé après `/implement`/`/add`/`/fix`, demeure le seul juge de vérité. L'objectif est de réduire les allers-retours de correction, pas de le remplacer.

## Entrée

Un argument : le chemin du fichier de diff (ex. `docs/sonarqube/diff_py_python-strong.json`), généré au préalable via :
```bash
python tools/sonarqube/extract_rules.py --language <lang> --profile <profil>
```

Si aucun argument n'est fourni, chercher le fichier le plus récent dans `docs/sonarqube/diff_*.json`. Si aucun n'existe, stopper :
> "Aucun fichier de diff trouvé. Lancer d'abord `python tools/sonarqube/extract_rules.py --language <lang> --profile <profil>`."

## Processus

### Étape 1 — Charger et résumer le diff

Lire le fichier JSON (`language`, `profile`, `profileKey`, `new`, `modified`, `deprecated`). Afficher un résumé :
> "X nouvelle(s), Y modifiée(s), Z dépréciée(s) pour `<language>` / profil `<profile>`."

Si le total (X + Y + Z) dépasse 20 règles (typiquement le premier run), demander confirmation avant de continuer — c'est le seul dry-run nécessaire, pas d'estimation de coût chiffrée.

Si le total est nul, stopper : rien à faire.

### Étape 2 — Mapper chaque règle nouvelle/modifiée à un skill cible

Pour chaque règle, déterminer le skill cible en évaluant ces conditions **dans l'ordre**, la première qui matche l'emporte :

| # | Condition | Skill cible |
|---|---|---|
| 1 | `sysTags` contient `test`, `pytest`, `playwright`, ou tout tag lié aux tests | `.claude/skills/testing/SKILL.md` |
| 2 | `type` = `VULNERABILITY` ou `SECURITY_HOTSPOT`, ou `sysTags` contient `owasp`/`cwe`/`security` | `.claude/skills/security/SKILL.md` |
| 3 | `context.key` correspond à un skill existant (`fastapi`, `pydantic`, `sqlalchemy`, `nextjs` pour react/nextjs, `auth`, `mongodb`, `docker`, etc. — voir la liste des dossiers dans `.claude/skills/`) | skill correspondant |
| 4 | `sysTags` contient un tag de stack mappé à un skill (`fastapi`/`uvicorn`/`starlette`/`httpx` → `fastapi`, `pydantic` → `pydantic`, `sqlalchemy` → `sqlalchemy`, `typescript` → `typescript`) — si plusieurs tags de stack matchent à la fois, prendre le premier de cette liste dans cet ordre : `fastapi`, `uvicorn`, `starlette`, `httpx`, `sqlalchemy`, `pydantic`, `typescript` (ordre fixe, jamais l'ordre d'itération d'un ensemble) | skill correspondant |
| 5 | Aucun des cas ci-dessus | fichier générique `.claude/skills/<language>-quality/SKILL.md` (le créer s'il n'existe pas, avec un titre minimal `# Qualité <language> (SonarQube)` en première ligne) |

`<language>` est le code SonarQube du diff (`py` → `python-quality`, `ts`/`js` → `typescript-quality`).

### Étape 3 — Générer le texte condensé (par groupe de skill, via un agent Haiku)

Regrouper les règles nouvelles/modifiées par skill cible. Pour **chaque groupe séparément** (jamais un seul appel avec tout le diff — ça garde le contexte raisonnable, surtout au premier run), invoquer l'outil Agent avec `model: "haiku"` et ce prompt :

```
Tu génères des règles de code concises pour un assistant IA qui code en {langage}.

Pour chaque règle SonarQube fournie ci-dessous, produis exactement ce format,
un bloc par règle, rien d'autre :

### {clé} — {nom_court}
**Interdit :** une phrase directe sur ce qui est interdit.
**Requis :** une phrase sur ce qui est attendu, avec exemple inline `code` si utile.
→ détail : `.claude/sonar-rules/{clé_sanitisée}.md`

Où {clé_sanitisée} = {clé} avec ":" remplacé par "_".

Sois technique et concis. Pas d'intro ni de conclusion, pas de texte entre les blocs.

Règles à traiter :
{JSON des règles du groupe — champs key, name, severity, descriptionSections}
```

Récupérer le texte retourné : un bloc par règle du groupe.

### Étape 4 — Écrire le détail complet par règle

Pour chaque règle nouvelle/modifiée (tous groupes confondus), écrire `.claude/sonar-rules/<clé_sanitisée>.md` (créer le dossier s'il n'existe pas) — recopie directe des champs, **sans passer par l'agent** :

```markdown
# {clé} — {nom}

**Sévérité :** {severity} · **Type :** {type}

## Introduction

{contenu de descriptionSections["introduction"]}

## Comment corriger

{contenu de descriptionSections["how_to_fix"]}
```

Ce fichier est la référence complète — il ne doit jamais être résumé ou tronqué.

### Étape 5 — Insérer dans les skills

Pour chaque skill cible touché :

1. Lire le fichier. S'il ne contient pas encore les marqueurs, les ajouter en fin de fichier :
   ```
   <!-- SONARQUBE:START -->
   ## Règles qualité (SonarQube)
   <!-- SONARQUBE:END -->
   ```
2. Entre les marqueurs, le contenu est une suite de blocs `### {clé} — ...`. Pour chaque règle du groupe généré à l'étape 3 :
   - Si un bloc avec la même clé existe déjà entre les marqueurs (cas d'une règle **modifiée**) : le remplacer intégralement par le nouveau bloc.
   - Sinon (règle **nouvelle**) : l'ajouter à la fin de la section, juste avant `<!-- SONARQUBE:END -->`.
3. Ne jamais toucher au contenu du skill en dehors des marqueurs. Ne jamais retirer un bloc qui n'est pas concerné par ce diff (autre profil, autre langue, run précédent).

### Étape 6 — Traiter les règles dépréciées

Pour chaque clé de `deprecated` :
1. Retrouver son skill cible et son fichier de détail via l'entrée existante du manifest (`.claude/sonar-rules/manifest.json`, section de la langue courante).
2. Retirer son bloc `### {clé} — ...` de la section marquée du skill correspondant.
3. Supprimer `.claude/sonar-rules/<clé_sanitisée>.md`.

### Étape 7 — Mettre à jour le manifest

Lire (ou créer) `.claude/sonar-rules/manifest.json`. Sous la clé `<language>` :
```json
{
  "<language>": {
    "_meta": {
      "profile": "<profile>",
      "profileKey": "<profileKey>",
      "language": "<language>",
      "generatedAt": "<horodatage ISO 8601 UTC actuel>"
    },
    "<clé-règle>": {
      "updatedAt": "<updatedAt de la règle>",
      "severity": "<severity>",
      "skill": "<chemin du skill cible>",
      "detailFile": ".claude/sonar-rules/<clé_sanitisée>.md"
    }
  }
}
```
Ajouter/mettre à jour une entrée par règle nouvelle/modifiée, retirer les entrées dépréciées. Ne toucher à aucune autre langue du manifest.

### Étape 8 — Changelog

Ajouter une entrée en tête de `CHANGELOG_skills.md` (le créer s'il n'existe pas) :
```markdown
## <date ISO> — <language> / <profile>
- X règle(s) nouvelle(s) : <clé1>, <clé2>, ...
- Y règle(s) modifiée(s) : <clé...>
- Z règle(s) dépréciée(s) : <clé...>
```

## Règles

- Ne jamais faire un seul appel Haiku avec tout le diff — toujours grouper par skill cible (étape 3)
- Le fichier de détail (`.claude/sonar-rules/`) n'est jamais généré par l'agent ni résumé : recopie directe des champs SonarQube
- Ne jamais écrire en dehors des marqueurs `SONARQUBE:START`/`SONARQUBE:END` dans un skill
- Ne jamais committer `.env` ni aucun token — ce fichier n'intervient pas ici, l'authentification est gérée par `extract_rules.py` en amont
- Si un skill cible (`.claude/skills/<x>-quality/`) n'existe pas encore, le créer avec le minimum (titre + section marquée), ne pas y ajouter de convention non demandée
