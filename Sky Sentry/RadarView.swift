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

    private let headLength: CGFloat = 30
    private let headWidth: CGFloat = 26
    private let shaftWidth: CGFloat = 12

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                draw(&context, size: size,
                     time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        // Leave room for the arrowheads to sit proud at the rim.
        let maxRadius = min(size.width, size.height) / 2 - 12
        guard maxRadius > 40 else { return }

        drawRings(&context, centre: centre, maxRadius: maxRadius)
        drawBearingTicks(&context, centre: centre, maxRadius: maxRadius)
        drawOwnship(&context, centre: centre)

        // Furthest first, so the closest (most urgent) mark is drawn on top.
        var placedLabels: [CGPoint] = []
        for solution in solutions.sorted(by: { $0.rangeNM > $1.rangeNM }) {
            if solution.relativeBearing == nil {
                drawBearinglessRing(&context, solution: solution, centre: centre,
                                    maxRadius: maxRadius, time: time,
                                    placedLabels: &placedLabels)
            } else {
                drawArrow(&context, solution: solution, centre: centre,
                          maxRadius: maxRadius, time: time, placedLabels: &placedLabels)
            }
        }
    }

    // MARK: Bearingless contacts

    /// A contact whose range is known but whose direction is not — a Mode S
    /// interrogation, or FLARM without bearing. Drawn as a pulsing ring at the
    /// right radius: it says "something is this far away, somewhere all around
    /// you", which is exactly as much as we actually know. Drawing it as an
    /// arrow would invent a direction we do not have.
    private func drawBearinglessRing(_ context: inout GraphicsContext, solution: TrafficSolution,
                                     centre: CGPoint, maxRadius: CGFloat, time: TimeInterval,
                                     placedLabels: inout [CGPoint]) {
        let radius = max(14, maxRadius * CGFloat(solution.rangeNM / config.displayRangeNM))
        let rect = CGRect(x: centre.x - radius, y: centre.y - radius,
                          width: radius * 2, height: radius * 2)
        let path = Path(ellipseIn: rect)

        // Pulse faster the closer it is, so urgency is felt as well as seen.
        let rate = solution.threat >= .warning ? 2.0 : (solution.threat >= .caution ? 1.4 : 0.9)
        let pulse = 0.30 + 0.70 * (0.5 + 0.5 * sin(time * 2 * .pi * rate))

        context.stroke(path, with: .color(palette.inkOutline.opacity(pulse * 0.9)),
                       style: StrokeStyle(lineWidth: 11, lineCap: .round))
        context.stroke(path, with: .color(palette.ink.opacity(pulse)),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [18, 10]))

        // Label it at the top of its ring, nudged clear of anything already placed.
        let candidates: [CGPoint] = [
            CGPoint(x: centre.x, y: centre.y - radius - 20),
            CGPoint(x: centre.x, y: centre.y + radius + 20),
            CGPoint(x: centre.x + radius + 26, y: centre.y),
            CGPoint(x: centre.x - radius - 26, y: centre.y),
        ]
        let anchor = candidates.first { candidate in
            placedLabels.allSatisfy { hypot($0.x - candidate.x, $0.y - candidate.y) > 52 }
        } ?? candidates[0]

        placedLabels.append(anchor)
        drawLabel(&context, solution: solution, at: anchor)
    }

    // MARK: Rings

    private func drawRings(_ context: inout GraphicsContext, centre: CGPoint, maxRadius: CGFloat) {
        let rings: [(range: Double, dashed: Bool)] = [
            (config.warningRangeNM, true),
            (config.cautionRangeNM, true),
            (config.displayRangeNM, false),
        ]

        for ring in rings {
            let radius = maxRadius * CGFloat(ring.range / config.displayRangeNM)
            let rect = CGRect(x: centre.x - radius, y: centre.y - radius,
                              width: radius * 2, height: radius * 2)
            let style = StrokeStyle(lineWidth: ring.dashed ? 2.5 : 2,
                                    dash: ring.dashed ? [9, 7] : [])
            context.stroke(Path(ellipseIn: rect), with: .color(palette.ring), style: style)

            // Range label sits just below the ring on the vertical, clear of most arrows.
            let label = context.resolve(
                Text("\(Int(ring.range))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.ring)
            )
            context.draw(label, at: CGPoint(x: centre.x, y: centre.y + radius - 10), anchor: .center)
        }
    }

    /// Ticks every 30 degrees to help judge direction; longer ones at the quadrants.
    private func drawBearingTicks(_ context: inout GraphicsContext, centre: CGPoint, maxRadius: CGFloat) {
        for degrees in stride(from: 0, to: 360, by: 30) {
            let isQuadrant = degrees % 90 == 0
            let angle = Double(degrees) * .pi / 180
            let ux = CGFloat(sin(angle)), uy = CGFloat(-cos(angle))
            let inner = maxRadius - (isQuadrant ? 16 : 9)

            var path = Path()
            path.move(to: CGPoint(x: centre.x + ux * inner, y: centre.y + uy * inner))
            path.addLine(to: CGPoint(x: centre.x + ux * maxRadius, y: centre.y + uy * maxRadius))
            context.stroke(path, with: .color(palette.ring),
                           style: StrokeStyle(lineWidth: isQuadrant ? 3 : 1.5, lineCap: .round))
        }
    }

    /// Ownship sits at the centre pointing up: the display is track-up, so
    /// straight up the screen is always where the nose is pointing.
    private func drawOwnship(_ context: inout GraphicsContext, centre: CGPoint) {
        var path = Path()
        path.move(to: CGPoint(x: centre.x, y: centre.y - 13))
        path.addLine(to: CGPoint(x: centre.x + 9, y: centre.y + 10))
        path.addLine(to: CGPoint(x: centre.x, y: centre.y + 5))
        path.addLine(to: CGPoint(x: centre.x - 9, y: centre.y + 10))
        path.closeSubpath()

        context.fill(path, with: .color(palette.ink))
        context.stroke(path, with: .color(palette.inkOutline), lineWidth: 1.5)
    }

    // MARK: Arrows

    private func drawArrow(_ context: inout GraphicsContext, solution: TrafficSolution,
                           centre: CGPoint, maxRadius: CGFloat, time: TimeInterval,
                           placedLabels: inout [CGPoint]) {
        guard let relativeBearing = solution.relativeBearing else { return }
        let angle = relativeBearing * .pi / 180
        let ux = CGFloat(sin(angle)), uy = CGFloat(-cos(angle))   // outward, along the bearing
        let px = CGFloat(cos(angle)), py = CGFloat(sin(angle))    // across it

        func point(_ radius: CGFloat, across: CGFloat = 0) -> CGPoint {
            CGPoint(x: centre.x + ux * radius + px * across,
                    y: centre.y + uy * radius + py * across)
        }

        let shoulder = maxRadius - headLength
        // Where the target actually is: the tail tip lands on its range ring.
        let ringRadius = maxRadius * CGFloat(solution.rangeNM / config.displayRangeNM)
        let tailRadius = min(ringRadius, shoulder - 2)

        var path = Path()
        path.move(to: point(maxRadius))
        path.addLine(to: point(shoulder, across: headWidth / 2))

        if tailRadius < shoulder - 2 {
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
                           style: StrokeStyle(lineWidth: 11, lineJoin: .round))
        }

        // 2 Hz square wave: the standard attention-getting flash rate.
        let isFlashing = solution.threat == .warning
        let flashOn = time.truncatingRemainder(dividingBy: 0.5) < 0.25
        let fill = (isFlashing && !flashOn) ? palette.flashAlternate : palette.ink

        context.fill(path, with: .color(fill))
        context.stroke(path, with: .color(palette.inkOutline),
                       style: StrokeStyle(lineWidth: 2, lineJoin: .round))

        // Only label the ones that matter, to keep a busy circuit readable.
        guard solution.threat >= .caution || solution.isConverging else { return }

        // Offset across the arrow rather than along it, so labels stay clear of
        // the range-ring numbers that sit on the vertical. Two aircraft on a
        // similar bearing would otherwise print on top of each other, so try a
        // few positions and take the first that is clear of what is already drawn.
        let labelRadius = max(tailRadius - 12, 34)
        let offsets: [CGFloat] = [shaftWidth + 20, -(shaftWidth + 20),
                                  shaftWidth + 62, -(shaftWidth + 62)]
        let candidates = offsets.map { point(labelRadius, across: $0) }
        let anchor = candidates.first { candidate in
            placedLabels.allSatisfy { hypot($0.x - candidate.x, $0.y - candidate.y) > 52 }
        } ?? candidates[0]

        placedLabels.append(anchor)
        drawLabel(&context, solution: solution, at: anchor)
    }

    private func drawLabel(_ context: inout GraphicsContext, solution: TrafficSolution, at point: CGPoint) {
        var lines = [solution.rangeLabel]
        if let altitude = solution.altitudeLabel {
            lines.append(altitude)
        }
        if solution.relativeBearing == nil {
            lines.append("NO BRG")
        }
        if solution.isConverging {
            // The countdown to closest approach is more use than the word alone.
            lines.append(solution.cpaLabel.map { "CBDR \($0)" } ?? "CBDR")
        }

        // Each line is drawn separately: Canvas can only resolve a Text, and the
        // layout modifiers that would centre a multi-line string return a View.
        for (index, line) in lines.enumerated() {
            let text = Text(line)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
            let origin = CGPoint(x: point.x, y: point.y + CGFloat(index) * 14)

            // Outline colour offset behind, so the figures stay readable wherever they land.
            let shadow = context.resolve(text.foregroundStyle(palette.inkOutline))
            context.draw(shadow, at: CGPoint(x: origin.x + 1, y: origin.y + 1), anchor: .center)

            let body = context.resolve(text.foregroundStyle(palette.ink))
            context.draw(body, at: origin, anchor: .center)
        }
    }
}
