import Foundation
import Combine
import CoreLocation
import CoreMotion
import simd
// NEW: Sensor fusion for accurate indoor/outdoor speed
import CoreLocation

final class DragViewModel: ObservableObject, Identifiable {
    let id = UUID()
    let startSpeed: Double // m/s
    let targetSpeed: Double?
    let targetDistance: Double?
    
    @Published var currentSpeed: Double = 0 // mph
    @Published var elapsed: Double = 0
    @Published var distance: Double = 0
    @Published var finishedMetrics: [String: Double]? = nil
    private var peakSpeedMph: Double = 0
    
    private var startTime: Date?
    private var startLocation: CLLocation?
    private var lastSampleLocation: CLLocation?
    // Removed filteredSpeed and smoothingFactor for real-time speed reporting
    private var speedPoints: [SpeedPoint] = []
    private var recentAccelerationMagnitude: Double = 0
    private var stationaryCounter: Int = 0 // counts motion frames below threshold

    // (Removed pedometer fallback properties)
    private var cancellables = Set<AnyCancellable>()
    private var timerCancellable: AnyCancellable?
    
    private let locationManager = LocationManager.shared
    private let fusionManager = SensorFusionManager.shared
    
    init(startSpeed: Double = 0, targetSpeed: Double? = nil, targetDistance: Double? = nil) {
        self.startSpeed = startSpeed
        self.targetSpeed = targetSpeed
        self.targetDistance = targetDistance
        startTime = Date()
        timerCancellable = Timer.publish(every: 0.02, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let st = self.startTime else { return }
                self.elapsed = Date().timeIntervalSince(st)
            }
        subscribe()
        subscribeFusion()
        subscribeMotion()
        // Pedometer support removed – no longer needed
        SensorFusionManager.shared.reset()
    }
    
    func reset() {
        SensorFusionManager.shared.reset()
        startTime = nil
        startLocation = nil
        elapsed = 0
        distance = 0
        speedPoints.removeAll()
        finishedMetrics = nil
        peakSpeedMph = 0
    }
    
    private func subscribe() {
        locationManager.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] loc in
                self?.handle(location: loc)
            }
            .store(in: &cancellables)
    }
    
    private func subscribeFusion() {
        // Map fused speed to currentSpeed (m/s)
        fusionManager.$fusedSpeedMps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mps in
                guard let self else { return }
                self.currentSpeed = mps
                let mph = mps * 2.23694
                if mph > self.peakSpeedMph { self.peakSpeedMph = mph }
            }
            .store(in: &cancellables)

        // Track distance using fusedDistanceMeters
        fusionManager.$fusedDistanceMeters
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dist in
                guard let self else { return }
                if dist > self.distance {
                    self.distance = dist
                }
            }
            .store(in: &cancellables)
    }
    
    private func subscribeMotion() {
        MotionManager.shared.$userAcceleration
            .sink { [weak self] acc in
                guard let self else { return }
                let mag = sqrt(acc.x * acc.x + acc.y * acc.y + acc.z * acc.z)
                self.recentAccelerationMagnitude = mag

                // Simple stationary detector
                if mag < 0.05 {
                    self.stationaryCounter += 1
                } else {
                    self.stationaryCounter = 0
                }
            }
            .store(in: &cancellables)
    }

    // Pedometer support removed – no longer needed
    private func handle(location: CLLocation) {
        let mphFactor = 2.23694
        // Use Core Location's Doppler speed for simplicity; fallback to 0 if invalid (-1)
        let gpsSpeed = location.speed >= 0 ? location.speed : 0 // m/s

        // Keep using GPS speed internally for metrics but don't override currentSpeed;
        // currentSpeed is now driven by the fused sensor stream for maximum accuracy.
        var internalSpeedMph = gpsSpeed * mphFactor
        if stationaryCounter > 25 && internalSpeedMph < 3.0 {
            internalSpeedMph = 0
        }

        if internalSpeedMph > peakSpeedMph {
            peakSpeedMph = internalSpeedMph
        }

        // Debug logging (currentSpeed now in m/s)
        print(String(format: "GPS raw %.2f m/s | fused %.2f m/s | horizAcc %.1f m", gpsSpeed, currentSpeed, location.horizontalAccuracy))
        let now = Date()
        
        let speedThreshold = 0.44704 // 1 mph in m/s

        if startTime == nil {
            if gpsSpeed >= speedThreshold {
                startTime = now
                startLocation = location
                lastSampleLocation = location
                speedPoints.append(SpeedPoint(timestamp: now, speed: gpsSpeed, distance: 0))

                // start high-freq timer for elapsed updates
                timerCancellable = Timer.publish(every: 0.02, on: .main, in: .common)
                    .autoconnect()
                    .sink { [weak self] _ in
                        guard let self, let st = self.startTime else { return }
                        self.elapsed = Date().timeIntervalSince(st)
                    }
            }
            return
        }
        guard let startTime else { return }

        elapsed = now.timeIntervalSince(startTime)

        var gpsDistance: Double = 0
        if let startLocation {
            gpsDistance = location.distance(from: startLocation)
        }

        // Replace pedometer fallback with GPS distance only
        distance = gpsDistance

        speedPoints.append(SpeedPoint(timestamp: now, speed: gpsSpeed, distance: distance))
        print(String(format: "Δdist %.2f m | total %.2f m", distance, distance))
        
        if let targetSpeed = targetSpeed, gpsSpeed >= targetSpeed {
            finish()
        }
        if let targetDistance = targetDistance, distance >= targetDistance {
            finish()
        }
    }
    
    private func finish() {
        if finishedMetrics != nil { return }
        timerCancellable?.cancel()
        var metrics: [String: Double] = [
            "Elapsed": elapsed,
            "Distance_m": distance,
            "PeakSpeed_mph": peakSpeedMph
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
        // stop location updates after saving
        LocationManager.shared.stop()
    }
    
    // Called from UI stop button to save partial run and reset
    func manualStop() {
        if finishedMetrics == nil {
            finish()
        }
    }
    
    func stop() {
        LocationManager.shared.stop()
        timerCancellable?.cancel()
        peakSpeedMph = 0
        reset()
    }
} 