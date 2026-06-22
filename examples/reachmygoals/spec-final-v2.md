# Spec — Reach Your Goals

## Résumé
Outil multi-utilisateur de suivi d'atteinte d'objectifs (ex : trouver un emploi, trouver des personnes à interviewer). Chaque utilisateur authentifié gère ses propres Objectifs et Tâches, en s'appuyant sur une base d'Entreprises et de Personnes partagée entre tous les utilisateurs, enrichie manuellement, par import CSV, par récupération automatique des dirigeants via une API publique (SIREN), et par une extension Chrome (hors périmètre) qui capture le contenu texte de pages web via une API d'ingestion authentifiée.

## Exigences fonctionnelles
- FR-001: Le système DOIT permettre à un utilisateur de créer un compte et de s'authentifier (JWT) avant d'accéder à l'application.
- FR-002: Le système DOIT permettre de créer manuellement un Objectif, une Entreprise, une Personne et une Tâche.
- FR-003: Le système DOIT permettre de rattacher une ou plusieurs Entreprises à un Objectif, et inversement.
- FR-004: Le système DOIT permettre de rattacher une ou plusieurs Personnes à une ou plusieurs Entreprises.
- FR-005: Le système DOIT permettre de rattacher une ou plusieurs Personnes à un ou plusieurs Objectifs.
- FR-006: Le système DOIT permettre de créer une Tâche générique (sans Objectif) ou une Tâche rattachée à un Objectif ; dans ce dernier cas, la Tâche peut en plus être rattachée à une Entreprise et/ou une Personne déjà liée à cet Objectif.
- FR-007: Le système DOIT afficher, pour chaque Objectif, un tableau de bord montrant la répartition des Tâches par statut, les Entreprises et Personnes rattachées, et les Tâches en retard.
- FR-008: Le système DOIT permettre d'importer des Entreprises depuis un fichier CSV, avec une interface de mapping entre les colonnes du fichier et les champs de la base.
- FR-009: Le système DOIT permettre d'importer des Personnes depuis un fichier CSV, avec une interface de mapping entre les colonnes du fichier et les champs de la base.
- FR-010: Lors d'un import CSV, si une Entreprise avec le même SIREN, ou une Personne avec la même combinaison nom + prénom + Entreprise, existe déjà, le système DOIT mettre à jour l'enregistrement existant plutôt que d'en créer un doublon.
- FR-011: Le système DOIT permettre de récupérer les dirigeants d'une Entreprise individuelle à partir de son numéro SIREN via l'API Recherche d'entreprises (gouv.fr).
- FR-012: Le système DOIT permettre de lancer une récupération en masse des dirigeants pour toutes les Entreprises de l'application, limitée à 30 000 Entreprises par passe.
- FR-013: Le système DOIT empêcher le déclenchement d'une nouvelle récupération en masse des dirigeants tant qu'une récupération est déjà en cours (verrou applicatif global), et informer l'utilisateur qu'un traitement est déjà actif.
- FR-014: L'URL de base de l'API de récupération SIREN DOIT être configurable via une variable d'environnement.
- FR-015: Le système DOIT exposer une API authentifiée par token JWT utilisateur permettant d'enregistrer le contenu texte brut d'une page web, horodaté, rattaché à exactement une Entreprise ou une Personne existante désignée explicitement par son identifiant (`entreprise_id` ou `personne_id`) dans la requête.
- FR-016: Les colonnes des tableaux listant Entreprises, Personnes, Objectifs et Tâches DOIVENT être triables et filtrables.
- FR-019: Le système DOIT exposer une API de contexte, authentifiée par JWT, permettant de récupérer — à partir d'un `personne_id` — le nom, le prénom de la Personne et le nom de toutes les Entreprises auxquelles elle est rattachée, ou — à partir d'un `entreprise_id` — le nom de l'Entreprise. Cette API est destinée à l'affichage d'un récapitulatif de confirmation par l'extension Chrome avant l'envoi d'une capture.
- FR-017: Le système DOIT permettre à un utilisateur authentifié de demander la suppression définitive (RGPD) des données personnelles d'une Entreprise ou d'une Personne, indépendamment des rattachements existants chez d'autres utilisateurs, et journaliser cette action (qui, quand).
- FR-018: En dehors d'une demande de suppression RGPD, le retrait d'une Entreprise ou d'une Personne par un utilisateur DOIT être un retrait logique qui ne supprime pas la donnée pour les autres utilisateurs qui la référencent.

