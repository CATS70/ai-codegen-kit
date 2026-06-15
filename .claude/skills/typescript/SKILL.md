---
name: typescript
description: Conventions TypeScript strictes. Typage fort, no-any, patterns d'erreurs, generics, utilitaires, async/await. Agnostique du framework.
---

# Conventions TypeScript

## Configuration stricte

```json
// tsconfig.json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitReturns": true,
    "exactOptionalPropertyTypes": true
  }
}
```

## Règle absolue : zéro `any`

```typescript
// ❌ INTERDIT — désactive la vérification de types
function process(data: any) { ... }

// ✅ unknown + type guard pour les données externes
function process(data: unknown) {
  if (!isUser(data)) throw new Error("Invalid data")
  return data.email  // typé correctement après le guard
}

function isUser(value: unknown): value is User {
  return (
    typeof value === "object" &&
    value !== null &&
    "id" in value &&
    "email" in value
  )
}
```

## Interfaces vs Types

```typescript
// Interface : objets et classes (extensible)
interface User {
  id: number
  email: string
  name: string
}

// Type : unions, intersections, primitives
type Status = "pending" | "active" | "inactive"
type AdminUser = User & { role: "admin" }
type UserId = number & { __brand: "UserId" }  // branded type
```

## Generics

```typescript
// Réponse paginée réutilisable
interface PaginatedResponse<T> {
  items: T[]
  total: number
  page: number
  size: number
}

// Fonction générique
async function fetchPaginated<T>(url: string): Promise<PaginatedResponse<T>> {
  const response = await fetch(url)
  const data: unknown = await response.json()
  // valider data avant de caster
  return data as PaginatedResponse<T>
}
```

## Pattern Result — erreurs explicites

```typescript
type Result<T, E = Error> =
  | { ok: true; value: T }
  | { ok: false; error: E }

// Usage
function parseAmount(raw: string): Result<number> {
  const amount = parseFloat(raw)
  if (isNaN(amount) || amount < 0) {
    return { ok: false, error: new Error(`Invalid amount: ${raw}`) }
  }
  return { ok: true, value: amount }
}

const result = parseAmount(input)
if (!result.ok) {
  logger.error(result.error.message)
  return
}
console.log(result.value)  // typé number ici
```

## Données externes — toujours `unknown`

```typescript
// Réponses API, localStorage, URL params : traiter comme unknown

async function fetchUser(id: number): Promise<User> {
  const response = await fetch(`/api/users/${id}`)
  const data: unknown = await response.json()

  if (!isUser(data)) throw new Error("Unexpected API response shape")
  return data
}

// localStorage
const raw: unknown = JSON.parse(localStorage.getItem("user") ?? "null")
const user = isUser(raw) ? raw : null
```

## Async/Await

```typescript
// Toujours async/await, jamais .then().catch() chaîné
async function loadUserOrders(userId: number): Promise<Order[]> {
  try {
    const [user, orders] = await Promise.all([
      fetchUser(userId),
      fetchOrders(userId),
    ])
    return orders.filter(o => o.userId === user.id)
  } catch (error) {
    logger.error("Failed to load user orders", { userId, error })
    throw error
  }
}
```

## Params de fonctions — max 2, sinon objet

```typescript
// ❌ trop de paramètres
function createOrder(userId: number, productId: number, qty: number, discount: number) { }

// ✅ objet typé
interface CreateOrderParams {
  userId: number
  productId: number
  quantity: number
  discount?: number
}
function createOrder(params: CreateOrderParams) { }
```

## Utilitaires TypeScript

```typescript
// Partial<T> — tous les champs optionnels (pour update)
type UserUpdate = Partial<Pick<User, "name" | "email">>

// Required<T> — tous les champs requis
type UserRequired = Required<User>

// Readonly<T> — immutable
const config: Readonly<Config> = loadConfig()

// ReturnType<T> — type de retour d'une fonction
type FetchResult = ReturnType<typeof fetchUser>

// satisfies — valide sans perdre l'inférence
const routes = {
  home: "/",
  profile: "/profile",
} satisfies Record<string, string>
```

## Enums — utiliser StrEnum pattern

```typescript
// ❌ enum numérique — valeur opaque
enum Status { Active, Inactive }

// ✅ const object — valeur lisible, tree-shakeable
const OrderStatus = {
  PENDING:   "pending",
  PAID:      "paid",
  SHIPPED:   "shipped",
  CANCELLED: "cancelled",
} as const

type OrderStatus = typeof OrderStatus[keyof typeof OrderStatus]
// équivalent à : "pending" | "paid" | "shipped" | "cancelled"
```

## Classes d'erreur personnalisées

```typescript
class AppError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly statusCode = 500,
  ) {
    super(message)
    this.name = this.constructor.name
  }
}

class NotFoundError extends AppError {
  constructor(resource: string, id: number | string) {
    super(`${resource} ${id} not found`, "NOT_FOUND", 404)
  }
}

class ValidationError extends AppError {
  constructor(message: string) {
    super(message, "VALIDATION_ERROR", 422)
  }
}
```

## Anti-patterns

```typescript
// ❌ assertion sans vérification
const user = data as User   // dangereux si data ne correspond pas

// ❌ non-null assertion abusive
const name = user!.name     // peut exploser en runtime

// ❌ ignorer les erreurs
try { ... } catch (_) { }   // erreur silencieuse = bug caché

// ✅ vérifier, pas asserter
if (!isUser(data)) throw new ValidationError("Invalid user data")
if (!user) throw new NotFoundError("User", id)
try { ... } catch (error) { logger.error("...", { error }); throw error }
```
