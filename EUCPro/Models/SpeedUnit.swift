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
    var label: String { self == .mph ? "mph" : "km/h" }
} 