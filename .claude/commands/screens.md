# /screens — Description des écrans de l'application

## Objectif

Décomposer `spec-final.md` en une liste concrète des écrans de l'application (un écran = un ou plusieurs FR-xxx pour un rôle humain donné), proposer un système de design cohérent avec un aperçu HTML pour validation visuelle, présenter le tout à l'utilisateur pour validation explicite et correction, puis générer `screens-final.md` — le contrat que `/implement` DOIT suivre pour construire le frontend, et la référence utilisée pour vérifier après coup que rien n'a été oublié.

Contrairement à `/spec` (boucle de questions sur des zones d'ombre), `/screens` part d'une spec déjà validée et complète — il n'y a pas d'ambiguïté à résoudre, seulement un découpage à proposer puis à faire valider ou corriger par l'utilisateur.

## Processus

### Étape 1 — Lire la spec

Lire `spec-final.md`. Si absent, stopper et demander d'exécuter `/spec` d'abord.

### Étape 2 — Identifier les FR-xxx nécessitant un écran

Reprendre la classification par acteur de `## Utilisateurs et rôles` (la même que celle qu'utilise `/implement`, étape 4 — "Couverture frontend par FR-xxx") :

- **Acteur = rôle humain** (Utilisateur, Admin...) : nécessite un écran.
- **Acteur = système externe** (API tierce, client externe type extension navigateur) : aucun écran à prévoir, exclu de la suite.

Si une FR-xxx énumère plusieurs cibles (cf règle d'atomicité de `/spec`), elle a normalement déjà été scindée en plusieurs FR-xxx distinctes à ce stade — si ce n'est pas le cas (spec antérieure à cette règle), traiter chaque cible séparément ici malgré tout.

### Étape 3 — Définir le layout général

Avant de découper les écrans individuels, décrire le ou les layouts partagés (header, navigation, footer) — c'est un standard Next.js (`layout.tsx`), distinct du contenu de chaque écran, et il conditionne l'ergonomie de toute l'application. Un seul layout suffit dans le cas simple ; plusieurs sont nécessaires si certaines sections ont une présentation distincte (ex: layout public minimal pour `/login` vs layout applicatif avec navigation pour le reste).

| Champ | Contenu |
|---|---|
| Layout | Nom (ex: "Layout applicatif", "Layout public") |
| Écrans concernés | Liste des écrans qui l'utilisent (renseignée après l'étape 4) |
| Header | Contenu (logo, nom de l'app, menu utilisateur, notifications...) et actions disponibles |
| Navigation | Liens principaux et leur **visibilité par rôle** si elle diffère (ex: lien "Utilisateurs" visible uniquement pour Admin — reprendre `## Utilisateurs et rôles` de `spec-final.md`) |
| Footer | Contenu si pertinent (souvent minimal ou absent dans une application interne) |
| Variantes | États particuliers du layout, uniquement si explicitement nécessaire (ex: navigation repliée sur mobile) |

Le layout n'est jamais déduit silencieusement de l'arborescence Next.js — il doit être explicitement décrit et validé, au même titre que les écrans.

### Étape 4 — Regrouper les FR-xxx en écrans

Un écran peut couvrir plusieurs FR-xxx (ex: une page "Objectifs" couvre la création, la liste et le tableau de bord). Une FR-xxx peut nécessiter plusieurs écrans (ex: liste + détail). Décrire ce découpage explicitement, pour chaque écran :

| Champ | Contenu |
|---|---|
| Écran | Nom convivial (ex: "Tableau de bord d'un objectif") |
| Route | Chemin frontend (ex: `/objectifs/[id]`) |
| Layout | Quel layout de l'étape 3 il utilise (uniquement si plusieurs layouts existent) |
| Rôle(s) | Qui y a accès |
| FR-xxx couvertes | Liste des identifiants |
| Objectif | Une phrase |
| Éléments clés | Formulaires, tableaux, boutons d'action, modales... — pour un écran liste/tableau ou CRUD, voir le sous-format obligatoire ci-dessous |
| Navigation | D'où on y arrive, vers où on peut aller depuis cet écran |
| États particuliers | Vide / chargement / erreur, uniquement si un AC-xxx ou EC-xxx de la spec l'exige explicitement — sinon "standard" |

**Sous-format obligatoire pour tout écran liste/tableau ou CRUD** — un oubli ici (bouton manquant, colonne non précisée) n'est visible qu'une fois le frontend codé, donc jamais laissé implicite :

| Sous-champ | Contenu |
|---|---|
| Actions CRUD | Pour chaque action présente (Ajouter / Modifier / Supprimer / Dupliquer...) : où elle se trouve (bouton en tête de liste, icône par ligne, menu contextuel...) et ce qu'elle déclenche (modale, page dédiée, confirmation avant suppression) — et explicitement lesquelles sont **absentes** si l'entité n'est pas éditable/supprimable |
| Colonnes | Pour chaque colonne du tableau : triable (oui/non), filtrable (oui/non), déplaçable/réordonnable (oui/non) |

### Étape 4b — Proposer un système de design

Avant de générer l'aperçu, proposer une direction esthétique cohérente pour l'application — sans recherche externe, directement à partir du contexte de `spec-final.md` (type de produit, ton, public visé) et des écrans définis à l'étape 4.

**Direction esthétique** — choisir celle qui correspond le mieux au produit et la justifier en 2-3 phrases ; ne jamais la présenter comme un menu à cocher :

| Direction | Quand l'utiliser |
|---|---|
| Minimaliste neutre | Outil interne, dashboard, focus sur la donnée — défaut le plus sûr |
| Éditorial dense | Fort volume d'information à hiérarchiser (reporting, CRM) |
| Utilitaire industriel | Outil technique, pipeline de données, monospace en accent |
| Chaleureux accessible | Support client, produit grand public — l'accueil compte |
| Raffiné | SaaS orienté décideurs/vente, présentation à des clients externes |

**Typographie** — 2-3 polices précises (jamais "à définir") :
- Display/titres : Satoshi, General Sans, Instrument Serif, Fraunces, Cabinet Grotesk...
- Texte courant : Instrument Sans, DM Sans, Source Sans 3, Geist, Plus Jakarta Sans...
- Données/tableaux : Geist ou DM Sans (`tabular-nums`), JetBrains Mono, IBM Plex Mono

**Anti-slop** — jamais dans la proposition :
- Fonts interdites : Papyrus, Comic Sans, Impact, Lobster, Bradley Hand, Trajan, Courier New (en body)
- Fonts trop vues à éviter en primary sauf demande explicite de l'utilisateur : Inter, Roboto, Arial, Helvetica, Open Sans, Lato, Montserrat, Poppins, Space Grotesk
- Patterns interdits : gradient violet par défaut, grille 3 colonnes avec icônes en cercles colorés, tout centré, `border-radius` bulle partout, CTA en gradient, `system-ui`/`-apple-system` en display (signal "typo abandonnée")

**Couleurs** : primary, secondary (optionnel), neutres (5-7 nuances clair → foncé), sémantiques (succès/avertissement/erreur/info) — en hex.

**Espacement et rayons** : unité de base (4px ou 8px) + échelle, `border-radius` (sm/md/lg).

Présenter le système en un seul bloc, prêt à copier dans `app/globals.css` (voir skill `nextjs` — section "Variables CSS globales") :

```css
:root {
  --color-primary: #XXXXXX;
  --color-secondary: #XXXXXX;
  --color-text: #XXXXXX;
  --color-bg: #XXXXXX;
  --color-success: #XXXXXX;
  --color-warning: #XXXXXX;
  --color-error: #XXXXXX;
  --font-display: "<police>", sans-serif;
  --font-sans: "<police>", sans-serif;
  --font-mono: "<police>", monospace;
  --radius-sm: Xpx;
  --radius-md: Xpx;
  --radius-lg: Xpx;
  --space-sm: Xpx;
  --space-md: Xpx;
  --space-lg: Xpx;
}
```

### Étape 4c — Générer l'aperçu HTML

Identifier les patterns d'écran distincts parmi ceux de l'étape 4 (liste/tableau, formulaire/CRUD, dashboard, détail, authentification...) — un écran représentatif par pattern, maximum 5 pour rester lisible en une seule passe de validation.

Pour chaque écran retenu, générer un fichier HTML autonome (CSS inline, pas de build, pas de framework) dans `screens-preview/<slug-ecran>.html` :
- Layout partagé (header/navigation/footer de l'étape 3) rendu autour du contenu
- Contenu réel de l'écran — noms de champs, colonnes, actions CRUD, libellés tels que décrits à l'étape 4 (pas de lorem ipsum, pas de placeholder générique)
- Tokens du système de design de l'étape 4b appliqués (couleurs, typographie, espacement)

Ouvrir les fichiers générés avec la commande adaptée à la plateforme (`open` macOS, `xdg-open` Linux, `start` Windows).

`screens-preview/` est un artefact jetable pour validation visuelle uniquement — `/implement` ne le lit jamais, il construit le vrai frontend Next.js à partir du texte de `screens-final.md`. Suggérer de l'ajouter au `.gitignore` du projet si absent.

### Étape 5 — Présenter pour validation

Afficher le layout général (étape 3), le tableau complet des écrans (étape 4), le système de design (étape 4b) et le chemin des fichiers d'aperçu générés (étape 4c) à l'utilisateur, et demander explicitement :

> "Validez-vous ce layout, ce découpage en écrans et ce système de design (voir l'aperçu HTML), ou souhaitez-vous des corrections (header/navigation/footer, ajout, suppression, fusion ou découpage d'un écran, ajustement des éléments listés, direction esthétique, typographie, couleurs) ?"

Itérer sans limite de tours tant que l'utilisateur demande des corrections — ce n'est pas une boucle de questions sur des inconnues comme `/spec`, mais une boucle de relecture/correction d'un document déjà complet. Si une correction touche le système de design (couleurs, typographie, direction esthétique), régénérer les fichiers HTML de l'étape 4c concernés avant de redemander validation. Ne jamais générer `screens-final.md` sans validation explicite ("oui"/"valide"/"ok" ou équivalent) — pas d'auto-validation silencieuse ici, contrairement à l'auto-validation de `/spec` : c'est un choix délibéré, l'utilisateur veut un vrai point d'arrêt humain sur ce document avant que `/implement` ne s'en empare comme contrat.

### Étape 6 — Générer screens-final.md

Une fois validé, écrire `screens-final.md` :

```markdown
# Écrans — [Nom du projet]

## Layout : [Nom du layout]
- Écrans concernés : ...
- Header : ...
- Navigation : ... (visibilité par rôle si elle diffère)
- Footer : ...
- Variantes : ...

## ... (un par layout si plusieurs)

## Système de design
- Direction esthétique : [nom] — [justification 2-3 phrases]
- Typographie : Display `<police>` / Texte `<police>` / Données `<police>`
- Aperçu HTML : `screens-preview/` ([N] écrans représentatifs)

```css
:root {
  --color-primary: #XXXXXX;
  --color-secondary: #XXXXXX;
  --color-text: #XXXXXX;
  --color-bg: #XXXXXX;
  --color-success: #XXXXXX;
  --color-warning: #XXXXXX;
  --color-error: #XXXXXX;
  --font-display: "<police>", sans-serif;
  --font-sans: "<police>", sans-serif;
  --font-mono: "<police>", monospace;
  --radius-sm: Xpx;
  --radius-md: Xpx;
  --radius-lg: Xpx;
  --space-sm: Xpx;
  --space-md: Xpx;
  --space-lg: Xpx;
}
```

## [Nom de l'écran]
- Route : `/chemin/[param]`
- Layout : [Nom du layout] (uniquement si plusieurs layouts existent)
- Rôle(s) : ...
- FR-xxx couvertes : FR-00X, FR-00Y
- Objectif : ...
- Éléments clés : ...
  - (si liste/tableau ou CRUD) Actions CRUD : ...
  - (si liste/tableau ou CRUD) Colonnes : Nom (triable, filtrable, non déplaçable), ...
- Navigation : ...
- États particuliers : ...

## ...

## Couverture FR-xxx
| FR-xxx | Écran(s) | Couvert |
|---|---|---|
| FR-00X | Nom de l'écran | ✅ |
```

### Étape 7 — Rapport de complétion

Rapporter à l'utilisateur :
- Chemin de `screens-final.md`
- Layout(s) générés et nombre d'écrans
- Direction esthétique retenue et chemin des fichiers d'aperçu générés (`screens-preview/`)
- Toute FR-xxx à acteur humain qui n'apparaît dans aucun écran — cas bloquant, à corriger avant de continuer (jamais de FR-xxx humaine orpheline dans ce document)

## Règles

- `screens-final.md` n'est généré qu'après validation humaine explicite — jamais par auto-validation silencieuse, layout et système de design inclus
- Le layout général (header, navigation, footer) est toujours décrit explicitement, même s'il est unique et simple — jamais déduit silencieusement de l'arborescence Next.js
- La visibilité des liens de navigation par rôle doit être cohérente avec `## Utilisateurs et rôles` de `spec-final.md`
- Chaque écran référence au moins une FR-xxx ; chaque FR-xxx à acteur humain de `spec-final.md` doit apparaître dans au moins un écran
- Pour tout écran liste/tableau ou CRUD, les actions CRUD présentes (et absentes) et le comportement de chaque colonne (triable/filtrable/déplaçable) sont toujours détaillés explicitement dans les Éléments clés — jamais laissés implicites derrière "boutons d'action" ou "tableau triable"
- Ne jamais inclure les FR-xxx dont l'acteur est un système externe — ces FR-xxx n'ont pas d'écran par définition
- La direction esthétique est toujours proposée directement (pas de recherche externe), justifiée en 2-3 phrases liées au produit — jamais un menu de choix neutres présenté à l'utilisateur
- Le bloc `:root` du système de design est écrit prêt à copier dans `app/globals.css` — `/implement` ne le réinvente jamais (voir la règle correspondante dans `implement.md`)
- `screens-preview/` est un artefact jetable de validation visuelle — jamais consommé par `/implement`, à ajouter au `.gitignore` du projet
- `/implement` lit ce fichier s'il existe et construit le frontend (layout(s) et système de design inclus) en suivant exactement ce qui est décrit — voir la règle correspondante dans `implement.md`
