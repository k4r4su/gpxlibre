import SwiftUI

/// Pictogrammes DESSINÉS dédiés pour les 3 paliers route-aware (spec
/// "roadbook-route-aware-maneuvers", it24, point 2 — retour terrain explicite : "pas une flèche
/// courbe générique" pour le rond-point, "pictogramme en Y" pour la fourche, "pictogramme dédié
/// distinct du virage classique" pour la fusion/bretelle). Utilisés par `RoadBookTabView`/
/// `RoadbookFocusedView` (écran) ET repris en Core Graphics par `RoadbookPDFExporter` (PDF,
/// même géométrie via `RoadbookPictogramGeometry`) — jamais un simple SF Symbol générique pour
/// ces trois paliers sur les surfaces où l'utilisateur les LIT réellement (le repli SF Symbol de
/// `RoadbookTier.systemImageName` ne sert plus qu'aux pins carte, trop petits pour un dessin).
///
/// Teinte unique reprenant `RoadBookConstants.pdfAccentColorRGB` (esprit chevrons orange/rouge du
/// logo, déjà utilisé par le PDF depuis it23) pour l'élément mis en avant ; `.secondary` pour le
/// contexte discret (sorties non prises, branche non suivie) — jamais l'inverse, l'accent doit
/// toujours désigner SANS AMBIGUÏTÉ ce qu'il faut faire.
enum RoadbookPictogramStyle {
    static let accentColor = Color(
        red: RoadBookConstants.pdfAccentColorRGB.red,
        green: RoadBookConstants.pdfAccentColorRGB.green,
        blue: RoadBookConstants.pdfAccentColorRGB.blue
    )
}

/// Point d'entrée UNIQUE pour afficher le pictogramme d'un `Checkpoint` (spec it24, point 2) —
/// `.roundabout`/`.fork`/`.merge` obtiennent un dessin dédié, tout le reste retombe sur le SF
/// Symbol existant (`RoadbookTier.systemImageName`/`rotationDegrees`, inchangé depuis it23bis).
/// Remplace la paire `Image(systemName:)`/`.rotationEffect` dupliquée sur les 3 écrans
/// consommateurs (table/vue focalisée) par un seul appel.
struct RoadbookManeuverIcon: View {
    let checkpoint: Checkpoint
    let size: CGFloat

    var body: some View {
        switch checkpoint.tier {
        case .roundabout:
            RoadbookRoundaboutPictogram(exitCount: checkpoint.roundaboutExitCount)
                .frame(width: size, height: size)
        case .fork:
            RoadbookForkPictogram(direction: checkpoint.direction)
                .frame(width: size, height: size)
        case .merge:
            RoadbookMergePictogram(direction: checkpoint.direction)
                .frame(width: size, height: size)
        case .light, .marked, .hard, .veryHard, .uTurn, .lightDirectionChange:
            Image(systemName: checkpoint.tier.systemImageName(direction: checkpoint.direction))
                .font(.system(size: size, weight: .semibold))
                .rotationEffect(.degrees(checkpoint.tier.rotationDegrees(direction: checkpoint.direction) ?? 0))
        }
    }
}

/// Anneau + sortie prise en surbrillance, sorties intermédiaires en traits fins discrets (voir
/// `RoadbookPictogramGeometry`) — 0° = 12h/tout droit, sens horaire.
struct RoadbookRoundaboutPictogram: View {
    let exitCount: Int?

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let ringRadius = min(size.width, size.height) * 0.30
            let lineWidth = size.width * 0.07

