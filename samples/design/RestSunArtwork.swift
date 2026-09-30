// Excerpt from Peakline (private repository), shared for portfolio review.
// © 2026 Noel Patricks. All rights reserved. Not licensed for reuse.
// Source: GymTracker/Views/Workout/RestSunArtwork.swift

import SwiftUI

/// Pure, `Equatable` geometry for the Rest page's "the sun crosses the peak"
/// artwork.
///
/// Every coordinate is ported from the approved board
/// (`boards/live-workout/source/Rest.dc.html`), which draws in a 358 × 240
/// box. The struct scales that box to whatever width it is handed, so the page
/// can build it once per size instead of once per timeline tick. Only the
/// sun's position and the sunlit face's alpenglow fill change while the rest
/// runs.
struct RestSunGeometry: Equatable {
    /// The board's drawing box. Geometry constants below are in its units.
    static let referenceSize = CGSize(width: 358, height: 240)

    /// The rest length this geometry was built for.
    let totalSeconds: Int
    let size: CGSize
    /// How much the reference box was scaled to fill `size`.
    let scale: CGFloat

    let leftSkyline: Path
    let rightSkyline: Path
    /// The peak's sunlit face, which soaks up alpenglow in the last 10 s.
    let sunlitFace: Path
    let arc: Path
    let peakOutline: Path
    let ridge: Path
    let subRidge: Path
    let horizon: Path
    let hachures: Path

    let sunDiameter: CGFloat
    /// The board clips the sun to the sky so it sets behind the horizon.
    let skyClipRect: CGRect

    private static let arcCentre = CGPoint(x: 179, y: 214)
    private static let arcRadii = CGSize(width: 163, height: 170)
    private static let hachureY: CGFloat = 226

    init(width: CGFloat, totalSeconds: Int) {
        let clampedWidth = max(1, width)
        let s = clampedWidth / Self.referenceSize.width
        let total = max(1, totalSeconds)

        scale = s
        size = CGSize(width: clampedWidth, height: Self.referenceSize.height * s)
        self.totalSeconds = total

        leftSkyline = Self.polyline([
            (0, 196), (24, 182), (44, 188), (70, 168), (92, 176), (112, 160)
        ], scale: s)

        rightSkyline = Self.polyline([
            (262, 176), (286, 150), (300, 158), (322, 136), (340, 150), (358, 140)
        ], scale: s)

        sunlitFace = Self.polyline([
            (179, 88), (192, 104), (204, 100), (222, 132), (240, 146), (262, 176),
            (280, 182), (320, 214), (214, 214), (196, 170), (190, 128)
        ], scale: s, closed: true)

        arc = Self.arcPath(scale: s)

        peakOutline = Self.polyline([
            (38, 214), (70, 188), (86, 194), (112, 160), (126, 166), (150, 124),
            (164, 112), (179, 88), (192, 104), (204, 100), (222, 132), (240, 146),
            (262, 176), (280, 182), (320, 214)
        ], scale: s)

        ridge = Self.polyline([(179, 88), (190, 128), (196, 170), (214, 214)], scale: s)

        subRidge = Self.polyline([
            (164, 112), (170, 120), (176, 114), (182, 124), (192, 104)
        ], scale: s)

        horizon = Self.polyline([(0, 214), (358, 214)], scale: s)

        hachures = Self.hachurePath(scale: s)

        sunDiameter = 18 * s
        skyClipRect = CGRect(x: -30 * s, y: -30 * s, width: 420 * s, height: 244 * s)
    }

    /// The sun's centre for a rest that has run `progress` (0 at the start,
    /// 1 when the rest is over), on the board's dotted arc.
    func sunPoint(progress: Double) -> CGPoint {
        sunPoint(unclampedProgress: min(max(progress, 0), 1))
    }

    /// The sun's centre for a rest that has run `progress`, without clamping
    /// the progress: past 1 the same ellipse carries the sun on below the
    /// horizon, so the Sunset summary can set it behind the peak.
    func sunPoint(unclampedProgress: Double) -> CGPoint {
        Self.scaled(Self.arcPoint(phi: Double.pi * (1 - unclampedProgress)), scale: scale)
    }

