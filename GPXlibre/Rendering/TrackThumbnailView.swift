import SwiftUI

/// Miniature directionnelle (spec "biblio-preview-direction", it11) — `Canvas` pur, PAS de
/// carte interactive : contrairement à `TrackMapView` (MKMapView complet, tuiles réseau,
/// gestes), ce dessin ne dépend que de `track.points` déjà en mémoire, déjà réordonnés. Se
/// redessine à chaque frame SwiftUI sans coût perceptible — changer le sens dans le panneau
/// d'aperçu met donc à jour la miniature immédiatement, sans rescan GPS ni round-trip disque.
struct TrackThumbnailView: View {
    let track: GPXTrack
    let appearance: TraceAppearance
    let chevronSpacingMeters: Double
    let isReversed: Bool

    private static let casingWidth: CGFloat = 3.5
    private static let lineWidth: CGFloat = 1.6
    private static let chevronLength: CGFloat = 8
    private static let inset: CGFloat = 14

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            directionBadge
        }
    }

    private var directionBadge: some View {
        Text(isReversed ? "B → A" : "A → B")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.black.opacity(0.65), in: Capsule())
            .padding(8)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let projection = TrackThumbnailGeometry.project(points: track.points, chevronSpacingMeters: chevronSpacingMeters)
        guard projection.points.count > 1 else { return }

        let drawableWidth = max(size.width - Self.inset * 2, 1)
        let drawableHeight = max(size.height - Self.inset * 2, 1)
        func screenPoint(_ normalized: CGPoint) -> CGPoint {
            CGPoint(x: Self.inset + normalized.x * drawableWidth, y: Self.inset + normalized.y * drawableHeight)
        }

        var path = Path()
        path.addLines(projection.points.map(screenPoint))

        // Casing d'abord (dessous), couleur ensuite (dessus) — même contraste que la trace
        // réelle sur la carte (voir TraceAppearance), juste des largeurs réduites : les
        // largeurs pleine carte (jusqu'à 9pt "Gants-épais") baveraient sur une image de
        // quelques dizaines de points.
        context.stroke(path, with: .color(Color(appearance.casingColor)), style: StrokeStyle(lineWidth: Self.casingWidth, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(Color(appearance.color)), style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round))

        for chevron in projection.chevrons {
            drawChevron(chevron, in: &context, screenPoint: screenPoint)
        }
    }

    /// Même convention que `RideMapLibreView.Coordinator.chevronImage` : un triangle plein
    /// dessiné pointant vers le HAUT au repos (0°), tourné en degrés horaires depuis le nord
    /// — cohérent avec le cap boussole (`bearingDegrees`) sans décalage de 90°.
    private func drawChevron(_ chevron: TrackThumbnailGeometry.ProjectedChevron, in context: inout GraphicsContext, screenPoint: (CGPoint) -> CGPoint) {
        let center = screenPoint(chevron.point)
        var triangle = Path()
        triangle.move(to: CGPoint(x: 0, y: -Self.chevronLength * 0.6))
        triangle.addLine(to: CGPoint(x: Self.chevronLength * 0.5, y: Self.chevronLength * 0.5))
        triangle.addLine(to: CGPoint(x: -Self.chevronLength * 0.5, y: Self.chevronLength * 0.5))
        triangle.closeSubpath()

        let transform = CGAffineTransform(rotationAngle: chevron.bearingDegrees * .pi / 180)
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
        let rotated = triangle.applying(transform)

        context.fill(rotated, with: .color(Color(appearance.color)))
        context.stroke(rotated, with: .color(.black.opacity(0.55)), lineWidth: 1)
    }
}