## Exigences non-fonctionnelles
- NFR-001: Charge — FAIBLE (< 100 utilisateurs simultanés). Architecture standard, pas de cache ni de queue dédiée.
- NFR-002: Sécurité — Authentification JWT obligatoire pour tous les accès applicatifs et pour l'API d'ingestion de l'extension Chrome ; aucun accès anonyme.
- NFR-003: Sécurité — Les mots de passe utilisateurs sont hashés (bcrypt ou équivalent), jamais stockés en clair.
- NFR-004: Conformité — RGPD : un utilisateur peut déclencher la suppression définitive des données personnelles d'une Entreprise ou d'une Personne ; chaque suppression est journalisée avec l'identité du demandeur et l'horodatage.
- NFR-005: Contrainte externe — Le système DOIT gérer l'indisponibilité de l'API SIREN externe (timeout, erreur HTTP) sans interrompre le reste du traitement, en journalisant les échecs individuellement lors d'un traitement en masse.
- NFR-006: Contrainte externe — Le système DOIT respecter le rate-limit imposé par l'API SIREN externe (pause/backoff entre appels) afin d'éviter un blocage de l'accès à l'API.
- NFR-007: Disponibilité — Pas de SLA formel ; une interruption ponctuelle pour maintenance ou en cas de panne est acceptable, sans haute disponibilité (pas de réplication ni de failover automatique).

## Utilisateurs et rôles
- Utilisateur (rôle unique) : s'authentifie, crée et gère ses propres Objectifs et Tâches, consulte et enrichit la base partagée d'Entreprises et de Personnes (création, import CSV, récupération SIREN, capture via extension), peut déclencher une suppression RGPD sur une Entreprise ou une Personne.

## Scénarios d'acceptation
- AC-001: Given un utilisateur authentifié, When il crée un Objectif avec un titre, Then l'Objectif apparaît dans sa liste personnelle avec le statut "actif".
- AC-002: Given un Objectif appartenant à l'utilisateur connecté, When il y rattache une Entreprise existante, Then l'Entreprise apparaît dans la liste des Entreprises liées à cet Objectif, visible par tous les utilisateurs qui consultent cette Entreprise.
- AC-003: Given une Personne existante, When un utilisateur la rattache à une Entreprise, Then la relation est visible par tous les utilisateurs consultant cette Personne ou cette Entreprise.
- AC-004: Given un Objectif appartenant à l'utilisateur connecté avec une Entreprise déjà liée, When il crée une Tâche rattachée à cet Objectif et à cette Entreprise, Then la Tâche apparaît dans le tableau de bord de l'Objectif avec le statut "à faire".
- AC-005: Given une Tâche générique créée sans Objectif, When elle est consultée, Then elle apparaît dans la liste des tâches génériques de l'utilisateur et dans aucun tableau de bord d'Objectif.
- AC-006: Given un fichier CSV d'Entreprises et un mapping de colonnes configuré, When l'utilisateur lance l'import, Then chaque ligne crée une nouvelle Entreprise ou met à jour l'Entreprise existante de même SIREN.
- AC-007: Given un fichier CSV de Personnes et un mapping de colonnes configuré, When l'utilisateur lance l'import, Then chaque ligne crée une nouvelle Personne ou met à jour la Personne existante de même nom + prénom + Entreprise.
- AC-008: Given une Entreprise avec un SIREN valide, When l'utilisateur déclenche la récupération individuelle des dirigeants, Then les Personnes correspondantes sont créées ou mises à jour et rattachées à l'Entreprise.
- AC-009: Given un ensemble d'Entreprises avec SIREN ne dépassant pas 30 000, When l'utilisateur déclenche la récupération en masse, Then le système traite toutes les Entreprises et journalise les succès et les échecs individuellement.
- AC-010: Given une récupération en masse déjà en cours, When l'utilisateur clique à nouveau sur le bouton de récupération, Then le système ne démarre pas un second traitement et affiche un message indiquant qu'un traitement est déjà en cours.
- AC-011: Given un token JWT valide et un `entreprise_id` ou `personne_id` explicite dans la requête, When l'extension Chrome envoie le contenu texte d'une page via l'API d'ingestion, Then un enregistrement horodaté est créé, associé à l'utilisateur du token et à l'entité désignée.
- AC-016: Given un `personne_id` valide, When l'API de contexte est appelée, Then la réponse contient le nom, le prénom de la Personne et le nom de toutes les Entreprises auxquelles elle est rattachée.
- AC-017: Given un `entreprise_id` valide, When l'API de contexte est appelée, Then la réponse contient le nom de l'Entreprise.
- AC-012: Given une liste d'Entreprises affichée, When l'utilisateur trie ou filtre sur une colonne, Then la liste affichée est réordonnée ou filtrée en conséquence.
- AC-013: Given une Entreprise ou une Personne référencée par d'autres utilisateurs, When un utilisateur la retire de sa propre vue sans demande RGPD, Then elle reste visible et utilisable par les autres utilisateurs.
- AC-014: Given une Entreprise ou une Personne, When un utilisateur initie une demande de suppression RGPD, Then ses données personnelles sont définitivement effacées, l'action est journalisée, et les Tâches/Objectifs d'autres utilisateurs qui la référençaient affichent une référence supprimée.
- AC-015: Given un Objectif passé au statut "atteint" ou "abandonné", When l'utilisateur consulte la liste des Objectifs actifs, Then cet Objectif n'y apparaît plus mais reste consultable dans l'historique.

