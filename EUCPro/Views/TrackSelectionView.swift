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
            }
            .navigationTitle("Tracks")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink("Add") { AddTrackView() }
                }
            }
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