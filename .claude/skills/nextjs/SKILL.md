---
name: nextjs
description: Conventions Next.js 16+ App Router. Server vs Client components, data fetching, route handlers, variables d'environnement, gestion d'erreurs, layouts.
---

# Conventions Next.js — App Router

## Version

`next>=16.2.6` — version minimale patchée suite à la publication coordonnée de sécurité de mai 2026 (13 advisories : DoS, contournement d'auth, SSRF, cache poisoning, XSS). Ne jamais pinner une version antérieure. Nécessite Node.js 20.9+ — vérifier que le `Dockerfile` du skill `docker` utilise une image `node:20`+ ou supérieure.

Aucune incompatibilité avec un déploiement Vercel — Next.js 16 y est nativement supporté (Vercel est l'éditeur du framework), API de déploiement stable depuis la 16.2 pour les autres hébergeurs (Netlify, AWS...).

## Structure des dossiers

```
app/
├── layout.tsx            # layout racine (Server Component)
├── page.tsx              # page d'accueil
├── error.tsx             # Error Boundary global
├── loading.tsx           # Suspense fallback global
├── (auth)/               # groupe de routes (sans segment URL)
│   ├── login/page.tsx
│   └── register/page.tsx
├── dashboard/
│   ├── layout.tsx        # layout spécifique dashboard
│   ├── page.tsx
│   └── [id]/page.tsx     # route dynamique
└── api/
    └── users/
        └── route.ts      # Route Handler
components/
├── ui/                   # composants génériques (Button, Input...)
└── features/             # composants métier (UserCard, OrderList...)
lib/
├── api.ts                # client API (fetch vers backend)
└── utils.ts
```

## CSS — CSS Modules

Approche par défaut : **CSS Modules** (`.module.css`). Natif Next.js, zéro dépendance, scoping automatique des classes (pas de collision entre composants).

### Conventions

- Fichier CSS co-localisé avec le composant : `Button.module.css` à côté de `Button.tsx`
- Noms de classes en **camelCase** (accessibles comme propriété JS : `styles.primaryButton`, pas `styles["primary-button"]`)
- Styles globaux (reset, variables CSS, fonts) uniquement dans `app/globals.css`, importé une seule fois dans `app/layout.tsx`

```
components/
├── ui/
│   ├── Button.tsx
│   └── Button.module.css     # co-localisé
└── features/
    ├── UserCard.tsx
    └── UserCard.module.css
app/
└── globals.css               # reset + variables CSS globales
```

### Usage

```typescript
// components/ui/Button.tsx
import styles from "./Button.module.css"

type Props = Readonly<{ label: string; variant?: "primary" | "secondary" }>

export function Button({ label, variant = "primary" }: Props) {
  return (
    <button className={styles[variant]}>
      {label}
    </button>
  )
}
```

```css
/* Button.module.css */
.primary {
  background: var(--color-primary);
  color: white;
  padding: 0.5rem 1rem;
  border: none;
  border-radius: 4px;
  cursor: pointer;
}

.secondary {
  background: transparent;
  color: var(--color-primary);
  border: 1px solid var(--color-primary);
}
```

### Combiner plusieurs classes

```typescript
// Plusieurs classes sur un même élément — template literal ou tableau
<div className={`${styles.card} ${styles.highlighted}`}>...</div>

// Avec une classe conditionnelle
<div className={`${styles.card} ${isActive ? styles.active : ""}`}>...</div>
```

### Variables CSS globales

Déclarer les tokens de design (couleurs, espacements, typographie) dans `globals.css` — réutilisables dans tous les modules sans import.

```css
/* app/globals.css */
:root {
  --color-primary: #0070f3;
  --color-text: #111;
  --font-sans: system-ui, sans-serif;
  --radius-md: 6px;
}

* {
  box-sizing: border-box;
  margin: 0;
}

body {
  font-family: var(--font-sans);
  color: var(--color-text);
}
```

### Anti-patterns CSS

```typescript
// ❌ — styles inline (pas de réutilisation, pas de media queries)
<div style={{ color: "red", padding: "16px" }}>...</div>

// ❌ — classes globales sans module (collisions garanties à l'échelle)
<div className="card">...</div>  // sans CSS Module

// ✅ — classe de module + variable CSS
<div className={styles.card}>...</div>
```

## Server Components vs Client Components

Par défaut : **Server Component** (pas de directive, pas d'interactivité).

```typescript
// app/users/page.tsx — Server Component (défaut)
// Peut fetch directement, accéder aux cookies/headers, pas de bundle JS
export default async function UsersPage() {
  const users = await fetchUsers()   // fetch côté serveur
  return <UserList users={users} />
}

// components/features/UserList.tsx — Client Component si interactif
"use client"

import { useState } from "react"

export function UserList({ users }: { users: User[] }) {
  const [filter, setFilter] = useState("")
  // ...
}
```

**Règle** : ajouter `"use client"` uniquement quand nécessaire (hooks, events, browser APIs).

## Data Fetching — Server Components

**`params` et `searchParams` sont des `Promise` depuis Next.js 15, et l'accès synchrone est totalement supprimé en 16** — toujours `await` avant utilisation.

```typescript
// app/products/page.tsx
export default async function ProductsPage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string; q?: string }>
}) {
  const { page: pageParam, q } = await searchParams
  const page = Number(pageParam ?? 1)
  const data = await fetchProducts({ page, q })

  return <ProductGrid items={data.items} total={data.total} page={page} />
}

// app/dashboard/[id]/page.tsx — même règle pour params
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  // ...
}
```

**Cache — modèle "opt-in" depuis Next.js 16** (Cache Components) : tout est dynamique (exécuté à chaque requête) par défaut ; la mise en cache passe par la directive explicite `"use cache"`, pas par une option implicite sur `fetch`.

```typescript
// lib/products.ts
async function fetchProducts(params: ProductParams) {
  "use cache"   // active le cache pour cette fonction — sans elle, exécution à chaque requête

  const url = new URL(`${process.env.API_URL}/products`)
  Object.entries(params).forEach(([k, v]) => v && url.searchParams.set(k, String(v)))

  const res = await fetch(url)
  if (!res.ok) throw new Error(`API error: ${res.status}`)
  return res.json() as Promise<PaginatedResponse<Product>>
}
```

`"use cache"` peut aussi être posé en tête de fichier (toutes les fonctions exportées sont cacheables) ou dans un composant Server. Combiner avec `cacheLife()`/`cacheTag()` (import `next/cache`) pour le TTL et l'invalidation ciblée plutôt que de revalider tout le cache.

## Route Handlers (API interne)

```typescript
// app/api/users/route.ts
import { NextRequest, NextResponse } from "next/server"

export async function GET(request: NextRequest) {
  const { searchParams } = request.nextUrl
  const page = Number(searchParams.get("page") ?? 1)

  const data = await fetchUsers({ page })
  return NextResponse.json(data)
}

export async function POST(request: NextRequest) {
  const body: unknown = await request.json()
  if (!isUserCreate(body)) {
    return NextResponse.json({ error: "Invalid body" }, { status: 422 })
  }
  const user = await createUser(body)
  return NextResponse.json(user, { status: 201 })
}
```

## Variables d'environnement

```typescript
// lib/config.ts — centralisation obligatoire
const config = {
  apiUrl:  process.env.API_URL      ?? "http://localhost:8000",
  appName: process.env.NEXT_PUBLIC_APP_NAME ?? "My App",
} as const

export default config
```

**Règles** :
- `NEXT_PUBLIC_*` → exposé au navigateur (valeurs non sensibles uniquement)
- Sans préfixe → serveur uniquement (secrets, clés API)
- Jamais `process.env.X` directement dans les composants — toujours via `lib/config.ts`

## Gestion des erreurs

```typescript
// app/error.tsx — Error Boundary global (doit être Client Component)
"use client"

export default function GlobalError({
  error,
  reset,
}: {
  error: Error
  reset: () => void
}) {
  return (
    <div>
      <h2>Une erreur est survenue</h2>
      <button onClick={reset}>Réessayer</button>
    </div>
  )
}

// app/dashboard/[id]/not-found.tsx
export default function NotFound() {
  return <div>Page introuvable</div>
}

// Dans un Server Component — déclencher le 404
import { notFound } from "next/navigation"

const user = await fetchUser(id)
if (!user) notFound()   // affiche not-found.tsx
```

## Loading States

```typescript
// app/dashboard/loading.tsx — Suspense automatique
export default function DashboardLoading() {
  return <DashboardSkeleton />
}

// Pour un chargement partiel — Suspense manuel
import { Suspense } from "react"

export default function Page() {
  return (
    <div>
      <h1>Dashboard</h1>
      <Suspense fallback={<ChartSkeleton />}>
        <AsyncChart />   {/* Server Component async */}
      </Suspense>
    </div>
  )
}
```

## Stockage des tokens — règle absolue

**Ne jamais stocker de JWT dans `localStorage` ou `sessionStorage`.**

Tout script malveillant (dépendance npm compromise, XSS) peut lire `localStorage` et siphonner toutes les sessions actives. C'est une faille de conception, pas un oubli.

```typescript
// ❌ — erreur classique
localStorage.setItem("access_token", token)
localStorage.setItem("refresh_token", refreshToken)

// ✅ — le refresh_token est un cookie httpOnly défini par le backend
// L'access_token peut être en mémoire (variable React/Zustand), pas persisté
```

Le backend doit émettre le `refresh_token` via `Set-Cookie` (httpOnly, Secure, SameSite=Strict), pas dans le corps de la réponse. L'`access_token` à courte durée de vie peut vivre en mémoire React (state ou store) — il ne survit pas à un rechargement, ce qui est acceptable.

## Client API — lib/api.ts

```typescript
// lib/api.ts — abstraction des appels vers le backend FastAPI
import { redirect } from "next/navigation"

const BASE_URL = config.apiUrl

async function apiFetch<T>(
  path: string,
  options: RequestInit = {},
): Promise<T> {
  const res = await fetch(`${BASE_URL}${path}`, {
    credentials: "include",   // envoie le cookie httpOnly automatiquement
    headers: {
      "Content-Type": "application/json",
      ...options.headers,
    },
    ...options,
  })

  if (res.status === 401) {
    // ❌ window.location.href = "/login" — plante en SSR (window inexistant)
    // ✅ redirect() de Next.js — fonctionne côté serveur ET client
    redirect("/login")
  }

  if (!res.ok) {
    const error = await res.json().catch(() => ({}))
    throw new ApiError(res.status, error.detail ?? "Request failed")
  }

  return res.json() as Promise<T>
}

export const api = {
  users: {
    list: (page = 1) => apiFetch<PaginatedResponse<User>>(`/users?page=${page}`),
    get:  (id: number) => apiFetch<User>(`/users/${id}`),
    create: (data: UserCreate) => apiFetch<User>("/users", { method: "POST", body: JSON.stringify(data) }),
  },
}
```

## Streaming — SSE pour génération IA

```typescript
// lib/stream.ts
export async function* streamGeneration(prompt: string): AsyncGenerator<string> {
  const response = await fetch("/api/generate", {
    method: "POST",
    body: JSON.stringify({ prompt }),
    headers: { "Content-Type": "application/json" },
  })

  const reader = response.body!.getReader()
  const decoder = new TextDecoder()

  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    yield decoder.decode(value, { stream: true })
  }
}

// Composant client
"use client"
export function StreamingOutput({ prompt }: { prompt: string }) {
  const [output, setOutput] = useState("")

  async function generate() {
    setOutput("")
    for await (const chunk of streamGeneration(prompt)) {
      setOutput(prev => prev + chunk)
    }
  }
  // ...
}
```

## Anti-patterns

```typescript
// ❌ "use client" sur un layout — empêche l'optimisation server
"use client"
export default function RootLayout(...) { ... }

// ❌ fetch côté client ce qui peut être fait côté serveur
"use client"
useEffect(() => { fetch("/api/users").then(...) }, [])  // perte de perf

// ❌ process.env directement dans un composant client
const url = process.env.API_URL   // undefined côté client sans NEXT_PUBLIC_

// ✅ fetch dans un Server Component
export default async function Page() {
  const users = await api.users.list()
  return <UserList users={users} />
}
```

## Règles de qualité SonarQube

### Props en lecture seule (S6759)

Toujours marquer les props comme `Readonly` — elles ne doivent jamais être mutées dans un composant.

```typescript
// ❌
type Props = { name: string; items: string[] }

// ✅
type Props = Readonly<{ name: string; items: readonly string[] }>

function MyComponent({ name, items }: Props) { ... }
```

### Formulaires — labels associés (S6853)

Chaque `<label>` doit avoir un `htmlFor` correspondant à l'`id` de son input.

```tsx
// ❌
<label>Email</label>
<input type="email" />

// ✅
<label htmlFor="email">Email</label>
<input id="email" type="email" name="email" />
```

### Clés React — pas d'index de tableau (S6479)

```tsx
// ❌ — l'index change lors des insertions/suppressions, React produit des bugs subtils
items.map((item, index) => <Card key={index} {...item} />)

// ✅ — utiliser un identifiant stable
items.map((item) => <Card key={item.id} {...item} />)
```

### Éléments interactifs natifs (S6848 / S1082)

Toujours utiliser des éléments HTML natifs pour les actions interactives.

```tsx
// ❌ — div cliquable sans rôle ni gestion clavier
<div onClick={handleClick}>Cliquer</div>

// ✅
<button type="button" onClick={handleClick}>Cliquer</button>
```
