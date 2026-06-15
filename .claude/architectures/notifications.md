# Blueprint : Notifications

## Cas d'usage
Système de notifications multi-canal (email, push, in-app) avec gestion des préférences utilisateur, file d'attente et retry automatique. Composant transversal réutilisable dans la majorité des applications SaaS.

## Composants

- Authentification et autorisation               ← skill associé : `auth`
- API REST notifications et préférences          ← skill associé : `fastapi`
- Modèles et persistance                         ← skill associé : `sqlalchemy`
- Validation des données                         ← skill associé : `pydantic`
- Règles OWASP transversales                     ← skill associé : `security`
- Tests unitaires et d'intégration               ← skill associé : `testing`
- Conteneurisation                               ← skill associé : `docker`

## Contraintes

- Toute notification transite par une file d'attente — jamais d'envoi synchrone en requête HTTP
- Chaque notification a un `idempotency_key` : un même événement ne produit jamais deux envois
- Les préférences utilisateur sont respectées avant tout envoi (canal désactivé → skip silencieux)
- Les erreurs d'envoi sont retentées avec backoff exponentiel (max 3 tentatives, délais : 1 min, 5 min, 30 min)
- Après 3 échecs, la notification passe en statut `FAILED` et alerte l'ops — pas de perte silencieuse
- Les tokens push (FCM, APNs) expirés sont supprimés automatiquement à l'échec d'envoi
- Configuration exclusivement via `core/settings.py` (Pydantic BaseSettings)

## Flux : envoi d'une notification

1. Événement métier produit une `NotificationRequest` (type, destinataire, payload)
2. Vérification des préférences utilisateur pour le canal ciblé
3. Si canal désactivé → skip, log `SKIPPED`
4. Sinon → création d'un enregistrement `Notification` (`status=PENDING`)
5. Mise en file d'attente du job d'envoi (async)
6. Le worker dépile et tente l'envoi via le provider (SMTP, FCM, in-app)
7. Succès → `status=SENT`, horodatage
8. Échec → retry avec backoff, `attempt_count++`
9. Après max tentatives → `status=FAILED`, alerte

## Structure de fichiers recommandée

```
backend/
├── app/
│   ├── main.py
│   ├── core/
│   │   ├── settings.py           # SMTP_HOST/PORT/USER/PASS, FCM_API_KEY
│   │   │                         # MAX_RETRY_ATTEMPTS, RETRY_DELAYS (env)
│   │   └── logging.py
│   ├── api/
│   │   ├── auth.py
│   │   ├── notifications.py      # GET /notifications (in-app), PATCH /notifications/{id}/read
│   │   └── preferences.py        # GET/PATCH /me/notification-preferences
│   ├── domain/
│   │   └── enums/
│   │       ├── notification_type.py   # WELCOME, PASSWORD_RESET, ORDER_CONFIRMED...
│   │       ├── notification_channel.py # EMAIL, PUSH, IN_APP
│   │       └── notification_status.py # PENDING, SENT, FAILED, SKIPPED
│   ├── models/
│   │   ├── user.py
│   │   ├── notification.py            # id, user_id, type, channel, status, payload, attempt_count
│   │   ├── notification_preference.py # user_id, channel, type, enabled
│   │   └── push_token.py              # user_id, token, platform (FCM/APNS), created_at
│   ├── schemas/
│   │   ├── notification.py
│   │   └── preference.py
│   ├── services/
│   │   ├── notification_service.py    # orchestration : préférences → file → dispatch
│   │   ├── preference_service.py      # CRUD préférences utilisateur
│   │   └── providers/
│   │       ├── email_provider.py      # envoi SMTP via smtplib ou sendgrid
│   │       ├── push_provider.py       # FCM / APNs, purge token expiré
│   │       └── inapp_provider.py      # persistance in-app, mark-as-read
│   ├── workers/
│   │   └── notification_worker.py     # dépilage file, retry avec backoff exponentiel
│   └── db.py
├── migrations/
└── tests/
    ├── test_notification_service.py   # préférences respectées, idempotence
    ├── test_retry.py                  # backoff, max tentatives, statut FAILED
    ├── test_providers.py              # mock SMTP, mock FCM
    └── test_preferences.py            # activation/désactivation canal
```
