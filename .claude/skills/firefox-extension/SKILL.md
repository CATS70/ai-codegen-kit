---
name: firefox-extension
description: Conventions pour extensions Firefox (WebExtensions API). Manifest V3, event pages, browser.* API à base de Promises, browser_specific_settings, CSP, publication AMO.
---

# Conventions Extension Firefox — WebExtensions

## Manifest V2 reste supporté — pas de migration forcée

Contrairement à Chrome (MV2 totalement désactivé depuis Chrome 138, juin 2026), **Mozilla n'a annoncé aucune date de dépréciation pour Manifest V2** et continue de le supporter indéfiniment. Migrer vers MV3 reste recommandé pour la parité cross-browser et l'accès aux nouvelles API, mais ce n'est pas une urgence technique côté Firefox seul. Si l'extension doit aussi tourner sur Chrome, MV3 est de toute façon obligatoire — dans ce cas, cibler MV3 des deux côtés plutôt que maintenir deux manifests.

## API — `browser.*` avec Promises, pas `chrome.*` callbacks

Firefox implémente nativement le namespace `browser.*`, basé sur des Promises (spec WebExtensions du W3C), alors que `chrome.*` est basé sur des callbacks avec `chrome.runtime.lastError`.

```typescript
// ✅ — natif sur Firefox, pas besoin de callback ni de vérifier lastError
const { theme } = await browser.storage.local.get("theme")

// Chrome nécessite soit des callbacks, soit (Chrome 99+) des Promises aussi —
// mais chrome.* reste le seul namespace disponible côté Chrome
```

## Outillage — WXT recommandé pour le cross-browser

Comme pour Chrome, utiliser **WXT** (`wxt.dev`, basé sur Vite) plutôt qu'un manifest manuel dès que le projet doit cibler Firefox ET Chrome depuis la même base de code — WXT génère les deux manifests (event page pour Firefox, service worker pour Chrome) à partir des mêmes fichiers.

```bash
pnpm dev --browser firefox      # lance Firefox avec l'extension chargée
pnpm build --browser firefox    # build dans .output/firefox-mv3/ (ou mv2/ selon config)
pnpm zip --browser firefox      # .xpi prêt pour soumission AMO
```

Pour un manifest écrit à la main, utiliser le CLI **`web-ext`** (mainteneur : Mozilla) :

```bash
npm install --global web-ext
web-ext lint                    # valide le manifest et le code contre les règles AMO
web-ext run                     # lance Firefox avec l'extension chargée temporairement
web-ext build                   # génère le .xpi dans web-ext-artifacts/
web-ext sign --api-key=$AMO_JWT_ISSUER --api-secret=$AMO_JWT_SECRET   # signe via l'API AMO
```

Les identifiants `AMO_JWT_ISSUER`/`AMO_JWT_SECRET` viennent des variables d'environnement (générés depuis le compte développeur AMO) — jamais en dur dans un script.

## manifest.json — exemple annoté (MV3 Firefox)

```json
{
  "manifest_version": 3,
  "name": "Mon Extension",
  "version": "1.0.0",
  "description": "Description courte",
  "icons": {
    "48": "icons/icon-48.png",
    "128": "icons/icon-128.png"
  },
  "action": {
    "default_popup": "popup/popup.html"
  },
  "background": {
    "scripts": ["background/background.js"],
    "type": "module"
  },
  "content_scripts": [
    {
      "matches": ["https://example.com/*"],
      "js": ["content/content-script.js"]
    }
  ],
  "permissions": ["storage"],
  "host_permissions": ["https://api.example.com/*"],
  "browser_specific_settings": {
    "gecko": {
      "id": "mon-extension@example.com",
      "strict_min_version": "121.0"
    }
  }
}
```

