import SwiftUI

struct TrackSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var store = DataStore.shared
    @Binding var selectedTrack: Track?
    var body: some View {
        NavigationStack {
            List {
                ForEach(store.tracks) { track in
                    Button {
                        selectedTrack = track
                        dismiss()
                    } label: {
                        HStack {
                            Text(track.name)
                            if selectedTrack?.id == track.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Tracks")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink("Add") { AddTrackView() }
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        // Capture the tracks being removed before deletion to update selection if needed
        let removed = offsets.map { store.tracks[$0] }
        store.deleteTracks(at: offsets)
        if let selected = selectedTrack, removed.contains(where: { $0.id == selected.id }) {
            selectedTrack = nil
        }
    }
}

struct AddTrackView: View {
    @Environment(\.dismiss) var dismiss
    // Observe the shared location manager so the UI updates as soon as a fix is obtained
    @ObservedObject private var locationManager = LocationManager.shared
    @State private var name: String = ""

    var body: some View {
        Form {
            Section(header: Text("Track Details")) {
                TextField("Track Name", text: $name)
            }

            Section {
                if let loc = locationManager.currentLocation {
                    Button {
                        let coordinate = Coordinate(latitude: loc.coordinate.latitude,
                                                    longitude: loc.coordinate.longitude)
                        let trackName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let finalName = trackName.isEmpty ? "Unnamed Track" : trackName
                        let track = Track(name: finalName, startFinish: coordinate)
                        DataStore.shared.add(track: track)
                        dismiss()
                    } label: {
                        Label("Use Current Location as Start/Finish", systemImage: "mappin.and.ellipse")
                    }
                    // Disable the button until the user provides a name
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    HStack {
                        ProgressView()
                        Text("Acquiring GPS location…")
                    }
                }
            }
        }
        .navigationTitle("New Track")
        .onAppear {
            // Ensure permission is requested if it hasn't been yet
            locationManager.requestAuthorization()
        }
    }
} 