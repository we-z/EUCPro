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
    @State private var name: String = ""
    @State private var status: String = ""
    var body: some View {
        Form {
            TextField("Track Name", text: $name)
            Button("Use Current Location as Start/Finish") {
                guard let loc = LocationManager.shared.currentLocation else {
                    status = "Location not available"
                    return
                }
                let coordinate = Coordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
                let track = Track(name: name, startFinish: coordinate)
                DataStore.shared.add(track: track)
                dismiss()
            }
            if !status.isEmpty {
                Text(status).foregroundColor(.red)
            }
        }
        .navigationTitle("New Track")
    }
} 