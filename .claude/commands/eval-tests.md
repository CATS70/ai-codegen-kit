# /eval-tests — Évaluation de la qualité des tests unitaires

## Objectif

Évaluer qualitativement les tests pytest produits par `/implement` (ou modifiés par `/fix`/`/add`) : est-ce qu'ils détectent réellement une régression, couvrent les comportements importants, vérifient correctement les résultats — pas seulement s'ils font monter un pourcentage de couverture.

À lancer **une fois l'implémentation terminée** (après `/test` en vert), pas pendant le développement — les métriques (mutation testing notamment) portent sur un état stable du code.

## Processus

### Étape 0 — Pré-requis

**Environnement** : même détection venv/uv qu'`/test` — Étape 1 (`uv run pytest` si `uv.lock`, sinon `<venv>/bin/pytest`). Ne jamais utiliser le Python système.

**Tous les tests doivent passer** : lancer `/test` d'abord si ce n'est pas déjà fait. Ne pas évaluer la qualité de tests qui échouent.

**Dépendances** : installer si absentes.
```bash
uv add --dev pytest-cov mutmut   # ou pip install pytest-cov mutmut
```

### Étape 1 — Validation fonctionnelle

```bash
uv run pytest --tb=short -q
```

Critères :
- Tous les tests passent
- Aucun test `skip`/`xfail` sans commentaire expliquant pourquoi (déjà une règle `/test`)
- Détection de flakiness : en cas d'échec isolé, relancer une fois avec `pytest --lf` — si le résultat change entre deux runs sans modification du code, signaler le test comme flaky plutôt que de l'ignorer

Si des tests échouent : ne pas noter — renvoyer à `/test` pour corriger le code (jamais les tests) avant de poursuivre.

### Étape 2 — Couverture de lignes (gate dure)

```bash
uv run pytest --cov=app --cov-report=term-missing --cov-fail-under=85
```

Seuil CI existant (skill `testing`) : **85%**. Grille de score :

| Couverture | Score |
|---|---|
| < 85% | insuffisant (échoue déjà le gate CI) |
| 85–90% | acceptable |
| 90–97% | bon |
| > 97% | excellent |

### Étape 3 — Couverture de branches (informative uniquement)

```bash
uv run pytest --cov=app --cov-report=term-missing --cov-branch
```

**Ne bloque jamais** `/test` ni la CI — sert uniquement à qualifier la profondeur des tests dans ce rapport. Une forte couverture de lignes avec une faible couverture de branches signale des tests qui suivent le chemin nominal sans exercer les branches d'erreur/alternatives.

Alerte graduée selon le % obtenu :

| Couverture branches | Alerte | Recommandation |
|---|---|---|
| < 60% | 🔴 forte | Les tests valident surtout le chemin nominal. Lister les branches non couvertes (`term-missing`) et écrire un test par branche d'erreur/condition métier manquante avant de considérer la feature testée. |
| 60–80% | 🟠 modérée | Couverture incomplète. Prioriser les branches liées aux EC-xxx de `spec-final.md` si elles existent — ce sont les cas métier jugés importants par la spec. |
| 80–90% | 🟡 légère | Correct. Vérifier au cas par cas les branches restantes non couvertes — souvent du code défensif (`else` inatteignable) qui ne justifie pas toujours un test dédié. |
| ≥ 90% | 🟢 aucune | Couverture de branches excellente. |

### Étape 4 — Mutation testing (scopé au diff de la feature)

Ne jamais muter tout `app/` — ça devient de plus en plus lent à mesure que le projet grossit, pour évaluer une portion de plus en plus petite de code réellement neuf. Scoper aux fichiers source modifiés par la feature en cours :

```bash
# Fichiers source modifiés depuis la base de la branche (hors tests)
git diff --name-only "$(git merge-base main HEAD)"...HEAD -- 'app/**/*.py' ':!app/**/test_*.py'
```