    static func clockLabel(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return "\(clamped / 60):\(String(format: "%02d", clamped % 60))"
    }

    // MARK: Geometry builders

    private static func polyline(
        _ points: [(CGFloat, CGFloat)],
        scale s: CGFloat,
        closed: Bool = false
    ) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.0 * s, y: first.1 * s))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.0 * s, y: point.1 * s))
        }
        if closed { path.closeSubpath() }
        return path
    }

    private static func arcPath(scale s: CGFloat) -> Path {
        // A sampled ellipse rather than an elliptical-arc command: the board
        // draws the upper half of an ellipse of radii 163 × 170 centred at
        // (179, 214), and 180 samples are visually identical at this size.
        let steps = 180
        var path = Path()
        for index in 0...steps {
            let phi = Double(index) / Double(steps) * .pi
            let point = scaled(arcPoint(phi: phi), scale: s)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    private static func hachurePath(scale s: CGFloat) -> Path {
        let marks: [(x: CGFloat, width: CGFloat)] = [
            (30, 14), (70, 14), (118, 14), (250, 14), (296, 9), (336, 9)
        ]
        var path = Path()
        for mark in marks {
            path.move(to: CGPoint(x: mark.x * s, y: hachureY * s))
            path.addLine(to: CGPoint(x: (mark.x + mark.width) * s, y: hachureY * s))
        }
        return path
    }


    private static func arcPoint(phi: Double) -> CGPoint {
        CGPoint(
            x: arcCentre.x + arcRadii.width * CGFloat(cos(phi)),
            y: arcCentre.y - arcRadii.height * CGFloat(sin(phi))
        )
    }

    private static func scaled(_ point: CGPoint, scale s: CGFloat) -> CGPoint {
        CGPoint(x: point.x * s, y: point.y * s)
    }
}

/// The Rest page's sun artwork: the static line art, the peak's sunlit face
/// and the alpenglow sun riding the arc.
///
/// The page builds the geometry once per size and hands in the timer state and
/// the once-a-second tick date. The line art re-renders on that tick only; the
/// sun is its own per-frame leaf (`RestSunMarker`), so nothing else here is on
/// the per-frame path.
struct RestSunArtwork: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let geometry: RestSunGeometry
    let state: RestTimerState
    /// The page's once-a-second tick date.
    let date: Date
    /// How much alpenglow soaks into the peak's sunlit face, 0...0.38.
    let faceGlow: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The skylines, the sunlit face and the ink line art are shared
            // with the Sunset summary hero; only the sun stays Rest's own.
            RestSunLineArt(
                geometry: geometry,
                faceGlow: faceGlow,
                faceGlowAnimation: faceGlowAnimation
            )

            RestSunMarker(geometry: geometry, state: state, date: date)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .accessibilityHidden(true)
    }

    private var faceGlowAnimation: Animation? {
        reduceMotion ? nil : AppMotion.easeOut(.settle)
    }
}

