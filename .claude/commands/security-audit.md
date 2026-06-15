# /security-audit — Audit de sécurité OWASP

## Objectif

Auditer le code produit contre la checklist OWASP et les règles du skill `security`. Identifier les vulnérabilités et proposer les corrections.

## Processus

### Étape 0 — Vérifier la documentation existante

Chercher `CODEBASE.md` à la racine du projet. Si le fichier existe, le lire pour obtenir la carte du code sans explorer le projet fichier par fichier — économie de tokens significative.

Si `CODEBASE.md` n'existe pas, informer l'utilisateur :
> "CODEBASE.md introuvable. Lancer `/documentation` d'abord réduira significativement le coût en tokens de cet audit. Continuer quand même ? (o/N)"

Si l'utilisateur confirme, procéder à l'inventaire manuel.

### Étape 1 — Inventaire des surfaces d'attaque

Lister :
- Toutes les routes dans `api/` (entrées utilisateur)
- Les fichiers de configuration (`core/settings.py`, `.env.example`)
- Les modèles SQLAlchemy (données persistées)
- Les appels à des services externes (Stripe, LLM, SMTP)
- Les uploads de fichiers si présents

### Étape 2 — Audit par catégorie

#### A1 — Injection

Pour chaque accès à la base de données :
- [ ] Vérifier l'absence de SQL par concaténation de chaînes
- [ ] Confirmer l'usage exclusif de l'ORM ou de paramètres liés (`bindparams`)

```python
# Chercher les patterns dangereux
grep -rn "f\"SELECT\|f'SELECT\|% s\|format(" app/
```

#### A2 — Authentification

- [ ] Toutes les routes sensibles ont `Depends(get_current_user)`
- [ ] Les mots de passe sont hashés avec bcrypt avant stockage
- [ ] Les tokens JWT ont une expiration définie
- [ ] Le refresh token est distinct de l'access token
- [ ] Les endpoints d'auth ont une gestion des tentatives échouées

#### A3 — Données sensibles exposées

- [ ] Aucun mot de passe ou hash dans les schémas `Response`
- [ ] Aucune clé API dans les logs ou les réponses d'erreur
- [ ] Les champs sensibles masqués avant logging (`password`, `token`, `api_key`)
- [ ] HTTPS imposé en production (variable `FORCE_HTTPS`)

#### A4 — Contrôle d'accès

- [ ] Vérification de l'appartenance de la ressource à l'utilisateur courant (pas seulement l'auth)
- [ ] Les routes admin utilisent `Depends(require_role(UserRole.ADMIN))`
- [ ] Les IDs exposés dans les URLs ne permettent pas l'énumération (UUID ou séquences non prédictibles)

#### A5 — Mauvaise configuration

- [ ] `docs_url=None` en production (swagger désactivé)
- [ ] `DEBUG=False` en production
- [ ] CORS configuré avec origines explicites (pas `*`)
- [ ] `.env` dans `.gitignore`
- [ ] Aucune valeur par défaut pour les secrets dans `Settings`

#### A6 — Composants vulnérables

- [ ] Les dépendances sont épinglées à une version précise
- [ ] Vérifier `pip audit` (Python) et `pnpm audit` (Node)

```bash
pip audit
pnpm audit --audit-level=high
```

#### A7 — Identification et authentification

- [ ] Rate limiting sur les routes d'auth (login, register, reset password)
- [ ] Pas de messages d'erreur qui distinguent "email inconnu" de "mot de passe incorrect"
- [ ] Logout invalide le refresh token en base (pas seulement côté client)

```bash
# Vérifier la présence de slowapi ou équivalent
grep -rn "limiter\|RateLimit\|slowapi" app/
```

#### A5b — Headers de sécurité HTTP

- [ ] Headers `X-Content-Type-Options`, `X-Frame-Options`, `Strict-Transport-Security` présents
- [ ] Middleware `secure` configuré ou headers ajoutés manuellement

```bash
# Vérifier la présence d'un middleware de headers sécurité
grep -rn "secure\|X-Frame\|X-Content-Type" app/
```

#### A8 — Intégrité des données

- [ ] Webhooks Stripe : vérification de signature avant traitement
- [ ] Opérations critiques idempotentes (clés d'idempotence Stripe)
- [ ] Transactions SQL sur les opérations multi-étapes

#### A9 — Logs et monitoring

- [ ] Chaque erreur 5xx est loggée avec contexte
- [ ] Aucune donnée sensible dans les logs
- [ ] Les actions critiques (login, paiement, création commande) sont tracées

#### A10 — Requêtes côté serveur (SSRF)

- [ ] Les URLs fournies par l'utilisateur ne sont pas appelées directement par le serveur
- [ ] Les appels vers des services externes utilisent des URLs configurées (pas fournies par l'utilisateur)

### Étape 3 — Upload de fichiers (si applicable)

- [ ] Validation du type MIME (pas seulement l'extension)
- [ ] Limite de taille configurée et appliquée
- [ ] Fichiers renommés avant stockage
- [ ] Stockage hors du répertoire web

### Étape 4 — Rapport

```
AUDIT DE SÉCURITÉ OWASP
========================

CRITIQUE (à corriger avant livraison)
- [Description] → Fichier:ligne → Correction recommandée

IMPORTANT (à corriger rapidement)
- [Description] → Fichier:ligne → Correction recommandée

MINEUR (bonne pratique)
- [Description] → Fichier:ligne → Correction recommandée

CONFORME
- A1 Injection        ✅
- A2 Authentification ✅
- ...

Score : XX/10 items conformes
```

### Étape 5 — Correction automatique

Pour les vulnérabilités **CRITIQUE** et **IMPORTANT** dont la correction est claire :
- Proposer le diff exact
- Demander confirmation avant d'appliquer

Ne jamais corriger silencieusement — toujours montrer ce qui change et pourquoi.