            var ring = Path()
            ring.addArc(center: center, radius: ringRadius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
            context.stroke(ring, with: .color(.secondary), lineWidth: lineWidth)

            // Entrée fixe, en bas (convention : on entre par le bas, "12h" = tout droit).
            Self.strokeSpoke(&context, center: center, ringRadius: ringRadius, size: size, angleDegrees: 180, outward: true, color: .secondary, lineWidth: lineWidth * 0.7, extraLength: 0)

            for rank in RoadbookPictogramGeometry.skippedExitRanks(exitCount: exitCount) {
                let angle = 180 - RoadbookPictogramGeometry.roundaboutExitAngleDegrees(exitCount: rank)
                Self.strokeSpoke(&context, center: center, ringRadius: ringRadius, size: size, angleDegrees: angle, outward: true, color: Color.secondary.opacity(0.35), lineWidth: lineWidth * 0.5, extraLength: -size.width * 0.05)
            }

            let takenAngle = 180 - RoadbookPictogramGeometry.roundaboutExitAngleDegrees(exitCount: exitCount)
            Self.strokeSpoke(&context, center: center, ringRadius: ringRadius, size: size, angleDegrees: takenAngle, outward: true, color: RoadbookPictogramStyle.accentColor, lineWidth: lineWidth, extraLength: size.width * 0.08, withArrowhead: true)
        }
    }

    /// Trace un rayon depuis (ou vers) le centre, à `angleDegrees` (0 = 12h, sens horaire) —
    /// `outward` part du bord de l'anneau vers l'extérieur (sorties/entrée), jamais du centre
    /// (qui resterait toujours vide, l'anneau lui-même porte le sens "rond-point").
    private static func strokeSpoke(
        _ context: inout GraphicsContext,
        center: CGPoint,
        ringRadius: CGFloat,
        size: CGSize,
        angleDegrees: Double,
        outward: Bool,
        color: Color,
        lineWidth: CGFloat,
        extraLength: CGFloat,
        withArrowhead: Bool = false
    ) {
        let radians = angleDegrees * .pi / 180
        let dx = sin(radians)
        let dy = -cos(radians)
        let outerRadius = min(size.width, size.height) * 0.48 + extraLength
        let start = CGPoint(x: center.x + dx * ringRadius, y: center.y + dy * ringRadius)
        let end = CGPoint(x: center.x + dx * outerRadius, y: center.y + dy * outerRadius)

        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

        guard withArrowhead else { return }
        let headLength = lineWidth * 1.6
        let headAngle = Double.pi / 7
        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - headLength * sin(radians + headAngle), y: end.y + headLength * cos(radians + headAngle)))
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - headLength * sin(radians - headAngle), y: end.y + headLength * cos(radians - headAngle)))
        context.stroke(head, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}

/// "Y" — tige commune puis deux branches divergentes, celle à suivre en surbrillance (accent +
/// trait plus épais), l'autre en trait fin discret. `.straight` met en avant la branche centrale
/// (l'axe qui continue tout droit à un embranchement, PAS un simple "tout droit" sans choix —
/// voir `ValhallaManeuverType.stayStraight`, toujours un vrai point de décision).
struct RoadbookForkPictogram: View {
    let direction: TurnDirection

    private var branchAngleDegrees: Double {
        switch direction {
        case .left: return -28
        case .right: return 28
        default: return 0
        }
    }

    var body: some View {
        Canvas { context, size in
            let bottom = CGPoint(x: size.width / 2, y: size.height * 0.92)
            let junction = CGPoint(x: size.width / 2, y: size.height * 0.5)
            let stem = Path { path in
                path.move(to: bottom)
                path.addLine(to: junction)
            }
            context.stroke(stem, with: .color(.secondary), style: StrokeStyle(lineWidth: size.width * 0.07, lineCap: .round))

            let branchLength = size.height * 0.42
            let dimAngle = branchAngleDegrees > 0 ? -22.0 : (branchAngleDegrees < 0 ? 22.0 : -26.0)
            let dimEnd = Self.point(from: junction, angleDegrees: dimAngle, length: branchLength)
            var dimBranch = Path()
            dimBranch.move(to: junction)
            dimBranch.addLine(to: dimEnd)
            context.stroke(dimBranch, with: .color(.secondary.opacity(0.4)), style: StrokeStyle(lineWidth: size.width * 0.05, lineCap: .round))

            let takenEnd = Self.point(from: junction, angleDegrees: branchAngleDegrees, length: branchLength * 1.05)
            var takenBranch = Path()
            takenBranch.move(to: junction)
            takenBranch.addLine(to: takenEnd)
            context.stroke(takenBranch, with: .color(RoadbookPictogramStyle.accentColor), style: StrokeStyle(lineWidth: size.width * 0.08, lineCap: .round))

            let headLength = size.width * 0.13
            let radians = branchAngleDegrees * .pi / 180
            let headAngle = Double.pi / 6.5
            var head = Path()
            head.move(to: takenEnd)
            head.addLine(to: CGPoint(x: takenEnd.x - headLength * sin(radians + headAngle), y: takenEnd.y - headLength * cos(radians + headAngle)))
            head.move(to: takenEnd)
            head.addLine(to: CGPoint(x: takenEnd.x - headLength * sin(radians - headAngle), y: takenEnd.y - headLength * cos(radians - headAngle)))
            context.stroke(head, with: .color(RoadbookPictogramStyle.accentColor), style: StrokeStyle(lineWidth: size.width * 0.08, lineCap: .round))
        }
    }

