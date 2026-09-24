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

    /// - Parameter landmarkCheckpoints : repères visibles en ligne dédiée (itération "repères =
    ///   uniquement ce que le conducteur voit"), intercalés dans l'ordre de progression — une ligne
    ///   dédiée par repère (pictogramme de la catégorie, nom, côté, distance cumulée).
    static func generate(
        trackName: String,
        maneuvers: [RoadbookManeuver],
        landmarkCheckpoints: [RoadbookLandmarkCheckpoint] = [],
        options: RoadbookPDFOptions,
        landmarks: [UUID: RoadbookLandmarkInfo?] = [:]
    ) -> Data {
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
        let entries = RoadbookEntry.merge(maneuvers: maneuvers, landmarks: landmarkCheckpoints)
        let pages: [[RoadbookEntry]] = maneuvers.isEmpty
            ? [[]]
            : stride(from: 0, to: entries.count, by: rowsPerPage).map {
                Array(entries[$0..<min($0 + rowsPerPage, entries.count)])
            }

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            for (pageIndex, pageEntries) in pages.enumerated() {
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
                for (rowIndex, entry) in pageEntries.enumerated() {
                    let rowY = contentRect.minY + rowHeight * CGFloat(rowIndex + 1) // +1 : ligne 0 = titres de colonnes
                    let rowRect = CGRect(x: contentRect.minX, y: rowY, width: contentRect.width, height: rowHeight)
                    let rowLayout = columnLayout(options: options, contentRect: rowRect)
                    switch entry {
                    case .maneuver(let maneuver, _):
                        drawRow(maneuver, layout: rowLayout, options: options, landmark: landmarks[maneuver.id] ?? nil)
                    case .landmark(let landmark):
                        drawLandmarkRow(landmark, layout: rowLayout, options: options)
                    }
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

    private static func drawRow(_ maneuver: RoadbookManeuver, layout: ColumnLayout, options: RoadbookPDFOptions, landmark: RoadbookLandmarkInfo? = nil) {
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
            // Cap ABSOLU du segment sortant (spec it23quater, cohérent avec l'écran) — plus la
            // rotation RELATIVE du virage (`turnAngleDegrees`), qui répondait à une question
            // différente ("de combien tourne-t-on ?" plutôt que "quel cap suivre ensuite ?").
            draw("\(Int(maneuver.headingDegrees.rounded()))°", in: layout.heading, attributes: attributes, alignment: .center)
        case .pictogram:
            drawPictogram(for: maneuver.checkpoint, in: layout.heading)
        }
        // Emoji du repère À CÔTÉ du pictogramme de cap (retour terrain it23sexies), quel que
        // soit le style de cap choisi — un emoji Unicode se dessine comme un caractère normal
        // via NSString.draw, aucun rendu spécial requis.
        if let landmark {
            let emojiAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: options.fontSize.points + 4)]
            draw(landmark.category.emoji, in: CGRect(x: layout.heading.minX, y: layout.heading.maxY - layout.heading.height * 0.32, width: layout.heading.width, height: layout.heading.height * 0.32), attributes: emojiAttributes, alignment: .center)
        }

        if let note = layout.note {
            if let landmark {
                // Repère OSM trouvé à proximité (spec it23quater) — remplace la ligne vierge,
                // l'utilisateur garde quand même de la place en dessous pour sa propre note.
                let landmarkAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.italicSystemFont(ofSize: max(options.fontSize.points - 1, 6)),
                    .foregroundColor: UIColor.darkGray,
                ]
                (landmark.displayLabel as NSString).draw(
                    in: CGRect(x: note.minX + 4, y: note.minY + 2, width: note.width - 8, height: note.height * 0.4),
                    withAttributes: landmarkAttributes
                )
            }
            // Ligne vierge façon roadbook papier — l'utilisateur l'annote à la main (danger,
            // revêtement, point de vue) ; reste présente même quand un repère est affiché
            // au-dessus, pour laisser de la place à une note manuscrite complémentaire.
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

    /// Ligne "repère visible" : distance cumulée (colonne cumulée si affichée, sinon colonne
    /// partielle — c'est l'info qu'on vérifie sur son compteur). Entrée d'agglomération : panneau
    /// (fond blanc, bordure rouge) portant son nom, comme le vrai panneau, sur les colonnes cap et
    /// note. Autres repères : emoji de la catégorie dans la colonne cap, "nom · catégorie · côté"
    /// dans la colonne note (ou sous l'emoji si la note est masquée).
    private static func drawLandmarkRow(_ landmark: RoadbookLandmarkCheckpoint, layout: ColumnLayout, options: RoadbookPDFOptions) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: options.fontSize.points),
            .foregroundColor: UIColor.black,
        ]
        let distance = options.distanceUnit.displayString(fromMeters: landmark.cumulativeDistanceMeters)
        draw(distance, in: layout.cumulative ?? layout.partial, attributes: attributes, alignment: .center)

        if landmark.info.category == .citySign {
            let signArea = layout.note.map { layout.heading.union($0) } ?? layout.heading
            let sign = signArea.insetBy(dx: 4, dy: signArea.height * 0.14)
            let path = UIBezierPath(roundedRect: sign, cornerRadius: min(sign.height * 0.18, 4))
            UIColor.white.setFill()
            path.fill()
            UIColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1).setStroke()
            path.lineWidth = 1.6
            path.stroke()
            var nameAttributes = attributes
            nameAttributes[.font] = UIFont.boldSystemFont(ofSize: min(options.fontSize.points, sign.height * 0.55))
            draw(landmark.info.displayLabel, in: sign.insetBy(dx: 6, dy: 0), attributes: nameAttributes, alignment: .center)
        } else {
            let emojiAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: options.fontSize.points + 4)]
            let text = [landmark.info.label, RoadbookLandmarkRowText.detail(landmark.info)].joined(separator: " · ")
            if let note = layout.note {
                draw(landmark.info.category.emoji, in: layout.heading, attributes: emojiAttributes, alignment: .center)
                draw(text, in: note.insetBy(dx: 4, dy: 0), attributes: attributes, alignment: .left)
            } else {
                draw(landmark.info.category.emoji + " " + text, in: layout.heading, attributes: attributes, alignment: .center)
            }
        }

        let separatorPath = UIBezierPath()
        separatorPath.move(to: CGPoint(x: layout.partial.minX, y: layout.partial.maxY))
        separatorPath.addLine(to: CGPoint(x: (layout.note ?? layout.heading).maxX, y: layout.partial.maxY))
        UIColor(white: 0.85, alpha: 1).setStroke()
        separatorPath.lineWidth = 0.5
        separatorPath.stroke()
    }

    /// Flèche vectorielle simple (jamais une image/SF Symbol rasterisée) : pointe "tout droit"
    /// au repos, tournée d'un angle représentatif STANDARDISÉ par palier — PAS proportionnelle
    /// à l'angle géométrique brut mesuré sur la trace. Fix "turn-icon-backward-looking"
    /// (it23bis) : une rotation proportionnelle continue (jusqu'à 170° pour un virage "fort")
    /// finissait par pointer quasiment vers le BAS, illisible comme "tourne fort" plutôt que
    /// "fait demi-tour" — même bug, même cause profonde que `RoadbookTier.rotationDegrees`
    /// (voir son commentaire), réutilisé ici tel quel pour que l'écran ET le PDF affichent
    /// exactement la même convention visuelle. Teinte d'accent orange/rouge (voir
    /// `RoadBookConstants.pdfAccentColorRGB`, clin d'œil à l'identité visuelle du logo) : une
    /// couleur PLEINE, pas un dégradé (resterait lisible imprimé en niveaux de gris, demande
    /// explicite de la fiche).
    private static func drawPictogram(for checkpoint: Checkpoint, in rect: CGRect) {
        switch checkpoint.tier {
        case .roundabout:
            drawRoundaboutPictogram(exitCount: checkpoint.roundaboutExitCount, in: rect)
        case .fork:
            drawForkPictogram(direction: checkpoint.direction, in: rect)
        case .merge:
            drawMergePictogram(direction: checkpoint.direction, in: rect)
        case .light, .marked, .hard, .veryHard, .uTurn, .lightDirectionChange:
            drawArrowPictogram(for: checkpoint, in: rect)
        }
    }

    private static func drawArrowPictogram(for checkpoint: Checkpoint, in rect: CGRect) {
        let size: CGFloat = min(rect.width, rect.height) * 0.6
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rotationDegrees = CGFloat(checkpoint.tier.rotationDegrees(direction: checkpoint.direction) ?? 0)

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

    /// Équivalent Core Graphics de `RoadbookRoundaboutPictogram` (écran) — même géométrie
    /// (`RoadbookPictogramGeometry`), même convention 0°=12h/sens horaire, pour que le PDF et
    /// l'écran affichent EXACTEMENT le même pictogramme pour un rond-point donné.
    private static func drawRoundaboutPictogram(exitCount: Int?, in rect: CGRect) {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let ringRadius = side * 0.30
        let lineWidth: CGFloat = 1.6

        let ring = UIBezierPath(arcCenter: center, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        UIColor.darkGray.setStroke()
        ring.lineWidth = lineWidth
        ring.stroke()

        strokeSpoke(center: center, ringRadius: ringRadius, side: side, angleDegrees: 180, color: .darkGray, lineWidth: lineWidth * 0.8, extraLength: 0, withArrowhead: false)

        for rank in RoadbookPictogramGeometry.skippedExitRanks(exitCount: exitCount) {
            let angle = 180 - RoadbookPictogramGeometry.roundaboutExitAngleDegrees(exitCount: rank)
            strokeSpoke(center: center, ringRadius: ringRadius, side: side, angleDegrees: angle, color: UIColor.darkGray.withAlphaComponent(0.4), lineWidth: lineWidth * 0.6, extraLength: -side * 0.05, withArrowhead: false)
        }

        let takenAngle = 180 - RoadbookPictogramGeometry.roundaboutExitAngleDegrees(exitCount: exitCount)
        strokeSpoke(center: center, ringRadius: ringRadius, side: side, angleDegrees: takenAngle, color: accentColor, lineWidth: lineWidth * 1.3, extraLength: side * 0.08, withArrowhead: true)
    }

    private static func strokeSpoke(
        center: CGPoint,
        ringRadius: CGFloat,
        side: CGFloat,
        angleDegrees: Double,
        color: UIColor,
        lineWidth: CGFloat,
        extraLength: CGFloat,
        withArrowhead: Bool
    ) {
        let radians = angleDegrees * .pi / 180
        let dx = sin(radians)
        let dy = -cos(radians)
        let outerRadius = side * 0.48 + extraLength
        let start = CGPoint(x: center.x + dx * ringRadius, y: center.y + dy * ringRadius)
        let end = CGPoint(x: center.x + dx * outerRadius, y: center.y + dy * outerRadius)

        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: end)
        color.setStroke()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.stroke()

        guard withArrowhead else { return }
        let headLength = lineWidth * 1.8
        let headAngle = Double.pi / 7
        let head = UIBezierPath()
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - headLength * sin(radians + headAngle), y: end.y + headLength * cos(radians + headAngle)))
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - headLength * sin(radians - headAngle), y: end.y + headLength * cos(radians - headAngle)))
        color.setStroke()
        head.lineWidth = lineWidth
        head.lineCapStyle = .round
        head.stroke()
    }

    /// Équivalent Core Graphics de `RoadbookForkPictogram` (écran) — tige commune, branche
    /// suivie en accent, branche ignorée en gris discret.
    private static func drawForkPictogram(direction: TurnDirection, in rect: CGRect) {
        let branchAngleDegrees: CGFloat = direction == .left ? -28 : (direction == .right ? 28 : 0)
        let bottom = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.92)
        let junction = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.5)

        let stem = UIBezierPath()
        stem.move(to: bottom)
        stem.addLine(to: junction)
        UIColor.darkGray.setStroke()
        stem.lineWidth = 1.6
        stem.lineCapStyle = .round
        stem.stroke()

        let branchLength = rect.height * 0.42
        let dimAngle: CGFloat = branchAngleDegrees > 0 ? -22 : (branchAngleDegrees < 0 ? 22 : -26)
        let dimEnd = forkPoint(from: junction, angleDegrees: dimAngle, length: branchLength)
        let dimBranch = UIBezierPath()
        dimBranch.move(to: junction)
        dimBranch.addLine(to: dimEnd)
        UIColor.darkGray.withAlphaComponent(0.4).setStroke()
        dimBranch.lineWidth = 1.2
        dimBranch.lineCapStyle = .round
        dimBranch.stroke()

        let takenEnd = forkPoint(from: junction, angleDegrees: branchAngleDegrees, length: branchLength * 1.05)
        let takenBranch = UIBezierPath()
        takenBranch.move(to: junction)
        takenBranch.addLine(to: takenEnd)
        accentColor.setStroke()
        takenBranch.lineWidth = 2
        takenBranch.lineCapStyle = .round
        takenBranch.stroke()

        let headLength = rect.width * 0.13
        let radians = branchAngleDegrees * .pi / 180
        let headAngle: CGFloat = .pi / 6.5
        let head = UIBezierPath()
        head.move(to: takenEnd)
        head.addLine(to: CGPoint(x: takenEnd.x - headLength * sin(radians + headAngle), y: takenEnd.y - headLength * cos(radians + headAngle)))
        head.move(to: takenEnd)
        head.addLine(to: CGPoint(x: takenEnd.x - headLength * sin(radians - headAngle), y: takenEnd.y - headLength * cos(radians - headAngle)))
        accentColor.setStroke()
        head.lineWidth = 2
        head.lineCapStyle = .round
        head.stroke()
    }

    private static func forkPoint(from origin: CGPoint, angleDegrees: CGFloat, length: CGFloat) -> CGPoint {
        let radians = angleDegrees * .pi / 180
        return CGPoint(x: origin.x + length * sin(radians), y: origin.y - length * cos(radians))
    }

    /// Équivalent Core Graphics de `RoadbookMergePictogram` (écran) — deux traits qui convergent
    /// vers une flèche unique, distinct visuellement du virage classique (une seule flèche
    /// tournée).
    private static func drawMergePictogram(direction: TurnDirection, in rect: CGRect) {
        let top = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.12)
        let junction = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.55)
        let mainStart: CGPoint
        let secondaryStart: CGPoint
        switch direction {
        case .right:
            mainStart = CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.92)
            secondaryStart = CGPoint(x: rect.minX + rect.width * 0.82, y: rect.minY + rect.height * 0.92)
        case .left:
            mainStart = CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.92)
            secondaryStart = CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.92)
        default:
            mainStart = CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.92)
            secondaryStart = CGPoint(x: rect.minX + rect.width * 0.68, y: rect.minY + rect.height * 0.92)
        }

        let secondary = UIBezierPath()
        secondary.move(to: secondaryStart)
        secondary.addLine(to: junction)
        UIColor.darkGray.withAlphaComponent(0.45).setStroke()
        secondary.lineWidth = 1.4
        secondary.lineCapStyle = .round
        secondary.stroke()

        let main = UIBezierPath()
        main.move(to: mainStart)
        main.addLine(to: junction)
        main.move(to: junction)
        main.addLine(to: top)
        accentColor.setStroke()
        main.lineWidth = 2
        main.lineCapStyle = .round
        main.stroke()

        let headLength = rect.width * 0.14
        let head = UIBezierPath()
        head.move(to: top)
        head.addLine(to: CGPoint(x: top.x - headLength * 0.6, y: top.y + headLength))
        head.move(to: top)
        head.addLine(to: CGPoint(x: top.x + headLength * 0.6, y: top.y + headLength))
        accentColor.setStroke()
        head.lineWidth = 2
        head.lineCapStyle = .round
        head.stroke()
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
