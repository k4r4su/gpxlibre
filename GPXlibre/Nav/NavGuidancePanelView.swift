import SwiftUI

/// Panneau de guidage tour-par-tour Mode Nav, EN HAUT pleine largeur (fix
/// "overlay-layout-grid", Bug 3). Pendant du RoadbookPanelView côté Trace, même style (fix
/// "panel-consistency", Bug 6).
///
/// Fix "nav-banner-too-verbose" (it21, retour terrain : "trop d'info. Je veux juste la
/// direction et dans combien de mètres on change de direction. Le numéro de sortie si c'est un
/// rond-point. [...] 2 parties : à gauche la direction et la distance, à droite des infos de
/// texte plus petites pour prioriser la visibilité de la direction") — deux zones cloisonnées :
/// GAUCHE proéminente (icône + distance + badge sortie, ce qu'un coup d'œil rapide en conduisant
/// doit capter), DROITE en retrait (texte d'instruction + nom de rue EN DESSOUS, séparés, pas
/// "à la suite" comme dans la version précédente qui empilait tout au même niveau visuel).
///
/// Spec "nav-classic-rebuild" (it21) : `maneuver` est un `ValhallaNavManeuver` — son
/// `instruction` est déjà un texte français complet composé par Valhalla lui-même (requête
/// `language: "fr-FR"`), plus besoin de synthétiser une phrase depuis un `type`/`modifier` OSRM
/// brut comme le faisait l'ancien `NavManeuver.instructionText`.
struct NavGuidancePanelView: View {
    let maneuver: ValhallaNavManeuver?
    let distanceMeters: Double?
    let destinationLabel: String
    let isRecalculating: Bool
    /// Fix "nav-guidance-stop-button" (it22, retour terrain : "une fois un itinéraire actif via
    /// Aller à, il faut un bouton visible pour l'arrêter") — jusqu'ici, cette bannière n'avait
    /// AUCUN contrôle de fermeture propre (seul `GoToStatusPillView`, le guidage SIMPLE, en
    /// avait un) : une fois `session.navRoute != nil`, rien dans cette vue ne permettait de
    /// revenir en arrière. Libellé décidé par l'appelant (`RideView`) — "Revenir à la trace" si
    /// une trace reste active (spec "manual-point-guidance-exclusivity"), sinon "Arrêter".
    let stopLabel: String
    let onStop: () -> Void

    var body: some View {
        // Fix "nav-panel-fullscreen" (it22bis, retour terrain : "le panneau de direction prend
        // toute la page, on ne voit même plus la carte") — root cause : le séparateur vertical
        // ci-dessous est un `Rectangle()` NU (un `Shape`), qui n'a AUCUNE taille intrinsèque et
        // accepte donc toute la hauteur proposée par le parent. `directionPanelLayer` vit dans
        // une VStack dont le SEUL autre enfant est un `Spacer()` (voir RideView.topStackLayer) —
        // rien ne borne la hauteur proposée à ce HStack, qui hérite donc de la hauteur PLEIN
        // ÉCRAN offerte par le ZStack racine (RideMapLibreView + overlays). `.fixedSize(vertical:
        // true)` force ce HStack à calculer sa hauteur RÉELLE depuis son contenu (ignore la
        // proposition ambiante), sans toucher à la largeur (reste flexible, `Spacer()` continue
        // de pousser le bouton stop à droite normalement).
        HStack(alignment: .center, spacing: 14) {
            // Zone GAUCHE (proéminente) : direction + distance + sortie de rond-point — tout ce
            // qu'un coup d'œil rapide doit capter, rien d'autre.
            //
            // Fix "nav-roundabout-badge-overlay" (retour terrain : "beaucoup trop d'info [...]
            // si on arrive sur un rond-point et prendre la 3e sortie, il faut mettre l'icône
            // d'un rond-point avec le numéro 3, de façon à optimiser l'affichage sans avoir
            // trop à lire") — le numéro de sortie était affiché comme un second élément texte
            // EMPILÉ sous l'icône (deux lignes à lire) ; il devient un badge numéroté superposé
            // EN OVERLAY sur l'icône elle-même (une seule unité visuelle icône+chiffre).
            VStack(spacing: 4) {
                Image(systemName: maneuver?.systemImageName ?? "location.north.line.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .overlay(alignment: .bottomTrailing) {
                        if let exitCount = maneuver?.roundaboutExitCount, maneuver?.type.isRoundabout == true {
                            Text("\(exitCount)")
                                .font(.caption2.bold())
                                .foregroundStyle(.blue)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(.white, in: Circle())
                                .offset(x: 6, y: 4)
                        }
                    }
                Text(distanceText)
                    .font(.system(.title3, design: .rounded).bold())
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .frame(minWidth: 76)

            Rectangle()
                .fill(.white.opacity(0.25))
                .frame(width: 1)
                .padding(.vertical, 4)

            // Zone DROITE (en retrait) : texte, plus petit, nom de rue sur SA PROPRE ligne en
            // dessous — jamais à la suite de l'instruction sur la même ligne.
            VStack(alignment: .leading, spacing: 3) {
                Text(maneuver?.instruction ?? "Vers \(destinationLabel)")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                if let street = maneuver?.displayStreetName, !street.isEmpty {
                    Text(street)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer()

            if isRecalculating {
                ProgressView()
                    .tint(.white)
            }

            Button(action: onStop) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .longPressTooltip(stopLabel)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .ridePanelStyle(tint: .blue, tintOpacity: 0.45)
        .padding(.horizontal, 12)
    }

    private var distanceText: String {
        guard let distanceMeters else { return "—" }
        if distanceMeters < 1000 {
            return "\(Int(distanceMeters.rounded())) m"
        }
        return String(format: "%.1f km", distanceMeters / 1000)
    }
}

/// Bannière secondaire "puis..." (spec "nav-classic-rebuild", P1) — visible UNIQUEMENT quand
/// Valhalla signale un enchaînement rapproché (`verbal_multi_cue` sur la manœuvre courante,
/// voir RideView.directionPanelLayer) : deux manœuvres trop proches pour laisser le temps de
/// réagir à la première seule, ex. "tournez à droite PUIS immédiatement à gauche".
struct NavSecondaryBannerView: View {
    let maneuver: ValhallaNavManeuver

    var body: some View {
        HStack(spacing: 10) {
            Text("Puis")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.7))
            Image(systemName: maneuver.systemImageName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            Text(maneuver.instruction)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .ridePanelStyle(tint: .blue, tintOpacity: 0.3)
        .padding(.horizontal, 24)
    }
}