    /// `angleDegrees` : 0 = vers le haut, positif = vers la droite (même convention que le reste
    /// du roadbook).
    private static func point(from origin: CGPoint, angleDegrees: Double, length: CGFloat) -> CGPoint {
        let radians = angleDegrees * .pi / 180
        return CGPoint(x: origin.x + length * sin(radians), y: origin.y - length * cos(radians))
    }
}

/// Deux traits qui convergent vers une flèche unique en surbrillance — distinct du virage
/// classique (une seule flèche tournée) : montre explicitement "une autre voie rejoint la
/// tienne", esprit bretelle/fusion. `direction` incline le trait secondaire du côté d'où vient la
/// bretelle (`.straight`/`.merge`, sans variante directionnelle côté Valhalla : les deux traits
/// convergent symétriquement).
struct RoadbookMergePictogram: View {
    let direction: TurnDirection

    var body: some View {
        Canvas { context, size in
            let top = CGPoint(x: size.width / 2, y: size.height * 0.12)
            let junction = CGPoint(x: size.width / 2, y: size.height * 0.55)
            let mainStart: CGPoint
            let secondaryStart: CGPoint
            switch direction {
            case .right:
                mainStart = CGPoint(x: size.width * 0.28, y: size.height * 0.92)
                secondaryStart = CGPoint(x: size.width * 0.82, y: size.height * 0.92)
            case .left:
                mainStart = CGPoint(x: size.width * 0.72, y: size.height * 0.92)
                secondaryStart = CGPoint(x: size.width * 0.18, y: size.height * 0.92)
            default:
                mainStart = CGPoint(x: size.width * 0.32, y: size.height * 0.92)
                secondaryStart = CGPoint(x: size.width * 0.68, y: size.height * 0.92)
            }

            var secondary = Path()
            secondary.move(to: secondaryStart)
            secondary.addLine(to: junction)
            context.stroke(secondary, with: .color(.secondary.opacity(0.45)), style: StrokeStyle(lineWidth: size.width * 0.06, lineCap: .round))

            var main = Path()
            main.move(to: mainStart)
            main.addLine(to: junction)
            context.stroke(main, with: .color(RoadbookPictogramStyle.accentColor), style: StrokeStyle(lineWidth: size.width * 0.08, lineCap: .round))

            var trunk = Path()
            trunk.move(to: junction)
            trunk.addLine(to: top)
            context.stroke(trunk, with: .color(RoadbookPictogramStyle.accentColor), style: StrokeStyle(lineWidth: size.width * 0.08, lineCap: .round))

            let headLength = size.width * 0.14
            var head = Path()
            head.move(to: top)
            head.addLine(to: CGPoint(x: top.x - headLength * 0.6, y: top.y + headLength))
            head.move(to: top)
            head.addLine(to: CGPoint(x: top.x + headLength * 0.6, y: top.y + headLength))
            context.stroke(head, with: .color(RoadbookPictogramStyle.accentColor), style: StrokeStyle(lineWidth: size.width * 0.08, lineCap: .round))
        }
    }
}
