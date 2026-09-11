import Foundation

/// Intercepte les requêtes de tuiles OSM émises par MapLibre (via
/// `MLNNetworkConfiguration.sessionConfiguration`, voir MapLibreBootstrap) : sert depuis le
/// cache disque si présent, sinon récupère sur le réseau puis met en cache. En avion / hors
/// zone, une tuile absente échoue simplement (MapLibre affiche la case vide) — pas de crash,
/// pas de tentative répétée bloquante.
final class TileCacheURLProtocol: URLProtocol {
    private static let host = "tile.openstreetmap.org"
    /// Session dédiée à la récupération réseau de secours — distincte de la configuration
    /// partagée MapLibre pour ne pas se ré-intercepter elle-même.
    private static let fetchSession = URLSession(configuration: .ephemeral)

    private var activeTask: URLSessionDataTask?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let tile = Self.parseTile(from: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        if let cached = TileCacheStore.shared.read(tile) {
            respond(with: cached, url: url)
            return
        }

        activeTask = Self.fetchSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            guard let data, let response else {
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

    /// URL attendue : https://tile.openstreetmap.org/{z}/{x}/{y}.png
    private static func parseTile(from url: URL) -> TileCoordinate? {
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 3,
              let z = Int(components[components.count - 3]),
              let x = Int(components[components.count - 2]),
              let y = Int(components[components.count - 1].replacingOccurrences(of: ".png", with: ""))
        else { return nil }
        return TileCoordinate(z: z, x: x, y: y)
    }
}
