import Foundation

enum RunType: String, Codable, CaseIterable, Identifiable {
    case drag = "Drag"
    case lap = "Lap"
    var id: String { rawValue }
}

struct SpeedPoint: Codable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let speed: Double // m/s
    let distance: Double // meters
}

struct Run: Identifiable, Codable {
    let id: UUID
    let date: Date
    let type: RunType
    let title: String
    let metrics: [String: Double]
    let speedData: [SpeedPoint]
    let trackName: String?
    
    init(date: Date = Date(),
         type: RunType,
         title: String,
         metrics: [String: Double],
         speedData: [SpeedPoint],
         trackName: String? = nil) {
        self.id = UUID()
        self.date = date
        self.type = type
        self.title = title
        self.metrics = metrics
        self.speedData = speedData
        self.trackName = trackName
    }
} 