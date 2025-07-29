import SwiftUI
import Charts
import UIKit

// MARK: - Timestamped helper
/// A lightweight protocol for time-series data points.
protocol Timestamped {
    var timestamp: Date { get }
}

// Conform existing models
extension SpeedPoint: Timestamped {}
extension AccelPoint: Timestamped {}

// MARK: - DomainXGesture utilities
// Protocol allowing numeric-like domain types to be converted to and from Double values.
public protocol ExpressibleByDouble: Comparable {
    var double: Double { get }
    init(_ double: Double)
}

extension TimeInterval: ExpressibleByDouble {
    public var double: Double { self }
    public init(_ double: Double) { self = double }
}

extension Date: ExpressibleByDouble {
    public var double: Double { timeIntervalSince1970 }
    public init(_ double: Double) { self = Date(timeIntervalSince1970: double) }
}

/// A UIKit-backed gesture recognizer that provides pan and pinch control over a chart’s horizontal domain.
public struct DomainXGesture<Bound: ExpressibleByDouble>: UIGestureRecognizerRepresentable {
    @Binding private var domain: ClosedRange<Bound>
    private let simultaneous: Bool
    private let isEnabled: () -> Bool
    private let onEnded: () -> Void
    private let onPinchState: (Bool) -> Void

    @State private var leading: Double?
    @State private var leadingValue: Double?
    @State private var trailingValue: Double?

    public init(
        domain: Binding<ClosedRange<Bound>>,
        simultaneous: Bool = false,
        enabled: @escaping () -> Bool = { true },
        onPinchState: @escaping (Bool) -> Void = { _ in },
        onEnded: @escaping () -> () = {}
    ) {
        self._domain = domain
        self.simultaneous = simultaneous
        self.isEnabled = enabled
        self.onPinchState = onPinchState
        self.onEnded = onEnded
    }

    public func makeUIGestureRecognizer(context: Context) -> GestureRecognizer {
        GestureRecognizer(simultaneous: simultaneous)
    }

    public func updateUIGestureRecognizer(_ recognizer: GestureRecognizer, context: Context) {
        recognizer.simultaneous = simultaneous
    }

    public func handleUIGestureRecognizerAction(_ recognizer: GestureRecognizer, context: Context) {
        guard isEnabled() else { return }
        let lower = domain.lowerBound.double
        let upper = domain.upperBound.double
        switch recognizer.interaction {
        case .pan(let x, let isInitial):
            if isInitial { leading = x }
            if let leading {
                let offset = (upper - lower) * (leading - x)
                domain = Bound(lower + offset)...Bound(upper + offset)
                self.leading = x
            }
        case .pinch(let leadingX, let trailingX, let isInitial):
            guard leadingX != trailingX else { return }
            if isInitial {
                let m = upper - lower
                leadingValue = (m * leadingX) + lower
                trailingValue = (m * trailingX) + lower
                onPinchState(true)
            }
            if let leadingValue, let trailingValue {
                let m = (trailingValue - leadingValue) / (trailingX - leadingX)
                let b = leadingValue - m * leadingX
                domain = Bound(b)...Bound(b + m)
            }
        case nil:
            onPinchState(false)
            onEnded()
        }
    }
}

// MARK: Internal gesture recognizer implementation
extension DomainXGesture {
    public class GestureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
        enum Interaction {
            case pan(x: Double, isInitial: Bool)
            case pinch(leadingX: CGFloat, trailingX: CGFloat, isInitial: Bool)
        }

        var simultaneous: Bool
        var interaction: Interaction?
        private var retainedTouches = Set<UITouch>()
        private var initialInteraction = true

        init(simultaneous: Bool) {
            self.simultaneous = simultaneous
            super.init(target: nil, action: nil)
            self.delegate = self
        }

        private func updateInteraction(isInitial: Bool) {
            guard let view else { return }
            let locations = retainedTouches.map { $0.location(in: view).x / view.frame.width }
            switch locations.count {
            case 1:
                interaction = .pan(x: locations.first!, isInitial: isInitial)
            case 2:
                interaction = .pinch(
                    leadingX: locations.min()!,
                    trailingX: locations.max()!,
                    isInitial: isInitial
                )
            default:
                break
            }
        }

        // MARK: UIGestureRecognizer overrides
        public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            switch retainedTouches.count + touches.count {
            case 1:
                retainedTouches.formUnion(touches)
                initialInteraction = true
                state = .began
            case 2:
                retainedTouches.formUnion(touches)
                initialInteraction = true
                state = .changed
            default:
                break
            }
        }

        public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            guard !retainedTouches.intersection(touches).isEmpty else { return }
            updateInteraction(isInitial: initialInteraction)
            initialInteraction = false
            state = .changed
        }

        public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            retainedTouches.subtract(touches)
            if retainedTouches.isEmpty {
                interaction = nil
                state = .ended
            } else {
                updateInteraction(isInitial: true)
            }
        }

        public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            retainedTouches.subtract(touches)
            if retainedTouches.isEmpty {
                interaction = nil
                state = .cancelled
            } else {
                updateInteraction(isInitial: true)
            }
        }

        // MARK: UIGestureRecognizerDelegate
        public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            simultaneous
        }
    }
}

