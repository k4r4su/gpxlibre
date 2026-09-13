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

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        onConfigure()
                    } label: {
                        Label("Paramètres", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

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
