import SwiftUI

/// Sélecteur de style de carte à vignettes (spec "map-style-visual-picker", it18-bis) — remplace
/// le `Picker` texte de Réglages > Carte > Thème par des vignettes, standard du marché pour un
/// choix de fond de carte (Apple/Google Maps affichent toujours des miniatures, jamais une
/// simple liste de texte, pour ce réglage précis). Vignettes DESSINÉES (icône + dégradé
/// représentatif), pas des cartes MapLibre live : 4 instances de carte simultanées dans une
/// liste de réglages serait un coût de rendu disproportionné pour un aperçu de quelques dizaines
/// de points — `CameraPreviewMapView` (MapKit) reste réservé aux 3 réglages qui ont vraiment
/// besoin d'un aperçu géographique réel (Position point bleu/Zoom), pas d'un simple choix de
/// palette.
struct MapThemePickerView: View {
    @Binding var selection: MapThemePreset

    var body: some View {
        HStack(spacing: 12) {
            ForEach(MapThemePreset.allCases) { preset in
                Button {
                    selection = preset
                } label: {
                    VStack(spacing: 6) {
                        preset.swatch
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(selection == preset ? Color.accentColor : Color.clear, lineWidth: 3)
                            }
                            .overlay(alignment: .topTrailing) {
                                if selection == preset {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white, Color.accentColor)
                                        .background(Circle().fill(.white))
                                        .offset(x: 4, y: -4)
                                }
                            }
                        Text(preset.label)
                            .font(.caption2)
                            .foregroundStyle(selection == preset ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.label)
                .accessibilityAddTraits(selection == preset ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private extension MapThemePreset {
    /// Représentation dessinée, jamais une vraie tuile — juste assez pour reconnaître le style
    /// au premier coup d'œil (palette + icône), cohérent avec le rendu réel de chaque thème :
    /// Standard (raster OSM clair/beige classique), Clair (fond neutre), Sombre (fond nuit,
    /// même filtre que le rendu réel), Relief (tons terrain, montagnes — OpenTopoMap).
    @ViewBuilder
    var swatch: some View {
        ZStack {
            LinearGradient(colors: swatchColors, startPoint: .top, endPoint: .bottom)
            Image(systemName: swatchIcon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(swatchIconColor)
        }
    }

    var swatchColors: [Color] {
        switch self {
        case .osmStandard: return [Color(red: 0.96, green: 0.94, blue: 0.88), Color(red: 0.80, green: 0.88, blue: 0.78)]
        case .clair: return [.white, Color(white: 0.92)]
        case .sombre: return [Color(red: 0.07, green: 0.08, blue: 0.12), Color(red: 0.16, green: 0.18, blue: 0.24)]
        case .relief: return [Color(red: 0.58, green: 0.48, blue: 0.34), Color(red: 0.36, green: 0.56, blue: 0.38)]
        }
    }

    var swatchIcon: String {
        switch self {
        case .osmStandard: return "map.fill"
        case .clair: return "sun.max.fill"
        case .sombre: return "moon.stars.fill"
        case .relief: return "mountain.2.fill"
        }
    }

    var swatchIconColor: Color {
        switch self {
        case .osmStandard, .clair: return .black.opacity(0.55)
        case .sombre, .relief: return .white
        }
    }
}
