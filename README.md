# GPXlibre

> « Le but de l'app c'est d'afficher une trace de façon simple, pouvoir la suivre, la reprendre plus loin si besoin. »

GPXlibre est une application iOS pour suivre une trace GPX en moto, à vélo ou à pied — sur route comme hors-piste. Pas de compte, pas de cloud, pas de fonctionnalités superflues : tu charges une trace, tu la suis, et si tu t'arrêtes en chemin tu la reprends là où tu en étais. Tout fonctionne hors-ligne une fois la carte téléchargée.

## Fonctionnalités principales

**Suivre une trace**
- Carte en mode cap-en-haut (comme un GPS moto) ou nord-en-haut, au choix
- Zoom qui s'adapte automatiquement à la vitesse — plus serré à l'arrêt, plus large en roulant
- Roadbook : une bannière annonce les virages à l'avance, avec une icône selon leur intensité (léger, prononcé, fort, demi-tour)
- Détection hors-trace : un indicateur compact et discret te le signale sans jamais masquer la carte ni effacer ta trace
- Si tu t'écartes franchement, l'app recalcule seule un itinéraire de liaison pour te ramener sur la trace, avec une bannière dédiée qui indique la distance restante
- « Reprendre ici » : tu peux reprendre le guidage depuis n'importe quel point de la trace, même après un détour
- Textes et symboles de la carte restent lisibles en mode cap-en-haut, quel que soit ton cap
- Avertissement de pente : un panneau triangle apparaît sur la carte aux endroits de forte montée ou descente

**Cartes hors-ligne**
- Téléchargement automatique du corridor autour d'une trace avant de partir
- Téléchargement manuel d'une zone plus large (avec estimation de taille en direct)
- Le contour des zones déjà téléchargées reste visible sur la carte
- Plusieurs palettes de couleur (standard, contraste élevé, terreux) sur le même fond de carte, plus un thème relief

**Une trace, jamais modifiée**
- Le fichier GPX chargé n'est jamais recalculé ni réécrit
- Le sens de parcours (A→B ou inversé) et l'apparence (couleur, épaisseur) sont des réglages d'affichage, pas des modifications du fichier
- Un détour ou un guidage vers un point tapé sur la carte se dessine à côté de la trace, jamais à sa place

**Enregistrer sa sortie**
- L'app enregistre le trajet réellement parcouru en tâche de fond, indépendamment de la trace suivie
- Export GPX en fin de sortie, sauvegardé automatiquement dans la bibliothèque avec une couleur ambre distinctive et un aperçu carte immédiat
- Points d'intérêt signalables en un tap pendant le trajet

**Bibliothèque**
- Toutes les traces importées ou enregistrées, triées par date
- Aperçu cartographique par trace avec chevrons de direction et repères de départ/arrivée
- Réglages indépendants par trace (sens, couleur, épaisseur, espacement des chevrons)

## Comment ça s'utilise

1. **Importer une trace** — depuis Fichiers, Mail, Safari ou directement dans l'app (onglet Bibliothèque)
2. **La rendre active** — un tap sur la trace dans la Bibliothèque
3. **Partir** — onglet Ride, la carte se centre et suit ta position
4. **Suivre le roadbook** — la bannière latérale annonce les virages, les épingles sur la carte indiquent leur intensité
5. **S'arrêter si besoin** — le bouton Pause coupe le guidage sans rien perdre ; un tap le relance
6. **Terminer** — bouton « Terminer la sortie » dans le panneau de vitesse, la trace parcourue est enregistrée et exportable

## Pourquoi hors-ligne d'abord

Beaucoup de sorties moto ou rando se font là où le réseau mobile ne suit pas. GPXlibre télécharge les cartes à l'avance (autour de la trace, ou sur une zone choisie) pour que rien ne dépende d'une connexion pendant la sortie.

## Stack technique

- SwiftUI, iOS 16+
- [MapLibre Native](https://maplibre.org/) pour la carte (tuiles OSM ou fond vectoriel, hors-ligne)
- Aucune dépendance tierce hors MapLibre

---

*Ce README suit les fonctionnalités clés de l'app au fil des itérations — voir `CLAUDE.md` pour le détail technique et `TODO.md` pour l'historique des itérations.*
