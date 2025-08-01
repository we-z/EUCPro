import Foundation
import CoreLocation
import Combine
import CoreMotion

final class LapViewModel: ObservableObject, Identifiable {
    let id = UUID()
    let track: Track
    @Published var currentSpeed: Double = 0 // m/s
    @Published var hasGPSFix: Bool = false
    @Published var currentLapTime: Double = 0
    @Published var completedLaps: [Double] = []
    @Published var predictiveLap: Double = 0
    
    private var startLocation: CLLocation
    private var lastCrossTime: Date?
    private var cancellables = Set<AnyCancellable>()
    private var speedPoints: [SpeedPoint] = []
    private var gpsSpeedPoints: [GPSPoint] = []
    private var accelData: [AccelPoint] = []
    private var timerCancellable: AnyCancellable?
    private var loggingCancellable: AnyCancellable?
    private var lastLoggedSample: Date?
    // Collect route coordinates for mapping
    private var route: [Coordinate] = []
    
    private let locationManager = LocationManager.shared
    private let fusionManager = SpeedSmoothingManager.shared
    
    init(track: Track) {
        self.track = track
        self.startLocation = track.startFinishLocation()
        lastCrossTime = Date()
        timerCancellable = Timer.publish(every: 0.02, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let last = self.lastCrossTime else { return }
                self.currentLapTime = Date().timeIntervalSince(last)
            }
        subscribe()
        subscribeFusion()
        subscribeMotion()
        // Start 10-Hz logging timer
        loggingCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self, let _ = self.lastCrossTime else { return }
                // Ensure exactly 10 Hz by relying on timer; prevent overlaps if timer catch-up
                if let last = self.lastLoggedSample, now.timeIntervalSince(last) < 0.099 {
                    return
                }
                self.lastLoggedSample = now
                self.speedPoints.append(SpeedPoint(timestamp: now, speed: self.currentSpeed, distance: 0))
            }
    }
    
    private func subscribe() {
        locationManager.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.handle(location: location)
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
    }
    
    private func subscribeMotion() {
        MotionManager.shared.$userAcceleration
            .sink { [weak self] acc in
                guard let self else { return }
                let mag = sqrt(acc.x * acc.x + acc.y * acc.y + acc.z * acc.z)
                self.accelData.append(AccelPoint(timestamp: Date(), accel: mag))
            }
            .store(in: &cancellables)
    }
    
    private func isValidGPSFix(_ location: CLLocation) -> Bool {
        // Accept fix with horizontal accuracy better than 15 m and a recent timestamp (<2 s old)
        return location.horizontalAccuracy >= 0 &&
               location.horizontalAccuracy < 15 &&
               abs(location.timestamp.timeIntervalSinceNow) < 2
    }
    
    private func handle(location: CLLocation) {
        // Update GPS fix status
        hasGPSFix = isValidGPSFix(location)
        
        // Store speed in m/s (Core Location already reports m/s)
        var gpsSpeed = max(location.speed, 0)
        // Stationary filtering – reject tiny speeds that are likely noise
        if gpsSpeed < 0.2 { gpsSpeed = 0 }
        
        // Log GPS speed data
        gpsSpeedPoints.append(GPSPoint(timestamp: Date(), speed: gpsSpeed))
        
        if let last = lastCrossTime {
            currentLapTime = Date().timeIntervalSince(last)
        }
        let distanceToStart = location.distance(from: startLocation)
        if distanceToStart < 10 {
            if let last = lastCrossTime, Date().timeIntervalSince(last) > 5 {
                completedLaps.append(Date().timeIntervalSince(last))
                lastCrossTime = Date()
                predictiveLap = predictive()
            } else if lastCrossTime == nil {
                lastCrossTime = Date()
                // start timer
                timerCancellable = Timer.publish(every: 0.02, on: .main, in: .common)
                    .autoconnect()
                    .sink { [weak self] _ in
                        guard let self, let last = self.lastCrossTime else { return }
                        self.currentLapTime = Date().timeIntervalSince(last)
                    }
            }
        }
        if lastCrossTime != nil {
            let distance = location.distance(from: startLocation)
            // Append coordinate to route
            route.append(Coordinate(latitude: location.coordinate.latitude,
                                    longitude: location.coordinate.longitude))
        }
    }
    
    private func predictive() -> Double {
        guard let lastLap = completedLaps.last else { return 0 }
        let avg = completedLaps.reduce(0, +) / Double(completedLaps.count)
        if currentLapTime == 0 { return avg }
        let ratio = currentLapTime / lastLap
        return avg * ratio
    }
    
    func finishSession() {
        guard !completedLaps.isEmpty else { return }
        timerCancellable?.cancel()
        loggingCancellable?.cancel()
        let metrics: [String: Double] = [
            "Best Lap": completedLaps.min() ?? 0,
            "Average Lap": completedLaps.reduce(0, +)/Double(completedLaps.count),
            "Total Laps": Double(completedLaps.count)
        ]
        let run = Run(type: .lap,
                      title: track.name + " " + DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short),
                      metrics: metrics,
                      speedData: speedPoints,
                      gpsSpeedData: gpsSpeedPoints,
                      accelData: accelData,
                      trackName: track.name,
                      route: route)
        DataStore.shared.add(run: run)
    }
} 