import Foundation
import CoreLocation

/// Élément de panneau de signalisation d'échangeur (`sign.exit_number_elements`/
/// `exit_branch_elements`/`exit_toward_elements`/`exit_name_elements` côté Valhalla) — modélisé
/// simplement (texte uniquement, `consecutive_count` ignoré) : aucune UI dédiée de panneau
/// d'autoroute cette itération (voir TODO.md, backlog "lane/sign guidance"), juste conservé sur
/// le modèle pour une itération future.
struct NavSignInfo: Equatable {
    let exitNumbers: [String]
    let exitBranches: [String]
    let exitTowards: [String]
    let exitNames: [String]

    var isEmpty: Bool { exitNumbers.isEmpty && exitBranches.isEmpty && exitTowards.isEmpty && exitNames.isEmpty }
}

/// Manœuvre Valhalla riche (spec "nav-classic-rebuild", it21) — REMPLACE `NavManeuver` (OSRM,
/// NavRoute.swift) comme source de la bannière de guidage, sans le supprimer (orphelin intact,
/// même patron que `TrackDetailView`/`RoadbookPanelView` ailleurs dans l'app — `NavRoutingService`
/// reste un point de repli documenté si Valhalla devient indisponible pour ce mode, voir
/// RideSessionManager.currentValhallaConfiguration).
///
/// `instruction`/`verbal_*` sont déjà rédigées en FRANÇAIS par Valhalla lui-même (requête avec
/// `language: "fr-FR"`, voir ValhallaNavigationService) — contrairement à l'ancien `NavManeuver`
/// qui synthétisait son propre texte français depuis les champs `type`/`modifier` OSRM (bruts,
/// non localisés), cette manœuvre n'a plus besoin de générer son propre texte.
struct ValhallaNavManeuver: Identifiable, Equatable {
    let id = UUID()
    let type: ValhallaManeuverType
    let instruction: String
    let verbalTransitionAlertInstruction: String?
    let verbalPreTransitionInstruction: String?
    let verbalPostTransitionInstruction: String?
    let streetNames: [String]
    let lengthMeters: Double
    let timeSeconds: Double
    let beginShapeIndex: Int
    let endShapeIndex: Int
    /// Vrai si `verbal_pre_transition_instruction` a déjà été enrichi par Valhalla de la
    /// manœuvre SUIVANTE (deux manœuvres rapprochées, ex. "puis tournez à droite dans 200m") —
    /// pilote l'affichage de la bannière secondaire "puis..." (spec, P1).
    let isMultiCue: Bool
    let roundaboutExitCount: Int?
    let sign: NavSignInfo?

    static func == (lhs: ValhallaNavManeuver, rhs: ValhallaNavManeuver) -> Bool { lhs.id == rhs.id }

    var systemImageName: String { type.systemImageName }

    /// Nom de rue affiché (spec : "street_names → Nom de rue affiché") — Valhalla peut retourner
    /// plusieurs noms alternatifs pour le même tronçon (ex. route nationale + nom local) ;
    /// affiche uniquement le premier, suffisant pour une bannière compacte.
    var displayStreetName: String? { streetNames.first }
}
