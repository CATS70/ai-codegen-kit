# /test — Lancement des tests

## Objectif

Détecter le framework de test, lancer la suite complète et rapporter les résultats.

## Processus

### Étape 1 — Identifier l'environnement d'exécution

**Venv Python :** Chercher dans cet ordre `.venv/`, `venv/`, `env/`. Si un venv est trouvé, utiliser `uv run pytest` (si `uv.lock` présent) ou `<venv>/bin/pytest` directement. **Ne jamais lancer pytest avec le Python système** — cela peut utiliser de mauvaises versions de dépendances et produire des faux positifs.

Si aucun venv n'est trouvé, arrêter et demander à l'utilisateur le chemin avant de continuer.

### Étape 2 — Détecter le framework

Chercher dans cet ordre :

**Python :**
- `pyproject.toml` avec `[tool.pytest.ini_options]` → pytest
- `pytest.ini` → pytest
- `setup.cfg` avec `[tool:pytest]` → pytest

**TypeScript / JavaScript :**
- `package.json` avec `"vitest"` → vitest
- `package.json` avec `"jest"` → jest
- `playwright.config.ts` → Playwright (E2E)

Si plusieurs frameworks sont détectés (backend + frontend), lancer dans cet ordre : pytest → vitest/jest → Playwright.

### Étape 3 — Lancer les tests

**pytest :**
```bash
# Avec uv (si uv.lock présent)
uv run pytest --tb=short -q

# Avec venv activé manuellement
.venv/bin/pytest --tb=short -q
```

Avec couverture si configurée :
```bash
pytest --cov=app --cov-report=term-missing -q
```

**vitest :**
```bash
pnpm vitest run
```

**jest :**
```bash
pnpm jest --passWithNoTests
```

**Playwright :**
```bash
pnpm playwright test
```

### Étape 4 — Analyser les résultats

**Si tous les tests passent :**
- Afficher le résumé (nb tests, couverture si disponible)
- Signaler si la couverture est sous 80 %

**Si des tests échouent :**
- Afficher les tests échoués avec leur message d'erreur
- Analyser la cause probable (erreur de config, assertion incorrecte, dépendance manquante)
- Proposer une correction si la cause est claire
- Ne pas modifier les tests pour les faire passer artificiellement

**Si aucun test n'existe :**
- Signaler l'absence de tests
- Proposer de créer `tests/conftest.py` et un premier test de sanité

### Étape 5 — Rapport

```
Tests Python   : X passed, Y failed, Z skipped
Couverture     : XX% (seuil : 80%)
Tests frontend : X passed, Y failed
Tests E2E      : X passed, Y failed

[LISTE DES ÉCHECS avec cause et fichier:ligne]
```

## Règles

- **Ne jamais modifier les tests pour les faire passer** — corriger le code à la place. Si les fixtures ou la configuration sont ajustées pour contourner un problème de compatibilité de librairie, documenter explicitement le pourquoi dans un commentaire
- Ne jamais `skip` un test sans commentaire expliquant pourquoi
- Si un test échoue à cause d'une variable d'environnement manquante, signaler la variable manquante
- **Ne jamais lancer pytest sans venv** — utiliser `uv run pytest` ou le chemin explicite du venv
- Si la couverture est sous 80 % : identifier les branches non couvertes et les tester directement (via la fixture `db`), pas via des tests HTTP (voir skill `testing` — section "Coverage et ASGI")
- Une couverture sous 100 % n'est pas un problème en soi — signaler les branches non couvertes pour information, pas comme un échec. Les branches qui ne peuvent pas être atteintes via ASGI sont documentées dans le skill `testing`
