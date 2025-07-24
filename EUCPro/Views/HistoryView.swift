import SwiftUI
import Charts

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
                if !run.speedData.isEmpty {
                    Chart(run.speedData) {
                        LineMark(x: .value("Distance", $0.distance), y: .value("Speed", $0.speed*3.6))
                    }.frame(height: 200)
                }
            }.padding()
        }
        .navigationTitle("Run Details")
    }
} 