# Spec — ReachMyGoals

## Résumé
ReachMyGoals est un outil de pilotage d'objectifs personnels (recherche d'emploi, sourcing de personnes à interviewer) permettant de centraliser entreprises, personnes et tâches autour d'objectifs, avec import CSV, enrichissement via l'API SIREN, capture d'informations via une extension navigateur externe, et un tableau de bord de suivi par objectif.

## Exigences fonctionnelles
- FR-001: Le système DOIT permettre de créer, consulter, modifier et supprimer manuellement un Objectif, une Entreprise, une Personne et une Tâche.
- FR-002: Le système DOIT permettre de rattacher une Entreprise à un ou plusieurs Objectifs.
- FR-003: Le système DOIT permettre de rattacher une Personne à une ou plusieurs Entreprises.
- FR-004: Le système DOIT permettre de rattacher une Personne à un ou plusieurs Objectifs.
- FR-005: Le système DOIT permettre de créer une Tâche rattachée à un Objectif (optionnellement aussi à une Entreprise ou une Personne), ou une Tâche générique sans Objectif.
- FR-006: Le système DOIT permettre d'importer des Entreprises depuis un fichier CSV via un écran de mapping des colonnes vers les champs cibles.
- FR-007: Le système DOIT permettre d'importer des Personnes depuis un fichier CSV via le même mécanisme de mapping.
- FR-008: Le système DOIT permettre de sauvegarder un mapping CSV comme modèle nommé réutilisable, par type d'entité.
- FR-009: Lors d'un import CSV, le système DOIT mettre à jour (upsert) une Entreprise existante si son SIREN correspond déjà, ou une Personne existante si son email correspond déjà, plutôt que d'en créer une nouvelle.
- FR-010: Le système DOIT produire, après chaque import CSV, un rapport indiquant le nombre d'enregistrements créés, mis à jour et ignorés.
- FR-011: Le système DOIT permettre de récupérer les dirigeants d'une Entreprise à partir de son SIREN, via une API externe dont l'URL est configurable.
- FR-012: La récupération des dirigeants DOIT être déclenchée manuellement et ne DOIT jamais bloquer la création/modification de l'Entreprise en cas d'échec de l'API externe.
- FR-013: Le système DOIT exposer une API permettant à un client externe (l'extension Chrome, hors périmètre de ce projet) d'enregistrer des informations diverses sur une Entreprise ou une Personne **existante** — sans capacité de création depuis cette API. Le client externe s'authentifie en appelant l'endpoint de login standard (FR-017) avec email/mot de passe pour obtenir son propre JWT, exactement comme le ferait le frontend Next.js — aucun mécanisme d'authentification séparé n'est prévu pour ce projet.
- FR-014: Le système DOIT permettre de définir, via une action explicite ("Rechercher") sur une fiche Entreprise ou Personne, un contexte courant utilisé par le client externe pour savoir à quelle fiche rattacher les informations capturées.
- FR-015: Le système DOIT exposer un endpoint permettant à un client externe authentifié de récupérer le contexte courant de l'utilisateur (type d'entité, identifiant, nom affichable).
- FR-016: Le système DOIT afficher, pour chaque Objectif, un tableau de bord présentant la répartition des Tâches rattachées par statut.
- FR-017: Le système DOIT permettre à un utilisateur de créer un compte et de s'authentifier.
- FR-018: Le système DOIT isoler les données (Objectifs, Entreprises, Personnes, Tâches, mappings, contexte courant) par utilisateur.

## Exigences non-fonctionnelles
- NFR-001: Sécurité — l'API destinée au client externe DOIT être authentifiée par le même mécanisme JWT Bearer que le reste de l'application. L'endpoint de login (FR-017) DOIT rester un endpoint HTTP générique, utilisable par tout client (frontend Next.js, extension de navigateur, ou autre), sans dépendance à un cookie de session propre au frontend web.
- NFR-002: Sécurité — les mots de passe DOIVENT être hashés (bcrypt ou équivalent), jamais stockés en clair.
- NFR-003: Conformité — la suppression d'un compte utilisateur DOIT entraîner la suppression en cascade de toutes ses données.
- NFR-004: Disponibilité — un échec de l'API SIREN externe ne DOIT jamais empêcher la création ou la modification d'une Entreprise.
- NFR-005: Anti-abus — le système DOIT limiter la fréquence de récupération des dirigeants d'une même Entreprise à un appel par intervalle configurable (défaut : 1 jour).
- NFR-006: Fiabilité — le contexte courant DOIT expirer après une période d'inactivité configurable (défaut : 30 minutes).

