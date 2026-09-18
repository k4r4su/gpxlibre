import SwiftUI

/// Fiche complète (spec "biblio-track-fullsheet", it13) — terrain : "Tap sur une ligne trace
/// = fiche complète". Contenu volontairement minimal (nom + longueur + infos dispo, rien de
/// plus) : 3 actions, pas une page de détail/carte — ça reste le rôle de TrackSettingsView
/// (sens/apparence/chevrons), ouvert ici via "Paramètres". Les swipes Biblio (Supprimer/
/// Renommer à droite, Paramétrer à gauche) restent des raccourcis inchangés — cette fiche est
/// un second point d'entrée vers les MÊMES actions, pas un remplacement.
struct TrackFullSheetView: View {
    let track: GPXTrack
    let isFullyOffline: Bool
    let isActive: Bool
    /// Spec "biblio-share-export"/"biblio-share-export-filename" (it19) : copie temporaire
    /// nommée d'après le titre de la trace (voir `LibraryStore.exportURL(for:)`), contenu
    /// identique octet pour octet au fichier stocké — passée par l'appelant plutôt que
    /// recalculée ici, cette vue n'ayant pas accès à `LibraryStore` autrement.
    let shareURL: URL
    let onDelete: () -> Void
    let onRename: () -> Void
    let onConfigure: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text(track.name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    if isActive {
                        Label("Trace active pour le Ride", systemImage: "checkmark.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                }
                .padding(.top, 8)

                HStack(spacing: 12) {
                    StatItem(title: "Distance", value: String(format: "%.1f km", track.totalDistanceKm))
                    Divider().frame(height: 32)
                    StatItem(title: "Points", value: "\(track.pointCount)")
                    Divider().frame(height: 32)
                    StatItem(title: "Dénivelé +", value: String(format: "%.0f m", track.elevationGainMeters))
                    if isFullyOffline {
                        Divider().frame(height: 32)
                        StatItem(title: "Hors-ligne", value: "100%")
                    }
                }

                // Spec "track-geek-metrics" (it21, retour terrain : "ça peut rester dans l'app
                // en mode petit côté geek pour ceux qui veulent savoir comment s'est passé le
                // trajet") — replié par défaut (même patron que l'encart "tiles-zoom-explainer",
                // it17) : la fiche reste volontairement minimale par défaut (voir doc du type
                // ci-dessus), ces stats sont un approfondissement OPT-IN, pas un ajout au bloc
                // principal déjà affiché plus haut.
                if let metrics = TrackMetricsCalculator.compute(for: track.points) {
                    DisclosureGroup("Statistiques avancées") {
                        geekMetricsGrid(metrics)
                            .padding(.top, 8)
                    }
                    .font(.subheadline)
                } else {
                    Text("Statistiques avancées indisponibles — cette trace n'a pas d'horodatage exploitable (import externe sans temps réel).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        onConfigure()
                    } label: {
                        Label("Paramètres", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    // Spec "biblio-share-export" (it19) : "une trace à la fois, share sheet iOS
                    // standard + export GPX fidèle au format vers Fichiers iOS" — ShareLink sur
                    // le fichier stocké tel quel couvre les deux (le share sheet standard
                    // propose déjà "Enregistrer dans Fichiers" pour toute URL de fichier, même
                    // patron que EndRideView.ShareLink après une sortie enregistrée).
                    ShareLink(item: shareURL) {
                        Label("Partager / Exporter", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onRename()
                    } label: {
                        Label("Renommer", systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .controlSize(.large)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .navigationTitle("Trace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .confirmationDialog(
                "Supprimer « \(track.name) » ?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) { onDelete() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Cette action est irréversible.")
            }
        }
    }

    private func geekMetricsGrid(_ metrics: TrackMetrics) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 16) {
            StatItem(title: "Durée totale", value: Self.durationText(metrics.durationSeconds))
            StatItem(title: "Dont en mouvement", value: Self.durationText(metrics.movingDurationSeconds))
            StatItem(title: "Vitesse moyenne", value: Self.speedText(metrics.averageSpeedKmh))
            StatItem(title: "Moyenne en mouvement", value: Self.speedText(metrics.averageMovingSpeedKmh))
            StatItem(title: "Vitesse max", value: Self.speedText(metrics.maxSpeedKmh))
            StatItem(title: "Pente max", value: String(format: "%.0f %%", metrics.maxGradePercent))
            StatItem(title: "Dénivelé −", value: String(format: "%.0f m", metrics.elevationLossMeters))
            StatItem(title: "Altitude min/max", value: "\(Int(metrics.minElevationMeters.rounded()))–\(Int(metrics.maxElevationMeters.rounded())) m")
        }
    }

    private static func durationText(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 60 else { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    private static func speedText(_ kmh: Double) -> String {
        String(format: "%.0f km/h", kmh)
    }
}

private struct StatItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
