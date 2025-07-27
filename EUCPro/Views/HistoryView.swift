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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(run.title).font(.title2)
                ForEach(run.metrics.sorted(by: { $0.key < $1.key }), id: \ .key) { key, value in
                    HStack {
                        Text(key)
                        Spacer()
                        Text(String(format: "%.2f", value))
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

                        Map(initialPosition: .region(region), interactionModes: []) {
                            MapPolyline(coordinates: coords)
                                .stroke(Color.blue, lineWidth: 3)
                        }
                        .frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                if !run.speedData.isEmpty {
                    let baseSpeedTime = run.speedData.first?.timestamp ?? run.date
                    Chart(run.speedData) {
                        LineMark(x: .value("Time", $0.timestamp.timeIntervalSince(baseSpeedTime)),
                                 y: .value("Speed", $0.speed*3.6))
                    }
                    .chartXAxisLabel("Time (s)")
                    .chartYAxisLabel("Speed (km/h)")
                    .frame(height: 200)
                }
                if let acc = run.accelData, !acc.isEmpty {
                    let baseTime = acc.first?.timestamp ?? run.date
                    Chart(acc) {
                        LineMark(x: .value("Time", $0.timestamp.timeIntervalSince(baseTime)),
                                 y: .value("Accel", $0.accel))
                    }
                    .chartXAxisLabel("Time (s)")
                    .chartYAxisLabel("Acceleration (G)")
                    .frame(height: 200)
                }
            }.padding()
        }
        .navigationTitle("Run Details")
    }
} 