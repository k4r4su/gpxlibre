import Foundation

/// Clé de tri de la liste Biblio (spec "biblio-date-display", it15, Bloc 1).
enum BiblioSortKey {
    /// Plus récente (`GPXTrack.displayDate`) en tête, repli alphabétique si égalité/dates
    /// manquantes — comportement par défaut demandé par le prompt d'itération.
    case dateDescending
    /// Alphabétique pur, ignore les dates — gardé en repli/toggle de secours.
    case alphabetical
}

/// Constantes Biblio (spec "biblio-date-display", it15, Bloc 1) — BIBLIO_DATE_DISPLAY /
/// BIBLIO_SORT_KEY exposées ici en toggles de code, pas de réglage UI demandé pour celles-ci.
enum LibraryConstants {
    /// BIBLIO_DATE_DISPLAY : coupe-circuit pour masquer entièrement le sous-titre date sous
    /// le nom de la trace (`TrackRow`) sans toucher au parsing/stockage sous-jacent.
    static let dateDisplayEnabled = true
    /// BIBLIO_SORT_KEY : voir `LibraryStore.sortTracks()`.
    static let sortKey: BiblioSortKey = .dateDescending
}
