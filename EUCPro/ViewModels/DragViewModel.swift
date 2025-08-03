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
    
    @Published var currentSpeed: Double = 0 // m/s
    @Published var hasGPSFix: Bool = false
    @Published var elapsed: Double = 0
    @Published var distance: Double = 0
    @Published var finishedMetrics: [String: Double]? = nil
    private var peakSpeedMph: Double = 0
    
    private var startTime: Date?
    private var lastGPSFixTime: Date = .distantPast
    private var startLocation: CLLocation?
    private var lastSampleLocation: CLLocation?
    // Removed filteredSpeed and smoothingFactor for real-time speed reporting
    private var speedPoints: [SpeedPoint] = []
    private var gpsSpeedPoints: [GPSPoint] = []
    private var accelData: [AccelPoint] = []
    private var recentAccelerationMagnitude: Double = 0
    private var stationaryCounter: Int = 0 // counts motion frames below threshold

    // (Removed pedometer fallback properties)
    private var cancellables = Set<AnyCancellable>()
    private var timerCancellable: AnyCancellable?
    private var loggingCancellable: AnyCancellable?
    private var lastLoggedSample: Date?
    
    private let locationManager = LocationManager.shared
    private let fusionManager = SpeedSmoothingManager.shared
    
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
        SpeedSmoothingManager.shared.reset()
        // Start 10-Hz logging timer
        loggingCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self, let _ = self.startTime else { return }
                // Ensure exactly 10 Hz by relying on timer; prevent overlaps if timer catch-up
                if let last = self.lastLoggedSample, now.timeIntervalSince(last) < 0.099 {
                    return
                }
                self.lastLoggedSample = now
                self.speedPoints.append(SpeedPoint(timestamp: now, speed: self.currentSpeed, distance: self.distance))
            }
    }
    
    func reset() {
        SpeedSmoothingManager.shared.reset()
        startTime = nil
        loggingCancellable?.cancel()
        lastLoggedSample = nil
        startLocation = nil
        elapsed = 0
        distance = 0
        speedPoints.removeAll()
        gpsSpeedPoints.removeAll()
        accelData.removeAll()
        finishedMetrics = nil
        peakSpeedMph = 0
        stationaryCounter = 0
        recentAccelerationMagnitude = 0
        
        // Clear all subscriptions to prevent interference with new sessions
        cancellables.removeAll()
        
        // Resubscribe to sensors after clearing
        subscribe()
        subscribeFusion()
        subscribeMotion()
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
        // High-rate fused speed -> UI (≈50 Hz)
        fusionManager.$fusedSpeedMps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] spd in
                guard let self else { return }
                let filtered = spd < 0.1 ? 0 : spd
                self.currentSpeed = filtered
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
                self.accelData.append(AccelPoint(timestamp: Date(), accel: mag))

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
    
    private func isValidGPSFix(_ location: CLLocation) -> Bool {
        // Accept fix with horizontal accuracy better than 15 m and a recent timestamp (<2 s old)
        return location.horizontalAccuracy >= 0 &&
               location.horizontalAccuracy < 15 &&
               abs(location.timestamp.timeIntervalSinceNow) < 2
    }
    
    private func handle(location: CLLocation) {
        guard isValidGPSFix(location) else {
            hasGPSFix = false
            // keep currentSpeed unchanged; fusion fallback will handle display
            return
        }
        hasGPSFix = true
        let mphFactor = 2.23694
        // Use Core Location's Doppler speed for simplicity; fallback to 0 if invalid (-1)
        var gpsSpeed = location.speed >= 0 ? location.speed : 0 // m/s
        // Stationary filtering – reject tiny speeds that are likely noise
        if gpsSpeed < 0.2 { gpsSpeed = 0 }

        // Log GPS speed data
        gpsSpeedPoints.append(GPSPoint(timestamp: Date(), speed: gpsSpeed))

        // Kalman already blends this GPS into fused stream.
        // We no longer override currentSpeed here to avoid glitching; the fused sink delivers high-rate view updates.
        lastGPSFixTime = Date()
        
        // Store for metrics.
        var internalSpeedMph = gpsSpeed * mphFactor
        if stationaryCounter > 25 && internalSpeedMph < 1.0 {
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
        loggingCancellable?.cancel()
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
                      gpsSpeedData: gpsSpeedPoints,
                      accelData: accelData,
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
        loggingCancellable?.cancel()
        peakSpeedMph = 0
        reset()
    }
} 