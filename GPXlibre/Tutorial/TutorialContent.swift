import Foundation

/// Tutoriel intégré (it31, point 3) — une page par onglet, contenu STATIQUE embarqué (aucun
/// réseau), localisé comme le reste de l'app. ⚠️ Document VIVANT : à relire en fin de CHAQUE
/// itération qui change l'interface (règle permanente, voir CLAUDE.md) — un tutoriel qui décrit une
/// fonctionnalité disparue ou modifiée est pire que pas de tutoriel. Propriété calculée (pas une
/// constante) : le texte suit la langue choisie dans Réglages sans relancer l'app.
struct TutorialPage: Identifiable {
    struct Topic: Identifiable {
        let title: String
        let points: [String]
        var id: String { title }
    }

    let id: String
    let title: String
    let systemImage: String
    let summary: String
    let topics: [Topic]
}

enum TutorialContent {
    static var pages: [TutorialPage] {
        [ride, goTo, roadBook, library, settings]
    }

    private static var ride: TutorialPage {
        TutorialPage(
            id: "ride",
            title: String(localized: "Ride"),
            systemImage: "location.north.line.fill",
            summary: String(localized: "La carte de conduite : suivre la trace active, voir les prochains virages et enregistrer la sortie."),
            topics: [
                .init(title: String(localized: "Suivre une trace"), points: [
                    String(localized: "La trace active (cochée dans la Bibliothèque) est dessinée sur la carte, avec des chevrons dans le sens de parcours."),
                    String(localized: "Le bandeau latéral annonce le prochain virage avec un compte à rebours ; l'écran flashe dans les 100 derniers mètres."),
                    String(localized: "Si tu t'écartes de plus de 30 m, la puce « Hors trace » apparaît ; après 30 s, elle indique la distance pour rejoindre la trace."),
                ]),
                .init(title: String(localized: "Enregistrer la sortie"), points: [
                    String(localized: "Au démarrage du suivi, l'app propose d'enregistrer la sortie. C'est recommandé, mais tu peux refuser."),
                    String(localized: "Le bouton au-dessus du compteur de vitesse démarre, met en pause ou reprend l'enregistrement."),
                    String(localized: "L'enregistrement continue dans les autres onglets, écran verrouillé ou dans une autre app : la flèche bleue d'iOS est alors affichée en haut de l'écran."),
                    String(localized: "Touche le compteur de vitesse pour les mesures, puis « Terminer la sortie » pour l'enregistrer dans la Bibliothèque ou la supprimer."),
                ]),
                .init(title: String(localized: "Contrôles"), points: [
                    String(localized: "+ et − zooment ; « Me recentrer » ramène la carte sur ta position."),
                    String(localized: "Pause suspend le guidage (appui long : l'arrêter). La trace et l'enregistrement restent actifs."),
                    String(localized: "« Bloqué » signale un chemin impraticable et propose un détour."),
                ]),
            ]
        )
    }

    private static var goTo: TutorialPage {
        TutorialPage(
            id: "goTo",
            title: String(localized: "Aller à"),
            systemImage: "magnifyingglass",
            summary: String(localized: "Aller vers une adresse ou un lieu, en dehors de toute trace."),
            topics: [
                .init(title: String(localized: "Chercher une destination"), points: [
                    String(localized: "Tape une adresse ou un lieu, puis choisis un profil : Itinéraire (routes), Piste ou Mixte."),
                    String(localized: "Domicile et Travail sont accessibles en un tap (à définir dans Réglages > Adresses favoris)."),
                    String(localized: "Tes dernières recherches sont proposées quand le champ est vide."),
                ]),
                .init(title: String(localized: "Pendant le guidage"), points: [
                    String(localized: "L'app bascule sur Ride et affiche le chemin vers la destination. Un seul guidage est actif à la fois : la trace est mise en pause."),
                    String(localized: "« Revenir à la trace » termine le guidage vers la destination."),
                ]),
            ]
        )
    }

