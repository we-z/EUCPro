import SwiftUI

struct StartView: View {
    @State private var selectedMode: RunType = .drag
    @State private var dragTargetSpeed: String = "60" // mph
    @State private var dragTargetDistance: String = ""
    @State private var selectedTrack: Track?
    @State private var showingTrackSelection = false
    
    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $selectedMode) {
                    Text("Drag").tag(RunType.drag)
                    Text("Lap").tag(RunType.lap)
                }
                .pickerStyle(.segmented)
                
                if selectedMode == .drag {
                    Section("Drag Configuration") {
                        TextField("Target Speed (mph)", text: $dragTargetSpeed)
                            .keyboardType(.decimalPad)
                        TextField("Target Distance (m)", text: $dragTargetDistance)
                            .keyboardType(.decimalPad)
                    }
                } else {
                    Section("Track") {
                        if let track = selectedTrack {
                            Text(track.name)
                        } else {
                            Text("None Selected")
                        }
                        Button("Select Track") {
                            showingTrackSelection = true
                        }
                    }
                }
                
                Section {
                    NavigationLink("Start") {
                        if selectedMode == .drag {
                            let mph = Double(dragTargetSpeed) ?? 60
                            let mps = mph * 0.44704
                            let dist = Double(dragTargetDistance)
                            DragMeasurementView(viewModel: DragViewModel(startSpeed: 0, targetSpeed: dist == nil ? mps : nil, targetDistance: dist))
                        } else {
                            if let track = selectedTrack {
                                LapTimerView(viewModel: LapViewModel(track: track))
                            } else {
                                Text("Select a track first")
                            }
                        }
                    }
                    .disabled(selectedMode == .lap && selectedTrack == nil)
                }
            }
            .navigationTitle("EUC Pro")
            .sheet(isPresented: $showingTrackSelection) {
                TrackSelectionView(selectedTrack: $selectedTrack)
            }
        }
        .onAppear {
            LocationManager.shared.requestAuthorization()
        }
    }
} 
