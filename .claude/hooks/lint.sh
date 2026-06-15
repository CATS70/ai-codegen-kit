#!/bin/bash
# PostToolUse — lancé après chaque Write ou Edit
# Lit le JSON de l'outil via stdin, extrait le chemin du fichier, lance le linter approprié
# La sortie est affichée à Claude pour correction immédiate

set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
PROJECT_NAME=$(basename "$PROJECT_ROOT")

# ─── Log (désactivé si CLAUDE_HOOK_LOG est vide ou absent) ────────────────────
LOG_FILE="${CLAUDE_HOOK_LOG:-}"
LOG_FILE="${LOG_FILE/#\~/$HOME}"
log() { [[ -n "$LOG_FILE" ]] && echo "[$(date '+%H:%M:%S')] [${PROJECT_NAME}] [lint] $*" >> "$LOG_FILE"; }

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('file_path', ''))
except Exception:
    print('')
" 2>/dev/null)

log "TRIGGERED file=$FILE_PATH"

if [[ -z "$FILE_PATH" ]] || [[ ! -f "$FILE_PATH" ]]; then
  log "SKIP file introuvable ou vide"
  exit 0
fi

log "START"
ERRORS=0

# ─── Python ───────────────────────────────────────────────────────────────────
if [[ "$FILE_PATH" == *.py ]]; then

  if command -v ruff &>/dev/null; then
    echo "→ ruff check $FILE_PATH"
    if ! ruff check "$FILE_PATH" --output-format=concise 2>&1; then
      ERRORS=1
      log "ruff check: ERREUR"
    else
      log "ruff check: OK"
    fi

    echo "→ ruff format --check $FILE_PATH"
    if ! ruff format --check "$FILE_PATH" 2>&1; then
      echo "  (pour corriger : ruff format $FILE_PATH)"
      ERRORS=1
      log "ruff format: ERREUR"
    else
      log "ruff format: OK"
    fi
  else
    echo "ℹ ruff non installé — linting Python ignoré (pip install ruff)"
    log "ruff: non installé"
  fi

  if command -v bandit &>/dev/null; then
    echo "→ bandit $FILE_PATH"
    # -ll : medium + high uniquement  -q : pas de barre de progression
    if ! bandit -q -ll "$FILE_PATH" 2>&1; then
      ERRORS=1
      log "bandit: ERREUR"
    else
      log "bandit: OK"
    fi
  else
    echo "ℹ bandit non installé — scan sécurité Python ignoré (pip install bandit)"
    log "bandit: non installé"
  fi

  # semgrep : taint-tracking cross-fichier, complémentaire à bandit
  # Pour CI renforcée : semgrep --config=auto ou semgrep --config=p/owasp-top-ten
  if command -v semgrep &>/dev/null; then
    echo "→ semgrep $FILE_PATH"
    if ! semgrep --config=auto --quiet --error "$FILE_PATH" 2>&1; then
      ERRORS=1
      log "semgrep: ERREUR"
    else
      log "semgrep: OK"
    fi
  fi

fi

# ─── TypeScript / TSX ─────────────────────────────────────────────────────────
if [[ "$FILE_PATH" == *.ts ]] || [[ "$FILE_PATH" == *.tsx ]]; then

  if [[ -f "$PROJECT_ROOT/tsconfig.json" ]] && command -v tsc &>/dev/null; then
    echo "→ tsc --noEmit"
    if ! (cd "$PROJECT_ROOT" && tsc --noEmit 2>&1 | head -30); then
      ERRORS=1
      log "tsc: ERREUR"
    else
      log "tsc: OK"
    fi
  elif command -v pnpm &>/dev/null && [[ -f "$PROJECT_ROOT/package.json" ]]; then
    # Tenter via pnpm typecheck si le script existe
    if (cd "$PROJECT_ROOT" && pnpm run --if-present typecheck 2>&1 | head -30); then
      log "pnpm typecheck: OK"
    else
      log "pnpm typecheck: ERREUR"
    fi
  else
    echo "ℹ tsc non disponible — vérification TypeScript ignorée"
    log "tsc: non disponible"
  fi

fi

# ─── Résultat ─────────────────────────────────────────────────────────────────
if [[ $ERRORS -ne 0 ]]; then
  echo ""
  echo "⚠ Des erreurs ont été détectées dans $FILE_PATH — corriger avant de continuer."
  log "END result=ERREUR"
  exit 1
fi

log "END result=OK"
exit 0
