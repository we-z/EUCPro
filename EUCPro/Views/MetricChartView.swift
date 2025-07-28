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
    private let onEnded: () -> Void

    @State private var leading: Double?
    @State private var leadingValue: Double?
    @State private var trailingValue: Double?

    public init(
        domain: Binding<ClosedRange<Bound>>,
        simultaneous: Bool = false,
        onEnded: @escaping () -> () = {}
    ) {
        self._domain = domain
        self.simultaneous = simultaneous
        self.onEnded = onEnded
    }

    public func makeUIGestureRecognizer(context: Context) -> GestureRecognizer {
        GestureRecognizer(simultaneous: simultaneous)
    }

    public func updateUIGestureRecognizer(_ recognizer: GestureRecognizer, context: Context) {
        recognizer.simultaneous = simultaneous
    }

    public func handleUIGestureRecognizerAction(_ recognizer: GestureRecognizer, context: Context) {
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
            }
            if let leadingValue, let trailingValue {
                let m = (trailingValue - leadingValue) / (trailingX - leadingX)
                let b = leadingValue - m * leadingX
                domain = Bound(b)...Bound(b + m)
            }
        case nil:
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

    // Baseline timestamp to convert absolute dates to relative seconds
    private let base: Date
    // Total duration of the data set (seconds)
    private let totalDuration: TimeInterval
    // The currently visible horizontal domain (relative seconds)
    @State private var domain: ClosedRange<TimeInterval>
    /// Raw X-value selected by built-in chart selection gesture (relative seconds)
    @State private var rawSelectedX: TimeInterval?

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
                if let selectedPoint {
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
                                Text(String(format: "%.2f", value(selectedPoint)))
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
            }
            // Bind zoom/pan domain to x-scale
            .chartXScale(domain: clampedDomain.wrappedValue)
            .chartXAxisLabel("Time (s)")
            .chartYAxisLabel(yAxisLabel)
            // Enable built-in x-selection
            .chartXSelection(value: $rawSelectedX)
            // Ensure rendered marks are clipped to the plotting rectangle so lines do not
            // extend beyond the visible chart area (especially noticeable when panning/zooming).
            .chartPlotStyle { plotArea in
                plotArea
                    .clipShape(HorizontalClipShape())
            }
            .frame(height: height)
            // Preserve custom pan/zoom gesture while allowing simultaneous recognition
            .gesture(DomainXGesture(domain: clampedDomain, simultaneous: true))
        }
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
