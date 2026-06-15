# Blueprint : E-commerce

## Cas d'usage
Catalogue produits, gestion du panier, tunnel de commande et paiement. Adapté aux boutiques en ligne avec ou sans frontend découplé.

## Composants

- Authentification et autorisation          ← skill associé : `auth`
- API REST produits / panier / commandes    ← skill associé : `fastapi`
- Paiement et webhooks                      ← skill associé : `payment`
- Conception schéma et intégrité des données ← skill associé : `database-design`
- Modèles et accès base de données           ← skill associé : `sqlalchemy`
- Validation des entrées et schémas         ← skill associé : `pydantic`
- Frontend boutique                         ← skill associé : `nextjs`
- Tests API et E2E                          ← skill associé : `testing`
- Conteneurisation                          ← skill associé : `docker`
- Caching catalogue et sessions             ← skill associé : `caching` *(charger si volume medium/high)*

## Contraintes

- Toute logique métier dans `services/` — les routes API font max 20 lignes
- Les opérations stock et paiement doivent être transactionnelles (SQLAlchemy session)
- Tous les traitements de paiement doivent être idempotents (idempotency keys Stripe)
- Les statuts de commande passent obligatoirement par la machine à états de `domain/`
- Les services doivent être testables sans dépendance externe (injection de dépendances)
- Configuration exclusivement via `core/settings.py` (Pydantic BaseSettings)
- **Réservation stock** : utiliser `SELECT ... FOR UPDATE` (verrou optimiste) pour éviter la survente sur accès concurrent — `await db.get(Product, id, with_for_update=True)`
- **Compensation Stripe** : le flux stock → payment intent → webhook est une transaction distribuée. Si le webhook n'arrive pas, la commande reste `PENDING` avec du stock réservé. Prévoir un job de nettoyage (tâche planifiée) qui expire les commandes `PENDING` depuis plus de `PAYMENT_TIMEOUT_MINUTES` et libère le stock

## Flux : création de commande

1. Valider le panier (quantités, cohérence)
2. Vérifier et réserver le stock (`inventory_service`)
3. Créer la commande (`status=PENDING`)
4. Créer un payment intent Stripe
5. Attendre le webhook de confirmation Stripe
6. Sur `payment_intent.succeeded` → passer la commande à `status=PAID`
7. Décrémenter définitivement le stock
8. Envoyer la confirmation par email (`notification_service`)

## Structure de fichiers recommandée

```
backend/
├── app/
│   ├── main.py
│   ├── core/
│   │   ├── settings.py           # Pydantic BaseSettings (DB, Stripe, JWT...)
│   │   └── logging.py            # configuration centralisée des logs
│   ├── api/
│   │   ├── auth.py               # login, register, refresh token
│   │   ├── products.py           # catalogue + pagination + filtres (prix, catégorie)
│   │   ├── cart.py
│   │   ├── orders.py
│   │   └── webhooks.py           # Stripe webhooks (vérification signature obligatoire)
│   ├── domain/
│   │   └── enums/
│   │       └── order_status.py   # PENDING, PAID, SHIPPED, CANCELLED
│   ├── models/                   # tables SQLAlchemy
│   │   ├── user.py
│   │   ├── product.py
│   │   ├── cart.py
│   │   └── order.py
│   ├── schemas/                  # validation Pydantic (input/output API)
│   │   ├── user.py
│   │   ├── product.py
│   │   ├── cart.py
│   │   └── order.py
│   ├── services/                 # logique métier
│   │   ├── auth_service.py       # hash, JWT, vérification
│   │   ├── cart_service.py       # calcul totaux
│   │   ├── inventory_service.py  # réservation + décrément stock (transactionnel)
│   │   ├── order_service.py      # création, transitions de statut
│   │   ├── payment_service.py    # Stripe intents, idempotence, events
│   │   └── notification_service.py # emails confirmation, expédition
│   └── db.py
├── migrations/                   # Alembic
├── tests/
│   ├── test_auth.py
│   ├── test_products.py
│   ├── test_cart.py
│   ├── test_orders.py
│   ├── test_inventory.py
│   └── test_payment.py
└── Dockerfile

frontend/
├── app/
│   ├── page.tsx
│   ├── products/
│   ├── cart/
│   └── checkout/
├── components/
└── lib/
    └── api.ts
```
