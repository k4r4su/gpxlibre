import SwiftUI
import UniformTypeIdentifiers

/// Écran "Paquets vectoriels" (spec "vector-pmtiles", it11, étape 2 self-host) — même famille
/// visuelle que `RegionDownloadView` (Cartes hors-ligne raster) : liste des `.pmtiles`
/// disponibles, import depuis Fichiers, téléchargement depuis une URL configurable (le NAS du
/// propriétaire), un seul paquet actif à la fois (voir `VectorPackageStore`).
struct VectorPackagesView: View {
    @EnvironmentObject private var vectorPackages: VectorPackageStore
    @State private var isImporting = false
    @State private var downloadURLString = ""
    @State private var isDownloading = false
    @State private var downloadErrorMessage: String?

    private static let pmtilesType = UTType(filenameExtension: "pmtiles") ?? .data

    var body: some View {
        List {
            Section {
                TextField("URL du paquet (ex : NAS)", text: $downloadURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                if isDownloading {
                    ProgressView("Téléchargement…")
                } else {
                    Button("Télécharger depuis cette URL") { startDownload() }
                        .disabled(URL(string: downloadURLString) == nil)
                }

                if let downloadErrorMessage {
                    Text(downloadErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    isImporting = true
                } label: {
                    Label("Importer un fichier .pmtiles", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Ajouter un paquet")
            } footer: {
                Text("Génération régionale (Alsace + Franche-Comté en test) : voir docs/generation-tuiles-regionales.md dans le dépôt.")
            }

            Section {
                if vectorPackages.packages.isEmpty {
                    Text("Aucun paquet vectoriel pour l'instant — la carte utilise la source hébergée (en ligne) ou le raster (hors-ligne).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(vectorPackages.packages) { package in
                    packageRow(package)
                }
            } header: {
                Text("Paquets disponibles")
            } footer: {
                Text("Un seul paquet actif à la fois. Actif = utilisé partout, y compris en mode avion.")
            }
        }
        .navigationTitle("Paquets vectoriels")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [Self.pmtilesType], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                urls.forEach { url in try? vectorPackages.importPackage(from: url) }
            case .failure(let error):
                downloadErrorMessage = error.localizedDescription
            }
        }
    }

    private func packageRow(_ package: VectorPackage) -> some View {
        let isActive = vectorPackages.activePackageID == package.id
        return HStack(spacing: 12) {
            Button {
                vectorPackages.setActive(isActive ? nil : package.id)
            } label: {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isActive ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(package.name).font(.headline)
                HStack(spacing: 12) {
                    Text(ByteCountFormatter.string(fromByteCount: package.sizeBytes, countStyle: .file))
                    Text(package.importedAt, style: .date)
                    if package.sourceURLString != nil {
                        Label("NAS", systemImage: "network")
                    } else {
                        Label("Importé", systemImage: "tray.and.arrow.down")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                vectorPackages.delete(package)
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private func startDownload() {
        guard let url = URL(string: downloadURLString) else { return }
        downloadErrorMessage = nil
        isDownloading = true
        vectorPackages.downloadPackage(from: url) { result in
            isDownloading = false
            switch result {
            case .success:
                downloadURLString = ""
            case .failure(let error):
                downloadErrorMessage = error.localizedDescription
            }
        }
    }
}
