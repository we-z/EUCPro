import Foundation

enum SpeedUnit: String, CaseIterable, Identifiable, Codable {
    case mph
    case kmh
    var id: String { rawValue }
    
    func convert(mps: Double) -> Double {
        switch self {
        case .mph: return mps * 2.23694
        case .kmh: return mps * 3.6
        }
    }
    func convert(distanceMeters: Double) -> Double {
        switch self {
        case .mph: return distanceMeters * 0.000621371 // miles
        case .kmh: return distanceMeters / 1000 // km
        }
    }
    var distanceLabel: String {
        switch self {
        case .mph: return "mi"
        case .kmh: return "km"
        }
    }
    var label: String { self == .mph ? "mph" : "km/h" }
} 