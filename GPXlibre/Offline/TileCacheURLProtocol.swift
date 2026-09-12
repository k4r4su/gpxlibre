import Foundation

/// Intercepte les requêtes de tuiles émises par MapLibre (via
/// `MLNNetworkConfiguration.sessionConfiguration`, voir MapLibreBootstrap) — OSM standard ET
/// OpenTopoMap (thème Relief) : sert depuis le cache disque si présent, sinon récupère sur le
/// réseau puis met en cache. En avion / hors zone, une tuile absente échoue simplement
/// (MapLibre affiche la case vide) — pas de crash, pas de tentative répétée bloquante.
final class TileCacheURLProtocol: URLProtocol {
    /// Session dédiée à la récupération réseau de secours — distincte de la configuration
    /// partagée MapLibre pour ne pas se ré-intercepter elle-même.
    private static let fetchSession = URLSession(configuration: .ephemeral)

    private var activeTask: URLSessionDataTask?

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return TileSource.matching(host: host) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let tile = Self.parseTile(from: url) else {
            print("[TileCache] ERREUR : URL de tuile non reconnue : \(request.url?.absoluteString ?? "nil")")
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        if let cached = TileCacheStore.shared.read(tile) {
            respond(with: cached, url: url)
            return
        }

        // User-Agent explicite plutôt que de dépendre de l'ordre d'application des headers
        // de MLNNetworkConfiguration.sessionConfiguration (l'interception URLProtocol peut
        // intervenir avant que httpAdditionalHeaders ne soit fusionné à la requête réelle).
        var outgoingRequest = request
        outgoingRequest.setValue(MapEngineConstants.userAgent, forHTTPHeaderField: "User-Agent")

        activeTask = Self.fetchSession.dataTask(with: outgoingRequest) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                print("[TileCache] ERREUR réseau tuile \(tile.path) : \(error.localizedDescription)")
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            guard let data, let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[TileCache] ERREUR tuile \(tile.path) : statut HTTP \(status)")
                self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            TileCacheStore.shared.write(data, for: tile)
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        activeTask?.resume()
    }

    override func stopLoading() {
        activeTask?.cancel()
        activeTask = nil
    }

    private func respond(with data: Data, url: URL) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png", "Content-Length": "\(data.count)"]
        ) ?? URLResponse(url: url, mimeType: "image/png", expectedContentLength: data.count, textEncodingName: nil)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// URL attendue : https://<host>/{z}/{x}/{y}.png — le host détermine la source (osm ou
    /// opentopo), donc le sous-dossier de cache dans lequel la tuile est rangée/lue.
    private static func parseTile(from url: URL) -> TileCoordinate? {
        guard let host = url.host, let source = TileSource.matching(host: host) else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 3,
              let z = Int(components[components.count - 3]),
              let x = Int(components[components.count - 2]),
              let y = Int(components[components.count - 1].replacingOccurrences(of: ".png", with: ""))
        else { return nil }
        return TileCoordinate(z: z, x: x, y: y, source: source)
    }
}
