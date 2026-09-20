import SwiftUI

/// Vue "focus" du mode Assisté GPS (spec "roadbook-focused-next-turn", it23ter, retour terrain :
/// "il faudrait clairement afficher le prochain virage qui prenne au moins la moitié de l'écran
/// pour être visible, et en dessous les 2 suivants en un peu plus petit"). Lit EXACTEMENT la
/// même liste `[RoadbookManeuver]`/le même calcul `RoadbookLiveProgress` que le mode Classique —
/// seule la présentation change, jamais une deuxième source de données (voir RoadBook/CLAUDE.md).
struct RoadbookFocusedView: View {
    let maneuvers: [RoadbookManeuver]
    let currentIndex: Int?
    let distanceRemainingMeters: Double?
    let unit: DistanceUnit
    /// Distingue "pas encore de position GPS" de "trace terminée" (les deux se traduisent par
    /// `currentIndex == nil`, mais méritent un message différent — jamais le même écran vide
    /// muet pour deux situations différentes).
    let hasLocationFix: Bool

    /// Les 2 manœuvres qui suivent celle actuellement mise en avant — distance recalculée
    /// DEPUIS LA POSITION ACTUELLE (pas depuis la manœuvre courante), pour rester une vraie
    /// distance "dans combien" plutôt qu'un simple report de `partialDistanceMeters`.
    private var upcoming: [(maneuver: RoadbookManeuver, distanceFromNowMeters: Double)] {
        guard let currentIndex, let distanceRemainingMeters,
              maneuvers.indices.contains(currentIndex)
        else { return [] }
        let currentCumulative = maneuvers[currentIndex].cumulativeDistanceMeters
        return maneuvers[(currentIndex + 1)...].prefix(2).map { maneuver in
            (maneuver, maneuver.cumulativeDistanceMeters - currentCumulative + distanceRemainingMeters)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let currentIndex, let distanceRemainingMeters, maneuvers.indices.contains(currentIndex) {
                    RoadbookBigManeuverCard(maneuver: maneuvers[currentIndex], distanceRemainingMeters: distanceRemainingMeters, unit: unit)
                } else if !hasLocationFix {
                    RoadbookFocusStatusView(systemImage: "location.slash", message: "En attente d'une position GPS…")
                } else {
                    RoadbookFocusStatusView(systemImage: "checkered.flag", message: "Toutes les manœuvres de cette trace ont été passées.")
                }
            }
            // "au moins la moitié de l'écran" : la carte occupe TOUT l'espace restant une fois
            // les 2 lignes suivantes (taille intrinsèque) posées — largement plus de la moitié
            // en pratique dès qu'il y a moins de 3 manœuvres à venir.
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !upcoming.isEmpty {
                Divider()
                VStack(spacing: 0) {
                    ForEach(Array(upcoming.enumerated()), id: \.element.maneuver.id) { offset, entry in
                        RoadbookUpcomingRow(maneuver: entry.maneuver, distanceFromNowMeters: entry.distanceFromNowMeters, unit: unit, rank: offset + 2)
                        if offset < upcoming.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }
}

/// Carte plein écran de la manœuvre EN COURS — pictogramme et distance très larges, lisibles
/// d'un coup d'œil bref (esprit "au moins la moitié de l'écran", demande explicite).
private struct RoadbookBigManeuverCard: View {
    let maneuver: RoadbookManeuver
    let distanceRemainingMeters: Double
    let unit: DistanceUnit

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: maneuver.checkpoint.tier.systemImageName(direction: maneuver.checkpoint.direction))
                .font(.system(size: 120, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .rotationEffect(.degrees(maneuver.checkpoint.tier.rotationDegrees(direction: maneuver.checkpoint.direction) ?? 0))
            Text(unit.displayString(fromMeters: distanceRemainingMeters))
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(maneuver.checkpoint.tier.label)
                .font(.title3.bold())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
    }
}

private struct RoadbookUpcomingRow: View {
    let maneuver: RoadbookManeuver
    let distanceFromNowMeters: Double
    let unit: DistanceUnit
    /// "+2"/"+3" — position relative à la manœuvre en cours, jamais l'index absolu dans la
    /// trace (ce que voit le pilote, c'est "dans 2 manœuvres", pas "la 7e de la liste").
    let rank: Int

    var body: some View {
        HStack(spacing: 16) {
            Text("+\(rank - 1)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28)

            Image(systemName: maneuver.checkpoint.tier.systemImageName(direction: maneuver.checkpoint.direction))
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.primary)
                .rotationEffect(.degrees(maneuver.checkpoint.tier.rotationDegrees(direction: maneuver.checkpoint.direction) ?? 0))
                .frame(width: 40)

            Text(maneuver.checkpoint.tier.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(unit.displayString(fromMeters: distanceFromNowMeters))
                .font(.headline.monospacedDigit())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct RoadbookFocusStatusView: View {
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.title3.bold())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}
