---
name: chrome-extension
description: Conventions pour extensions Chrome Manifest V3. Service worker, permissions, content scripts, messaging, storage, CSP, publication Chrome Web Store.
---

# Conventions Extension Chrome — Manifest V3

## Manifest V3 obligatoire — pas d'alternative

Depuis Chrome 138 (juin 2026), **Manifest V2 est désactivé pour tous les utilisateurs, sans exception entreprise** — la stratégie `ExtensionManifestV2Availability` a été retirée en Chrome 139. Le Chrome Web Store retire toutes les extensions MV2 le 31 août 2026. Ne jamais générer de `manifest_version: 2` ni proposer MV2 comme fallback : le code ne pourrait plus s'installer ni se mettre à jour.

## Outillage — WXT recommandé

Pour tout projet neuf, utiliser **WXT** (`wxt.dev`) plutôt qu'un manifest écrit à la main : basé sur Vite, génère le `manifest.json` depuis la structure de fichiers, gère le rechargement à chaud, et permet de cibler Chrome/Firefox/Edge depuis la même base de code (utile si un skill `firefox-extension` doit être chargé en parallèle).

```bash
pnpm dlx wxt@latest init mon-extension
cd mon-extension && pnpm dev        # lance Chrome avec l'extension chargée, HMR actif
pnpm build                          # build de production dans .output/chrome-mv3/
pnpm zip                            # package prêt pour le Chrome Web Store
```

Si l'utilisateur demande explicitement un manifest manuel (pas de build tool), suivre la structure ci-dessous.

## Structure du projet (sans WXT)

```
extension/
├── manifest.json
├── src/
│   ├── background/
│   │   └── service-worker.ts
│   ├── content/
│   │   └── content-script.ts
│   ├── popup/
│   │   ├── popup.html
│   │   └── popup.ts
│   ├── options/
│   │   ├── options.html
│   │   └── options.ts
│   └── lib/
│       ├── messaging.ts
│       └── storage.ts
├── public/
│   └── icons/
│       ├── icon-16.png
│       ├── icon-48.png
│       └── icon-128.png
└── package.json
```

## manifest.json — exemple annoté

```json
{
  "manifest_version": 3,
  "name": "Mon Extension",
  "version": "1.0.0",
  "description": "Description courte et exacte (max 132 caractères, doit correspondre au listing Web Store)",
  "icons": {
    "16": "icons/icon-16.png",
    "48": "icons/icon-48.png",
    "128": "icons/icon-128.png"
  },
  "action": {
    "default_popup": "popup/popup.html",
    "default_icon": "icons/icon-48.png"
  },
  "background": {
    "service_worker": "background/service-worker.js",
    "type": "module"
  },
  "content_scripts": [
    {
      "matches": ["https://example.com/*"],
      "js": ["content/content-script.js"],
      "run_at": "document_idle"
    }
  ],
  "permissions": ["storage", "activeTab"],
  "host_permissions": ["https://api.example.com/*"],
  "options_page": "options/options.html"
}
```

**Champs clés** :
- `action` remplace `browser_action`/`page_action` (unifiés depuis MV3)
- `background.service_worker` est une **chaîne unique**, pas un tableau (contrairement à `background.scripts` en MV2)
- `permissions` : accès aux API Chrome (`storage`, `alarms`, `tabs`...) — pas d'URL
- `host_permissions` : domaines sur lesquels l'extension peut agir — séparé des `permissions` depuis MV3

## Permissions — principe du moindre privilège

**Règle absolue du Chrome Web Store** : demander les permissions les plus étroites possibles pour la fonctionnalité. Une permission large (`<all_urls>`, `<all_urls>` en `host_permissions`) déclenche une revue manuelle plus longue et est la première cause de rejet.

```json
// ❌ — accès à tous les sites alors que seul un domaine est utilisé
"host_permissions": ["<all_urls>"]

// ✅ — domaine précis
"host_permissions": ["https://api.example.com/*"]

// ✅ — activeTab au lieu d'un host_permissions large quand l'action
// ne s'exécute que sur clic utilisateur sur l'onglet actif
"permissions": ["activeTab"]
```

Utiliser `optional_permissions`/`optional_host_permissions` pour toute permission qui n'est nécessaire qu'à une fonctionnalité secondaire, demandée à la volée via `chrome.permissions.request()` plutôt qu'à l'installation.

Ne jamais demander une permission "au cas où" pour une fonctionnalité pas encore implémentée — motif de rejet explicite dans les program policies.

## Service worker — pas de page de fond persistante

Le service worker peut être déchargé par Chrome à tout moment d'inactivité — aucune variable en mémoire ne survit.

```typescript
// ❌ — état perdu au prochain réveil du service worker
let sessionCount = 0
chrome.action.onClicked.addListener(() => {
  sessionCount++
})

// ✅ — persister via chrome.storage
chrome.action.onClicked.addListener(async () => {
  const { sessionCount = 0 } = await chrome.storage.local.get("sessionCount")
  await chrome.storage.local.set({ sessionCount: sessionCount + 1 })
})
```

**Enregistrer les listeners de façon synchrone, en tête de fichier** — jamais dans une promesse résolue ou un callback asynchrone, sinon Chrome peut décharger le worker avant l'enregistrement effectif.

```typescript
// ❌ — l'enregistrement est asynchrone, le listener peut ne jamais s'attacher
chrome.storage.local.get("config").then((config) => {
  chrome.runtime.onMessage.addListener(handleMessage)
})

// ✅ — listener synchrone au chargement du module
chrome.runtime.onMessage.addListener(handleMessage)

async function handleMessage(message: unknown) {
  const { config } = await chrome.storage.local.get("config")
  // ...
}
```

