import Foundation
import Combine

final class DataStore: ObservableObject {
    static let shared = DataStore()
    
    @Published private(set) var runs: [Run] = []
    @Published private(set) var tracks: [Track] = []
    
    private let runsURL: URL
    private let tracksURL: URL
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        runsURL = documents.appendingPathComponent("runs.json")
        tracksURL = documents.appendingPathComponent("tracks.json")
        loadRuns()
        loadTracks()
        
        $runs
            .dropFirst()
            .debounce(for: .seconds(2), scheduler: DispatchQueue.global(qos: .utility))
            .sink { [weak self] _ in self?.saveRuns() }
            .store(in: &cancellables)
    }
    
    // MARK: - Runs
    func add(run: Run) {
        runs.insert(run, at: 0)
    }
    
    private func loadRuns() {
        if let data = try? Data(contentsOf: runsURL),
           let decoded = try? JSONDecoder().decode([Run].self, from: data) {
            runs = decoded
        }
    }
    
    private func saveRuns() {
        if let data = try? JSONEncoder().encode(runs) {
            try? data.write(to: runsURL)
        }
    }
    
    // MARK: - Tracks
    private func loadTracks() {
        if let data = try? Data(contentsOf: tracksURL),
           let decoded = try? JSONDecoder().decode([Track].self, from: data) {
            tracks = decoded
            return
        }
        if let bundleURL = Bundle.main.url(forResource: "Tracks", withExtension: "json"),
           let data = try? Data(contentsOf: bundleURL),
           let decoded = try? JSONDecoder().decode([Track].self, from: data) {
            tracks = decoded
        }
    }
    
    func add(track: Track) {
        tracks.append(track)
        saveTracks()
    }
    
    private func saveTracks() {
        if let data = try? JSONEncoder().encode(tracks) {
            try? data.write(to: tracksURL)
        }
    }
} 