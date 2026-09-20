import UIKit

/// Génère un export PDF façon roadbook papier de rallye (spec "roadbook-mode", it23, point 2)
/// — bande verticale en colonnes : distance partielle, distance cumulée (optionnelle),
/// pictogramme de direction OU cap en degrés, colonne note (optionnelle, vierge — l'utilisateur
/// l'annote à la main, esprit rallye papier). Génération CÔTÉ APP (`UIGraphicsPDFRenderer`,
/// natif iOS), aucun service externe.
///
/// Lit la MÊME liste `[RoadbookManeuver]` que l'écran Road Book (`RoadbookExtractor`) — une
/// seule source de vérité partagée entre affichage à l'écran et export, jamais de divergence
/// possible entre les deux (spec, point 2).
enum RoadbookPDFExporter {
    private static let accentColor = UIColor(
        red: RoadBookConstants.pdfAccentColorRGB.red,
        green: RoadBookConstants.pdfAccentColorRGB.green,
        blue: RoadBookConstants.pdfAccentColorRGB.blue,
        alpha: 1
    )

    struct ColumnLayout {
        let partial: CGRect
        let cumulative: CGRect?
        let heading: CGRect
        let note: CGRect?
    }

    /// Répartit la largeur de contenu disponible entre les colonnes ACTIVÉES — une colonne
    /// masquée (cumulée/note) rend sa place aux autres plutôt que de laisser un blanc, jamais
    /// une largeur négative ou une colonne qui déborde (vérifié par
    /// `RoadbookPDFExporterTests.testColumnWidthsAlwaysSumToContentWidthAndNeverGoNegative`).
    ///
    /// Fix "column-layout-blank-space" (it23, bug attrapé par le test ci-dessus AVANT tout
    /// usage réel) : la première version faisait toujours absorber le reste par "note" — si
    /// "note" était masquée, sa fraction tombait à 0 et l'espace récupéré n'était redistribué
    /// NULLE PART, laissant un blanc à droite de la page. Corrigé : c'est désormais TOUJOURS la
    /// DERNIÈRE colonne active (quelle qu'elle soit) qui absorbe la largeur restante.
    static func columnLayout(options: RoadbookPDFOptions, contentRect: CGRect) -> ColumnLayout {
        var activeKeys = ["partial"]
        if options.showCumulativeDistance { activeKeys.append("cumulative") }
        activeKeys.append("heading")
        if options.showNoteColumn { activeKeys.append("note") }

        let fixedFraction: [String: CGFloat] = [
            "partial": RoadBookConstants.pdfPartialColumnFraction,
            "cumulative": RoadBookConstants.pdfCumulativeColumnFraction,
            "heading": RoadBookConstants.pdfHeadingColumnFraction,
        ]
        let lastKey = activeKeys[activeKeys.count - 1]
        let fixedFractionsSum = activeKeys.dropLast().reduce(0) { $0 + (fixedFraction[$1] ?? 0) }
        let lastFraction = max(1 - fixedFractionsSum, 0.1)

        var x = contentRect.minX
        var rects: [String: CGRect] = [:]
        for key in activeKeys {
            let fraction = key == lastKey ? lastFraction : (fixedFraction[key] ?? 0)
            let width = contentRect.width * fraction
            rects[key] = CGRect(x: x, y: contentRect.minY, width: width, height: contentRect.height)
            x += width
        }

        return ColumnLayout(partial: rects["partial"] ?? .zero, cumulative: rects["cumulative"], heading: rects["heading"] ?? .zero, note: rects["note"])
    }

