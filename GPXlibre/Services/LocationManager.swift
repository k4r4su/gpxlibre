import Foundation
import CoreLocation

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Fix "region-picker-atlantic-ocean-default" (it21) — "dernière position connue" :
        // `manager.location` renvoie SYNCHRONEMENT le dernier fix mis en cache par CoreLocation
        // (déjà présent si l'autorisation a été accordée par une session précédente, sans
        // attendre `startUpdating()`/le premier `didUpdateLocations`), utile pour tout écran qui
        // a besoin d'une position raisonnable dès l'affichage (ex. RegionDownloadView) plutôt
        // que de rester sur `nil` jusqu'au premier fix frais.
        currentLocation = manager.location
    }

    func requestAuthorization() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            startUpdating()
        }
    }

    func startUpdating() {
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.startUpdating()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = last
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Suivi best-effort pour l'itération 1 : pas de remontée d'erreur bloquante.
    }
}
