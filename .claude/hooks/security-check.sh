#!/bin/bash
# PreToolUse — lancé avant chaque Write ou Edit
# Détecte les secrets hardcodés et les patterns dangereux dans le contenu à écrire
# Exit 1 bloque l'écriture et affiche un message à Claude

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
PROJECT_NAME=$(basename "$PROJECT_ROOT")

# ─── Log (désactivé si CLAUDE_HOOK_LOG est vide ou absent) ────────────────────
LOG_FILE="${CLAUDE_HOOK_LOG:-}"
LOG_FILE="${LOG_FILE/#\~/$HOME}"
# Bloc if (pas de "&&") : sinon log() renvoie 1 quand LOG_FILE est vide, et set -e avorte le script au 1er appel
log() { if [[ -n "$LOG_FILE" ]]; then echo "[$(date '+%H:%M:%S')] [${PROJECT_NAME}] [security] $*" >> "$LOG_FILE"; fi; }

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('file_path', ''))
except Exception:
    print('')
" 2>/dev/null)

CONTENT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # Write utilise 'content', Edit utilise 'new_string'
    print(d.get('content', d.get('new_string', '')))
except Exception:
    print('')
" 2>/dev/null)

log "TRIGGERED file=$FILE_PATH"

if [[ -z "$CONTENT" ]]; then
  log "SKIP contenu vide"
  exit 0
fi

log "START"
BLOCKED=0

# ─── Bloquer l'écriture dans .env (sauf .env.example) ─────────────────────────
if [[ "$FILE_PATH" == *".env" ]] && [[ "$FILE_PATH" != *".env.example" ]]; then
  echo "🚫 BLOQUÉ : écriture dans .env interdite."
  echo "   → Modifier .env manuellement. Ne jamais le committer."
  log "BLOQUÉ: écriture dans .env"
  exit 1
fi

# ─── Détecter les secrets hardcodés ───────────────────────────────────────────

# Clés API Anthropic
if echo "$CONTENT" | grep -qE 'sk-ant-[a-zA-Z0-9_-]{20,}'; then
  echo "🚫 BLOQUÉ : clé API Anthropic détectée dans le code."
  echo "   → Utiliser settings.anthropic_api_key (depuis .env)"
  log "BLOQUÉ: clé API Anthropic"
  BLOCKED=1
fi

# Clés API OpenAI
if echo "$CONTENT" | grep -qE 'sk-[a-zA-Z0-9]{20,}'; then
  echo "🚫 BLOQUÉ : clé API OpenAI détectée dans le code."
  echo "   → Utiliser settings.openai_api_key (depuis .env)"
  log "BLOQUÉ: clé API OpenAI"
  BLOCKED=1
fi

# Clés Stripe
if echo "$CONTENT" | grep -qE '(sk_live_|sk_test_)[a-zA-Z0-9]{20,}'; then
  echo "🚫 BLOQUÉ : clé Stripe détectée dans le code."
  echo "   → Utiliser settings.stripe_secret_key (depuis .env)"
  log "BLOQUÉ: clé Stripe"
  BLOCKED=1
fi

# Mots de passe en dur dans le code (heuristique)
if echo "$CONTENT" | grep -qiE '(password|passwd|secret|token)\s*=\s*"[^"]{6,}"'; then
  # Vérifier que ce n'est pas une variable settings ou un test
  if ! echo "$CONTENT" | grep -qiE '(settings\.|test|fake|mock|example|placeholder|changeme|your[_-])'; then
    echo "⚠ AVERTISSEMENT : valeur hardcodée détectée pour un champ sensible."
    echo "   → Vérifier que ce secret vient bien d'une variable d'environnement."
    echo "   → Si c'est intentionnel (test, exemple), ignorer cet avertissement."
    log "AVERTISSEMENT: valeur hardcodée champ sensible"
    # Avertissement seulement, pas de blocage
  fi
fi

# ─── Résultat ─────────────────────────────────────────────────────────────────
if [[ $BLOCKED -ne 0 ]]; then
  echo ""
  echo "L'écriture a été bloquée pour raison de sécurité."
  echo "Corriger le code avant de réessayer."
  log "END result=BLOQUÉ"
  exit 1
fi

log "END result=OK"
exit 0