**Pas de connexion persistante** (WebSocket long-lived) depuis un service worker qui se termine après quelques secondes d'inactivité. Pour un besoin de push périodique, utiliser `chrome.alarms` (intervalle minimum 1 minute) plutôt qu'un `setInterval` qui ne survit pas au déchargement.

```typescript
chrome.alarms.create("poll-updates", { periodInMinutes: 1 })
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === "poll-updates") checkForUpdates()
})
```

## Messaging — content script ↔ background ↔ popup

```typescript
// content-script.ts → service worker : chrome.runtime.sendMessage
const response = await chrome.runtime.sendMessage({ type: "GET_USER_DATA" })

// service worker → content script d'un onglet précis : chrome.tabs.sendMessage
// (runtime.sendMessage ne peut PAS cibler un content script)
const [tab] = await chrome.tabs.query({ active: true, currentWindow: true })
if (tab.id) await chrome.tabs.sendMessage(tab.id, { type: "HIGHLIGHT" })

// listener — retourner `true` si la réponse est asynchrone
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === "GET_USER_DATA") {
    fetchUserData().then(sendResponse)
    return true   // indispensable : garde le canal ouvert pour sendResponse async
  }
})
```

**Sécurité** : un content script tourne dans une page web potentiellement compromise — ne jamais faire confiance aveuglément à un message reçu côté service worker. Valider `sender.origin`/`sender.tab` et le contenu du message avant d'agir.

## Storage — chrome.storage, jamais localStorage

| API | Quota | Usage |
|---|---|---|
| `chrome.storage.local` | 10 Mo (`unlimitedStorage` pour lever la limite) | Données volumineuses, cache, état applicatif |
| `chrome.storage.sync` | 100 Ko total, 8 Ko/item | Préférences utilisateur synchronisées entre appareils |
| `chrome.storage.session` | En mémoire, effacé à la fermeture du navigateur | Données sensibles temporaires (jamais persistées) |

```typescript
// ❌ — localStorage inaccessible dans un service worker (pas de DOM/window)
localStorage.setItem("theme", "dark")

// ✅
await chrome.storage.local.set({ theme: "dark" })
const { theme } = await chrome.storage.local.get("theme")
```

Vérifier la taille avant d'écrire dans `sync` (`getBytesInUse()`) — un dépassement de quota fait échouer silencieusement l'écriture (`runtime.lastError` ou rejet de promesse), pas d'exception synchrone.

## Content Security Policy — pas de code distant

MV3 impose `script-src 'self' 'wasm-unsafe-eval'; object-src 'self';` par défaut, **non modifiable pour ajouter `unsafe-eval` ou `unsafe-inline`**. Toute la logique JS doit être embarquée dans le bundle de l'extension.

```typescript
// ❌ — interdit en MV3 : exécution de code non embarqué dans le package
const script = document.createElement("script")
script.src = "https://cdn.example.com/lib.js"
document.head.appendChild(script)

eval(userInput)              // interdit
new Function(userInput)()    // interdit
```

Pour manipuler le DOM depuis un service worker (qui n'a pas accès à `document`/`window`), utiliser un **offscreen document** (`chrome.offscreen.createDocument`) plutôt que de déplacer la logique dans un content script si elle n'a pas besoin d'accéder à la page hôte.

## Anti-patterns

```typescript
// ❌ — XSS via innerHTML avec des données non fiables dans un content script
element.innerHTML = untrustedApiResponse

// ✅ — textContent ou sanitization explicite
element.textContent = untrustedApiResponse

// ❌ — webRequest bloquant, supprimé en MV3 pour la plupart des cas
chrome.webRequest.onBeforeRequest.addListener(blockHandler, filter, ["blocking"])

// ✅ — declarativeNetRequest, règles déclaratives évaluées par Chrome (pas de proxy JS)
chrome.declarativeNetRequest.updateDynamicRules({
  addRules: [{ id: 1, condition: { urlFilter: "ads.example.com" }, action: { type: "block" } }],
})
```

## Publication — Chrome Web Store

Avant soumission, vérifier :
- [ ] Chaque permission listée dans `manifest.json` a une justification écrite dans le formulaire de soumission
- [ ] Aucune permission "au cas où" pour une fonctionnalité non implémentée
- [ ] Politique de confidentialité publiée si l'extension collecte des données utilisateur (obligatoire dès qu'une permission sensible est demandée : `storage` avec données perso, `tabs`, `history`...)
- [ ] Description et captures d'écran du listing correspondent exactement au comportement réel de l'extension
- [ ] Aucun code minifié/obfusqué au-delà d'un bundler standard (Vite/webpack) — le code obfusqué manuellement est un motif de rejet automatique
- [ ] Testé sans erreur console sur `chrome://extensions` en mode développeur avant packaging

Délai de revue variable (heures à plusieurs jours selon la charge de la file) — prévoir une marge avant toute date de lancement communiquée.

## Règles

- Toujours `manifest_version: 3` — MV2 est mort sur Chrome, aucun fallback possible
- `host_permissions` et `permissions` les plus étroits possibles ; `optional_permissions` pour le superflu
- Aucun état en variable de module dans le service worker — persister via `chrome.storage`
- Listeners `chrome.runtime.onMessage`/`chrome.alarms`/etc. enregistrés de façon synchrone en tête de fichier
- `chrome.storage`, jamais `localStorage`/`sessionStorage` (indisponibles dans le service worker)
- Aucun `eval`, `new Function`, ou script chargé depuis une URL distante
- Valider/sanitizer tout message reçu d'un content script avant de l'utiliser côté service worker
