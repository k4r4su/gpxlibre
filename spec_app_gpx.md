# Spécification fonctionnelle — App de navigation GPX moto (iOS + CarPlay)

Nom de travail : **GPXlibre**

## 1. Contexte et objectif

Créer une application iPhone de navigation GPS conçue pour la moto, qui combine dans **une seule app** des fonctionnalités actuellement fragmentées chez plusieurs concurrents :

- Lecture et import de traces **GPX** (fichiers d'itinéraires moto)
- **Suivi strict de trace** : position GPS affichée en temps réel le long du tracé, **sans jamais recalculer** l'itinéraire (comportement indispensable en off-road/piste)
- **Cartes hors-ligne** (fonctionnement en zone blanche — montagne, campagne)
- **Intégration Apple CarPlay** : la carte et le guidage s'affichent sur l'écran du véhicule
- **100 % gratuite**, sans abonnement, sans pub, sans compte obligatoire

Positionnement : "un Garmin pour moto trail, gratuit, en une app".

Utilisateur cible : motard pratiquant route ET off-road (pistes, enduro, trails). Interface lisible avec des gants, utilisable au soleil, sur un guidon.

## 2. Exigences fonctionnelles (MVP)

### 2.1 Import et gestion des traces
- Import de fichiers `.gpx` (waypoints, routes, tracks) depuis Fichiers/Mail/Safari via le partage système iOS
- Support `.tcx`, `.kml`, `.itn` en bonus (nice-to-have)
- Bibliothèque locale de traces : renommer, supprimer, sauvegarde iCloud optionnelle
- Import d'un lien direct (URL vers un fichier GPX hébergé)

### 2.2 Suivi de trace (le cœur du produit)
- Mode **suivi strict de trace** (follow-only) : la position GPS avance sur le tracé, affichage distance restante sur la trace, point le plus proche calculé
- AUCUN recalcul d'itinéraire. Jamais. Option séparée "router vers le début de la trace" acceptée, mais désactivée par défaut
- **Alerte hors-trace** : signal sonore + bannière visuelle si écart > seuil configurable (défaut 50 m, réglable 10–200 m)
- Profil d'altitude de la trace avec position actuelle indiquée dessus
- Affichage cap/N, distance totale de la trace, % parcouru
- Fonctionnement à l'écran allumé ET pendant le veille (guidage géré en background, localisation autorisée "toujours")

### 2.3 Cartographie hors-ligne
- Téléchargement de **tuiles vectorielles hors-ligne par région** (ex: MBTiles/PMTiles OpenStreetMap)
- Aucune énumération réseau exigée en zone blanche : tout l'affichage carte est local
- Style de carte moto-trail priorisé : pistes non revêtues et chemins forestiers visibles et distinctifs (tags OSM `highway=track`, `trail_visibility`, etc.)

### 2.4 Apple CarPlay
- Intégration via `CPInterfaceController` / template navigation CarPlay
- Affichage sur l'écran du véhicule : carte + position temps réel sur la trace
- Une seule action requise pour démarrer la trace depuis CarPlay (gros bouton "GO")
- Deux modes CarPlay : **Route** (instructions tour-par-tour générées depuis le tracé) et **Offroad** (suivi de trace pur, carte seule sans recalcul)

### 2.5 Enregistrement et export
- Enregistrement de nouvelles traces pendant qu'on roule (bouton REC)
- Export en `.gpx` vers Fichiers avec partage Mail/Messages

## 3. Exigences non fonctionnelles

- **Zéro abonnement, zéro pub, zéro compte obligatoire**
- Données 100 % locales ; pas d'analytics sans consentement explicite
- Autonomie raisonnable : cible <10 % batterie/heure d'écran allumé actif
- Lisibilité outdoor : mode contraste élevé, cibles tactiles larges (gants), orientation verrouillée optionnelle
- iOS 16+

## 4. Pile technique suggérée (Swift natif, gratuite et sans abonnement)

| Besoin | Outil proposé | Pourquoi |
|---|---|---|
| Langage / UI | Swift + SwiftUI | Natif, accès complet aux API Apple requises |
| Localisation | CoreLocation + `startUpdatingLocation`, autorisation "toujours" | GPS background pendant veille écran |
| Carte offline | MapLibre Native iOS + tuiles vectorielles offline (MBTiles) | Gratuit, open source, hors-ligne natif |
| Données carte | OpenStreetMap | Licence permissive, données mondiales gratuites |
| Parsing GPX | Framework `CoreGPX` (open source) ou parser maison Swift | `.gpx` bien supporté |
| CarPlay | Framework CarPlay (`CPMapTemplate`) + éligibilité dans Info.plist | Intégration native écran véhicule |
| Alertes hors-trace | Calcul géodésique (haversine) vs trace, local, sans serveur | Fonctionne en zone blanche |
| Enregistrement trace | CoreLocation + sauvegarde locale (SQLite/CoreData), export GPX via share sheet | Sans compte, fichiers sandbox app |

## 5. Parcours utilisateur critère d'acceptation (testable end-to-end)

1. L'utilisateur reçoit un fichier GPX par Mail → partage → "Ouvrir dans l'app" → la trace apparaît dans la bibliothèque
2. Il télécharge la carte de sa région en offline — confirmation visuelle du stockage local
3. Il met le téléphone en mode avion, branche CarPlay : la carte s'affiche, la trace est visible, sa position évolue en temps réel sans réseau
4. Il roule volontairement à côté de la trace de 80 m : l'alerte hors-trace se déclenche (son + visuel) automatiquement
5. Il roule toute la trace : l'app n'a jamais recalculé d'itinéraire, jamais tenté de le remettre "sur la route la plus proche"
6. À l'arrivée : la trace enregistrée s'exporte en GPX et se réouvre dans une autre app sans erreur de format
7. L'app n'a affiché aucune pub, aucune demande d'abonnement, aucune demande de compte pendant tout le parcours

## 6. Hors périmètre MVP (architecturer pour, ne pas construire)

- Routage moteur complet (calcul d'itinéraire A→B par routes)
- Communauté de partage de traces
- Météo, alertes radars
- Sorties de groupe en direct

## 7. Risques et points d'attention pour l'agent dev

- Éligibilité CarPlay exige une autorisation Apple : `com.apple.developer.carplay-maps` — nécessite un compte développeur payant (99 $/an) et une approbation Apple. Archit. code CarPlay derrière un module isolé, simulable sans entitlement.
- MapLibre + CarPlay simultanés = le point le plus délicat du projet. Si bloquant en V1 : CarPlay online (MapKit) + offline hors CarPlay, itérer en V2.
- GPS en background impose `UIBackgroundModes: location` dans Info.plist — sinon l'alerte hors-trace meurt écran éteint.
- Licence des tuiles offline : attribution OSM obligatoire.

Générer le projet Xcode initial, l'écran de bibliothèque GPX, et le module de chargement/parsing d'une trace comme première itération livrable. Inclure un fichier GPX de test fonctionnel dans le projet.
