# Relais Internet du mode duo

Petit serveur qui relaie les messages entre les deux téléphones d'une partie duo jouée par Internet.
Un Worker Cloudflare reçoit les connexions WebSocket et envoie chaque salle (code à 4 lettres) vers son
propre Durable Object, qui fait suivre les messages de l'hôte à l'invité et inversement.

Offre gratuite de Cloudflare : suffisante. Les Durable Objects en SQLite y sont disponibles (migration
`new_sqlite_classes`). Le serveur ne stocke rien. Une salle vide disparaît d'elle-même.

Le réseau local (même Wi-Fi ou partage de connexion) marche sans ce serveur.

## Mise en service : 3 étapes

### 1. Créer le jeton Cloudflare

1. Se connecter sur https://dash.cloudflare.com (créer un compte gratuit si besoin).
2. Menu **Workers & Pages** : l'ouvrir une fois. Au premier passage, Cloudflare fait choisir le
   sous-domaine `*.workers.dev` du compte. Sans ce sous-domaine, le déploiement échoue.
3. Noter l'**Account ID**. Il est affiché à droite de la page **Workers & Pages**, et dans l'adresse du
   tableau de bord (`dash.cloudflare.com/<account id>/…`).
4. Profil (en haut à droite) > **My Profile** > **API Tokens** > **Create Token**.
5. Choisir le modèle **Edit Cloudflare Workers** (« Modifier les Workers Cloudflare »).
   - Account Resources : *Include* > le compte.
   - Zone Resources : *All zones* (aucun domaine n'est utilisé, le relais tourne sur `workers.dev`).
6. **Continue to summary** > **Create Token**. Copier le jeton : il ne s'affiche qu'une fois.

### 2. Ajouter les deux secrets GitHub

Dépôt `vroux18/gunbrov2` > **Settings** > **Secrets and variables** > **Actions** > **New repository secret** :

| Nom                     | Valeur                |
| ----------------------- | --------------------- |
| `CLOUDFLARE_API_TOKEN`  | le jeton de l'étape 1 |
| `CLOUDFLARE_ACCOUNT_ID` | l'Account ID          |

### 3. Lancer le workflow

Dépôt > **Actions** > **Relais duo (Cloudflare)** > **Run workflow**.

Le workflow :

1. teste le relais en local (`wrangler dev` et `test/relay.test.mjs`) ;
2. le déploie sur Cloudflare ;
3. le teste en ligne ;
4. publie son adresse (`wss://passeurs-relay.<sous-domaine>.workers.dev`) dans `relay.txt`, en asset de
   la release `relay`.

Le jeu lit ce fichier en ouvrant **DUO > INTERNET** :
https://github.com/vroux18/gunbrov2/releases/download/relay/relay.txt

Le workflow se relance seul à chaque modification de `server/`. Sans les secrets, il saute le déploiement
et reste vert.

## Vérifier

- `https://passeurs-relay.<sous-domaine>.workers.dev/health` répond `passeurs-relay ok`.
- Dans le jeu, **DUO > INTERNET** affiche **CRÉER UNE SALLE**. Il n'affiche plus « Serveur non déployé ».

## En cas d'échec

- *« You need to register a workers.dev subdomain »* : étape 1, point 2.
- *Authentication error (10000)* : le jeton n'a pas les bonnes permissions ou n'est pas attaché au bon
  compte. Le recréer avec le modèle **Edit Cloudflare Workers**.
- Le jeu affiche toujours « Serveur non déployé » : vérifier que la release `relay` contient `relay.txt`. Le
  jeu lit ce fichier quand on ouvre l'écran INTERNET. Revenir au Relais, puis rouvrir DUO > INTERNET.

## Développement local

```
cd server/relay
npm install
npx wrangler dev --ip 127.0.0.1 --port 8787      # relais local
node test/relay.test.mjs ws://127.0.0.1:8787     # essais : salle, refus, relais binaire, départs
```

Deux instances du jeu sur la même machine, par ce relais local :

```
godot --path . -- --duo-host --duo-relay=ws://127.0.0.1:8787 --duo-room=ABCD
godot --path . -- --duo-relay=ws://127.0.0.1:8787 --duo-room=ABCD
```

## Protocole

- `GET /room/ABCD?role=host` crée la salle. Refus si un hôte l'occupe déjà.
- `GET /room/ABCD?role=guest` rejoint la salle. Refus si elle n'existe pas ou si elle est pleine.
- Messages texte du serveur (JSON) :
  - `{"t":"hello","role","code","peer"}` : connexion acceptée ;
  - `{"t":"peer","on"}` : arrivée ou départ du partenaire ;
  - `{"t":"err","why"}` : refus (`occupied`, `no_room`, `full`).
- Le client envoie `"ping"` toutes les 5 s. Le runtime répond `"pong"` sans réveiller l'objet : pas de
  coût en durée.
- Les messages binaires sont relayés tels quels à l'autre joueur.
- L'hôte part : la salle ferme et l'invité est déconnecté (code 4000).
- Une connexion muette depuis 90 s est fermée (alarme toutes les 30 s).

Coût sur l'offre gratuite (chiffres à revérifier sur la page tarifs de Cloudflare, ils changent) :

- limite : 100 000 requêtes Durable Objects par jour ;
- un message WebSocket entrant compte pour 1/20 de requête ;
- une partie consomme environ 35 messages par seconde (15 instantanés et 20 entrées), soit environ
  6 000 requêtes par heure de jeu.