// MARK: - Reusable zoomable chart
/// Generic SwiftUI view that renders a line chart with horizontal scrolling and pinch-to-zoom support.
/// It works with any data type that provides a `timestamp` and an `Identifiable` conformance.
struct MetricChartView<Point>: View where Point: Identifiable & Timestamped {
    // Data set to render
    let data: [Point]
    /// Closure that extracts the Y-axis value from `Point`.
    let value: (Point) -> Double
    /// Label for the Y-axis (e.g. "Speed (mph)")
    let yAxisLabel: String
    /// Height of the chart view (defaults to 200)
    let height: CGFloat

    /// Unit extracted from yAxisLabel if present (e.g., "mph" from "Speed (mph)")
    private var unitLabel: String {
        if let start = yAxisLabel.firstIndex(of: "("),
           let end = yAxisLabel.firstIndex(of: ")"), start < end {
            return String(yAxisLabel[yAxisLabel.index(after: start)..<end])
        }
        return ""
    }
    // Baseline timestamp to convert absolute dates to relative seconds
    private let base: Date
    // Total duration of the data set (seconds)
    private let totalDuration: TimeInterval
    // The currently visible horizontal domain (relative seconds)
    @State private var domain: ClosedRange<TimeInterval>
    /// Flag indicating if the user is currently inspecting a point (after long press)
    @State private var isSelecting: Bool = false
    /// Flag indicating if the user is currently performing a range selection (two-finger)
    @State private var isRangeSelecting: Bool = false
    /// Flag set while a pinch-zoom is in progress by DomainXGesture
    @State private var isZooming: Bool = false
    /// Raw X-value selected by built-in chart selection gesture (relative seconds)
    @State private var rawSelectedX: TimeInterval?
    /// Raw X-range selected by two-finger gesture (relative seconds)
    @State private var rawSelectedRange: ClosedRange<TimeInterval>?

    /// Nearest data point to the currently selected X value (if any)
    private var selectedPoint: Point? {
        guard let rawSelectedX else { return nil }
        // Convert relative seconds back to absolute timestamp
        let targetDate = base.addingTimeInterval(rawSelectedX)
        // Find the point whose timestamp is closest to the selected date
        return data.min(by: { abs($0.timestamp.timeIntervalSince(targetDate)) <
                              abs($1.timestamp.timeIntervalSince(targetDate)) })
    }
    
    init(data: [Point],
         value: @escaping (Point) -> Double,
         yAxisLabel: String,
         height: CGFloat = 200) {
        self.data = data
        self.value = value
        self.yAxisLabel = yAxisLabel
        self.height = height

        // Establish baseline and full-range domain
        let base = data.first?.timestamp ?? Date()
        let total = max(1, data.last?.timestamp.timeIntervalSince(base) ?? 1)
        self.base = base
        self.totalDuration = total
        _domain = State(initialValue: 0...total)
    }

    var body: some View {
        if data.isEmpty {
            Text("No data")
                .foregroundColor(.secondary)
        } else {
            // Create a binding that clamps any updates from the gesture so the domain
            // never moves outside the recorded time span.
            let clampedDomain = Binding<ClosedRange<TimeInterval>>(get: { domain }) { newValue in
                var new = newValue
                // If the range is wider than the total duration, just snap to full range
                if new.upperBound - new.lowerBound >= totalDuration {
                    new = 0...totalDuration
                }
                // Shift the range right if it goes past the left edge (0)
                if new.lowerBound < 0 {
                    let offset = -new.lowerBound
                    new = (new.lowerBound + offset)...(new.upperBound + offset)
                }
                // Shift the range left if it goes past the right edge (totalDuration)
                if new.upperBound > totalDuration {
                    let offset = new.upperBound - totalDuration
                    new = (new.lowerBound - offset)...(new.upperBound - offset)
                }
                // Final safety clamp
                new = max(0, new.lowerBound)...min(totalDuration, new.upperBound)
                domain = new
            }

            // Main chart with optional selection rule/tooltip
            Chart {
                // Primary line
                ForEach(data) { point in
                    LineMark(
                        x: .value("Time (s)", point.timestamp.timeIntervalSince(base)),
                        y: .value(yAxisLabel, value(point))
                    )
                }

                // Selection indicator & tooltip
                if !isRangeSelecting, let selectedPoint {
                    let relativeX = selectedPoint.timestamp.timeIntervalSince(base)

                    RuleMark(x: .value("Selected", relativeX))
                        .foregroundStyle(Color.gray.opacity(0.3))
                        .offset(yStart: -10)
                        .annotation(
                            position: .top,
                            spacing: 0,
                            overflowResolution: .init(
                                x: .fit(to: .chart),
                                y: .disabled)
                        ) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(String(format: "%.2f", value(selectedPoint))) \(unitLabel)")
                                    .font(.caption2.bold())
                                Text(String(format: "%.1f s", relativeX))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(uiColor: .systemBackground))
                                    .shadow(radius: 2)
                            )
                        }
                        
                }

