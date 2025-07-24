import Foundation
import Combine
import CoreLocation

final class DragViewModel: ObservableObject {
    let startSpeed: Double // m/s
    let targetSpeed: Double?
    let targetDistance: Double?
    
    @Published var currentSpeed: Double = 0
    @Published var elapsed: Double = 0
    @Published var distance: Double = 0
    @Published var finishedMetrics: [String: Double]? = nil
    
    private var startTime: Date?
    private var startLocation: CLLocation?
    private var speedPoints: [SpeedPoint] = []
    private var cancellables = Set<AnyCancellable>()
    
    private let locationManager = LocationManager.shared
    
    init(startSpeed: Double = 0, targetSpeed: Double? = nil, targetDistance: Double? = nil) {
        self.startSpeed = startSpeed
        self.targetSpeed = targetSpeed
        self.targetDistance = targetDistance
        subscribe()
    }
    
    func reset() {
        startTime = nil
        startLocation = nil
        elapsed = 0
        distance = 0
        speedPoints.removeAll()
        finishedMetrics = nil
    }
    
    func stop() {
        LocationManager.shared.stop()
    }
    
    private func subscribe() {
        locationManager.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] loc in
                self?.handle(location: loc)
            }
            .store(in: &cancellables)
    }
    
    private func handle(location: CLLocation) {
        currentSpeed = max(location.speed, 0) * 3.6 // km/h
        let now = Date()
        
        if startTime == nil {
            if location.speed >= startSpeed {
                startTime = now
                startLocation = location
                speedPoints.append(SpeedPoint(timestamp: now, speed: location.speed, distance: 0))
            }
            return
        }
        guard let startTime, let startLocation else { return }
        elapsed = now.timeIntervalSince(startTime)
        distance = location.distance(from: startLocation)
        speedPoints.append(SpeedPoint(timestamp: now, speed: location.speed, distance: distance))
        
        if let targetSpeed = targetSpeed, location.speed >= targetSpeed {
            finish()
        }
        if let targetDistance = targetDistance, distance >= targetDistance {
            finish()
        }
    }
    
    private func finish() {
        if finishedMetrics != nil { return }
        stop()
        var metrics: [String: Double] = [
            "Elapsed": elapsed,
            "Distance": distance
        ]
        if let targetSpeed = targetSpeed {
            metrics["TargetSpeed(m/s)"] = targetSpeed
        }
        finishedMetrics = metrics
        let run = Run(type: .drag,
                      title: "Drag " + DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short),
                      metrics: metrics,
                      speedData: speedPoints,
                      trackName: nil)
        DataStore.shared.add(run: run)
    }
} 