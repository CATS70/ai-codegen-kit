# AGENTS.md — Portabilité multi-agents

Ce fichier décrit comment utiliser ce kit avec n'importe quel assistant de code IA (Claude Code, Cursor, Windsurf, Copilot, etc.).

---

## Ce qu'est ce kit

Un ensemble de conventions, blueprints et skills pour produire du code Python / TypeScript production-ready. Il définit :
- **Comment démarrer** (workflow spec → implement → test → audit)
- **Quelles conventions suivre** (skills par domaine)
- **Quelle architecture utiliser** (blueprints par cas d'usage)

---

## Workflow universel

Quel que soit l'agent utilisé, suivre cette séquence :

```
1. Décrire la demande dans spec.md
2. Clarifier (5 questions max) → produire spec-final.md
3. Identifier le blueprint correspondant dans .claude/architectures/
4. Lire les skills associés dans .claude/skills/
5. Implémenter en respectant les conventions des skills
6. Lancer les tests
7. Auditer la sécurité si nécessaire
```

### Avec Claude Code

Les commandes `/spec`, `/implement`, `/test`, `/doc`, `/documentation`, `/security-audit` automatisent ce workflow. Les hooks lint et sécurité s'exécutent automatiquement.

### Avec un autre agent

Exécuter manuellement les étapes ci-dessus. Charger explicitement les fichiers de skills pertinents en contexte avant de coder.

---

## Résolution blueprint → skills

Lire le blueprint dans `.claude/architectures/`. Chaque composant indique le skill associé :

```
- Authentification et autorisation  ← skill associé : `auth`
- API REST                          ← skill associé : `fastapi`
- Modèles de données                ← skill associé : `sqlalchemy`
```

Lire les fichiers `SKILL.md` correspondants dans `.claude/skills/` avant de générer du code. Le skill `security` est **toujours** chargé, quel que soit le blueprint.

---

## Conventions transversales

Ces règles s'appliquent à tout agent, pour tout projet.

### Configuration
- Toute valeur variable (URL, modèle, port, timeout) → variable d'environnement
- Python : `Pydantic BaseSettings` dans `core/settings.py`
- TypeScript : `import.meta.env` centralisé dans `lib/config.ts`
- Jamais de secret dans le code

### Architecture
- `services/` contient toute la logique métier
- Les routes API font max 20 lignes — elles orchestrent, elles ne décident pas
- Un fichier = une responsabilité
- `core/settings.py` est le seul point de configuration

### Sécurité
- Toutes les entrées validées par Pydantic à la frontière du système
- Toutes les routes qui modifient des données → authentification requise
- Aucune requête SQL par concaténation de chaînes
- Stack traces absentes des réponses d'erreur

### Tests
- Couverture minimum 85%
- Chaque test est isolé (rollback DB après chaque test)
- Les services sont testables sans dépendance externe (injection)

### Documentation
- Fonctions et classes publiques : docstring décrivant le contrat
- Commentaires inline : uniquement le *pourquoi* non évident
- Décisions d'architecture → commit message

---

## Structure des fichiers de référence

```
.claude/
├── CLAUDE.md          # Point d'entrée — lire en premier
├── AGENTS.md          # Ce fichier
├── architectures/     # Blueprints par cas d'usage métier
│   ├── ecommerce.md
│   ├── crm.md
│   └── ...
├── commands/          # Instructions des commandes (Claude Code)
│   ├── spec.md
│   ├── implement.md
│   └── ...
├── skills/            # Conventions par domaine technique
│   ├── security/SKILL.md   ← toujours charger
│   ├── fastapi/SKILL.md
│   ├── auth/SKILL.md
│   └── ...
├── hooks/             # Scripts lint et sécurité (Claude Code)
└── settings.json      # Permissions et hooks (Claude Code)
```

---

## Priorité de lecture pour un agent

Quand un agent démarre sur ce projet, lire dans cet ordre :

1. `CLAUDE.md` — vue d'ensemble et conventions globales
2. `architectures/<blueprint>.md` — structure et contraintes du cas d'usage
3. `skills/security/SKILL.md` — règles de sécurité (systématique)
4. Skills du blueprint (listés dans les composants)
5. `spec-final.md` — la demande spécifique à implémenter

---

## Compatibilité testée

| Agent | Support commandes | Support hooks | Notes |
|---|---|---|---|
| Claude Code | ✅ natif | ✅ natif | Workflow complet automatisé |
| Cursor | ⬜ manuel | ⬜ non | Charger les skills manuellement en contexte |
| Windsurf | ⬜ manuel | ⬜ non | Charger les skills manuellement en contexte |
| Copilot | ⬜ manuel | ⬜ non | Utiliser les skills comme référence |
| Tout LLM | ⬜ manuel | ⬜ non | Coller le contenu des skills dans le contexte |
