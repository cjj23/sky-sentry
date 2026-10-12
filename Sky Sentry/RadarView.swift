//
//  RadarView.swift
//  Sky Sentry
//
//  The traffic display: a track-up plan view where each aircraft is an arrow
//  whose head sits at the rim of the screen, pointing out towards where the
//  aircraft actually is, and whose tail grows in towards the centre as it gets
//  closer. The tail tip lands exactly on the range ring for its distance, so a
//  target crossing the 5 nm ring is unmistakable.
//

import SwiftUI

// MARK: - Colours

/// Colours are chosen so the background alone reads at a glance in peripheral
/// vision, with the arrows staying high-contrast against whichever state we're in.
struct Palette {
    let background: Color
    let ink: Color
    let inkOutline: Color
    let ring: Color
    /// The colour a warning arrow flashes to on the "off" half of the cycle.
    let flashAlternate: Color

    /// Shown when the receiver has nothing to say. Deliberately not green:
    /// "I don't know" must not look like "you are clear".
    static let unknown = Palette(background: Color(red: 0.28, green: 0.30, blue: 0.33),
                                 ink: .white,
                                 inkOutline: .black.opacity(0.55),
                                 ring: .white.opacity(0.35),
                                 flashAlternate: .black)

    static func of(_ threat: ThreatLevel) -> Palette {
        switch threat {
        case .clear, .advisory:
            return Palette(background: Color(red: 0.06, green: 0.48, blue: 0.20),
                           ink: .white,
                           inkOutline: .black.opacity(0.55),
                           ring: .white.opacity(0.45),
                           flashAlternate: .black)
        case .caution:
            return Palette(background: Color(red: 0.95, green: 0.58, blue: 0.02),
                           ink: .black.opacity(0.88),
                           inkOutline: .white.opacity(0.55),
                           ring: .black.opacity(0.40),
                           flashAlternate: .white)
        case .warning:
            return Palette(background: Color(red: 0.82, green: 0.09, blue: 0.09),
                           ink: .white,
                           inkOutline: .black.opacity(0.55),
                           ring: .white.opacity(0.50),
                           flashAlternate: .black)
        }
    }
}

// MARK: - Radar

struct RadarView: View {
    let solutions: [TrafficSolution]
    let config: AlertConfig
    let palette: Palette

