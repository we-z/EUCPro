import SwiftUI
import Charts
import MapKit

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @State private var sharingCSV: URL?
    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.runs) { run in
                    NavigationLink {
                        RunDetailView(run: run)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(run.title)
                            Text(run.date, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        exportCSV()
                    } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
            .sheet(item: $sharingCSV) { url in
                ShareSheet(activityItems: [url])
            }
        }
    }
    private func exportCSV() {
        let csvString = viewModel.runs.reduce("Title,Date,Type,Metrics\n") { partial, run in
            let metricString = run.metrics.map { "\($0.key):\($0.value)" }.joined(separator: "|")
            return partial + "\(run.title),\(run.date),\(run.type.rawValue),\(metricString)\n"
        }
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("runs.csv")
        try? csvString.write(to: tmpURL, atomically: true, encoding: .utf8)
        sharingCSV = tmpURL
    }
}

struct RunDetailView: View {
    let run: Run
    @AppStorage("speedUnit") private var speedUnitRaw: String = SpeedUnit.kmh.rawValue
    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnitRaw) ?? .mph }
    // Visible span (in seconds) for the X-axis of the speed and acceleration charts.
    @State private var speedVisibleLength: Double
    @State private var accelVisibleLength: Double

    // Temporary magnification during an active pinch gesture (resets to 1 afterwards)
    @GestureState private var speedMagnifyBy: CGFloat = 1
    @GestureState private var accelMagnifyBy: CGFloat = 1

    // Custom initializer to compute default visible lengths based on data duration
    init(run: Run) {
        self.run = run

        // Compute total speed duration
        let speedStart = run.speedData.first?.timestamp ?? run.date
        let speedEnd = run.speedData.last?.timestamp ?? run.date
        var speedDur = speedEnd.timeIntervalSince(speedStart)
        if speedDur <= 0 { speedDur = 10 }

        // Compute total acceleration duration (if accel data present)
        let accStart = run.accelData?.first?.timestamp ?? run.date
        let accEnd = run.accelData?.last?.timestamp ?? run.date
        var accDur = accEnd.timeIntervalSince(accStart)
        if accDur <= 0 { accDur = 10 }

        _speedVisibleLength = State(initialValue: speedDur)
        _accelVisibleLength = State(initialValue: accDur)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(run.title).font(.title2)
                // Display metrics converted to preferred units where applicable
                ForEach(convertedMetrics().sorted(by: { $0.key < $1.key }), id: \ .key) { key, value in
                    HStack {
                        Text(key)
                        Spacer()
                        Text(value)
                    }
                }
                // Map of route for lap sessions
                if run.type == .lap, let route = run.route, route.count > 1 {
                    let coords = route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }

                    // Compute simple bounding region that fits the route
                    let lats = coords.map { $0.latitude }
                    let lons = coords.map { $0.longitude }
                    if let minLat = lats.min(), let maxLat = lats.max(),
                       let minLon = lons.min(), let maxLon = lons.max() {
                        let center = CLLocationCoordinate2D(latitude: (minLat+maxLat)/2,
                                                             longitude: (minLon+maxLon)/2)
                        let span = MKCoordinateSpan(latitudeDelta: max(0.001, (maxLat-minLat)*1.4),
                                                    longitudeDelta: max(0.001, (maxLon-minLon)*1.4))
                        let region = MKCoordinateRegion(center: center, span: span)

                        Map(initialPosition: .region(region), interactionModes: [.zoom, .pan]) {
                            MapPolyline(coordinates: coords)
                                .stroke(Color.blue, lineWidth: 3)

                            // Annotate speed at each logged coordinate (every Nth to reduce clutter)
                            let paired = Array(zip(coords, run.speedData))
                            ForEach(Array(paired.enumerated()), id: \ .offset) { idx, pair in
                                let (coord, spd) = pair
                                // Show every ~10th point to avoid hundreds of markers
                                if idx % 10 == 0 {
                                    Annotation(coordinate: coord) {
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 6, height: 6)
                                    } label: {
                                        Text(String(format: "%.0f", unit.convert(mps: spd.speed)))
                                            .font(.caption2)
                                            .padding(2)
                                            .background(.thinMaterial)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                            }
                        }
                        .frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                if !run.speedData.isEmpty {
                    let baseSpeedTime = run.speedData.first?.timestamp ?? run.date
                    // Total time span of the recording – used to clamp zoom limits
                    let totalSpeedDuration = run.speedData.last?.timestamp.timeIntervalSince(baseSpeedTime) ?? 1
                    // Effective visible span reflects ongoing pinch gesture
                    let currentSpeedLength = max(1, min(totalSpeedDuration, speedVisibleLength / Double(speedMagnifyBy)))

                    Chart(run.speedData) {
                        LineMark(x: .value("Time", $0.timestamp.timeIntervalSince(baseSpeedTime)),
                                 y: .value("Speed", unit.convert(mps: $0.speed)))
                    }
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: currentSpeedLength)
                    .chartXAxisLabel("Time (s)")
                    .chartYAxisLabel("Speed (\(unit.label))")
                    .frame(height: 200)
                    // Pinch-to-zoom gesture that updates continuously
                    .highPriorityGesture(
                        MagnifyGesture()
                            .updating($speedMagnifyBy) { value, state, _ in
                                state = value.magnification
                            }
                            .onEnded { value in
                                var newLength = speedVisibleLength / value.magnification
                                newLength = max(1, min(totalSpeedDuration, newLength))
                                speedVisibleLength = newLength
                            }
                    )
                }
                if let acc = run.accelData, !acc.isEmpty {
                    let baseTime = acc.first?.timestamp ?? run.date
                    let totalAccDuration = acc.last?.timestamp.timeIntervalSince(baseTime) ?? 1
                    let currentAccelLength = max(1, min(totalAccDuration, accelVisibleLength / Double(accelMagnifyBy)))

                    Chart(acc) {
                        LineMark(x: .value("Time", $0.timestamp.timeIntervalSince(baseTime)),
                                 y: .value("Accel", $0.accel))
                    }
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: currentAccelLength)
                    .chartXAxisLabel("Time (s)")
                    .chartYAxisLabel("Acceleration (G)")
                    .frame(height: 200)
                    // Pinch-to-zoom for the acceleration chart (continuous)
                    .highPriorityGesture(
                        MagnifyGesture()
                            .updating($accelMagnifyBy) { value, state, _ in
                                state = value.magnification
                            }
                            .onEnded { value in
                                var newLength = accelVisibleLength / value.magnification
                                newLength = max(1, min(totalAccDuration, newLength))
                                accelVisibleLength = newLength
                            }
                    )
                }
            }.padding()
        }
        .navigationTitle("Run Details")
    }

    // Converts metrics based on selected unit; returns dictionary key->formatted string
    private func convertedMetrics() -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in run.metrics {
            var displayKey = key
            var displayValue = value
            // Speed conversions
            if key.hasSuffix("_mph") {
                if unit == .kmh {
                    displayValue = value * 1.60934
                    displayKey = key.replacingOccurrences(of: "_mph", with: "_kmh")
                }
            } else if key.hasSuffix("_kmh") {
                if unit == .mph {
                    displayValue = value / 1.60934
                    displayKey = key.replacingOccurrences(of: "_kmh", with: "_mph")
                }
            }
            // Distance conversions (meters -> km or mi)
            if key.hasSuffix("_m") {
                let converted = unit.convert(distanceMeters: value)
                displayValue = converted
                displayKey = key.replacingOccurrences(of: "_m", with: "_\(unit.distanceLabel)")
            }
            result[displayKey] = String(format: "%.2f", displayValue)
        }
        return result
    }
} 