## Edge cases
- EC-001: Que se passe-t-il si l'API SIREN externe est indisponible pendant une récupération en masse ? Le système journalise l'échec entreprise par entreprise, poursuit le traitement des suivantes, et permet de relancer uniquement les échecs.
- EC-002: Que se passe-t-il si l'utilisateur clique plusieurs fois de suite sur le bouton de récupération en masse ? Les clics suivants sont ignorés tant qu'un traitement est en cours (verrou applicatif global).
- EC-003: Que se passe-t-il si le rate-limit de l'API SIREN est atteint ? Le système applique un backoff et reprend automatiquement, sans provoquer de blocage de l'accès à l'API.
- EC-004: Que se passe-t-il si un fichier CSV contient des lignes mal formées ou avec des champs obligatoires manquants ? La ligne est ignorée et journalisée comme erreur, le reste de l'import se poursuit.
- EC-005: Que se passe-t-il si l'extension Chrome envoie une requête avec un token JWT invalide ou expiré ? L'API retourne une erreur 401 et n'enregistre aucune donnée.
- EC-006: Que se passe-t-il si la requête de capture web ne précise ni Entreprise ni Personne, ou précise les deux ? La requête est rejetée avec une erreur 400.
- EC-007: Que se passe-t-il si un utilisateur tente d'accéder à un Objectif ou une Tâche appartenant à un autre utilisateur ? L'accès est refusé (erreur 403/404).
- EC-008: Que se passe-t-il si une Entreprise a un SIREN au format invalide lors d'une récupération individuelle ou en masse ? L'entrée est ignorée et journalisée comme erreur, sans interrompre le reste du traitement.
- EC-009: Que se passe-t-il si deux utilisateurs modifient simultanément la même Entreprise ou Personne partagée ? La dernière écriture l'emporte ; aucun verrouillage de modification concurrente n'est requis pour cette version.
- EC-010: Que se passe-t-il si l'utilisateur demande la suppression RGPD d'une Personne encore référencée par des Tâches actives d'autres utilisateurs ? La suppression est effectuée malgré tout (priorité au droit à l'oubli) ; les Tâches concernées affichent une référence "personne supprimée".
- EC-011: Que se passe-t-il si l'API de contexte ou l'API d'ingestion reçoit un `entreprise_id`/`personne_id` qui n'existe pas ? Le système retourne une erreur 404 et n'enregistre aucune donnée.
- EC-012: Que se passe-t-il si le contexte mémorisé par l'extension correspond à un onglet précédent différent de celui réellement actif (ex: deux recherches ouvertes sans repasser par l'application) ? Le système ne peut pas le détecter côté serveur ; le risque est atténué par l'affichage du récapitulatif de contexte (FR-019) que l'extension doit présenter à l'utilisateur avant l'envoi, mais sa prévention reste de la responsabilité de l'extension (hors périmètre).

## Critères de succès
- Un utilisateur peut suivre, pour chaque objectif, l'avancement de ses tâches sans consulter d'autre outil.
- Une liste d'entreprises ou de personnes peut être importée depuis un fichier CSV externe sans saisie manuelle ligne par ligne.
- La récupération des dirigeants aboutit pour les entreprises ayant un SIREN valide, sans provoquer de blocage d'accès à l'API externe utilisée.
- Une demande de suppression RGPD aboutit à l'effacement réel des données personnelles concernées, de façon traçable.

## Entités métier
- Utilisateur : identifiant, email, mot de passe hashé, date de création.
- Objectif : identifiant, utilisateur propriétaire, titre, description, statut (actif / atteint / abandonné), dates de création/modification.
- Entreprise : identifiant, nom, SIREN (unique), champs issus du mapping CSV, dates de création/modification. Partagée entre tous les utilisateurs.
- Personne : identifiant, nom, prénom, fonction, champs issus du mapping CSV, dates de création/modification. Partagée entre tous les utilisateurs.
- Tâche : identifiant, utilisateur propriétaire, titre, description, statut (à faire / en cours / terminée / annulée), Objectif rattaché (optionnel), Entreprise rattachée (optionnelle, uniquement si Objectif renseigné), Personne rattachée (optionnelle, uniquement si Objectif renseigné), dates de création/modification.
- CaptureWeb : identifiant, contenu texte brut, horodatage, utilisateur ayant capturé, Entreprise OU Personne rattachée (exactement une des deux).
- Relations N-N : Objectif↔Entreprise, Objectif↔Personne, Personne↔Entreprise.