## Utilisateurs et rôles
- Utilisateur : seul rôle de cette version. Gère ses propres Objectifs/Entreprises/Personnes/Tâches, totalement isolé des autres utilisateurs.

## Scénarios d'acceptation
- AC-001: Given un utilisateur authentifié, When il crée un Objectif avec un titre, Then l'Objectif apparaît dans sa liste avec un tableau de bord à 0 tâche.
- AC-002: Given un Objectif existant, When l'utilisateur y rattache une Entreprise, Then l'Entreprise apparaît dans la liste des entreprises liées à cet Objectif.
- AC-003: Given une Entreprise et une Personne existantes, When l'utilisateur rattache la Personne à l'Entreprise, Then la Personne apparaît dans les contacts de l'Entreprise.
- AC-004: Given un fichier CSV de 50 entreprises et un mapping configuré, When l'utilisateur lance l'import, Then les entreprises sont créées ou mises à jour selon leur SIREN, et un rapport détaille le résultat.
- AC-005: Given une Entreprise avec un SIREN valide, When l'utilisateur clique sur "Récupérer les dirigeants", Then la liste des dirigeants s'affiche et la date de dernière récupération est mise à jour.
- AC-006: Given une Entreprise dont les dirigeants ont été récupérés il y a moins d'un jour, When l'utilisateur reclique sur "Récupérer les dirigeants", Then le système affiche le résultat déjà connu sans rappeler l'API externe.
- AC-007: Given une fiche Personne ouverte, When l'utilisateur clique sur "Rechercher", Then un nouvel onglet s'ouvre et le contexte courant est mis à jour avec cette Personne.
- AC-008: Given un contexte courant actif pointant vers "Jean Dupont", When le client externe envoie des informations capturées, Then ces informations sont enregistrées sur la fiche de Jean Dupont.
- AC-009: Given un contexte courant expiré (plus de 30 minutes), When le client externe tente d'envoyer des informations, Then l'API renvoie une erreur explicite et aucune donnée n'est enregistrée.
- AC-010: Given un Objectif avec 10 tâches (6 Terminée, 2 En cours, 2 À faire), When l'utilisateur consulte son tableau de bord, Then il voit la répartition par statut (60%/20%/20%).

## Edge cases
- EC-001: Import du même fichier CSV deux fois → upsert par SIREN/email, pas de doublon.
- EC-002: Clics répétés sur "Récupérer les dirigeants" avant l'intervalle minimum → résultat en cache renvoyé, date de dernière récupération affichée.
- EC-003: SIREN invalide ou API SIREN indisponible → message d'erreur explicite, Entreprise inchangée.
- EC-004: Suppression d'une Entreprise/Personne avec des Tâches actives (À faire/En cours) rattachées → suppression bloquée, message invitant à clore/réaffecter.
- EC-005: Suppression d'une Entreprise/Personne dont toutes les tâches sont Terminée/Annulée → suppression autorisée.
- EC-006: Ouverture de plusieurs fiches dans des onglets différents avant l'envoi par le client externe → le contexte courant est écrasé par le dernier "Rechercher" cliqué ; le nom de l'entité concernée est toujours affiché avant l'envoi pour permettre à l'utilisateur de détecter l'erreur.
- EC-007: Appel à l'API d'enregistrement sans contexte courant défini ou avec un contexte expiré → erreur explicite invitant à recliquer sur "Rechercher".
- EC-008: Tentative d'accès à une Entreprise/Personne/Objectif/Tâche appartenant à un autre utilisateur → refusé (404, sans révéler l'existence de la ressource à l'utilisateur non autorisé).