/// The sun circle. Its position is computed straight from the clock on every
/// frame instead of being animated between once-a-second ticks, so a long gap
/// (leaving the app and coming back) cannot be squeezed into a one-second glide
/// or retargeted mid-flight.
///
/// Where the target jumps (returning to the app, the page re-appearing, a
/// −15 s / +30 s tap) the sun eases from where it was last drawn to the live
/// position over one settle, then tracks the clock exactly. Reduce Motion keeps
/// the once-a-second step with no glide.
private struct RestSunMarker: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let geometry: RestSunGeometry
    let state: RestTimerState
    /// The page's once-a-second tick date.
    let date: Date

    @State private var tracker = RestSunTracker()

    private static let frameInterval: TimeInterval = 1.0 / 30

    var body: some View {
        if reduceMotion {
            sun(progress: state.progress(at: date))
        } else {
            // Runs before the frame reads the tracker, so a shortened or
            // extended rest glides from the last drawn position.
            let _ = tracker.noteEndDate(state.endDate)
            let paused = isPaused

            TimelineView(.animation(minimumInterval: Self.frameInterval, paused: paused)) { timeline in
                if paused && !isRestOver {
                    // The app went inactive mid-rest (Control Centre, a call): the
                    // sun holds where it was drawn rather than stepping back to
                    // the last once-a-second tick.
                    sun(progress: tracker.held(live: state.progress(at: date)))
                } else {
                    // While paused, the page's tick date closes the run out at
                    // its exact end position.
                    let frameDate = paused ? date : timeline.date
                    sun(
                        progress: tracker.displayedProgress(
                            live: state.progress(at: frameDate),
                            at: frameDate,
                            resumes: !paused
                        )
                    )
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { tracker.noteInterruption() }
            }
            .onDisappear { tracker.noteInterruption() }
        }
    }

    /// Idle when the app is not active, or when the rest is over (complete or
    /// reset) and any glide to its end position has finished.
    private var isPaused: Bool {
        guard scenePhase == .active else { return true }
        return isRestOver && !tracker.isBlending(at: date)
    }

    private var isRestOver: Bool {
        state.endDate == nil || state.isComplete
    }

    private func sun(progress: Double) -> some View {
        ZStack {
            Color.clear

            Circle()
                .fill(appTheme.colors.alpenglow)
                .frame(width: geometry.sunDiameter, height: geometry.sunDiameter)
                .position(geometry.sunPoint(progress: progress))
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .clipShape(SkyClip(rect: geometry.skyClipRect))
    }
}

/// Remembers where the sun was last drawn and blends from there to the live
/// position after a discontinuity. A plain reference type on purpose: it
/// changes every frame and must never invalidate a view.
private final class RestSunTracker {
    private var lastDrawn: Double?
    private var endDate: Date?
    private var blendFrom = 0.0
    private var blendStart: Date?
    private var resumePending = false

    private static let blendDuration = AppMotion.Timing.settle.seconds

    /// The rest's end moved (an adjust tap): glide to the new live position.
    func noteEndDate(_ newEndDate: Date?) {
        defer { endDate = newEndDate }
        guard endDate != newEndDate, endDate != nil, let lastDrawn else { return }
        blendFrom = lastDrawn
        blendStart = .now
    }

    /// The app left the foreground or the page went away: the next drawn frame
    /// starts a glide from the last one.
    func noteInterruption() {
        resumePending = true
    }

    /// The last drawn position, for a frame that must not move the sun.
    func held(live: Double) -> Double {
        lastDrawn ?? live
    }

    func isBlending(at date: Date) -> Bool {
        guard let blendStart else { return false }
        return date.timeIntervalSince(blendStart) < Self.blendDuration
    }

    /// The progress to draw for a frame at `date`, given the live value the
    /// clock puts it at. `resumes` is false for a paused draw, which must not
    /// consume a pending return-to-foreground glide.
    func displayedProgress(live: Double, at date: Date, resumes: Bool) -> Double {
        if resumes, resumePending {
            resumePending = false
            if let lastDrawn {
                blendFrom = lastDrawn
                blendStart = date
            }
        }

        var value = live
        if let blendStart {
            let fraction = date.timeIntervalSince(blendStart) / Self.blendDuration
            if fraction >= 1 {
                self.blendStart = nil
            } else {
                let eased = AppMotion.easeOutCurve.value(at: max(0, fraction))
                value = blendFrom + (live - blendFrom) * eased
            }
        }

        lastDrawn = value
        return value
    }
}

/// The Rest page's still artwork — the skylines, the peak's sunlit face with
/// its alpenglow, the dotted arc, the peak outline, its ridges, the horizon and
/// the hachures — drawn once for a `RestSunGeometry`.
///
/// The Rest page and the Sunset summary hero share it: each screen supplies its
/// own alpenglow amount and animation, then draws its own sun on top.
struct RestSunLineArt: View {
    @Environment(\.appTheme) private var appTheme

    let geometry: RestSunGeometry
    /// How much alpenglow soaks into the peak's sunlit face, 0...0.38.
    let faceGlow: Double
    let faceGlowAnimation: Animation?

    var body: some View {
        ZStack(alignment: .topLeading) {
            skyline

            geometry.sunlitFace
                .fill(appTheme.colors.alpenglow.opacity(faceGlow))
                .animation(faceGlowAnimation, value: faceGlow)

            lineArt
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .accessibilityHidden(true)
    }

    private var skyline: some View {
        let ink = appTheme.colors.textPrimary
        let style = StrokeStyle(
            lineWidth: 1.1 * geometry.scale,
            lineCap: .round,
            lineJoin: .round
        )

        return ZStack(alignment: .topLeading) {
            geometry.leftSkyline.stroke(ink.opacity(0.2), style: style)
            geometry.rightSkyline.stroke(ink.opacity(0.2), style: style)
        }
    }

    private var lineArt: some View {
        Canvas { context, _ in
            let ink = appTheme.colors.textPrimary
            let s = geometry.scale

            context.stroke(
                geometry.arc,
                with: .color(ink.opacity(0.3)),
                style: StrokeStyle(
                    lineWidth: 1.2 * s,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: [1.5 * s, 5 * s]
                )
            )

            // No time marks on the arc (Noel, 28 Sep): the sun's place on the
            // arc and the countdown under it already say how much is left.

            context.stroke(
                geometry.peakOutline,
                with: .color(ink),
                style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                geometry.ridge,
                with: .color(ink.opacity(0.45)),
                style: StrokeStyle(lineWidth: 1.1 * s, lineJoin: .round)
            )
            context.stroke(
                geometry.subRidge,
                with: .color(ink.opacity(0.6)),
                style: StrokeStyle(lineWidth: 1.1 * s, lineJoin: .round)
            )
            context.stroke(
                geometry.horizon,
                with: .color(ink.opacity(0.55)),
                style: StrokeStyle(lineWidth: 1.1 * s)
            )
            context.stroke(
                geometry.hachures,
                with: .color(ink.opacity(0.18)),
                style: StrokeStyle(lineWidth: 1 * s, lineCap: .round)
            )
        }
    }
}

/// The minimised sun for the logger's rest bar: a small arc with the sun on
/// it, drawn as one static frame. The caller supplies `progress` from its own
/// `TimelineView`, so this view never owns a clock.
struct RestSunMiniView: View {
    @Environment(\.appTheme) private var appTheme

    let progress: Double

    static let size = CGSize(width: 28, height: 16)

    var body: some View {
        Canvas { context, size in
            let ink = appTheme.colors.textPrimary
            let centre = CGPoint(x: size.width / 2, y: size.height - 2)
            let radii = CGSize(width: size.width / 2 - 2, height: size.height - 4)

            var arc = Path()
            let steps = 48
            for index in 0...steps {
                let phi = Double(index) / Double(steps) * .pi
                let point = CGPoint(
                    x: centre.x + radii.width * CGFloat(cos(phi)),
                    y: centre.y - radii.height * CGFloat(sin(phi))
                )
                if index == 0 {
                    arc.move(to: point)
                } else {
                    arc.addLine(to: point)
                }
            }
            context.stroke(
                arc,
                with: .color(ink.opacity(0.3)),
                style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 3])
            )

            let clamped = min(max(progress, 0), 1)
            let phi = Double.pi * (1 - clamped)
            let sun = CGPoint(
                x: centre.x + radii.width * CGFloat(cos(phi)),
                y: centre.y - radii.height * CGFloat(sin(phi))
            )
            let radius: CGFloat = 2.6
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: sun.x - radius,
                        y: sun.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                ),
                with: .color(appTheme.colors.alpenglow)
            )
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }
}

/// The board keeps the sun above the horizon, so the last stretch of the arc
/// shows a setting half-disc. Shared with the Sunset summary hero, whose sun
/// carries on below the horizon.
struct SkyClip: Shape {
    let rect: CGRect

    func path(in _: CGRect) -> Path {
        Path(rect)
    }
}
