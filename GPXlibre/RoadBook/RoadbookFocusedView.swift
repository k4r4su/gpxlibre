import SwiftUI

/// Vue "focus" du mode Assisté GPS (spec "roadbook-focused-next-turn", it23ter ; refonte
/// UI/UX "roadbook-ui-redesign", it25). Lit EXACTEMENT la même liste `[RoadbookManeuver]`/le
/// même calcul `RoadbookLiveProgress` que le mode Classique — seule la présentation change,
/// jamais une deuxième source de données (voir RoadBook/CLAUDE.md).
///
/// Layout PORTRAIT (it23ter, "au moins la moitié de l'écran... et en dessous les suivants") :
/// carte hero fixe en haut (`RoadBookConstants.focusedHeroHeightFraction`), liste SCROLLABLE de
/// TOUTES les manœuvres restantes en dessous (it25, point 1 — retour terrain : "seuls 2 éléments
/// s'affichent avant d'être coupés par la tab bar", plus de limite à `.prefix(2)`).
///
/// Layout PAYSAGE (it25, point 2 — retour terrain détaillé : mini-carte en bande illisible,
/// texte qui chevauche la tab bar) : hero à hauteur FIXE et COMPACTE
/// (`focusedHeroLandscapeHeight`, pas la moitié de l'écran — un écran deux fois moins haut ne
/// laisserait sinon presque rien à la liste), disposition HORIZONTALE dédiée (pictogramme à
/// gauche, distance à droite) plutôt que le portrait simplement compressé.
struct RoadbookFocusedView: View {
    let maneuvers: [RoadbookManeuver]
    /// Repères visibles en ligne dédiée — intercalés dans la liste des étapes À VENIR, jamais
    /// dans la carte hero (qui reste le prochain changement de direction).
    let landmarkCheckpoints: [RoadbookLandmarkCheckpoint]
    let currentIndex: Int?
    let distanceRemainingMeters: Double?
    /// Position actuelle projetée sur la trace — distance "dans combien" des checkpoints.
    let currentCumulativeDistanceMeters: Double?
    let unit: DistanceUnit
    /// Distingue "pas encore de position GPS" de "trace terminée" (les deux se traduisent par
    /// `currentIndex == nil`, mais méritent un message différent — jamais le même écran vide
    /// muet pour deux situations différentes).
    let hasLocationFix: Bool
    /// Repères OSM à proximité (spec "roadbook-mode", it23quater) — voir `RoadBookTabView`,
    /// clé absente = pas encore résolu, valeur `nil` = résolu sans résultat.
    let landmarks: [UUID: RoadbookLandmarkInfo?]
    /// Largeur à réserver à DROITE du hero en paysage quand la mini-carte sera affichée par-
    /// dessus (`RoadBookTabView`, même condition exacte que `showsLandscapeMiniMap`) — `0` sinon.
    /// Fix "roadbook-landscape-minimap-overlap" (it25, retour terrain avec capture : la mini-
    /// carte chevauchait le texte de distance) : sans cette réservation, le texte de distance
    /// (aligné à droite) et la mini-carte (ancrée à droite) se disputaient le même espace.
    var landscapeMiniMapReservedWidth: CGFloat = 0

    /// `.compact` = paysage sur iPhone (TARGETED_DEVICE_FAMILY "1", pas d'iPad à gérer) — signal
    /// natif SwiftUI, se met à jour automatiquement à la rotation, jamais besoin d'observer
    /// `UIDevice.orientation` à la main.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isLandscape: Bool { verticalSizeClass == .compact }

    private enum UpcomingStep: Identifiable {
        case maneuver(RoadbookManeuver, rank: Int, distanceFromNowMeters: Double)
        case landmark(RoadbookLandmarkCheckpoint, distanceFromNowMeters: Double)

        var id: String {
            switch self {
            case .maneuver(let maneuver, _, _): return "maneuver-\(maneuver.id.uuidString)"
            case .landmark(let landmark, _): return landmark.id
            }
        }

        var distanceFromNowMeters: Double {
            switch self {
            case .maneuver(_, _, let distance), .landmark(_, let distance): return distance
            }
        }
    }

