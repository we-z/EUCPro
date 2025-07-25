import Foundation
import Combine
import CoreLocation

final class DragViewModel: ObservableObject {
    let startSpeed: Double // m/s
    let targetSpeed: Double?
    let targetDistance: Double?
    
    @Published var currentSpeed: Double = 0 // mph
    @Published var elapsed: Double = 0
    @Published var distance: Double = 0
    @Published var finishedMetrics: [String: Double]? = nil
    
    private var startTime: Date?
    private var startLocation: CLLocation?
    private var lastSampleLocation: CLLocation?
    private var filteredSpeed: Double = 0 // m/s
    private let smoothingFactor: Double = 0.2
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
    
    private func subscribe() {
        locationManager.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] loc in
                self?.handle(location: loc)
            }
            .store(in: &cancellables)
    }
    
    private func handle(location: CLLocation) {
        let mphFactor = 2.23694
        // Use Core Location's Doppler speed for simplicity; fallback to 0 if invalid (-1)
        let gpsSpeed = location.speed >= 0 ? location.speed : 0 // m/s

        // Simple exponential smoothing to reduce jitter
        filteredSpeed = smoothingFactor * gpsSpeed + (1 - smoothingFactor) * filteredSpeed
        currentSpeed = filteredSpeed * mphFactor // mph

        // Debug logging
        print(String(format: "GPS raw %.2f m/s (%.2f mph) | filtered %.2f mph | horizAcc %.1f m", gpsSpeed, gpsSpeed*mphFactor, currentSpeed, location.horizontalAccuracy))
        let now = Date()
        
        let speedThreshold = 0.44704 // 1 mph in m/s

        if startTime == nil {
            if gpsSpeed >= speedThreshold {
                startTime = now
                startLocation = location
                lastSampleLocation = location
                speedPoints.append(SpeedPoint(timestamp: now, speed: filteredSpeed, distance: 0))
            }
            return
        }
        guard let startTime else { return }

        elapsed = now.timeIntervalSince(startTime)

        if let last = lastSampleLocation {
            let ds = location.distance(from: last)
            // Ignore noise below horizontal accuracy
            if ds >= location.horizontalAccuracy {
                distance += ds
            }
            lastSampleLocation = location
        }
        speedPoints.append(SpeedPoint(timestamp: now, speed: filteredSpeed, distance: distance))
        print(String(format: "Δdist %.2f m | total %.2f m", distance, distance))
        
        if let targetSpeed = targetSpeed, filteredSpeed >= targetSpeed {
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
            "Distance_m": distance,
            "PeakSpeed_mph": currentSpeed
        ]
        if let targetSpeed = targetSpeed {
            metrics["TargetSpeed_mph"] = targetSpeed * 2.23694
        }
        finishedMetrics = metrics
        let run = Run(type: .drag,
                      title: "Drag " + DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short),
                      metrics: metrics,
                      speedData: speedPoints,
                      trackName: nil)
        DataStore.shared.add(run: run)
    }
    
    // Called from UI stop button to save partial run and reset
    func manualStop() {
        if finishedMetrics == nil {
            finish()
        }
    }
    
    func stop() {
        LocationManager.shared.stop()
        reset()
    }
} 