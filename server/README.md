# GPXlibre — serveur de points bloqués partagés

Base communautaire minimale des "chemins bloqués" signalés par les utilisateurs de
l'app. Auto-hébergeable (NAS, Raspberry Pi, VPS...), aucune dépendance à un service
tiers, aucune donnée nominative.

## Démarrer

```bash
cd server
docker compose up -d --build
curl http://localhost:8000/health
```

Les données persistent dans `server/data/blockages.db` (SQLite, monté en volume) —
sauvegarder ce fichier suffit à sauvegarder toute la base.

## API

### `POST /blockages` — signaler un point bloqué

```bash
curl -X POST http://localhost:8000/blockages \
  -H "Content-Type: application/json" \
  -d '{"lat": 45.188529, "lon": 5.724524, "note": "arbre au sol", "reporter_id": "a1b2c3d4"}'
```

Si un point existant se trouve à moins de 100 m, il est **reconfirmé** (sa date de
fraîcheur est mise à jour) au lieu de créer un doublon — c'est le seul mécanisme de
confiance en v1, il n'y a pas de vote.

### `GET /blockages` — lister les points d'une zone

```bash
curl "http://localhost:8000/blockages?min_lat=45.0&min_lon=5.5&max_lat=45.4&max_lon=6.0"
```

Retourne uniquement les points de la zone demandée (bounding box), jamais l'ensemble de
la base — un client mobile n'a besoin que des points autour de sa trace chargée.

## Modèle de confiance (v1)

- **Aucune modération, aucun vote** : un signalement est accepté tel quel. C'est un
  compromis assumé pour un v1 — documenté ici plutôt que caché.
- **Expiration** : un point non reconfirmé depuis plus de 180 jours est supprimé côté
  serveur (purge passive, à chaque écriture). Le *fondu visuel* au-delà de 90 jours sans
  reconfirmation est une décision d'affichage côté client uniquement (voir
  `SharedBlockage.swift` dans l'app) — le serveur ne renvoie que des points encore
  valides, faded ou non.
- **Dédoublonnage géographique** : rayon fixe de 100 m (`DEDUP_RADIUS_METERS` dans
  `app.py`).

## Vie privée

- Aucun compte, aucune authentification.
- `reporter_id` est un identifiant anonyme **rotatif**, généré et conservé uniquement
  sur l'appareil du client (jamais transmis à un tiers, jamais un identifiant Apple/
  Google). Il n'est stocké côté serveur que pour permettre une éventuelle future
  fonctionnalité de "mes signalements" — **il n'est jamais renvoyé dans les réponses de
  l'API** (voir le modèle `Blockage`, qui l'omet volontairement).
- Aucune donnée nominative n'est demandée ni acceptée : ni nom, ni email, ni identifiant
  de compte.
- Le champ `note` est un texte libre optionnel (280 caractères max) — l'utilisateur est
  seul responsable de son contenu, l'app ne l'invite à décrire que le blocage lui-même
  (ex. "arbre au sol", "barrière fermée").

## Configuration côté app

Dans GPXlibre, Réglages → section "Avancé" (repliée par défaut) : URL du serveur,
modifiable pour pointer vers votre instance auto-hébergée. Par défaut, l'app pointe vers
une constante (`SharedBlockageConstants.defaultServerURLString`) qui n'est volontairement
pas un service public déployé par ce projet — voir la note dans le code : sans instance
réelle déployée à cette URL, l'app reste **offline-first** et continue de fonctionner
sur son dernier instantané local, sans jamais afficher d'écran d'erreur.