    /// TOUTES les étapes restantes (it25, point 1 — plus de `.prefix(2)`), manœuvres et
    /// checkpoints de commune (it26 point 3) mêlés par distance — distance recalculée DEPUIS LA
    /// POSITION ACTUELLE, une vraie distance "dans combien" plutôt qu'un simple report de
    /// `partialDistanceMeters`.
    private var upcoming: [UpcomingStep] {
        guard let currentIndex, let distanceRemainingMeters,
              maneuvers.indices.contains(currentIndex)
        else { return [] }
        let currentCumulative = maneuvers[currentIndex].cumulativeDistanceMeters
        let upcomingManeuvers = maneuvers[(currentIndex + 1)...].enumerated().map { offset, maneuver in
            UpcomingStep.maneuver(maneuver, rank: offset + 2, distanceFromNowMeters: maneuver.cumulativeDistanceMeters - currentCumulative + distanceRemainingMeters)
        }
        let position = currentCumulativeDistanceMeters ?? (currentCumulative - distanceRemainingMeters)
        let upcomingLandmarks = landmarkCheckpoints
            .filter { $0.cumulativeDistanceMeters > position }
            .map { UpcomingStep.landmark($0, distanceFromNowMeters: $0.cumulativeDistanceMeters - position) }
        return (upcomingManeuvers + upcomingLandmarks).sorted { $0.distanceFromNowMeters < $1.distanceFromNowMeters }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                heroContent
                    .frame(maxWidth: .infinity)
                    .frame(height: heroHeight(availableHeight: geometry.size.height))

                if !upcoming.isEmpty {
                    Divider()
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(upcoming) { step in
                                switch step {
                                case .maneuver(let maneuver, let rank, let distance):
                                    RoadbookUpcomingRow(
                                        maneuver: maneuver,
                                        distanceFromNowMeters: distance,
                                        unit: unit,
                                        rank: rank,
                                        landmark: landmarks[maneuver.id] ?? nil
                                    )
                                case .landmark(let landmark, let distance):
                                    RoadbookUpcomingLandmarkRow(landmark: landmark, distanceFromNowMeters: distance, unit: unit)
                                }
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var heroContent: some View {
        if let currentIndex, let distanceRemainingMeters, maneuvers.indices.contains(currentIndex) {
            let current = maneuvers[currentIndex]
            if isLandscape {
                RoadbookBigManeuverCardLandscape(maneuver: current, distanceRemainingMeters: distanceRemainingMeters, unit: unit, landmark: landmarks[current.id] ?? nil, trailingReservedWidth: landscapeMiniMapReservedWidth)
            } else {
                RoadbookBigManeuverCard(maneuver: current, distanceRemainingMeters: distanceRemainingMeters, unit: unit, landmark: landmarks[current.id] ?? nil)
            }
        } else if !hasLocationFix {
            RoadbookFocusStatusView(systemImage: "location.slash", message: "En attente d'une position GPS…")
        } else {
            RoadbookFocusStatusView(systemImage: "checkered.flag", message: "Toutes les manœuvres de cette trace ont été passées.")
        }
    }

    private func heroHeight(availableHeight: CGFloat) -> CGFloat {
        if isLandscape {
            return min(CGFloat(RoadBookConstants.focusedHeroLandscapeHeight), availableHeight)
        }
        return max(availableHeight * RoadBookConstants.focusedHeroHeightFraction, RoadBookConstants.focusedHeroMinHeight)
    }
}

/// Carte plein écran de la manœuvre EN COURS, layout PORTRAIT — pictogramme et distance très
/// larges, lisibles d'un coup d'œil bref (esprit "au moins la moitié de l'écran").
private struct RoadbookBigManeuverCard: View {
    let maneuver: RoadbookManeuver
    let distanceRemainingMeters: Double
    let unit: DistanceUnit
    let landmark: RoadbookLandmarkInfo?

    /// Spec "roadbook-jump-to-map" — retour terrain : "clic sur un virage... aller dans l'onglet
    /// Ride pour voir de quel virage on parle". `AppNavigationState` reste le SEUL point de
    /// passage vers l'onglet Ride (jamais un accès direct à `RideSessionManager` depuis ce
    /// module, invariant "découplé de l'état de Ride actif").
    @EnvironmentObject private var navigationState: AppNavigationState

    var body: some View {
        Button {
            navigationState.focusRideMap(on: maneuver.checkpoint.coordinate)
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
    }

    private var cardContent: some View {
        VStack(spacing: 16) {
            // Pictogramme emoji du repère À CÔTÉ de la flèche (retour terrain it23sexies :
            // "à côté de la flèche il y ait des pictogrammes afin d'augmenter l'aide au niveau
            // du prochain virage") — HStack pour rester bien lisible même en très grande taille.
            HStack(alignment: .center, spacing: 12) {
                RoadbookManeuverIcon(checkpoint: maneuver.checkpoint, size: 120)
                    .foregroundStyle(Color.accentColor)
                if let landmark {
                    Text(landmark.category.emoji)
                        .font(.system(size: 64))
                }
            }
            Text("Cap \(Int(maneuver.headingDegrees.rounded()))°")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(unit.displayString(fromMeters: distanceRemainingMeters))
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(maneuver.checkpoint.tier.label)
                .font(.title3.bold())
                .foregroundStyle(.secondary)
            if let landmark {
                Text(landmark.displayLabel)
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
    }
}

/// Équivalent PAYSAGE (spec "roadbook-ui-redesign", it25, point 2, demande explicite) :
/// pictogramme à GAUCHE, distance à DROITE — jamais le portrait simplement compressé (root cause
/// du bug terrain : les mêmes tailles de police qu'en portrait, sur un écran deux fois moins
/// haut, débordaient jusqu'à chevaucher la tab bar). Agrandi une seconde fois (retour terrain :
/// "augmenter encore plus la taille de la flèche... priorité à la direction et la distance")
/// une fois le sélecteur de mode déplacé dans une colonne à droite (voir `RoadBookTabView.
/// landscapeModeColumn`) — la hauteur ainsi libérée (`RoadBookConstants.
/// focusedHeroLandscapeHeight`, 170→210) permet un pictogramme et un chiffre de distance
/// nettement plus imposants sans déborder.
private struct RoadbookBigManeuverCardLandscape: View {
    let maneuver: RoadbookManeuver
    let distanceRemainingMeters: Double
    let unit: DistanceUnit
    let landmark: RoadbookLandmarkInfo?
    /// Cf. `RoadbookFocusedView.landscapeMiniMapReservedWidth`.
    let trailingReservedWidth: CGFloat

    /// Spec "roadbook-jump-to-map" — voir `RoadbookBigManeuverCard` (portrait) pour le détail.
    @EnvironmentObject private var navigationState: AppNavigationState

    var body: some View {
        Button {
            navigationState.focusRideMap(on: maneuver.checkpoint.coordinate)
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
    }

    private var cardContent: some View {
        HStack(spacing: 24) {
            VStack(spacing: 4) {
                RoadbookManeuverIcon(checkpoint: maneuver.checkpoint, size: 120)
                    .foregroundStyle(Color.accentColor)
                if let landmark {
                    Text(landmark.category.emoji)
                        .font(.system(size: 40))
                }
            }

            // Fix "roadbook-landscape-tier-label-truncated" (it25, retour terrain avec capture :
            // "Virage prononcé" tronqué en "Virage pr...") — agrandi une seconde fois par erreur
            // en même temps que le pictogramme/la distance ; la demande portait explicitement sur
            // "la flèche" et "la distance", pas ce texte. Revenu à sa taille d'origine
            // (`.headline`, qui tenait déjà correctement) + `minimumScaleFactor` en filet de
            // sécurité plutôt qu'une troncature "..." si jamais l'espace redevient juste.
            VStack(alignment: .leading, spacing: 2) {
                Text(maneuver.checkpoint.tier.label)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let landmark {
                    Text(landmark.displayLabel)
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text("Cap \(Int(maneuver.headingDegrees.rounded()))°")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(unit.displayString(fromMeters: distanceRemainingMeters))
                .font(.system(size: 60, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .padding(.leading, 20)
        .padding(.trailing, 20 + trailingReservedWidth)
    }
}

private struct RoadbookUpcomingRow: View {
    let maneuver: RoadbookManeuver
    let distanceFromNowMeters: Double
    let unit: DistanceUnit
    /// "+2"/"+3" — position relative à la manœuvre en cours, jamais l'index absolu dans la
    /// trace (ce que voit le pilote, c'est "dans 2 manœuvres", pas "la 7e de la liste").
    let rank: Int
    let landmark: RoadbookLandmarkInfo?

    /// Spec "roadbook-jump-to-map" — voir `RoadbookBigManeuverCard` pour le détail.
    @EnvironmentObject private var navigationState: AppNavigationState

    var body: some View {
        Button {
            navigationState.focusRideMap(on: maneuver.checkpoint.coordinate)
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
    }

    private var rowContent: some View {
        HStack(spacing: 16) {
            Text("+\(rank - 1)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28)

            HStack(spacing: 4) {
                RoadbookManeuverIcon(checkpoint: maneuver.checkpoint, size: 28)
                    .foregroundStyle(.primary)
                if let landmark {
                    Text(landmark.category.emoji)
                        .font(.system(size: 22))
                }
            }
            .frame(width: 60)

            VStack(alignment: .leading, spacing: 1) {
                Text(maneuver.checkpoint.tier.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let landmark {
                    Text(landmark.displayLabel)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(unit.displayString(fromMeters: distanceFromNowMeters))
                    .font(.headline.monospacedDigit())
                Text("\(Int(maneuver.headingDegrees.rounded()))°")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// Repère visible dans la liste des étapes à venir — pictogramme de la catégorie + nom, côté,
/// fond teinté : jamais confondu avec un virage.
private struct RoadbookUpcomingLandmarkRow: View {
    let landmark: RoadbookLandmarkCheckpoint
    let distanceFromNowMeters: Double
    let unit: DistanceUnit

    @EnvironmentObject private var navigationState: AppNavigationState

    var body: some View {
        Button {
            navigationState.focusRideMap(on: landmark.coordinate)
        } label: {
            HStack(spacing: 16) {
                Color.clear.frame(width: 28, height: 1)
                RoadbookLandmarkIcon(category: landmark.info.category, size: 22)
                    .frame(width: 60)
                VStack(alignment: .leading, spacing: 1) {
                    Text(landmark.info.label)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Text(RoadbookLandmarkRowText.detail(landmark.info))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(unit.displayString(fromMeters: distanceFromNowMeters))
                    .font(.headline.monospacedDigit())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.accentColor.opacity(0.06))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Repère : \(landmark.info.displayLabel), dans \(unit.displayString(fromMeters: distanceFromNowMeters))")
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
