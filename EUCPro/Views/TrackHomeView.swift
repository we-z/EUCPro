import SwiftUI

struct TrackHomeView: View {
    @State private var selectedTrack: Track?
    @State private var showTrackSheet = false
    @State private var lapVM: LapViewModel? = nil
    @StateObject private var historyVM = HistoryViewModel()
    var lapRuns: [Run] { historyVM.runs.filter { $0.type == .lap } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    configSection
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.top)
                    if !lapRuns.isEmpty {
                        historySection
                    }
                }
                .padding()
            }
            .navigationTitle("Track")
            .sheet(isPresented: $showTrackSheet) {
                TrackSelectionView(selectedTrack: $selectedTrack)
            }
            .fullScreenCover(item: $lapVM) { vm in
                LapTimerView(viewModel: vm)
            }
        }
    }
    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Track")
                .font(.headline)
            HStack {
                Text(selectedTrack?.name ?? "None")
                Spacer()
                Button("Choose") { showTrackSheet = true }
            }
            Button {
                guard let track = selectedTrack else { return }
                lapVM = LapViewModel(track: track)
            } label: {
                Label("Start", systemImage: "timer.circle.fill")
                    .font(.title2)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedTrack == nil)
        }
    }
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History")
                .font(.headline)
            ForEach(lapRuns) { run in
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
    TrackHomeView()
} 
