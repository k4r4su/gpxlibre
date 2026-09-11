import Foundation

/// État de chargement du fond de carte, remonté par l'implémentation MapProvider active —
/// permet d'afficher un bandeau visible plutôt qu'un écran noir muet en cas d'échec.
enum MapLoadStatus: Equatable {
    case loading
    case loaded
    case failed(String)
}
