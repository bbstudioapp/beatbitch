# Déploiement de la PWA sur Cloudflare Pages

Doc interne BB Studio — setup à faire **une fois** pour que le workflow
`.github/workflows/web-deploy.yml` puisse pousser la version web à chaque
push `main`.

---

## 1. Créer le projet Cloudflare Pages

1. Aller sur [dash.cloudflare.com](https://dash.cloudflare.com) (même compte que R2).
2. Menu de gauche : **Workers & Pages** → bouton **Create application** → onglet **Pages** → **Direct upload**.

   > ⚠ Ne pas choisir « Connect to Git ». Le build sera fait par GitHub
   > Actions (qui a déjà l'accès R2 pour les assets externalisés).

3. **Project name** : `beatbitch` (exactement ce nom — le workflow le référence en dur via `--project-name=beatbitch`). Ça donne l'URL `https://beatbitch.pages.dev`.
4. **Production branch** : `main` (la default).
5. Bouton **Create project**. Cloudflare propose un upload manuel — **on ignore**, on va déployer via le workflow.

Le projet est créé, vide. Première URL : `https://beatbitch.pages.dev` (renvoie 404 tant qu'aucun déploiement n'a eu lieu).

---

## 2. Récupérer l'Account ID

1. Dans le dashboard, panneau de droite sur n'importe quelle page Workers & Pages → bloc **Account ID**.
2. Copier la valeur (~32 chars hex). On va la coller dans les secrets GitHub.

---

## 3. Créer un API Token Cloudflare

1. Cloudflare dashboard → en haut à droite, avatar → **My Profile** → onglet **API Tokens**.
2. **Create Token** → template **Custom token** → **Get started**.
3. Configurer :
   - **Token name** : `beatbitch-pages-deploy` (ou ce que tu veux)
   - **Permissions** : `Account` → `Cloudflare Pages` → `Edit`
   - **Account Resources** : `Include` → ton compte
   - **Zone Resources** : laisser tel quel (non utilisé)
   - **TTL** : laisser vide (token permanent) ou poser une date d'expiration si tu préfères roter manuellement
4. **Continue to summary** → **Create Token**.
5. **Copier la valeur affichée immédiatement** (Cloudflare ne la remontre plus après cette page).

---

## 4. Ajouter les secrets côté GitHub

Sur `github.com/bbstudioapp/beatbitch` → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

Deux secrets à créer :

| Nom | Valeur |
|---|---|
| `CLOUDFLARE_API_TOKEN` | le token de l'étape 3 |
| `CLOUDFLARE_ACCOUNT_ID` | l'Account ID de l'étape 2 |

> ℹ️ Les secrets R2 (`R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT`,
> `R2_BUCKET`) sont déjà en place (utilisés par `release.yml`). Le workflow
> `web-deploy.yml` les réutilise tels quels — rien à ajouter.

---

## 5. Premier déploiement

Deux options :

**A. Push sur main** (déclenchement automatique du workflow).

**B. Déclenchement manuel** :
1. `github.com/bbstudioapp/beatbitch/actions` → workflow **Deploy PWA to Cloudflare Pages** → **Run workflow** → branche `main` → **Run workflow**.

Le job tourne pendant ~3-5 min (Flutter cache + R2 sync + build + upload).
Quand il est vert, l'app est en ligne sur **`https://beatbitch.pages.dev`**.

> Premier déploiement seulement : Cloudflare Pages peut mettre 1-2 min de
> plus pour propager le DNS du sous-domaine. Si l'URL renvoie une page
> blanche au début, attendre puis hard-refresh.

---

## 6. Mettre à jour l'URL dans les docs

Une fois la première publication validée, remplacer `URL_BEATBITCH_PWA` par
l'URL finale dans :

- `docs/INSTALL-iOS.fr.md`
- `docs/INSTALL-iOS.en.md`
- `docs/INSTALL-iOS.de.md`

Si on reste sur `beatbitch.pages.dev` :

```bash
sed -i 's|URL_BEATBITCH_PWA|https://beatbitch.pages.dev|g' docs/INSTALL-iOS.*.md
```

(ou édition manuelle).

Pour aussi linker ces docs depuis la landing GitHub Pages, on peut éditer
`docs/index.md` pour ajouter un lien « Installer sur iPhone » à côté des
liens APK existants.

---

## 7. (Optionnel) Domaine personnalisé

Si on prend `beatbitch.app` (ou similaire) :

1. Cloudflare Pages → projet `beatbitch` → onglet **Custom domains** → **Set up a custom domain**.
2. Saisir `beatbitch.app` (ou un sous-domaine type `app.beatbitch.app`).
3. Si le domaine est déjà géré par Cloudflare (zone existante) : 1 clic, le CNAME se pose tout seul.
4. Sinon : Cloudflare donne un CNAME à ajouter chez le registrar.
5. HTTPS auto (cert Cloudflare).

Repasser sur les docs `INSTALL-iOS.*.md` et `index.md` avec le nouveau domaine.

---

## Maintenance — itérer sur la PWA

Workflow nominal :

1. Branche depuis `develop` (cf. `[[feedback_git_branch_workflow]]`).
2. PR → merge dans `develop`.
3. PR `develop` → `main` quand on est prêt à pousser une version.
4. Le push sur `main` déclenche **deux workflows en parallèle** :
   - `release.yml` — build APK + zip Windows + tar.gz Linux (gate par tag : ne fait rien si la version n'a pas bougé)
   - `web-deploy.yml` — build web + push Cloudflare Pages (pas de gate : déploie à chaque push)
5. Les utilisateurs PWA reçoivent la mise à jour silencieusement au prochain lancement avec réseau (service worker Flutter).

> Le `web-deploy.yml` n'est **pas** gating sur la version (`pubspec.yaml`) :
> on peut hotfixer du CSS / JS / asset web sans bumper la version. Si tu
> ne veux pas déployer un push donné, retire-le du flow main (PR refus,
> reset) — pas de mécanisme de skip implicite.

---

## Rollback

Cloudflare Pages garde tous les déploiements précédents :

1. Dashboard Pages → projet `beatbitch` → onglet **Deployments**.
2. Sur un déploiement antérieur : `⋮` → **Rollback to this deployment**.
3. Effet immédiat, pas besoin de redéployer le code.

Utile si un build casse silencieusement sur Safari iOS sans qu'on le voie
en CI.

---

## Coûts

Cloudflare Pages plan **Free** :
- 500 builds/mois (largement suffisant pour 1 push/jour)
- 100 GB/mois de bande passante (BeatBitch ~50 MB de bundle × ~2000 visiteurs/mois)
- Stockage illimité
- Custom domain inclus

Si on dépasse : plan **Pro** à $20/mois augmente les quotas. Aucune raison
d'y arriver avant un succès viral marqué.
