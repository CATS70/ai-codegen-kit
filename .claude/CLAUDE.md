# Kit Claude Code — Production Ready

Stack cible : Python / TypeScript. Approche vibecoding.

---

## Chaîne de travail

```
spec.md
  → /spec             clarification interactive → génère spec-final.md
  → /implement        identifie blueprint → charge skills → code
  → hook lint         PostToolUse automatique → feedback si erreurs
  → /test             lance les tests
  → /security-audit   audit OWASP (à la demande)
```

Partir toujours de `/spec` avant `/implement`. Ne jamais coder sans `spec-final.md`.

---

## Commandes

| Commande          | Rôle                                              |
|-------------------|---------------------------------------------------|
| `/spec`           | Clarifie la spec en 5 questions max → spec-final.md |
| `/implement`      | Lit spec-final.md, identifie blueprint, code      |
| `/fix`            | Corrige un bug ciblé sans refactorer              |
| `/add`            | Ajoute une fonctionnalité en mode delta           |
| `/test`           | Lance les tests du projet                         |
| `/doc`            | Génère la documentation technique (API, README)   |
| `/documentation`  | Produit une documentation orientée humains et/ou assistants IA |
| `/security-audit` | Audit OWASP sur le code produit                   |

---

## Logique de /implement

1. Lire `spec-final.md`
2. Identifier le blueprint dans `.claude/architectures/`
3. Lister les composants du blueprint
4. Charger les skills associés à chaque composant
5. Charger `skills/security/` systématiquement
6. Charger `caching` et `observability` selon `## Niveau de charge` (FAIBLE/MOYEN/ÉLEVÉ)
7. Coder en respectant les conventions des skills chargés

---

## Blueprints disponibles

| Blueprint              | Cas d'usage typique                        |
|------------------------|--------------------------------------------|
| `auth`                 | SSO, JWT, RBAC, refresh tokens             |
| `notifications`        | Email, push, in-app, retry, préférences    |
| `rag-chatbot`          | Chatbot avec mémoire et recherche RAG      |
| `saas-multitenant`     | Organisations, isolation données, rôles    |
| `ecommerce`            | Catalogue, panier, paiement                |
| `crm`                  | Contacts, pipeline, activités              |
| `email-ai`             | Traitement et génération d'emails par IA   |
| `document-processing`  | Extraction, transformation de documents    |
| `customer-support`     | Tickets, chatbot, base de connaissance     |
| `data-pipeline`        | Ingestion, transformation, stockage        |
| `dashboard-reporting`  | Visualisation, rapports, exports           |
| `content-generation`   | Génération de contenu par IA               |

---

## Skills disponibles

| Skill          | Domaine                                  |
|----------------|------------------------------------------|
| `security`          | Règles OWASP transversales — toujours chargé        |
| `auth`              | JWT, OAuth2, RBAC, middleware                       |
| `notifications`     | Email, push, in-app, idempotence, retry backoff     |
| `saas-multitenant`  | Isolation tenant_id, RBAC org, invitations          |
| `payment`           | Stripe, webhooks, idempotence                       |
| `fastapi`      | API REST Python                          |
| `typescript`   | Conventions TypeScript                   |
| `nextjs`       | Frontend React/Next.js                   |
| `testing`      | pytest + Playwright                      |
| `langgraph`    | Agents ReAct, checkpoints                |
| `mcp`          | Serveur FastMCP + client                 |
| `llm-router`   | Pattern adaptateur provider-agnostique (interface commune, swap via env var) |
| `litellm`      | Abstraction LLM multi-provider clé en main (Anthropic, OpenAI, Mistral…) |
| `claude-api`   | Appels Anthropic, streaming              |
| `openai-api`   | Appels OpenAI                            |
| `database-design` | Schéma PostgreSQL, index, données sensibles, permissions DB  |
| `sqlalchemy`      | ORM Python, sessions async, migrations Alembic               |
| `mongodb`         | Beanie ODM, design documents, index, agrégation, sécurité    |
| `pydantic`     | Validation de données                    |
| `docker`       | Conventions Docker                       |
| `git`          | Commits, branches                        |
| `caching`      | Redis async, cache-aside, rate limiting, ARQ — charger si volume medium/high |
| `observability` | Logs structurés, Prometheus, OpenTelemetry — charger si volume high |

---

## Conventions transversales

**Configuration**
- Toute valeur susceptible de changer (URL, modèle, port, timeout) → variable d'environnement
- Toujours `load_dotenv()` en Python, `import.meta.env` en TypeScript
- Valeur par défaut raisonnable dans le code

**Sécurité**
- Valider toutes les entrées utilisateur aux frontières du système
- Jamais de secrets dans le code
- Voir `skills/security/` pour la checklist OWASP complète

**Code**
- Implémenter uniquement ce qui est demandé
- Un fichier = une responsabilité
- Gestion des erreurs explicite à chaque frontière externe

**Documentation**
- Fonctions et classes : docstring décrivant ce que ça fait, les paramètres clés et le retour
- Commentaires inline : uniquement le *pourquoi* non évident (contrainte, workaround, invariant)
- Décisions d'architecture → commit message ou `spec-final.md`

**Avant de modifier du code existant**
1. Chercher tous les usages
2. Identifier les impacts
3. Signaler avant de procéder
