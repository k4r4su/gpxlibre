import SwiftUI

struct TrackDetailView: View {
    let track: GPXTrack
    @StateObject private var locationManager = LocationManager()
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var navigationState: AppNavigationState
    @State private var showPrecacheSheet = false

    var body: some View {
        VStack(spacing: 0) {
            TrackMapView(track: track, currentLocation: locationManager.currentLocation)
                .ignoresSafeArea(edges: .horizontal)
            statsBar
        }
        .navigationTitle(track.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showPrecacheSheet = true
                } label: {
                    Label("Utiliser pour le Ride", systemImage: "location.north.line.fill")
                }
            }
        }
        .sheet(isPresented: $showPrecacheSheet) {
            PrecacheConfirmationView(track: track) {
                showPrecacheSheet = false
                library.selectedTrackID = track.id
                navigationState.selectedTab = .ride
            }
        }
        .onAppear {
            locationManager.requestAuthorization()
            locationManager.startUpdating()
        }
        .onDisappear {
            locationManager.stopUpdating()
        }
    }

    private var statsBar: some View {
        HStack {
            StatItem(title: "Distance", value: String(format: "%.1f km", track.totalDistanceKm))
            Divider().frame(height: 32)
            StatItem(title: "Points", value: "\(track.pointCount)")
            Divider().frame(height: 32)
            StatItem(title: "Dénivelé +", value: String(format: "%.0f m", track.elevationGainMeters))
            Divider().frame(height: 32)
            StatItem(title: "GPS", value: locationManager.currentLocation == nil ? "—" : "Actif")
        }
        .padding()
        .background(.bar)
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
