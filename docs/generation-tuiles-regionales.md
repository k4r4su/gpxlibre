# Génération d'un paquet PMTiles régional — GPXlibre (it11, "vector-pmtiles" étape 2)

Ce manuel s'exécute sur le NAS (ou toute machine Linux/macOS) du propriétaire — **pas** dans
l'app. Objectif : produire un fichier `region.pmtiles` unique à partir d'un ou plusieurs
extraits Geofabrik `.osm.pbf`, compatible avec le style embarqué dans l'app
(`GPXlibre/Resources/vector-style-liberty.json`, schéma **OpenMapTiles**). Cas test retenu :
Alsace + Franche-Comté fusionnées en un seul paquet.

Toutes les commandes ci-dessous ont été vérifiées contre la documentation officielle des
outils au moment de l'écriture (README `onthegomap/planetiler`, man page `osmium-merge`) —
si une commande échoue, vérifier d'abord que la version installée n'a pas changé sa syntaxe.

## 1. Prérequis

- **Java 21+** (requis par Planetiler).
- **osmium-tool** (fusionne plusieurs extraits Geofabrik en un seul `.osm.pbf`) :
  - macOS : `brew install osmium-tool`
  - Linux (Debian/Ubuntu) : `apt install osmium-tool`
- **Planetiler** — pas d'installation, un seul jar exécutable téléchargé à la volée (voir
  étape 3).
- Espace disque : compter large — l'extrait fusionné + le `.pmtiles` de sortie + la marge de
  travail de Planetiler (fichiers memory-mapped temporaires).

## 2. Télécharger les extraits régionaux (Geofabrik)

```bash
mkdir -p ~/gpxlibre-tuiles && cd ~/gpxlibre-tuiles
curl -LO https://download.geofabrik.de/europe/france/alsace-latest.osm.pbf
curl -LO https://download.geofabrik.de/europe/france/franche-comte-latest.osm.pbf
```

D'autres régions françaises suivent le même schéma d'URL
(`europe/france/<region>-latest.osm.pbf`) — voir la liste complète sur
`download.geofabrik.de/europe/france.html`.

## 3. Fusionner les deux extraits en un seul fichier

```bash
osmium merge alsace-latest.osm.pbf franche-comte-latest.osm.pbf -o alsace-franche-comte.osm.pbf
```

Pour un seul région, sauter cette étape et passer directement le `.osm.pbf` téléchargé à
Planetiler.

## 4. Générer le `.pmtiles` avec Planetiler

```bash
wget https://github.com/onthegomap/planetiler/releases/latest/download/planetiler.jar

java -Xmx4g -jar planetiler.jar \
  --osm-path=alsace-franche-comte.osm.pbf \
  --output=region.pmtiles
```

- Le jar téléchargé ainsi utilise par défaut le **profil OpenMapTiles** — c'est ce qui
  garantit la compatibilité avec les noms de couches (`transportation`, `landuse`, `water`,
  etc.) attendus par le style embarqué de l'app. Ne pas utiliser un autre profil/schéma sans
  adapter aussi le style.
- **`-Xmx`** (RAM allouée à la JVM) : Planetiler recommande environ **0.5× la taille du
  fichier `.osm.pbf` en entrée** (le reste passe par des fichiers memory-mapped sur disque).
  Alsace + Franche-Comté fusionnées pèsent environ 250-300 Mo en `.osm.pbf` → `-Xmx4g` est
  large, ajuster à la baisse si le NAS est contraint en RAM.
- Durée : de l'ordre de quelques minutes pour deux régions françaises sur du matériel NAS
  correct (très inférieur à un run planète entière, qui se compte en heures et demande des
  dizaines de Go de RAM — sans rapport avec ce cas d'usage).

## 5. Mettre le fichier à disposition de l'app

Déposer `region.pmtiles` sur un serveur HTTP(S) accessible depuis le téléphone (le NAS avec
un partage HTTP simple suffit — pas besoin d'un vrai serveur de tuiles, l'app télécharge le
fichier ENTIER une fois via `VectorPackageStore.downloadPackage`, jamais tuile par tuile).
Dans l'app : Bibliothèque → icône "Paquets vectoriels" → coller l'URL complète du fichier
(ex : `https://mon-nas.local/tuiles/region.pmtiles`) → "Télécharger depuis cette URL".

Une fois téléchargé et rendu actif (coche verte), ce paquet est utilisé PARTOUT, y compris en
mode avion — voir `MapSourceResolver` pour la logique de priorité (paquet local > vectoriel
hébergé > raster existant).

## 6. Régénérer plus tard (mise à jour des données OSM)

Aucune magie : retélécharger les extraits Geofabrik à jour (étape 2), refaire la fusion et la
génération (étapes 3-4), redéposer le nouveau `region.pmtiles` sur le NAS sous la même URL (ou
une nouvelle — l'app retélécharge simplement ce qu'on lui pointe). Le paquet précédent reste
utilisable tel quel dans l'app tant qu'il n'est pas supprimé manuellement.