                // Range highlight visuals
                if let r = rawSelectedRange {
                    let lower = r.lowerBound
                    let upper = r.upperBound
                    let mid  = (lower + upper) / 2

                    // Rule marks at bounds
                    RuleMark(x: .value("Start", lower))
                        .foregroundStyle(Color.accentColor.opacity(0.25))
                    RuleMark(x: .value("End", upper))
                        .foregroundStyle(Color.accentColor.opacity(0.25))

                    // Annotation in the middle
                    RuleMark(x: .value("Mid", mid))
                        .opacity(0) // invisible anchor for annotation
                        .annotation(
                            position: .top,
                            spacing: 0,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                        ) {
                            if let startPt = nearestPoint(relativeX: lower),
                               let endPt   = nearestPoint(relativeX: upper) {
                                let duration = upper - lower
                                // Pre-compute formatted strings to reduce expression complexity
                                let durationStr = String(format: "%.1f s", duration)
                                let startStr = String(format: "%.2f", value(startPt))
                                let endStr = String(format: "%.2f", value(endPt))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("⏱ \(durationStr)")
                                        .font(.caption2.bold())
                                    Text("📈 \(startStr) → \(endStr) \(unitLabel)")
                                        .font(.caption2)
                                }
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(uiColor: .systemBackground))
                                        .shadow(radius: 2)
                                )
                            }
                        }
                }
            }
            // Bind zoom/pan domain to x-scale
            .chartXScale(domain: clampedDomain.wrappedValue)
            .chartXAxisLabel("Time (s)")
            .chartYAxisLabel(yAxisLabel)
            // Custom one-finger long-press gesture for point selection
            .gesture(
                PointSelectGesture(
                    domain: clampedDomain,
                    selected: $rawSelectedX,
                    isSelecting: $isSelecting,
                    isZooming: $isZooming
                )
            )
            // Two-finger long-press –> drag for range selection
            .gesture(
                RangeXGesture(
                    domain: clampedDomain,
                    range: $rawSelectedRange,
                    isSelecting: $isRangeSelecting,
                    isZooming: $isZooming
                )
            )
            // Ensure rendered marks are clipped to the plotting rectangle so lines do not
            // extend beyond the visible chart area (especially noticeable when panning/zooming).
            .chartPlotStyle { plotArea in
                plotArea
                    .clipShape(HorizontalClipShape())
            }
            .frame(height: height)
            // Preserve custom pan/zoom gesture while allowing simultaneous recognition
            .gesture(
                DomainXGesture(
                    domain: clampedDomain,
                    simultaneous: true,
                    enabled: { !isSelecting && !isRangeSelecting },
                    onPinchState: { active in isZooming = active }
                )
            )
        }
    }

    // MARK: - One-finger point selection gesture
    private struct PointSelectGesture<Bound: ExpressibleByDouble>: UIGestureRecognizerRepresentable {
        @Binding private var domain: ClosedRange<Bound>
        @Binding private var selected: Bound?
        @Binding private var isSelecting: Bool
        @Binding private var isZooming: Bool

        init(domain: Binding<ClosedRange<Bound>>, selected: Binding<Bound?>, isSelecting: Binding<Bool>, isZooming: Binding<Bool>) {
            self._domain = domain
            self._selected = selected
            self._isSelecting = isSelecting
            self._isZooming = isZooming
        }

        // Recognizer: single-finger long press that continues as drag
        class GestureRecognizer: UILongPressGestureRecognizer, UIGestureRecognizerDelegate {
            override init(target: Any?, action: Selector?) {
                super.init(target: target, action: action)
                minimumPressDuration = 0.3
                numberOfTouchesRequired = 1
                // Keep default allowableMovement (~10pt) so a drag cancels the long-press.
                delegate = self
            }

            func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
                // Allow simultaneous recognition so other gestures (e.g., Domain pan/zoom) can still work when not selecting.
                return true
            }
        }

        // MARK: UIGestureRecognizerRepresentable
        func makeUIGestureRecognizer(context: Context) -> GestureRecognizer {
            GestureRecognizer(target: nil, action: nil)
        }

        func updateUIGestureRecognizer(_ recognizer: GestureRecognizer, context: Context) {}

        func handleUIGestureRecognizerAction(_ recognizer: GestureRecognizer, context: Context) {
            guard let view = recognizer.view else { return }

            // Ignore if a pinch-zoom is active
            if isZooming { return }

            let lowerDouble = domain.lowerBound.double
            let upperDouble = domain.upperBound.double
            let span = upperDouble - lowerDouble
            let normX = recognizer.location(in: view).x / view.frame.width
            let value = Bound(lowerDouble + span * Double(normX))

            switch recognizer.state {
            case .began:
                selected = value
                isSelecting = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case .changed:
                selected = value
                isSelecting = true
                // Provide subtle feedback as the finger moves across points
                UISelectionFeedbackGenerator().selectionChanged()
            default:
                selected = nil
                isSelecting = false
            }
        }
    }
}

