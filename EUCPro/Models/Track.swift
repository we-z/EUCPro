import Foundation
import CoreLocation

struct Coordinate: Codable {
    let latitude: Double
    let longitude: Double
}

struct Track: Identifiable, Codable {
    let id: UUID
    let name: String
    let startFinish: Coordinate
    let waypoints: [Coordinate]
    
    init(name: String, startFinish: Coordinate, waypoints: [Coordinate] = []) {
        self.id = UUID()
        self.name = name
        self.startFinish = startFinish
        self.waypoints = waypoints
    }
    
    func startFinishLocation() -> CLLocation {
        CLLocation(latitude: startFinish.latitude, longitude: startFinish.longitude)
    }
} 