    // Nominal sizes, tuned against a full-width phone screen (radius ~185pt).
    // In a small iPadOS window everything is scaled down together by `scale`,
    // so arrows stay proportionate rather than swamping a small ring.
    private let nominalHeadLength: CGFloat = 30
    private let nominalHeadWidth: CGFloat = 26
    private let nominalShaftWidth: CGFloat = 12
    private let nominalRadius: CGFloat = 185

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                draw(&context, size: size,
                     time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    /// Margin kept clear at the edge so arrowheads sit proud rather than touching.
    private let edgeInset: CGFloat = 12

    private func draw(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let bias = config.forwardBias
        let centre: CGPoint
        let maxRadius: CGFloat

        // The scale never changes: the outer ring is always the largest circle
        // that would fit whole, whatever the bias. Nothing is magnified.
        maxRadius = min(size.width, size.height) / 2 - edgeInset

        // Ownship simply moves down. Because the scale is fixed, the space
        // above now reaches further in nautical miles than the space below —
        // which is the whole point: more distance ahead, the sides unchanged.
        centre = CGPoint(x: size.width / 2, y: size.height * bias.ownshipFraction)

        // Below this there is not enough room for the picture to mean anything.
        guard maxRadius > 26 else { return }

        let scale = min(1.0, max(0.45, maxRadius / nominalRadius))

        drawRings(&context, centre: centre, maxRadius: maxRadius, size: size, scale: scale)
        drawForwardArcs(&context, centre: centre, maxRadius: maxRadius,
                        size: size, scale: scale)
        drawBearingTicks(&context, centre: centre, maxRadius: maxRadius, scale: scale)
        drawOwnship(&context, centre: centre, scale: scale)

        // In a small window there is no room for a label on every target, and
        // crowding them defeats the point of a glanceable display. Label only
        // the one that matters — converging first, otherwise nearest — and let
        // the arrows themselves carry the rest.
        // Graded by the actual radius rather than the scale factor: below about
        // 120pt there is no room for legible text at all, and the header is
        // already carrying the headline figure.
        let labelBudget: Int
        if maxRadius < 120 {
            labelBudget = 0
        } else if maxRadius < 175 {
            labelBudget = 1
        } else {
            labelBudget = solutions.count
        }
        let priority = solutions.sorted {
            $0.isConverging != $1.isConverging ? $0.isConverging : $0.rangeNM < $1.rangeNM
        }
        let labelled = Set(priority.prefix(labelBudget).map(\.target.icaoAddress))

        // Furthest first, so the closest (most urgent) mark is drawn on top.
        var placedLabels: [CGPoint] = []
        for solution in solutions.sorted(by: { $0.rangeNM > $1.rangeNM }) {
            if solution.relativeBearing == nil {
                drawBearinglessRing(&context, solution: solution, centre: centre,
                                    maxRadius: maxRadius, time: time, scale: scale,
                                    mayLabel: labelled.contains(solution.target.icaoAddress),
                                    placedLabels: &placedLabels)
            } else {
                drawArrow(&context, solution: solution, centre: centre,
                          maxRadius: maxRadius, size: size, time: time, scale: scale,
                          mayLabel: labelled.contains(solution.target.icaoAddress),
                          placedLabels: &placedLabels)
            }
        }
    }

    /// Traffic beyond the selected range, in the extra space ahead. A hollow
    /// chevron at its true position — present, but visibly secondary to the
    /// ranged picture inside the ring.
    private func drawDistantMark(_ context: inout GraphicsContext, at point: CGPoint,
                                 ux: CGFloat, uy: CGFloat, scale: CGFloat) {
        let length = 15 * scale
        let halfWidth = 10 * scale
        let px = -uy, py = ux

        var path = Path()
        path.move(to: CGPoint(x: point.x + ux * length, y: point.y + uy * length))
        path.addLine(to: CGPoint(x: point.x + px * halfWidth, y: point.y + py * halfWidth))
        path.addLine(to: CGPoint(x: point.x - px * halfWidth, y: point.y - py * halfWidth))
        path.closeSubpath()

        context.stroke(path, with: .color(palette.inkOutline),
                       style: StrokeStyle(lineWidth: 3.5 * scale, lineJoin: .round))
        context.stroke(path, with: .color(palette.ink.opacity(0.75)),
                       style: StrokeStyle(lineWidth: 2 * scale, lineJoin: .round))
    }

    private func drawDistantLabel(_ context: inout GraphicsContext, text: String,
                                  at point: CGPoint, scale: CGFloat) {
        let resolved = Text(text).font(.trafficLabel(max(10, 12 * scale)))
        let shadow = context.resolve(resolved.foregroundStyle(palette.inkOutline))
        context.draw(shadow, at: CGPoint(x: point.x + 1, y: point.y + 1), anchor: .center)
        let body = context.resolve(resolved.foregroundStyle(palette.ink.opacity(0.8)))
        context.draw(body, at: point, anchor: .center)
    }

    /// How far the view's edge is from a point, along a direction. Used to pin
    /// arrowheads to the screen edge once the rim runs off it.
    private func distanceToEdge(from centre: CGPoint, ux: CGFloat, uy: CGFloat,
                                in size: CGSize) -> CGFloat {
        var distance = CGFloat.greatestFiniteMagnitude
        if ux > 0.0001  { distance = min(distance, (size.width - edgeInset - centre.x) / ux) }
        if ux < -0.0001 { distance = min(distance, (edgeInset - centre.x) / ux) }
        if uy > 0.0001  { distance = min(distance, (size.height - edgeInset - centre.y) / uy) }
        if uy < -0.0001 { distance = min(distance, (edgeInset - centre.y) / uy) }
        return max(headLengthFloor, distance)
    }

    /// Never collapse an arrow to nothing, even if ownship sits on the edge.
    private var headLengthFloor: CGFloat { nominalHeadLength * 0.6 }

    // MARK: Bearingless contacts

    /// A contact whose range is known but whose direction is not — a Mode S
    /// interrogation, or FLARM without bearing. Drawn as a pulsing ring at the
    /// right radius: it says "something is this far away, somewhere all around
    /// you", which is exactly as much as we actually know. Drawing it as an
    /// arrow would invent a direction we do not have.
    private func drawBearinglessRing(_ context: inout GraphicsContext, solution: TrafficSolution,
                                     centre: CGPoint, maxRadius: CGFloat, time: TimeInterval,
                                     scale: CGFloat, mayLabel: Bool,
                                     placedLabels: inout [CGPoint]) {
        let radius = max(14 * scale, maxRadius * CGFloat(solution.rangeNM / config.displayRangeNM))
        let rect = CGRect(x: centre.x - radius, y: centre.y - radius,
                          width: radius * 2, height: radius * 2)
        let path = Path(ellipseIn: rect)

        // Pulse faster the closer it is, so urgency is felt as well as seen.
        let rate = solution.threat >= .warning ? 2.0 : (solution.threat >= .caution ? 1.4 : 0.9)
        let pulse = 0.30 + 0.70 * (0.5 + 0.5 * sin(time * 2 * .pi * rate))

        context.stroke(path, with: .color(palette.inkOutline.opacity(pulse * 0.9)),
                       style: StrokeStyle(lineWidth: 11 * scale, lineCap: .round))
        context.stroke(path, with: .color(palette.ink.opacity(pulse)),
                       style: StrokeStyle(lineWidth: 6 * scale, lineCap: .round,
                                          dash: [18 * scale, 10 * scale]))

        guard mayLabel else { return }

        // Label it at the top of its ring, nudged clear of anything already placed.
        let offset = 20 * scale
        let candidates: [CGPoint] = [
            CGPoint(x: centre.x, y: centre.y - radius - offset),
            CGPoint(x: centre.x, y: centre.y + radius + offset),
            CGPoint(x: centre.x + radius + offset * 1.3, y: centre.y),
            CGPoint(x: centre.x - radius - offset * 1.3, y: centre.y),
        ]
        let anchor = candidates.first { isClear($0, of: placedLabels, scale: scale) }
            ?? candidates[0]

        placedLabels.append(anchor)
        drawLabel(&context, solution: solution, at: anchor, scale: scale)
    }

    // MARK: Rings

    private func drawRings(_ context: inout GraphicsContext, centre: CGPoint,
                           maxRadius: CGFloat, size: CGSize, scale: CGFloat) {
        let rings: [(range: Double, dashed: Bool)] = [
            (config.innerRingNM, true),
            (config.middleRingNM, true),
            (config.displayRangeNM, false),
        ]

        for ring in rings {
            let radius = maxRadius * CGFloat(ring.range / config.displayRangeNM)
            let rect = CGRect(x: centre.x - radius, y: centre.y - radius,
                              width: radius * 2, height: radius * 2)
            let style = StrokeStyle(lineWidth: (ring.dashed ? 2.5 : 2) * scale,
                                    dash: ring.dashed ? [9 * scale, 7 * scale] : [])
            context.stroke(Path(ellipseIn: rect), with: .color(palette.ring), style: style)

            // Range label sits just below the ring on the vertical, clear of most arrows.
            let label = context.resolve(
                Text("\(Int(ring.range)) nm")
                    .font(.annunciatorDetail(12 * scale, weight: .semibold))
                    .foregroundStyle(palette.ring)
            )
            // Normally below centre, clear of most arrows. With a forward bias
            // the outer ring runs off the bottom, taking its label with it, so
            // fall back to the forward side where there is room.
            var labelY = centre.y + radius - 10 * scale
            var labelX = centre.x

            // With a forward bias the outer ring runs off the bottom, taking its
            // label with it, so fall back to the forward side. Only that one is
            // nudged off the vertical, because only up there does it land on a
            // bearing tick; the inner labels are fine where they sit.
            if labelY > size.height - edgeInset {
                labelY = centre.y - radius + 12 * scale
                labelX = centre.x + 25 * scale
            }
            context.draw(label, at: CGPoint(x: labelX, y: labelY), anchor: .center)
        }
    }

    /// With a forward bias the screen reaches well past the outer ring in
    /// front, and without a reference out there the extra space has no scale.
    /// These are drawn only across the forward half, and deliberately fainter
    /// than the main rings: they are context for the occasional distant
    /// contact, not part of the ranged picture.
    private func drawForwardArcs(_ context: inout GraphicsContext, centre: CGPoint,
                                 maxRadius: CGFloat, size: CGSize, scale: CGFloat) {
        guard config.forwardBias != .centred else { return }

        // Multiples of the selected range, so they stay sensible at 5 or 20 nm
        // just as they do at 10.
        for multiple in [2.0, 3.0] {
            let radius = maxRadius * multiple
            // Skip one that would be entirely off the top of the view.
            guard centre.y - radius > edgeInset else { continue }

            var path = Path()
            path.addArc(center: centre, radius: radius,
                        startAngle: .degrees(180), endAngle: .degrees(360),
                        clockwise: false)
            // Same colour as the main rings, so they read as part of the same
            // scale. The dotted stroke is what distinguishes them.
            context.stroke(path, with: .color(palette.ring),
                           style: StrokeStyle(lineWidth: 2 * scale,
                                              dash: [2.5 * scale, 7 * scale]))

            let label = context.resolve(
                Text("\(Int(config.displayRangeNM * multiple)) nm")
                    .font(.annunciatorDetail(11 * scale, weight: .semibold))
                    .foregroundStyle(palette.ring)
            )
            context.draw(label, at: CGPoint(x: centre.x, y: centre.y - radius + 11 * scale),
                         anchor: .center)
        }
    }

    /// Ticks every 30 degrees to help judge direction; longer ones at the quadrants.
    private func drawBearingTicks(_ context: inout GraphicsContext, centre: CGPoint,
                                  maxRadius: CGFloat, scale: CGFloat) {
        for degrees in stride(from: 0, to: 360, by: 30) {
            let isQuadrant = degrees % 90 == 0
            let angle = Double(degrees) * .pi / 180
            let ux = CGFloat(sin(angle)), uy = CGFloat(-cos(angle))
            let inner = maxRadius - (isQuadrant ? 16 : 9) * scale

            var path = Path()
            path.move(to: CGPoint(x: centre.x + ux * inner, y: centre.y + uy * inner))
            path.addLine(to: CGPoint(x: centre.x + ux * maxRadius, y: centre.y + uy * maxRadius))
            context.stroke(path, with: .color(palette.ring),
                           style: StrokeStyle(lineWidth: (isQuadrant ? 3 : 1.5) * scale,
                                              lineCap: .round))
        }
    }

    /// Ownship sits at the centre pointing up: the display is track-up, so
    /// straight up the screen is always where the nose is pointing.
    private func drawOwnship(_ context: inout GraphicsContext, centre: CGPoint, scale: CGFloat) {
        var path = Path()
        path.move(to: CGPoint(x: centre.x, y: centre.y - 13 * scale))
        path.addLine(to: CGPoint(x: centre.x + 9 * scale, y: centre.y + 10 * scale))
        path.addLine(to: CGPoint(x: centre.x, y: centre.y + 5 * scale))
        path.addLine(to: CGPoint(x: centre.x - 9 * scale, y: centre.y + 10 * scale))
        path.closeSubpath()

        context.fill(path, with: .color(palette.ink))
        context.stroke(path, with: .color(palette.inkOutline), lineWidth: 1.5 * scale)
    }

    // MARK: Arrows

    private func drawArrow(_ context: inout GraphicsContext, solution: TrafficSolution,
                           centre: CGPoint, maxRadius: CGFloat, size: CGSize,
                           time: TimeInterval, scale: CGFloat, mayLabel: Bool,
                           placedLabels: inout [CGPoint]) {
        guard let relativeBearing = solution.relativeBearing else { return }

        let headLength = nominalHeadLength * scale
        let headWidth = nominalHeadWidth * scale
        let shaftWidth = nominalShaftWidth * scale
        let angle = relativeBearing * .pi / 180
        let ux = CGFloat(sin(angle)), uy = CGFloat(-cos(angle))   // outward, along the bearing
        let px = CGFloat(cos(angle)), py = CGFloat(sin(angle))    // across it

        func point(_ radius: CGFloat, across: CGFloat = 0) -> CGPoint {
            CGPoint(x: centre.x + ux * radius + px * across,
                    y: centre.y + uy * radius + py * across)
        }

        let edge = distanceToEdge(from: centre, ux: ux, uy: uy, in: size)
        let ringRadius = maxRadius * CGFloat(solution.rangeNM / config.displayRangeNM)

        // Further out than the selected range, but inside the extra space a
        // forward bias opens up. Drawn as a small outline at its true position
        // rather than a full arrow: it is awareness of something out there, not
        // part of the ranged picture, and it should not read as urgently as
        // traffic inside the ring.
        if ringRadius > maxRadius {
            guard ringRadius < edge else { return }
            drawDistantMark(&context, at: point(ringRadius), ux: ux, uy: uy, scale: scale)
            guard mayLabel, let altitude = solution.altitudeLabel else { return }
            let anchor = clamped(point(ringRadius, across: shaftWidth + 20 * scale),
                                 in: size, scale: scale)
            placedLabels.append(anchor)
            drawDistantLabel(&context, text: altitude, at: anchor, scale: scale)
            return
        }

        // Within the ring. The head sits at whichever comes first: the rim, or
        // the edge of the view — with a bias the rim runs off the bottom. The
        // tail still lands on the true range, so distance is never
        // misrepresented; only the pointer is shortened.
        let headRadius = min(maxRadius, edge)
        let isOffScreen = ringRadius > edge

        let shoulder = headRadius - headLength
        let tailRadius = min(ringRadius, shoulder - 2)

        var path = Path()
        path.move(to: point(headRadius))
        path.addLine(to: point(shoulder, across: headWidth / 2))

        if !isOffScreen, tailRadius < shoulder - 2 {
            path.addLine(to: point(shoulder, across: shaftWidth / 2))
            path.addLine(to: point(tailRadius, across: shaftWidth * 0.3))
            path.addLine(to: point(tailRadius, across: -shaftWidth * 0.3))
            path.addLine(to: point(shoulder, across: -shaftWidth / 2))
        }

        path.addLine(to: point(shoulder, across: -headWidth / 2))
        path.closeSubpath()

        // A target on a collision bearing gets a pulsing halo behind the arrow.
        // It is deliberately a different signal from the range flash below: this
        // one says "this one is actually converging", not "this one is near".
        if solution.isConverging {
            let pulse = 0.35 + 0.55 * (0.5 + 0.5 * sin(time * 2 * .pi * 1.4))
            context.stroke(path, with: .color(palette.flashAlternate.opacity(pulse)),
                           style: StrokeStyle(lineWidth: 11 * scale, lineJoin: .round))
        }

        // 2 Hz square wave: the standard attention-getting flash rate.
        let isFlashing = solution.threat == .warning
        let flashOn = time.truncatingRemainder(dividingBy: 0.5) < 0.25
        let fill = (isFlashing && !flashOn) ? palette.flashAlternate : palette.ink

        context.fill(path, with: .color(fill))
        context.stroke(path, with: .color(palette.inkOutline),
                       style: StrokeStyle(lineWidth: 2 * scale, lineJoin: .round))

        // Height is shown on every aircraft we draw, as a TCAS traffic display
        // does — it is the quickest discriminator between an aircraft worth
        // looking for and one passing 2,000 ft over the top. The rest of the
        // detail is kept for the ones that matter, so a busy circuit stays
        // readable.
        guard mayLabel else { return }

        // Offset across the arrow rather than along it, so labels stay clear of
        // the range-ring numbers that sit on the vertical. Two aircraft on a
        // similar bearing would otherwise print on top of each other, so try a
        // few positions and take the first that is clear of what is already drawn.
        let labelRadius = isOffScreen
            ? max(headRadius - headLength - 18 * scale, 34 * scale)
            : max(tailRadius - 12 * scale, 34 * scale)
        let offsets: [CGFloat] = [shaftWidth + 20 * scale, -(shaftWidth + 20 * scale),
                                  shaftWidth + 62 * scale, -(shaftWidth + 62 * scale)]
        let candidates = offsets.map { point(labelRadius, across: $0) }
        let anchor = candidates.first { isClear($0, of: placedLabels, scale: scale) }
            ?? candidates[0]

        placedLabels.append(anchor)
        drawLabel(&context, solution: solution, at: clamped(anchor, in: size, scale: scale),
                  scale: scale)
    }

    /// Labels are far wider than they are tall, so a plain radial distance test
    /// lets two of them sit side by side and overlap. This checks the boxes
    /// they actually occupy.
    private func isClear(_ candidate: CGPoint, of placed: [CGPoint], scale: CGFloat) -> Bool {
        let halfWidth = 46 * scale
        let halfHeight = 26 * scale
        return placed.allSatisfy { existing in
            abs(existing.x - candidate.x) > halfWidth
                || abs(existing.y - candidate.y) > halfHeight
        }
    }

    /// Keeps a label inside the view. With a forward bias the arrowheads sit on
    /// the edge, and an un-clamped label beside one runs straight off it.
    private func clamped(_ point: CGPoint, in size: CGSize, scale: CGFloat) -> CGPoint {
        let halfWidth = 38 * scale
        let halfHeight = 24 * scale
        return CGPoint(
            x: min(max(point.x, halfWidth), size.width - halfWidth),
            y: min(max(point.y, halfHeight), size.height - halfHeight))
    }

    private func drawLabel(_ context: inout GraphicsContext, solution: TrafficSolution,
                           at point: CGPoint, scale: CGFloat) {
        // Height is the thing most worth reading quickly — co-altitude traffic
        // is the dangerous kind — so it gets the largest text, and it is written
        // ABOVE the rest when the aircraft is above us and BELOW when it is
        // below. Position says it as well as the sign does, which is TCAS's
        // convention and is far quicker to read than parsing "+" or "−".
        var middle: [String] = []
        if solution.threat >= .caution || solution.isConverging {
            middle.append(solution.rangeLabel)
            if let category = solution.target.category.shortLabel {
                middle.append(category)
            }
            if solution.relativeBearing == nil {
                middle.append("NO BRG")
            }
            if solution.isConverging {
                // The countdown to closest approach is more use than the word alone.
                middle.append(solution.cpaLabel.map { "CBDR \($0)" } ?? "CBDR")
            }
        }

        // Nothing at all to say about this one.
        guard solution.altitudeLabel != nil || !middle.isEmpty else { return }

        // Labels shrink more slowly than the geometry: below about 11pt they
        // stop being readable at a glance, which defeats the point.
        let bodySize = max(11, 13 * scale)
        let altitudeSize = max(13, 16 * scale)

        var lines: [(text: String, size: CGFloat)] = middle.map { ($0, bodySize) }

        if let altitude = solution.altitudeLabel {
            // A climb or descent arrow rides with it, past 500 fpm.
            let trend = solution.verticalTrend.map { " \($0)" } ?? ""
            let entry = (altitude + trend, altitudeSize)
            if solution.isAbove {
                lines.insert(entry, at: 0)
            } else {
                lines.append(entry)
            }
        }

        // Each line is drawn separately: Canvas can only resolve a Text, and the
        // layout modifiers that would centre a multi-line string return a View.
        var y = point.y - lines.reduce(0) { $0 + $1.size + 1 } / 2
        for line in lines {
            let text = Text(line.text)
                .font(.trafficLabel(line.size))
            let origin = CGPoint(x: point.x, y: y + line.size / 2)

            // Outline colour offset behind, so the figures stay readable wherever they land.
            let shadow = context.resolve(text.foregroundStyle(palette.inkOutline))
            context.draw(shadow, at: CGPoint(x: origin.x + 1, y: origin.y + 1), anchor: .center)

            let body = context.resolve(text.foregroundStyle(palette.ink))
            context.draw(body, at: origin, anchor: .center)

            y += line.size + 1
        }
    }
}
