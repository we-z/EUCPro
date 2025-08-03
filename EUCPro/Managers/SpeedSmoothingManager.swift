import Foundation
import Combine
import CoreLocation
import CoreMotion
import QuartzCore

/// Performs GPS speed smoothing to provide a smooth, low-latency speed
/// read-out that reacts quickly to changes yet rejects false motion caused
/// by GPS noise. The class can be treated as a black box that emits
/// `@Published` values on the main thread.
final class SpeedSmoothingManager: ObservableObject {
    // MARK: – Public, observable properties
    @Published private(set) var fusedSpeedMps: Double = 0           // metres / second
    @Published private(set) var fusedDistanceMeters: Double = 0     // metres
    @Published private(set) var fusedLocation: CLLocation?          // last GPS fix used in the smoothing
    @Published private(set) var fusedHeading: Double = 0            // degrees (0=N)
    @Published private(set) var stepCount: Int = 0                  // very rough pedometer for debugging

    // MARK: – Singleton
    static let shared = SpeedSmoothingManager()

    // MARK: – Private helpers
    private let location = LocationManager.shared
    private let motion    = MotionManager.shared
    private var displayLink: CADisplayLink?

    private var cancellables = Set<AnyCancellable>()
    
    // GPS smoothing parameters
    private var lastGPSSpeedMps: Double = 0.0
    private var filteredSpeedMps: Double = 0.0
    private var lastGPSLocation: CLLocation?
    private var lastUpdateTime: TimeInterval = 0

    private init() {
        subscribeSensors()
        setupUpdateLoop()
    }

    // MARK: – Lifecycle helpers
    func start() {
        location.start()
        motion.start()
    }

    func stop() {
        location.stop()
        motion.stop()
        displayLink?.invalidate()
        displayLink = nil
    }

    func reset() {
        fusedSpeedMps = 0
        fusedDistanceMeters = 0
        fusedLocation = nil
        fusedHeading = 0
        stepCount = 0
        lastGPSSpeedMps = 0.0
        filteredSpeedMps = 0.0
        lastGPSLocation = nil
        lastUpdateTime = 0
    }

    // MARK: – Sensor subscription
    private func subscribeSensors() {
        // Subscribe to GPS location updates
        location.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.handleGPSUpdate(location: location)
            }
            .store(in: &cancellables)
            
        // Keep accelerometer data for analysis but don't use for speed calculation
        motion.$userAcceleration
            .sink { [weak self] acceleration in
                // Store accelerometer data for later analysis but don't use for speed calculation
                let accMag = sqrt(acceleration.x * acceleration.x + acceleration.y * acceleration.y + acceleration.z * acceleration.z)
                if accMag > 1.2 { // Step detection threshold
                    DispatchQueue.main.async {
                        self?.stepCount += 1
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: – GPS handling
    private func handleGPSUpdate(location: CLLocation) {
        // Validate GPS fix quality
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 10 else { return }
        guard location.speed >= 0 else { return } // Valid Doppler speed
        
        // Store raw GPS speed for smoothing
        lastGPSSpeedMps = max(location.speed, 0)
        lastGPSLocation = location
        lastUpdateTime = Date().timeIntervalSince1970
        
        // Update fused location and heading
        DispatchQueue.main.async {
            self.fusedLocation = location
            if location.course >= 0 {
                self.fusedHeading = location.course
            }
        }
    }
    
    // MARK: – High-frequency update loop
    private func setupUpdateLoop() {
        displayLink = CADisplayLink(target: self, selector: #selector(updateSmoothedSpeed))
        displayLink?.preferredFramesPerSecond = 100
        displayLink?.add(to: .main, forMode: .default)
    }
    
    @objc private func updateSmoothedSpeed() {
        // Low-pass filter with alpha smoothing
        let alpha = 0.01
        filteredSpeedMps = alpha * lastGPSSpeedMps + (1 - alpha) * filteredSpeedMps
        
        // Clamp to zero for very small speeds
        let finalSpeedMps = filteredSpeedMps < 0.1 ? 0 : filteredSpeedMps
        
        // Update distance using trapezoidal integration
        let now = Date().timeIntervalSince1970
        if lastUpdateTime > 0 {
            let dt = now - lastUpdateTime
            fusedDistanceMeters += finalSpeedMps * dt
        }
        lastUpdateTime = now
        
        DispatchQueue.main.async {
            self.fusedSpeedMps = finalSpeedMps
        }
    }
}