**Différences avec le manifest Chrome** :
- `background.scripts` (tableau) au lieu de `background.service_worker` (chaîne) — Firefox démarre une **event page** non-persistante, pas un service worker
- `browser_specific_settings.gecko.id` **obligatoire** pour la publication sur AMO — identifiant unique de l'extension (format email ou UUID)
- `gecko.strict_min_version` fixe la version minimale de Firefox compatible — importe si le manifest utilise des API récentes (`host_permissions` affiché à l'installation seulement depuis Firefox 127)

## Compatibilité croisée Chrome/Firefox dans le même manifest

```json
{
  "background": {
    "service_worker": "background.js",
    "scripts": ["background.js"],
    "type": "module"
  }
}
```

Chrome ignore `scripts` et utilise `service_worker` ; Firefox ignore `service_worker` (sauf Firefox 121+, qui démarre quand même l'event page en présence des deux clés) et utilise `scripts`. Cette double déclaration permet un seul manifest pour les deux navigateurs sans build tool — WXT gère cette différence automatiquement si utilisé.

## Polyfill — code Promise-based sur Chrome aussi

Pour écrire une seule base de code utilisant `browser.*`/Promises sur Chrome également, utiliser `webextension-polyfill` (Mozilla) :

```bash
pnpm add webextension-polyfill
pnpm add -D @types/webextension-polyfill
```

```typescript
import browser from "webextension-polyfill"

// Fonctionne identiquement sur Firefox (no-op, browser.* déjà natif)
// et sur Chrome (wrapper Promise autour de chrome.*)
const { theme } = await browser.storage.local.get("theme")
```

Ne pas mélanger `chrome.*` et `browser.*` dans le même fichier — choisir `browser.*` + polyfill comme unique API dans tout le code partagé, et réserver `chrome.*` aux API réellement absentes de Firefox (à détecter par feature-detection, pas par `navigator.userAgent`).

## Content Security Policy — encore plus stricte que Chrome

MV3 sur Firefox interdit aussi tout code distant. Seuls `'self'` et `'wasm-unsafe-eval'` sont acceptés dans `script-src`, déclaré sous `content_security_policy.extension_pages` (pas `content_security_policy` seul, qui était la clé MV2) :

```json
{
  "content_security_policy": {
    "extension_pages": "script-src 'self' 'wasm-unsafe-eval'; object-src 'self';"
  }
}
```

Aucun hash CSP ne permet de débloquer un script inline en MV3 — toute la logique doit être dans les fichiers embarqués du package.

## Renommages MV2 → MV3 côté Firefox

```typescript
// ❌ — API et raccourci MV2
browser.browserAction.setIcon(...)
// manifest: "browser_action": {...}, "commands": {"_execute_browser_action": {...}}

// ✅ — MV3
browser.action.setIcon(...)
// manifest: "action": {...}, "commands": {"_execute_action": {...}}

// ❌ — déprécié
browser.extension.lastError

// ✅
browser.runtime.lastError
```

`browser_style` (styles par défaut hérités du navigateur pour popup/options) est retiré en MV3 — fournir son propre CSS.

## Storage — mêmes quotas que Chrome

`browser.storage.local` (10 Mo, `unlimitedStorage` pour lever la limite) et `browser.storage.sync` (100 Ko total, 8 Ko/item, synchronisé via le compte Firefox Sync) suivent les mêmes règles que côté Chrome — voir le skill `chrome-extension` pour le détail des quotas et anti-patterns `localStorage`.

## Permissions — affichage à l'installation

Depuis Firefox 127, les `host_permissions` s'affichent dans la boîte de dialogue d'installation et sont accordées directement à l'installation (pas de prompt runtime comme certaines permissions optionnelles). Garder `host_permissions` aussi restreint que possible réduit la friction d'installation autant que le risque de rejet en review AMO.

```json
// ❌ — accès large, prompt d'installation alarmant pour l'utilisateur
"host_permissions": ["<all_urls>"]

// ✅ — domaine précis
"host_permissions": ["https://api.example.com/*"]
```

## Publication — AMO (addons.mozilla.org)

Deux modes de distribution :

| Mode | Usage | Process de review |
|---|---|---|
| **Listed** | Publié publiquement sur AMO, découvrable | Review automatique + manuelle possible, mise à jour visible dès signature |
| **Unlisted (self-distribution)** | Diffusion privée/beta, non listé sur AMO | Review automatisée en général en quelques secondes, signature immédiate si conforme |

```bash
web-ext sign --channel=unlisted --api-key=$AMO_JWT_ISSUER --api-secret=$AMO_JWT_SECRET
```

Toute soumission — y compris unlisted — reste sujette à une review manuelle a posteriori en cas de signalement ou de contrôle de conformité aux Add-on Policies.

Avant soumission, vérifier :
- [ ] `browser_specific_settings.gecko.id` renseigné et stable entre les versions (changer l'id casse les mises à jour existantes)
- [ ] `web-ext lint` exécuté sans erreur avant `web-ext sign`
- [ ] Aucun code minifié sans les sources correspondantes fournies si demandé en review manuelle (Mozilla peut exiger le code source non minifié pour les extensions complexes)
- [ ] `strict_min_version` cohérent avec les API réellement utilisées dans le manifest

## Anti-patterns

```typescript
// ❌ — mélange chrome.* et browser.* sans polyfill dans un code cross-browser
chrome.storage.local.get("theme", (result) => { ... })
const tabs = await browser.tabs.query({ active: true })

// ✅ — browser.* uniforme via webextension-polyfill
import browser from "webextension-polyfill"
const { theme } = await browser.storage.local.get("theme")
const tabs = await browser.tabs.query({ active: true })

// ❌ — détection de navigateur par user-agent pour choisir l'API
if (navigator.userAgent.includes("Firefox")) { ... }

// ✅ — feature detection directe
if (typeof browser.offscreen === "undefined") {
  // fallback : API non disponible sur ce navigateur
}
```

## Règles

- `browser.*` + Promises partout, jamais de callback `chrome.*` non-polyfillé dans du code cross-browser
- `browser_specific_settings.gecko.id` obligatoire et stable dès la première publication
- `background.scripts` (event page) sur Firefox — ne pas copier tel quel un `background.service_worker` de Chrome sans adapter
- `host_permissions`/`permissions` les plus étroits possibles — affichés à l'installation depuis Firefox 127
- CSP sous `content_security_policy.extension_pages`, jamais `unsafe-eval`/`unsafe-inline`
- `web-ext lint` avant chaque `web-ext sign` ou soumission AMO
- Pas de dépréciation forcée MV2→MV3 côté Firefox seul — migrer par choix (parité Chrome, nouvelles API), pas par urgence