    static func generate(trackName: String, maneuvers: [RoadbookManeuver], options: RoadbookPDFOptions) -> Data {
        let pageSize = options.orientation == .portrait
            ? CGSize(width: RoadBookConstants.pdfPageWidthPoints, height: RoadBookConstants.pdfPageHeightPoints)
            : CGSize(width: RoadBookConstants.pdfPageHeightPoints, height: RoadBookConstants.pdfPageWidthPoints)
        let pageRect = CGRect(origin: .zero, size: pageSize)
        let margin = RoadBookConstants.pdfMarginPoints
        let headerHeight = RoadBookConstants.pdfHeaderHeightPoints
        let rowHeight = options.density.rowHeightPoints
        let contentRect = CGRect(
            x: margin,
            y: margin + headerHeight,
            width: pageRect.width - margin * 2,
            height: pageRect.height - margin * 2 - headerHeight
        )
        let rowsPerPage = max(Int(contentRect.height / rowHeight), 1)

        // Trace vide/sans manœuvre détectée : une seule page, message explicite plutôt qu'une
        // page blanche muette — jamais un crash (spec, tests attendus).
        let pages: [[RoadbookManeuver]] = maneuvers.isEmpty
            ? [[]]
            : stride(from: 0, to: maneuvers.count, by: rowsPerPage).map {
                Array(maneuvers[$0..<min($0 + rowsPerPage, maneuvers.count)])
            }

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            for (pageIndex, pageManeuvers) in pages.enumerated() {
                context.beginPage()
                drawHeader(
                    trackName: trackName,
                    pageIndex: pageIndex,
                    totalPages: pages.count,
                    pageRect: pageRect,
                    margin: margin
                )
                if maneuvers.isEmpty {
                    drawEmptyMessage(contentRect: contentRect, fontSize: options.fontSize.points)
                    continue
                }
                let layout = columnLayout(options: options, contentRect: CGRect(x: contentRect.minX, y: contentRect.minY, width: contentRect.width, height: rowHeight))
                drawColumnTitles(layout: layout, options: options, fontSize: options.fontSize.points)
                for (rowIndex, maneuver) in pageManeuvers.enumerated() {
                    let rowY = contentRect.minY + rowHeight * CGFloat(rowIndex + 1) // +1 : ligne 0 = titres de colonnes
                    let rowRect = CGRect(x: contentRect.minX, y: rowY, width: contentRect.width, height: rowHeight)
                    let rowLayout = columnLayout(options: options, contentRect: rowRect)
                    drawRow(maneuver, layout: rowLayout, options: options)
                }
            }
        }
    }

    private static func drawHeader(trackName: String, pageIndex: Int, totalPages: Int, pageRect: CGRect, margin: CGFloat) {
        let title = trackName.isEmpty ? "Road Book" : trackName
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 16),
            .foregroundColor: UIColor.black,
        ]
        (title as NSString).draw(at: CGPoint(x: margin, y: margin), withAttributes: titleAttributes)

        let pageLabel = "Page \(pageIndex + 1)/\(totalPages)"
        let pageAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.darkGray,
        ]
        let pageSize = (pageLabel as NSString).size(withAttributes: pageAttributes)
        (pageLabel as NSString).draw(
            at: CGPoint(x: pageRect.width - margin - pageSize.width, y: margin + 2),
            withAttributes: pageAttributes
        )

        let ruleY = margin + 28
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: ruleY))
        path.addLine(to: CGPoint(x: pageRect.width - margin, y: ruleY))
        UIColor.lightGray.setStroke()
        path.lineWidth = 0.75
        path.stroke()
    }

    private static func drawEmptyMessage(contentRect: CGRect, fontSize: CGFloat) {
        let text = "Aucune manœuvre détectée sur cette trace (pas de changement de direction au-dessus du seuil configuré)."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: fontSize + 1),
            .foregroundColor: UIColor.darkGray,
        ]
        let rect = CGRect(x: contentRect.minX, y: contentRect.minY + 20, width: contentRect.width, height: 60)
        (text as NSString).draw(with: rect, options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
    }

    private static func drawColumnTitles(layout: ColumnLayout, options: RoadbookPDFOptions, fontSize: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: fontSize - 1),
            .foregroundColor: UIColor.darkGray,
        ]
        draw("Partiel", in: layout.partial, attributes: attributes, alignment: .center)
        if let cumulative = layout.cumulative { draw("Cumulé", in: cumulative, attributes: attributes, alignment: .center) }
        draw(options.headingStyle == .pictogram ? "Cap" : "Degrés", in: layout.heading, attributes: attributes, alignment: .center)
        if let note = layout.note { draw("Note", in: note, attributes: attributes, alignment: .center) }

        let ruleY = layout.partial.maxY - 2
        let path = UIBezierPath()
        path.move(to: CGPoint(x: layout.partial.minX, y: ruleY))
        path.addLine(to: CGPoint(x: (layout.note ?? layout.heading).maxX, y: ruleY))
        UIColor.darkGray.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private static func drawRow(_ maneuver: RoadbookManeuver, layout: ColumnLayout, options: RoadbookPDFOptions) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: options.fontSize.points),
            .foregroundColor: UIColor.black,
        ]

        draw(options.distanceUnit.displayString(fromMeters: maneuver.partialDistanceMeters), in: layout.partial, attributes: attributes, alignment: .center)
        if let cumulative = layout.cumulative {
            draw(options.distanceUnit.displayString(fromMeters: maneuver.cumulativeDistanceMeters), in: cumulative, attributes: attributes, alignment: .center)
        }

        switch options.headingStyle {
        case .degrees:
            let sign = maneuver.checkpoint.direction == .left ? "-" : ""
            let degreesText = maneuver.checkpoint.direction == .uTurn
                ? "180°"
                : "\(sign)\(Int(maneuver.checkpoint.turnAngleDegrees.rounded()))°"
            draw(degreesText, in: layout.heading, attributes: attributes, alignment: .center)
        case .pictogram:
            drawPictogram(for: maneuver.checkpoint, in: layout.heading)
        }

        if let note = layout.note {
            // Colonne vierge lignée façon roadbook papier — l'utilisateur l'annote à la main
            // (danger, revêtement, point de vue). Aucune donnée de note n'existe dans l'app.
            let path = UIBezierPath()
            path.move(to: CGPoint(x: note.minX + 4, y: note.maxY - 4))
            path.addLine(to: CGPoint(x: note.maxX - 4, y: note.maxY - 4))
            UIColor.lightGray.setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }

        let separatorPath = UIBezierPath()
        separatorPath.move(to: CGPoint(x: layout.partial.minX, y: layout.partial.maxY))
        separatorPath.addLine(to: CGPoint(x: (layout.note ?? layout.heading).maxX, y: layout.partial.maxY))
        UIColor(white: 0.85, alpha: 1).setStroke()
        separatorPath.lineWidth = 0.5
        separatorPath.stroke()
    }

    /// Flèche vectorielle simple (jamais une image/SF Symbol rasterisée) : pointe "tout droit"
    /// au repos, tournée selon le signe/l'amplitude du virage — plus l'angle affiché est grand,
    /// plus la flèche s'incline, un demi-tour affiche une flèche retournée. Teinte d'accent
    /// orange/rouge (voir `RoadBookConstants.pdfAccentColorRGB`, clin d'œil à l'identité
    /// visuelle du logo) : une couleur PLEINE, pas un dégradé (resterait lisible imprimé en
    /// niveaux de gris, demande explicite de la fiche).
    private static func drawPictogram(for checkpoint: Checkpoint, in rect: CGRect) {
        let size: CGFloat = min(rect.width, rect.height) * 0.6
        let center = CGPoint(x: rect.midX, y: rect.midY)

        let rotationDegrees: CGFloat
        switch checkpoint.direction {
        case .uTurn: rotationDegrees = 180
        case .right: rotationDegrees = CGFloat(min(checkpoint.turnAngleDegrees, 170))
        case .left: rotationDegrees = -CGFloat(min(checkpoint.turnAngleDegrees, 170))
        case .straight: rotationDegrees = 0
        }

        let arrow = UIBezierPath()
        let half = size / 2
        arrow.move(to: CGPoint(x: 0, y: -half))
        arrow.addLine(to: CGPoint(x: 0, y: half * 0.4))
        arrow.move(to: CGPoint(x: -half * 0.4, y: -half * 0.2))
        arrow.addLine(to: CGPoint(x: 0, y: -half))
        arrow.addLine(to: CGPoint(x: half * 0.4, y: -half * 0.2))

        var transform = CGAffineTransform(translationX: center.x, y: center.y)
        transform = transform.rotated(by: rotationDegrees * .pi / 180)
        arrow.apply(transform)

        accentColor.setStroke()
        arrow.lineWidth = 2.4
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.stroke()
    }

    private static func draw(_ text: String, in rect: CGRect, attributes: [NSAttributedString.Key: Any], alignment: NSTextAlignment) {
        var attrs = attributes
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        attrs[.paragraphStyle] = paragraph
        let size = (text as NSString).size(withAttributes: attrs)
        let y = rect.midY - size.height / 2
        (text as NSString).draw(in: CGRect(x: rect.minX, y: y, width: rect.width, height: size.height), withAttributes: attrs)
    }
}