// MARK: - Two-finger range selection gesture
private struct RangeXGesture<Bound: ExpressibleByDouble>: UIGestureRecognizerRepresentable {
    @Binding private var domain: ClosedRange<Bound>
    @Binding private var range: ClosedRange<Bound>?
    @Binding private var isSelecting: Bool
    @Binding private var isZooming: Bool

    init(domain: Binding<ClosedRange<Bound>>, range: Binding<ClosedRange<Bound>?>, isSelecting: Binding<Bool>, isZooming: Binding<Bool>) {
        self._domain = domain
        self._range = range
        self._isSelecting = isSelecting
        self._isZooming = isZooming
    }

    // Custom recognizer: two-finger long press that continues as drag
    class GestureRecognizer: UILongPressGestureRecognizer, UIGestureRecognizerDelegate {
        override init(target: Any?, action: Selector?) {
            super.init(target: target, action: action)
            minimumPressDuration = 0.3
            numberOfTouchesRequired = 2
            allowableMovement = 1000
            delegate = self
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Permit simultaneous recognition so we can begin even if DomainXGesture is already active.
            return true
        }
    }

    // MARK: UIGestureRecognizerRepresentable

    func makeUIGestureRecognizer(context: Context) -> GestureRecognizer {
        GestureRecognizer(target: nil, action: nil)
    }

    func updateUIGestureRecognizer(_ recognizer: GestureRecognizer, context: Context) {}

    func handleUIGestureRecognizerAction(_ recognizer: GestureRecognizer, context: Context) {
        guard let view = recognizer.view else { return }

        let lowerDouble = domain.lowerBound.double
        let upperDouble = domain.upperBound.double
        let span = upperDouble - lowerDouble

        func value(forTouch idx: Int) -> Bound? {
            guard idx < recognizer.numberOfTouches else { return nil }
            let normX = recognizer.location(ofTouch: idx, in: view).x / view.frame.width
            return Bound(lowerDouble + span * Double(normX))
        }

        switch recognizer.state {
        case .began, .changed:
            // Ignore if zooming is active
            if isZooming { return }
            guard let v0: Bound = value(forTouch: 0), let v1: Bound = value(forTouch: 1) else { return }
            range = min(v0, v1)...max(v0, v1)
            isSelecting = true

            // Haptics: medium impact on begin, subtle selection for subsequent updates
            if recognizer.state == .began {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } else {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        default:
            range = nil
            isSelecting = false
        }
    }
}

// MARK: - Helper to find nearest point
extension MetricChartView {
    private func nearestPoint(relativeX: TimeInterval) -> Point? {
        let targetDate = base.addingTimeInterval(relativeX)
        return data.min(by: { abs($0.timestamp.timeIntervalSince(targetDate)) <
                              abs($1.timestamp.timeIntervalSince(targetDate)) })
    }
}

// MARK: - Helper shape
/// A shape that clips horizontally (left/right) while allowing unlimited vertical overflow.
private struct HorizontalClipShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Extend far beyond vertical bounds so the clip only affects horizontal edges.
        let extendedRect = CGRect(x: rect.minX,
                                  y: rect.minY - 10_000,
                                  width: rect.width,
                                  height: rect.height + 20_000)
        return Path(extendedRect)
    }
}

#if DEBUG
// MARK: - Preview
struct MetricChartView_Previews: PreviewProvider {
    // Generate 2 minutes of sample speed data at 1 Hz
    static var sampleData: [SpeedPoint] {
        let base = Date()
        return (0..<120).map { i in
            SpeedPoint(
                timestamp: base.addingTimeInterval(Double(i)),
                speed: .random(in: 0...15), // m/s
                distance: Double(i)
            )
        }
    }

    static var previews: some View {
        MetricChartView(
            data: sampleData,
            value: { $0.speed * 2.23694 }, // convert to mph for display
            yAxisLabel: "Speed (mph)"
        )
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif 
