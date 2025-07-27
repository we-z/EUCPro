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
    // Zoom handling and gestures are now encapsulated in `MetricChartView`.
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
                // Speed chart
                if !run.speedData.isEmpty {
                    MetricChartView(
                        data: run.speedData,
                        value: { unit.convert(mps: $0.speed) },
                        yAxisLabel: "Speed (\(unit.label))"
                    )
                }
                // Acceleration chart
                if let acc = run.accelData, !acc.isEmpty {
                    MetricChartView(
                        data: acc,
                        value: { $0.accel },
                        yAxisLabel: "Acceleration (G)"
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