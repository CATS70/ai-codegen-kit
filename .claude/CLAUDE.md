# Kit Claude Code — Production Ready

Stack cible : Python / TypeScript. Approche vibecoding.

---

## Chaîne de travail

```
spec.md
  → /spec             clarification interactive → génère spec-final.md
  → /screens          (si rôle humain présent) décrit les écrans → génère screens-final.md, validé par l'utilisateur
  → /implement        identifie blueprint → charge skills → code (suit screens-final.md si présent)
  → hook lint         PostToolUse automatique → feedback si erreurs
  → /test             lance les tests
  → /check-spec       vérifie la conformité du code à spec-final.md et screens-final.md (à la demande)
  → /security-audit   audit OWASP (à la demande)
```

Partir toujours de `/spec` avant `/implement`. Ne jamais coder sans `spec-final.md`. Si `spec-final.md` contient au moins un rôle humain, `/implement` exige aussi `screens-final.md` (généré par `/screens`).

---

## Commandes

| Commande          | Rôle                                              |
|-------------------|---------------------------------------------------|
| `/spec`           | Clarification interactive et rigoureuse → spec-final.md |
| `/screens`        | Décrit les écrans de l'application (si rôle humain) → screens-final.md, validé par l'utilisateur |
| `/implement`      | Lit spec-final.md (et screens-final.md si présent), identifie blueprint, code |
| `/fix`            | Corrige un bug ciblé sans refactorer              |
| `/add`            | Ajoute une fonctionnalité en mode delta           |
| `/test`           | Lance les tests du projet                         |
| `/doc`            | Génère la documentation technique (API, README)   |
| `/documentation`  | Génère CODEBASE.md, FILE_LINKS.md (cartographie des liens entre fichiers) et README.md |
| `/check-spec`     | Vérifie la conformité du code à spec-final.md et screens-final.md |
| `/security-audit` | Audit OWASP sur le code produit                   |

---

## Logique de /implement

1. Lire `spec-final.md` (et `screens-final.md` si un rôle humain est présent — sinon le demander avant de continuer)
2. Identifier le blueprint dans `.claude/architectures/`
3. Lister les composants du blueprint
4. Charger les skills associés à chaque composant
5. Charger `skills/security/` systématiquement
6. Charger `caching` et `observability` selon la NFR taguée "Charge" (FAIBLE/MOYEN/ÉLEVÉ)
7. Coder en respectant les conventions des skills chargés ; construire le frontend exactement selon `screens-final.md` s'il existe

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
| `csv-import`        | Import CSV en masse, mapping colonnes, délimiteur, dédoublonnage, rapport d'erreurs |
| `fastapi`      | API REST Python                          |
| `typescript`   | Conventions TypeScript                   |
| `nextjs`       | Frontend React/Next.js                   |
| `chrome-extension` | Extension Chrome Manifest V3 (service worker, permissions, CSP, Web Store) |
| `firefox-extension` | Extension Firefox WebExtensions (event pages, browser.*, AMO)        |
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
1. Chercher tous les usages — si `FILE_LINKS.md` existe (généré par `/documentation`), le consulter en premier : il révèle les liens indirects (route ↔ frontend, composant partagé, table partagée) qu'un grep peut manquer
2. Identifier les impacts
3. Signaler avant de procéder
