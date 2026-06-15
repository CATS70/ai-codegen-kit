# /spec — Clarification interactive de la spécification

## Objectif

Clarifier la demande en 5 questions maximum, puis générer `spec-final.md` prêt à être consommé par `/implement`.

## Processus

### Étape 1 — Lire ce qui existe

Chercher dans le répertoire courant :
- `spec.md` — description initiale de l'utilisateur
- `spec-final.md` — spec existante à mettre à jour

Si `spec.md` n'existe pas, demander à l'utilisateur de décrire sa demande avant de continuer.

### Étape 2 — Identifier les zones floues

Analyser la demande et identifier ce qui manque pour implémenter sans ambiguïté. Se concentrer sur :

1. **Fonctionnalité** — Que fait le système ? Quelles sont les actions principales ?
2. **Utilisateurs** — Qui utilise le système ? Quels rôles ?
3. **Données** — Quelles entités ? Quelles relations ?
4. **Intégrations** — APIs externes, services tiers, bases de données existantes ?
5. **Contraintes** — Stack imposée, sécurité spécifique ?
6. **Volume** — Combien d'utilisateurs simultanés ? *(question obligatoire — impacte l'architecture)*

### Étape 3 — Poser les questions

Poser **au maximum 5 questions**, uniquement sur les zones vraiment floues. Ne pas demander ce qui peut être inféré raisonnablement.

Reformuler chaque question avec une réponse par défaut suggérée :
> "Quel provider LLM utiliser ? (défaut : Anthropic Claude)"

**Questions systématiques à inclure si non évidentes dans la spec :**

- **Base de données** : "Y a-t-il une base de données existante à utiliser ? Si oui, donner host, port, user, password, dbname. (défaut : nouvelle base PostgreSQL locale)"
- **Environnement Python** : "Quel chemin pour l'environnement virtuel Python ? (défaut : `.venv` à la racine)"

### Étape 4 — Générer spec-final.md

Une fois les réponses obtenues, générer `spec-final.md` avec ce format :

```markdown
# Spec — [Nom du projet]

## Résumé
[2-3 phrases décrivant ce que fait le système]

## Fonctionnalités principales
- [Fonctionnalité 1]
- [Fonctionnalité 2]
- ...

## Utilisateurs et rôles
- [Rôle] : [ce qu'il peut faire]

## Entités métier
- [Entité] : [champs clés et relations]

## Intégrations externes
- [Service] : [usage]

## Contraintes techniques
- Stack : [Python / TypeScript / les deux]
- Volume : [low < 100 users / medium 100–10k / high > 10k simultanés]
- [Autres contraintes]

## Hors périmètre
- [Ce qui n'est PAS inclus dans cette implémentation]

## Blueprint identifié
[Nom du blueprint dans .claude/architectures/ — laisser vide si incertain. Peut indiquer plusieurs blueprints séparés par + si la fonctionnalité les combine, ex: saas-multitenant + rag-chatbot]

## Configuration environnement
- Venv Python : [chemin du virtualenv, ex: .venv]
- Base de données : [new | existing — host:port/dbname user/password]
```

## Règles

- Ne jamais générer `spec-final.md` sans avoir obtenu les informations minimales
- Si une question est difficile à répondre, proposer une valeur par défaut raisonnable et continuer
- Le champ "Hors périmètre" est obligatoire — il prévient le scope creep pendant `/implement`
- Le champ "Blueprint identifié" guide `/implement` — renseigner si le match est évident. Plusieurs blueprints peuvent être combinés (ex: `saas-multitenant + rag-chatbot`)
- **La question sur le volume est obligatoire** — elle détermine si `/implement` doit charger les skills `caching` et `observability`
- Toujours demander l'existence d'une base de données et le chemin du venv — ces informations sont nécessaires dès `/implement`

## Règle volume → architecture

| Volume | Conséquence sur `/implement` |
|--------|------------------------------|
| **low** < 100 users simultanés | Architecture standard — pas de caching, pas de queue |
| **medium** 100–10k | Ajouter skill `caching` — cache catalogue, sessions |
| **high** > 10k | Ajouter skills `caching` + `observability` — Redis obligatoire, metrics, queue pour tâches lourdes |
