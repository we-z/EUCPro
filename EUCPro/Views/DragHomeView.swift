import SwiftUI

struct DragHomeView: View {
    @State private var dragTargetSpeed: String = "40"
    @State private var dragTargetDistance: String = ""
    @State private var showRun = false
    @State private var runViewModel: DragViewModel? = nil
    @StateObject private var historyVM = HistoryViewModel()
    @Environment(\.horizontalSizeClass) var sizeClass
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    configSection
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.top)
                        .animation(.spring(), value: dragTargetSpeed+dragTargetDistance)
                    if !dragRuns.isEmpty {
                        historySection
                            .transition(.move(edge: .bottom))
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("Drag")
            .fullScreenCover(item: $runViewModel) { vm in
                DragMeasurementView(viewModel: vm)
            }
        }
    }
    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configure Run")
                .font(.headline)
            HStack {
                TextField("Target Speed (mph)", text: $dragTargetSpeed)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                Text("mph")
            }
            HStack {
                TextField("Target Distance (m)", text: $dragTargetDistance)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                Text("m")
            }
            Button {
                let mph = Double(dragTargetSpeed) ?? 60
                let mps = mph*0.44704
                let dist = Double(dragTargetDistance)
                runViewModel = DragViewModel(startSpeed: 0, targetSpeed: dist == nil ? mps : nil, targetDistance: dist)
            } label: {
                Label("Start", systemImage: "flag.circle.fill")
                    .font(.title2)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
    private var dragRuns: [Run] {
        historyVM.runs.filter { $0.type == .drag }
    }
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History")
                .font(.headline)
            ForEach(dragRuns) { run in
                NavigationLink {
                    RunDetailView(run: run)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(run.title)
                            Text(run.date, style: .date)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

#Preview {
    DragHomeView()
} 