    private static var roadBook: TutorialPage {
        TutorialPage(
            id: "roadBook",
            title: String(localized: "Road Book"),
            systemImage: "list.bullet.rectangle",
            summary: String(localized: "La trace active en liste de directions, comme un road book papier de rallye."),
            topics: [
                .init(title: String(localized: "Deux modes de lecture"), points: [
                    String(localized: "Assisté GPS : le prochain élément en grand, avec la distance qui diminue, puis la liste de ce qui suit."),
                    String(localized: "Roadbook classique : toute la liste avec distances partielles et cumulées, comme sur papier."),
                    String(localized: "Le prochain élément est toujours le plus proche, virage ou repère : un stop à 200 m passe avant un virage à 300 m."),
                    String(localized: "Si tu t'écartes de la trace, « Hors trace » remplace le prochain élément jusqu'à ton retour."),
                ]),
                .init(title: String(localized: "Repères"), points: [
                    String(localized: "Seul ce qui se voit depuis la route est affiché : panneaux, ponts, églises, stations-service, entrées de village…"),
                    String(localized: "Les catégories se choisissent dans Réglages > Repères du Road Book."),
                    String(localized: "Le téléchargement des repères s'affiche en haut, avec sa progression ; les directions restent utilisables pendant ce temps."),
                ]),
                .init(title: String(localized: "Autres actions"), points: [
                    String(localized: "En haut à gauche, le nom de la trace active : un tap ouvre la Bibliothèque, seul endroit où la changer."),
                    String(localized: "Le bouton de partage exporte le road book en PDF."),
                    String(localized: "Un tap sur un élément le montre sur la carte Ride."),
                ]),
            ]
        )
    }

    private static var library: TutorialPage {
        TutorialPage(
            id: "library",
            title: String(localized: "Biblio"),
            systemImage: "books.vertical",
            summary: String(localized: "Tes traces GPX : importer, choisir la trace active, ranger, partager."),
            topics: [
                .init(title: String(localized: "Traces"), points: [
                    String(localized: "« + » importe un fichier GPX (ou ouvre-le depuis Fichiers, Mail, Safari)."),
                    String(localized: "Le rond à gauche d'une trace la rend active : c'est elle que suivent Ride et Road Book."),
                    String(localized: "Un tap sur une trace ouvre sa fiche : partager, renommer, supprimer, statistiques."),
                    String(localized: "Glisser vers la droite : paramétrer la trace (sens de parcours, apparence) ou la déplacer."),
                ]),
                .init(title: String(localized: "Dossiers"), points: [
                    String(localized: "« + » > Nouveau dossier, puis « Déplacer » sur une trace (glisser ou appui long) pour la ranger."),
                    String(localized: "Le menu … d'un dossier permet de le renommer ou le supprimer ; ses traces ne sont jamais supprimées, elles retournent dans « Non classé »."),
                ]),
                .init(title: String(localized: "Sorties non enregistrées"), points: [
                    String(localized: "Une sortie en cours d'enregistrement est sauvegardée régulièrement ; si l'app se ferme, récupère-la ici."),
                ]),
            ]
        )
    }

    private static var settings: TutorialPage {
        TutorialPage(
            id: "settings",
            title: String(localized: "Réglages"),
            systemImage: "gearshape",
            summary: String(localized: "Tous les réglages s'appliquent tout de suite."),
            topics: [
                .init(title: String(localized: "Principaux réglages"), points: [
                    String(localized: "Langue : automatique (langue de l'appareil) ou forcée."),
                    String(localized: "Navigation : position du point bleu, zoom par défaut et zoom automatique, avec aperçu."),
                    String(localized: "Roadbook : sensibilité de détection des virages ; Repères du Road Book : catégories affichées."),
                    String(localized: "Carte et Apparence : orientation, thème, unité de vitesse, trace, position des contrôles, palette du Road Book."),
                    String(localized: "Enregistrement de la sortie : densité des points et nombre de sauvegardes de secours conservées."),
                    String(localized: "Avancé : routage Valhalla (optionnel)."),
                ]),
            ]
        )
    }
}
