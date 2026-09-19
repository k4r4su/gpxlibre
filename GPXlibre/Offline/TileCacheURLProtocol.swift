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
            respond(with: cached, url: url, tile: tile)
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

    private func respond(with data: Data, url: URL, tile: TileCoordinate) {
        let mimeType = tile.source.tileFileExtension == "jpg" ? "image/jpeg" : "image/png"
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": mimeType, "Content-Length": "\(data.count)"]
        ) ?? URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: nil)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// Fix "satellite-black-map" (it22bis) : l'ancienne version supposait un ORDRE FIXE
    /// `.../{z}/{x}/{y}.png` (position + extension codées en dur) — valable pour OSM/OpenTopoMap,
    /// mais silencieusement FAUX pour la source satellite (EOX : ordre z/y/x, extension .jpg),
    /// qui échouait donc sur CHAQUE tuile (`Int("16.jpg")` retourne `nil`), d'où l'écran
    /// totalement noir signalé en retour terrain. Nouvelle approche : dérive un motif regex
    /// directement du gabarit d'URL DE LA SOURCE (jamais une position/extension supposée),
    /// donc valable quel que soit l'ordre des jetons ou le format d'image.
    ///
    /// `internal` (pas `private`) UNIQUEMENT pour la testabilité — même patron que
    /// `navRoutingTask`/`mapMatchingProvider` ailleurs dans le projet.
    static func parseTile(from url: URL) -> TileCoordinate? {
        guard let host = url.host, let source = TileSource.matching(host: host) else { return nil }
        guard let template = source.tileURLTemplates.first(where: { $0.contains(host) }) ?? source.tileURLTemplates.first,
              let templatePath = URLComponents(string: template)?.path,
              let (z, x, y) = extractZXY(fromPath: url.path, matchingTemplatePath: templatePath)
        else { return nil }
        return TileCoordinate(z: z, x: x, y: y, source: source)
    }

    /// Construit un regex à partir du CHEMIN du gabarit (jamais l'URL complète, pour rester
    /// indifférent au sous-domaine a/b/c d'OpenTopoMap) en remplaçant `{z}`/`{x}`/`{y}` par des
    /// groupes nommés, quel que soit leur ordre ou l'extension qui suit.
    private static func extractZXY(fromPath path: String, matchingTemplatePath templatePath: String) -> (z: Int, x: Int, y: Int)? {
        var placeholderPattern = templatePath
            .replacingOccurrences(of: "{z}", with: "@Z@")
            .replacingOccurrences(of: "{x}", with: "@X@")
            .replacingOccurrences(of: "{y}", with: "@Y@")
        placeholderPattern = NSRegularExpression.escapedPattern(for: placeholderPattern)
        placeholderPattern = placeholderPattern
            .replacingOccurrences(of: "@Z@", with: "(?<z>\\d+)")
            .replacingOccurrences(of: "@X@", with: "(?<x>\\d+)")
            .replacingOccurrences(of: "@Y@", with: "(?<y>\\d+)")
        guard let regex = try? NSRegularExpression(pattern: "^" + placeholderPattern + "$") else { return nil }
        let fullRange = NSRange(path.startIndex..., in: path)
        guard let match = regex.firstMatch(in: path, range: fullRange) else { return nil }
        func value(named name: String) -> Int? {
            let range = match.range(withName: name)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: path) else { return nil }
            return Int(path[swiftRange])
        }
        guard let z = value(named: "z"), let x = value(named: "x"), let y = value(named: "y") else { return nil }
        return (z, x, y)
    }
}