## Intégrations externes
- API Recherche d'entreprises (gouv.fr) : récupération des dirigeants par numéro SIREN. URL de base configurable via variable d'environnement, pas de clé d'authentification requise. Mode d'échec : indisponibilité et rate-limit gérés avec retry/backoff et journalisation individuelle par entreprise.
- Extension Chrome (hors périmètre du projet) : utilise l'API de contexte (FR-019) pour afficher un récapitulatif de confirmation, puis envoie le contenu texte brut d'une page web vers l'API d'ingestion (FR-015) authentifiée par JWT, avec l'identifiant explicite de la cible. Le mécanisme par lequel l'extension détermine cet identifiant (lecture de l'URL de la fiche dans l'application, mémorisation dans le stockage propre de l'extension) est interne à l'extension et hors périmètre.

## Hors périmètre
- Développement, distribution et store de l'extension Chrome — seule l'API qui la reçoit fait partie de ce projet.
- Rôle admin distinct ou RBAC différencié au-delà de l'authentification utilisateur standard.
- Verrouillage optimiste/pessimiste sur l'édition concurrente des Entreprises/Personnes partagées.
- Haute disponibilité (réplication, failover automatique).
- Export ou notification automatique des données, hors le processus de suppression RGPD ponctuel décrit.
- Détection ou prévention côté serveur d'un contexte d'extension obsolète (ex: capture envoyée vers la mauvaise Personne/Entreprise faute d'avoir réactivé le contexte sur un nouvel onglet) — atténué côté UX par l'API de contexte, mais la prévention reste de la responsabilité de l'extension elle-même.

## Hypothèses
- Le contenu précis du tableau de bord d'un Objectif (répartition des tâches par statut, entreprises/personnes liées, tâches en retard) est un choix d'affichage ajustable en implémentation, sans impact architectural majeur.
- Le dédoublonnage des Personnes lors de l'import CSV se base sur la combinaison nom + prénom + Entreprise rattachée, à défaut d'identifiant unique fourni.
- L'enregistrement CaptureWeb inclut le contenu texte, un horodatage, l'utilisateur capturant et l'entité liée ; l'URL source de la page est conservée si fournie par l'extension, mais reste optionnelle puisque l'extension n'est pas définie dans ce projet.
- Les identifiants des fiches Entreprise/Personne sont visibles dans l'URL de l'application (ex: `/entreprises/{id}`, `/personnes/{id}`), ce qui permet à l'extension de les récupérer sans intégration applicative dédiée.
- L'API de contexte ne conserve aucun état serveur entre deux appels (lookup pur par identifiant) : aucun risque de fuite de contexte entre deux utilisateurs ou deux sessions différentes.
- En cas de modification concurrente d'une même Entreprise/Personne partagée, la dernière écriture l'emporte (pas de verrouillage optimiste), cohérent avec la charge FAIBLE.
- La suppression d'un Objectif par son propriétaire entraîne la suppression en cascade de ses Tâches rattachées, celles-ci n'étant jamais partagées entre utilisateurs.

## Configuration environnement
- Venv Python : `.venv` (à créer à la racine du projet)
- Base de données : existante — PostgreSQL, `localhost:5434`, base `reach_your_goals` (à créer dans cette instance), utilisateur `postgres`. Le mot de passe DOIT être fourni via une variable d'environnement (ex: `DATABASE_URL`), jamais en dur dans le code.

## Checklist qualité
- [x] Aucun détail d'implémentation dans les Critères de succès
- [x] Chaque exigence fonctionnelle (FR-xxx) est testable et non ambiguë
- [x] Chaque exigence non-fonctionnelle (NFR-xxx) est mesurable, y compris la NFR-Charge
- [x] Les scénarios d'acceptation couvrent les flux principaux
- [x] Les edge cases couvrent les cas d'erreur et les accès non autorisés
- [x] Le périmètre est clairement borné (Hors périmètre rempli)
- [x] Chaque hypothèse non confirmée par l'utilisateur est documentée

## Couverture par catégorie
| Catégorie | Statut |
|---|---|
| Périmètre fonctionnel | Résolu |
| Modèle de données | Résolu |
| Flux UX et interaction | Résolu (détail dashboard différé en hypothèse) |
| Exigences non-fonctionnelles | Résolu |
| Intégrations externes | Résolu |
| Edge cases et erreurs | Résolu |
| Terminologie | Clair |
| Signaux de complétion | Résolu |
| Configuration d'exécution | Résolu |