Si la commande est lancée directement sur `main` (rien à differ), demander à l'utilisateur le périmètre à muter plutôt que de muter tout `app/` par défaut.

```bash
uv run mutmut run --paths-to-mutate="<fichiers listés ci-dessus, séparés par des virgules>"
uv run mutmut results
```

Grille de score :

| Mutation score | Qualité |
|---|---|
| < 50% | tests faibles |
| 50–75% | moyen |
| 75–90% | bon |
| > 90% | excellent |

Un mutant survivant signifie "le code peut changer sans que les tests détectent la modification". Pour chaque mutant survivant sur un fichier non trivial, identifier le comportement non testé et proposer le test manquant (`mutmut show <id>` pour voir le diff du mutant).

### Étape 5 — Analyse statique des tests

Sur les fichiers `tests/**/*.py` touchés par le diff de la feature :

**Tests sans assertion** — un test qui appelle du code sans jamais vérifier de résultat ne détecte rien.

**Assertions trop faibles** — `assert result` seul là où une valeur précise est attendue (`assert result.status == "success"`).

**Couplage excessif à l'implémentation** — tests qui vérifient des détails internes/privés, mocks qui remplacent la logique testée plutôt que d'isoler une dépendance externe (voir skill `testing` — section Mocking : un mock isole une dépendance externe, pas le système testé).

**Tests trop larges** — un test qui vérifie plusieurs comportements indépendants dans le même corps ; préférer un test = un comportement.

### Étape 6 — Cas limites

Si `spec-final.md` existe : vérifier que chaque AC-xxx et EC-xxx concerné par la feature a bien un test correspondant — c'est déjà une règle de fin d'implémentation (`implement.md`), cette étape revalide qu'aucun n'a été oublié ou supprimé depuis.

Pour chaque fonction/service touché par le diff, vérifier la présence de tests couvrant : entrée normale, valeurs limites (vide, zéro, négatif, maximum), valeurs invalides, exceptions (`pytest.raises`).

### Étape 7 — Fixtures et mocks

Réutilise les conventions du skill `testing` (fixtures réutilisables, `db`/`client`/`user`, pas de duplication de setup). Signaler :
- mocks inutiles ou qui remplacent trop de logique
- duplication de données/setup qui devrait passer par une fixture partagée dans `conftest.py`

### Étape 8 — Score et rapport final

```
ÉVALUATION QUALITÉ DES TESTS
==============================

Score global : XX/100

MÉTRIQUES
- Tests            : X passed, Y failed, Z flaky
- Couverture lignes    : XX% (seuil CI 85% : ✅/❌)
- Couverture branches  : XX% [🔴/🟠/🟡/🟢]
- Mutation score       : XX% (scope : N fichiers modifiés)

RÉPARTITION DU SCORE
- Tests passent          .. /10
- Couverture lignes      .. /15
- Couverture branches    .. /10
- Mutation testing       .. /30
- Qualité assertions     .. /10
- Cas limites            .. /10
- Isolation et mocks     .. /5
- Maintenabilité         .. /10

PROBLÈMES DÉTECTÉS
- [Description] → fichier:ligne

MUTANTS SURVIVANTS NOTABLES
- [Comportement non testé] → fichier:ligne → test proposé

TESTS MANQUANTS
- ...

RECOMMANDATIONS COUVERTURE DE BRANCHES
- [selon le tableau étape 3]
```

## Règles de décision

- **≥ 90** : tests excellents → accepter
- **75–90** : tests acceptables → lister les améliorations possibles, ne pas bloquer
- **50–75** : tests insuffisants → demander à l'agent d'améliorer en priorité les mutants survivants, puis les cas limites, puis les assertions faibles
- **< 50** : tests de faible qualité → régénérer ou refactorer les tests concernés

## Principe directeur

Un test n'est pas bon parce qu'il augmente la couverture. Un bon test doit échouer lorsque le comportement attendu du logiciel est cassé — c'est ce que mesure directement le mutation score, d'où son poids dans le score final.
