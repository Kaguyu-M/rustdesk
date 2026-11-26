# Installateur RustDesk « host uniquement » — fonctionnement et recommandations

## Ce qui a été mis en place

| Élément | Rôle |
|---|---|
| `src/common.rs` → `load_build_time_config()` | Lit au **moment de la compilation** les variables `RENDEZVOUS_SERVER`, `RS_PUB_KEY`, `API_SERVER`, `RELAY_SERVER` (optionnel), `RUSTDESK_CONN_TYPE`, `RUSTDESK_DISABLE_UPDATE`, et les injecte comme réglages **verrouillés** (non modifiables dans l'interface). Sans ces variables, le comportement est identique à l'upstream. |
| `.github/workflows/host-installer.yml` | Build Windows x64 uniquement, mode `incoming` (host only), MAJ automatique désactivée. Produit un `.msi` + un `.exe` auto-installable + `SHA256SUMS.txt`, publiés dans une Release GitHub. |
| `res/deploy/deploy-host.ps1` | Installation silencieuse du MSI, mot de passe permanent optionnel, affichage de l'ID. |

Les secrets ne sont jamais écrits dans le dépôt : ils n'existent que dans les binaires produits.

> ⚠️ Le serveur et la clé publique sont lisibles dans le binaire (c'est normal : la clé publique n'est pas un secret). Ne mettez **jamais** de mot de passe ou de jeton dans des variables de build.

### Lancer un build
- Onglet **Actions → Build host-only Windows installer → Run workflow**, ou
- pousser un tag `host-*` : `git tag host-1.5.3-1 && git push origin host-1.5.3-1`.

Durée : ~45–60 min (vcpkg + Flutter + Rust), plus rapide ensuite grâce aux caches.

### Déployer
```powershell
msiexec /i rustdesk-host-1.5.3-x86_64.msi /qn
# ou, avec mot de passe permanent et récupération de l'ID :
.\deploy-host.ps1 -Msi .\rustdesk-host-1.5.3-x86_64.msi -Password 'MotDePasseLong!'
```
Compatible GPO / Intune / PDQ (MSI standard, installation par machine, service Windows `RustDesk`).

---

## Recommandations

### 1. Signature de code (priorité haute)
Les binaires ne sont pas signés → avertissement SmartScreen et faux positifs antivirus fréquents (RustDesk est souvent détecté comme « RemoteAdmin »).
- Option économique : **Azure Trusted Signing** (~10 $/mois), s'intègre via l'action `azure/trusted-signing-action` juste avant « Build self-extracted executable » et après « Build msi ».
- Sinon un certificat OV/EV classique + `signtool`.
- En entreprise : ajouter une exclusion Defender/EDR sur le hash ou l'éditeur.

### 2. Désactiver les workflows upstream inutiles dans le fork
Les workflows `ci.yml`, `flutter-ci.yml`, `flutter-nightly.yml`, `playground.yml`, `fdroid.yml`… consomment des minutes Actions pour rien :
```bash
for w in ci.yml flutter-ci.yml flutter-nightly.yml flutter-tag.yml playground.yml fdroid.yml clear-cache.yml update-webpki-roots.yml; do gh workflow disable $w -R Kaguyu-M/rustdesk; done
```

### 3. Sécurité du serveur (hbbs/hbbr)
- Vérifier que hbbs **exige la clé** (versions récentes : par défaut ; sinon option `-k _`), pour qu'aucun client sans votre clé ne puisse utiliser votre serveur.
- Pare-feu : n'ouvrir que 21115–21117/TCP, 21116/UDP (+ 21118/21119 seulement si client web), 21114 seulement si Server Pro.
- Sauvegarder `id_ed25519` / `id_ed25519.pub` : les perdre = rebuild + redéploiement de tous les postes.
- Si `API_SERVER` est exposé, le mettre derrière un reverse proxy HTTPS.

### 4. Politique d'accès sur les hosts
Réglages intéressants à figer à l'avenir (même mécanisme que `load_build_time_config`, via `OVERWRITE_SETTINGS`) :
- `verification-method = use-permanent-password` (pas de mot de passe temporaire) ou au contraire `approve-mode = click` (l'utilisateur doit accepter) selon l'usage (parc non surveillé vs assistance).
- `enable-file-transfer`, `enable-clipboard`, `enable-audio`… selon la politique de sécurité.
- `whitelist` : n'accepter que les IP de l'équipe support.
- `allow-remote-config-modification = N`.
Le mot de passe permanent se définit **après** l'installation (`rustdesk.exe --password`, cf. script), jamais dans le binaire.

### 4 bis. Rangement automatique des postes (API gratuite `lejianwen/rustdesk-api`)
L'API gratuite **ignore** les réglages `preset-*` (groupe de postes, utilisateur, carnet) et n'implémente pas `rustdesk.exe --assign` : ces fonctions sont réservées à RustDesk Server Pro.
Solution retenue : `deploy-host.ps1` se connecte avec un **compte générique non-admin** et ajoute le poste à un carnet d'adresses :
1. Dans l'admin web de l'API, créer un utilisateur `host-generique` (non admin).
2. Optionnel : créer une **collection de carnet d'adresses** (ex. `Clients`) appartenant à ce compte, et la partager en lecture avec les techniciens (règles de collection).
3. Déployer :
   ```powershell
   .\deploy-host.ps1 -Msi .\rustdesk-host-1.5.3-x86_64.msi -Password '...' `
       -ApiServer https://<api> -AbUser host-generique -AbPassword '...' -AbCollection Clients -Tags 'Site-Paris'
   ```
   Sans `-AbCollection`, le poste va dans le carnet personnel du compte (option `rustdesk.personal: 1` côté API, active par défaut).
- Le mot de passe du compte générique n'est utilisé que par le script, jamais écrit sur le poste ; ne pas donner les droits admin à ce compte.
- **Kit chiffré généré par le workflow** : si les secrets `AB_USER`, `AB_PASSWORD` (et optionnellement `AB_COLLECTION`) et `KIT_PASSWORD` existent, la release contient `rustdesk-host-kit-<version>.7z` (AES-256, noms de fichiers chiffrés) avec le MSI, les scripts et un `kit.json` prérempli. Ouvrir avec 7-Zip (mot de passe = `KIT_PASSWORD`), puis double-cliquer `INSTALLER.cmd`. Le fork étant public, ne jamais publier ces identifiants autrement que dans ce 7z.
- Le **groupe de postes** (`group_id`) ne se règle qu'avec un compte admin dans l'admin web : à faire à la main, ou en lot depuis la liste des postes.

### 5. Suivre l'upstream
- Utiliser « Sync fork » régulièrement (correctifs de sécurité). Le patch est volontairement additif et isolé dans une fonction : les conflits devraient être rares.
- Optionnel : un workflow planifié mensuel qui synchronise le fork puis pousse un tag `host-*`.
- La mise à jour automatique étant désactivée (sinon RustDesk se remplacerait par la version officielle sans votre config), redéployez le nouveau MSI (même ProductCode upgrade → mise à jour en place).

### 6. Autres plateformes
Le même hook fonctionne pour Linux (`.deb`), macOS et Android : il suffirait d'ajouter un job avec les mêmes variables d'environnement, en s'inspirant de `flutter-build.yml`.

### 7. Personnalisation (optionnel, à faire avec prudence)
Logo/icône : remplacer `res/icon.ico`, `flutter/assets/logo.png`… Le **renommage** de l'application (`APP_NAME`) change les chemins de config et le nom du service : à éviter tant que le parc est déjà déployé.

### 8. Alternative sans compilation
RustDesk reconnaît aussi un nom de fichier du type `rustdesk-host=serveur,key=CLE.exe` sur l'exe officiel. Pratique pour dépanner, mais sans mode host-only ni verrouillage : le build de ce fork reste préférable pour un parc.
