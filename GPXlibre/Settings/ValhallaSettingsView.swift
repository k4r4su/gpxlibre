import SwiftUI

/// Spec "valhalla-client-toggle" (it19) : endpoint configurable + Basic Auth via Keychain
/// (username ET password en champs libres, aucune valeur codée en dur — décision tranchée avec
/// le propriétaire, formulaire générique plutôt qu'un username pré-rempli), `/route` + `/status`
/// prioritaires, toggle désactivé par défaut. Tout ici s'applique EN DIRECT (convention par
/// défaut de l'app) sauf mention contraire — pas de bouton "Enregistrer" : chaque champ écrit
/// immédiatement (UserDefaults pour l'endpoint/toggle via `RideSettingsStore`, Keychain pour les
/// identifiants via `ValhallaKeychainStore`).
struct ValhallaSettingsView: View {
    @EnvironmentObject private var settings: RideSettingsStore

    @State private var username = ""
    @State private var password = ""
    @State private var connectionTestResult: ConnectionTestResult?
    @State private var isTestingConnection = false

    private enum ConnectionTestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Utiliser Valhalla pour le routage", isOn: $settings.valhallaEnabled)
                    .longPressTooltip("Remplace OSRM pour le détour/la reprise hors-trace/le hors-route d'Aller à — désactiver revient instantanément au comportement OSRM habituel")
                // Spec "valhalla-live-routing" (it20) : rendre visible que le toggle est
                // désormais le VRAI interrupteur du provider actif, pas seulement du test de
                // connexion — périmètre réel (voir RoutingProviderResolver), pas une simplification.
                if settings.valhallaEnabled {
                    Text("Utilisé pour : contournement (chemin bloqué), reprise hors-trace, hors-route d'Aller à, détection fine de virages légers, guidage classique complet (Aller à > Itinéraire).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Désactivé par défaut. \"Aller à\" > Mixte continue d'utiliser OSRM dans tous les cas — Valhalla reste retenté en premier partout ailleurs (dont le guidage classique \"Aller à\" > Itinéraire, qui en a besoin pour ses manœuvres détaillées), avec repli automatique et silencieux en cas d'échec ou si désactivé.")
            }

            Section {
                TextField("URL du serveur (ex. https://valhalla.mondomaine.fr)", text: $settings.valhallaEndpointURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Nom d'utilisateur (Basic Auth)", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: username) { newValue in
                        ValhallaKeychainStore.save(username: newValue, password: password)
                    }
                SecureField("Mot de passe (Basic Auth)", text: $password)
                    .onChange(of: password) { newValue in
                        ValhallaKeychainStore.save(username: username, password: newValue)
                    }
            } header: {
                Text("Endpoint et identifiants")
            } footer: {
                Text("Laisser username/password vides si ton serveur n'exige pas d'authentification. Les identifiants sont stockés dans le Trousseau iOS, jamais dans les réglages classiques.")
            }

            Section {
                Button {
                    testConnection()
                } label: {
                    if isTestingConnection {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Test en cours…")
                        }
                    } else {
                        Text("Tester la connexion (/status)")
                    }
                }
                .disabled(isTestingConnection || settings.valhallaEndpointURLString.trimmingCharacters(in: .whitespaces).isEmpty)

                switch connectionTestResult {
                case .success(let message):
                    Label(message, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failure(let message):
                    Label(message, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                case nil:
                    EmptyView()
                }
            }
        }
        .navigationTitle("Routage Valhalla")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            username = ValhallaKeychainStore.username()
            password = ValhallaKeychainStore.password()
        }
    }

    private func testConnection() {
        let configuration = ValhallaConfiguration(
            endpointURLString: settings.valhallaEndpointURLString,
            username: username,
            password: password
        )
        isTestingConnection = true
        connectionTestResult = nil
        Task {
            do {
                let version = try await ValhallaRoutingService.checkStatus(configuration: configuration)
                await MainActor.run {
                    connectionTestResult = .success("Connecté (\(version))")
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionTestResult = .failure(error.localizedDescription)
                    isTestingConnection = false
                }
            }
        }
    }
}
