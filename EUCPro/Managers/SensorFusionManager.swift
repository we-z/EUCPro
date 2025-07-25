import Foundation
import CoreMotion
import CoreLocation
import Combine
// No simd needed after removing custom integration

/// Combines Core Motion sensors and Core Location to estimate position, speed, heading and steps both indoors and outdoors.
/// NOTE: This is a simplified example – true sensor-fusion (e.g. extended Kalman filter) would be more sophisticated.
final class SensorFusionManager: NSObject, ObservableObject {
    static let shared = SensorFusionManager()

    // MARK: – Published fused outputs
    @Published private(set) var fusedLocation: CLLocation?
    @Published private(set) var fusedSpeedMps: Double = 0 // metres / second
    @Published private(set) var fusedHeading: Double = 0 // degrees
    @Published private(set) var fusedOrientation: CMAttitude?
    @Published private(set) var stepCount: Int = 0
    @Published private(set) var fusedDistanceMeters: Double = 0

    // MARK: – Private sensors
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    private let pedometer = CMPedometer()

    private var cancellables = Set<AnyCancellable>()

    // Pedometer delta tracking
    private var lastPedometerUpdate: Date?
    private var lastPedometerDistance: Double = 0

    // MARK: – Integration state for dead-reckoning
    private var lastValidLocation: CLLocation?
    private var lastLocationForDistance: CLLocation?
    private var stationaryCounter: Int = 0 // counts consecutive low-accel frames
    private let stationaryThresholdFrames = 25 // ≈0.5 s at 50 Hz
    private let accelQuietThreshold = 0.04 // g

    private var speedKF = SpeedEstimator()
    private var lastMotionTimestamp: TimeInterval? = nil

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .fitness
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
    }

    // MARK: – Public control
    func start() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()

        startMotion()
        startPedometer()
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        motionManager.stopDeviceMotionUpdates()
        pedometer.stopUpdates()
    }

    // MARK: – Public reset
    /// Clears all accumulators so a new run starts from zero.
    func reset() {
        fusedSpeedMps = 0
        fusedDistanceMeters = 0
        stepCount = 0
        fusedLocation = nil
        lastValidLocation = nil
        lastLocationForDistance = nil
        lastPedometerUpdate = nil
        lastPedometerDistance = 0
        stationaryCounter = 0
        speedKF.reset()
        lastMotionTimestamp = nil
    }

    // MARK: – Core Motion
    private func startMotion() {
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self, let motion else { return }
            self.fusedOrientation = motion.attitude
            // Stationary detector – increment when negligible user acceleration
            let mag = sqrt(motion.userAcceleration.x * motion.userAcceleration.x +
                           motion.userAcceleration.y * motion.userAcceleration.y +
                           motion.userAcceleration.z * motion.userAcceleration.z)
            if mag < self.accelQuietThreshold {
                self.stationaryCounter += 1
            } else {
                self.stationaryCounter = 0
            }
            let timestamp = motion.timestamp
            if let lastTs = self.lastMotionTimestamp {
                let dt = timestamp - lastTs
                self.speedKF.predict(accelMeasured: mag, dt: dt)
                self.fusedSpeedMps = self.speedKF.speed
            }
            self.lastMotionTimestamp = timestamp
            // Instant zeroing when device is at rest for consecutive frames
            if self.stationaryCounter >= self.stationaryThresholdFrames {
                self.speedKF.reset()
                self.fusedSpeedMps = 0
                return
            }
        }
    }

    // MARK: – CMPedometer
    private func startPedometer() {
        guard CMPedometer.isDistanceAvailable() || CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            guard let self, let data else { return }
            DispatchQueue.main.async {
                self.stepCount = data.numberOfSteps.intValue
                if let dist = data.distance?.doubleValue {
                    self.fusedDistanceMeters = dist
                    if let lastDist = self.lastPedometerDistance as Double? {
                        let deltaD = dist - lastDist
                        if deltaD >= 0 {
                            let now = Date()
                            if let lastT = self.lastPedometerUpdate {
                                let dt = now.timeIntervalSince(lastT)
                                if dt > 0.15 { // shorter threshold for more responsive updates
                                    // Calculate indoor walking speed but don't overwrite GPS-derived fusedSpeedMps here;
                                    // we'll expose it later as a separate metric if needed.
                                    _ = deltaD / dt // m/s (computed but not stored; could be used for indoor metrics later)
                                }
                            }
                            self.lastPedometerUpdate = now
                            self.lastPedometerDistance = dist
                        }
                    }
                }
            }
        }
    }

    // MARK: – Helpers
    // No offset function needed now
}

// MARK: – CLLocationManagerDelegate
extension SensorFusionManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        fusedLocation = loc

        // Derive instantaneous speed: use doppler if valid, else distance over time
        var rawSpeed = max(loc.speed, 0)
        if rawSpeed == 0, let last = lastValidLocation {
            let dt = loc.timestamp.timeIntervalSince(last.timestamp)
            if dt > 0 {
                rawSpeed = loc.distance(from: last) / dt
            }
        }
        lastValidLocation = loc

        // Supply GPS update to Kalman Filter
        speedKF.update(gpsSpeed: rawSpeed)

        // Overwrite rawSpeed with filter estimate for further processing
        rawSpeed = speedKF.speed

        if stationaryCounter >= stationaryThresholdFrames || rawSpeed < 0.2 {
            rawSpeed = 0
            speedKF.reset()
        }

        fusedSpeedMps = rawSpeed

        // Distance accumulate (only when horizAcc reasonable < 20 m)
        if loc.horizontalAccuracy < 20 {
            if let last = lastLocationForDistance {
                fusedDistanceMeters += loc.distance(from: last)
            }
            lastLocationForDistance = loc
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        fusedHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("SensorFusionManager location error: \(error.localizedDescription)")
    }
} 