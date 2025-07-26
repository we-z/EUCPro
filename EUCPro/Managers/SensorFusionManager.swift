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

    private var cancellables = Set<AnyCancellable>()

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
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        motionManager.stopDeviceMotionUpdates()
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

            // Project user acceleration onto the current heading to obtain signed forward accel
            let ua = motion.userAcceleration // in g units
            let R = motion.attitude.rotationMatrix
            // Transform body-frame accel to navigation frame (NED). Only horizontal components used.
            let accX = R.m11 * ua.x + R.m12 * ua.y + R.m13 * ua.z
            let accY = R.m21 * ua.x + R.m22 * ua.y + R.m23 * ua.z
            let headingRad = self.fusedHeading * Double.pi / 180.0
            // Forward component along heading (signed). Units: g
            let forwardG =  accX * cos(headingRad) + accY * sin(headingRad)

            // Ignore tiny acceleration to suppress noise
            let forwardMps2: Double
            if abs(forwardG) < self.accelQuietThreshold {
                forwardMps2 = 0
            } else {
                forwardMps2 = forwardG * 9.81 // convert g → m/s²
            }

            let timestamp = motion.timestamp
            if let lastTs = self.lastMotionTimestamp {
                let dt = timestamp - lastTs
                self.speedKF.predict(accelMeasured: forwardMps2, dt: dt)
                var predicted = self.speedKF.speed
                if predicted < 0 { predicted = 0 }
                // Hard-cap to 25 m/s (≈90 km/h) to suppress runaway drift.
                if predicted > 25 { predicted = 25 }
                self.fusedSpeedMps = predicted
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

        rawSpeed = max(0, min(rawSpeed, 25))
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