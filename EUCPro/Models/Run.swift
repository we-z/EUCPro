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

// GPS speed data point
struct GPSPoint: Codable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let speed: Double // m/s
}

// New: acceleration magnitude samples (G)
struct AccelPoint: Codable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let accel: Double // G
}

struct Run: Identifiable, Codable {
    let id: UUID
    let date: Date
    let type: RunType
    let title: String
    let metrics: [String: Double]
    let speedData: [SpeedPoint]
    let gpsSpeedData: [GPSPoint]?
    let accelData: [AccelPoint]?
    let trackName: String?
    // Optional array of coordinates representing the route path (for lap sessions)
    let route: [Coordinate]?
    
    init(date: Date = Date(),
         type: RunType,
         title: String,
         metrics: [String: Double],
         speedData: [SpeedPoint],
         gpsSpeedData: [GPSPoint]? = nil,
         accelData: [AccelPoint]? = nil,
         trackName: String? = nil,
         route: [Coordinate]? = nil) {
        self.id = UUID()
        self.date = date
        self.type = type
        self.title = title
        self.metrics = metrics
        self.speedData = speedData
        self.gpsSpeedData = gpsSpeedData
        self.accelData = accelData
        self.trackName = trackName
        self.route = route
    }
} 