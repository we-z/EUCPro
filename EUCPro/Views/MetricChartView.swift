import SwiftUI
import Charts

// MARK: - Timestamped helper
/// A lightweight protocol for time-series data points.
protocol Timestamped {
    var timestamp: Date { get }
}

// Conform existing models
extension SpeedPoint: Timestamped {}
extension AccelPoint: Timestamped {}

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

    // Available preset window sizes for the X-axis (seconds)
    let intervals: [Double]

    // Currently selected span along the X-axis (seconds)
    @State private var visibleLength: Double

    init(data: [Point],
         value: @escaping (Point) -> Double,
         yAxisLabel: String,
         height: CGFloat = 200,
         intervals: [Double] = [5, 10, 30, 60, 300]) {
        self.data = data
        self.value = value
        self.yAxisLabel = yAxisLabel
        self.height = height
        self.intervals = intervals

        // Default to showing the full duration of the data set
        let base = data.first?.timestamp ?? Date()
        let total = max(1, data.last?.timestamp.timeIntervalSince(base) ?? 1)
        _visibleLength = State(initialValue: total)
    }

    var body: some View {
        if data.isEmpty {
            Text("No data")
                .foregroundColor(.secondary)
        } else {
            let base = data.first!.timestamp
            let total = max(1, data.last!.timestamp.timeIntervalSince(base))
            let current = max(1, min(total, visibleLength))

            VStack(spacing: 10) {
                Chart(data) { point in
                    LineMark(
                        x: .value("Time", point.timestamp.timeIntervalSince(base)),
                        y: .value(yAxisLabel, value(point))
                    )
                }
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: current)
                .chartXAxisLabel("Time (s)")
                .chartYAxisLabel(yAxisLabel)
                .frame(height: height)

                // Interval selection controls
                HStack {
                    ForEach(intervals, id: \.self) { interval in
                        Button(action: {
                            visibleLength = interval
                        }) {
                            Text(label(for: interval))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(interval == visibleLength ? .accentColor.opacity(0.1) : .clear)
                    }
                }
            }
        }
    }

    // Helper that turns a time interval (seconds) into a human-readable label
    private func label(for seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        } else {
            return String(format: "%.0fm", seconds / 60)
        }
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
