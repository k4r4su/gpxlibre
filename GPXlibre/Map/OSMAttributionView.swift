import SwiftUI

/// Attribution visible en permanence — exigence de licence, non désactivable. Le texte
/// dépend du fond de carte actif (spec "vector-pmtiles", it11) : chaque source a sa propre
/// exigence d'attribution (OSM seul pour le raster standard, OSM+SRTM+OpenTopoMap pour le
/// thème Relief, OpenFreeMap+OpenMapTiles+OSM pour le fond vectoriel hébergé).
struct OSMAttributionView: View {
    let mapSource: MapSourceSelection

    private var attributionText: String {
        switch mapSource {
        case .raster(let tileSource): return tileSource.attributionPlainText
        case .vectorHosted: return MapEngineConstants.vectorHostedAttributionPlainText
        // Paquet local : la provenance exacte dépend de l'extrait Geofabrik choisi par le
        // propriétaire (voir docs/generation-tuiles-regionales.md) — attribution OSM de base,
        // toujours valide quelle que soit la région.
        case .vectorLocal: return MapEngineConstants.osmAttributionPlainText
        }
    }

    var body: some View {
        Text(attributionText)
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