## Critères de succès
- Un import de 100 entreprises avec mapping de champs s'effectue en moins de 5 minutes.
- Le tableau de bord d'un objectif reflète la progression des tâches sans délai perceptible pour l'utilisateur.
- Une information capturée par le client externe est visible sur la fiche correspondante en quelques secondes.
- Aucune donnée n'est perdue ou altérée par erreur en cas d'indisponibilité de l'API SIREN externe.
- L'utilisateur peut vérifier visuellement, avant chaque envoi depuis le client externe, quelle fiche est concernée.

## Entités métier
- **Objectif** : titre, description, date cible (optionnelle), statut (actif/atteint/abandonné)
- **Entreprise** : nom, SIREN (optionnel), secteur (optionnel), site web (optionnel), dirigeants (alimentés via API SIREN), date de dernière récupération des dirigeants
- **Personne** : nom, prénom, email (optionnel), poste (optionnel), téléphone (optionnel)
- **Tâche** : titre, description, statut (À faire/En cours/Terminée/Annulée), échéance (optionnelle), priorité (basse/moyenne/haute)
- **Modèle de mapping CSV** : nom, type d'entité (Entreprise/Personne), correspondance colonnes→champs
- **Contexte courant** : pointeur léger par utilisateur (type d'entité, identifiant, nom affichable, horodatage) — expire après 30 min d'inactivité, pas de persistance longue

## Intégrations externes
- **API SIREN** (URL configurable) : récupération des dirigeants d'une Entreprise. Échec → erreur affichée, aucune donnée modifiée.
- **Client externe (extension Chrome, hors périmètre)** : consomme l'API d'enregistrement d'informations et l'API de contexte courant, authentifié par JWT Bearer.

## Contraintes techniques
- Stack : Python (FastAPI) + TypeScript (Next.js)

## Niveau de charge
FAIBLE — usage mono à quelques utilisateurs, pas de pic de charge attendu.

## Hors périmètre
- Développement, packaging et distribution de l'extension Chrome elle-même
- Fonctionnalités RGPD avancées (export, anonymisation) — suppression en cascade uniquement
- Création de nouvelles fiches Entreprise/Personne depuis le client externe — enrichissement uniquement
- Retry automatique en arrière-plan pour l'API SIREN
- Rôles et permissions différenciés entre utilisateurs
- Notifications (email/push) de rappel de tâches

## Hypothèses
- Champs détaillés des entités déduits des besoins exprimés, non confirmés un par un — ajustables via `/add`
- Expiration du contexte courant fixée à 30 minutes par défaut, configurable
- Intervalle minimum entre deux récupérations de dirigeants fixé à 1 jour par défaut, configurable
- Le bouton "Rechercher" ouvre un nouvel onglet de recherche générique — le ciblage précis n'est pas spécifié
- L'extension Chrome implémente elle-même un formulaire de login (email/mot de passe) qui appelle `/auth/login` pour obtenir son JWT — ce formulaire n'est pas développé dans ce projet, seul l'endpoint backend doit rester accessible à un client externe

## Blueprint identifié
crm + saas-multitenant

## Configuration environnement
- Venv Python : à créer (`.venv` à la racine)
- Base de données : existante — localhost:5434, user postgres, password postgres, dbname `reachmygoals` (à créer)

## Checklist qualité
- [x] Aucun détail d'implémentation dans les Critères de succès
- [x] Chaque exigence fonctionnelle (FR-xxx) est testable et non ambiguë
- [x] Chaque exigence non-fonctionnelle (NFR-xxx) est mesurable
- [x] Les scénarios d'acceptation couvrent les flux principaux
- [x] Les edge cases couvrent les cas d'erreur et les accès non autorisés
- [x] Le périmètre est clairement borné (Hors périmètre rempli)
- [x] Chaque hypothèse non confirmée par l'utilisateur est documentée
- [x] Niveau de charge renseigné avec justification

## Couverture par catégorie
| Catégorie | Statut |
|---|---|
| Périmètre fonctionnel | Résolu |
| Modèle de données | Résolu |
| Flux UX et interaction | Différé (faible impact, hypothèses) |
| Exigences non-fonctionnelles | Résolu |
| Intégrations externes | Résolu |
| Edge cases et erreurs | Résolu |
| Contraintes techniques et blueprint | Résolu (déduit) |
| Terminologie | Clair |
| Signaux de complétion | Résolu |
| Volume et niveau de charge | Résolu |
| Configuration d'exécution | Résolu |
