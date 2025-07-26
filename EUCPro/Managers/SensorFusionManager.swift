import Foundation
import Combine
import CoreLocation
import CoreMotion

/// Performs lightweight sensor-fusion to provide a smooth, low-latency speed
/// read-out that reacts quickly to acceleration yet rejects false motion caused
/// by sensor noise or phone shaking. The class can be treated as a black box
/// that emits `@Published` values on the main thread.
final class SensorFusionManager: ObservableObject {
    // MARK: – Public, observable properties
    @Published private(set) var fusedSpeedMps: Double = 0           // metres / second
    @Published private(set) var fusedDistanceMeters: Double = 0     // metres
    @Published private(set) var fusedLocation: CLLocation?          // last GPS fix used in the fusion
    @Published private(set) var fusedHeading: Double = 0            // degrees (0=N)
    @Published private(set) var stepCount: Int = 0                  // very rough pedometer for debugging

    // MARK: – Singleton
    static let shared = SensorFusionManager()

    // MARK: – Private helpers
    private let location = LocationManager.shared
    private let motion    = MotionManager.shared
    private let estimator = SpeedEstimator()

    private var cancellables = Set<AnyCancellable>()
    private var stationaryFrames = 0

    private init() {
        subscribeSensors()
    }

    // MARK: – Lifecycle helpers
    func start() {
        location.start()
        motion.start()
    }

    func stop() {
        location.stop()
        motion.stop()
    }

    func reset() {
        estimator.reset()
        fusedSpeedMps = 0
        fusedDistanceMeters = 0
        fusedLocation = nil
        fusedHeading = 0
        stepCount = 0
        stationaryFrames = 0
    }

    // MARK: – Sensor subscription
    private func subscribeSensors() {
        // `CombineLatest3` waits until each publisher has produced at least one
        // value before emitting. That is perfect here – we want a consistent
        // sensor frame containing location (may be `nil`) and the two inertial
        // measurements.
        location.$currentLocation
            .combineLatest(motion.$userAcceleration, motion.$rotationRate)
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] locationOpt, acceleration, rotation in
                guard let self else { return }
                self.processFrame(location: locationOpt,
                                  userAcc: acceleration,
                                  rotation: rotation)
            }
            .store(in: &cancellables)
    }

    // MARK: – Frame processing
    private func processFrame(location: CLLocation?,
                              userAcc: CMAcceleration,
                              rotation: CMRotationRate) {
        let now = Date().timeIntervalSince1970
        // MARK: – GPS validation & noise suppression
        // Drop GPS fixes that are likely spurious before they contaminate the estimator.
        var gpsSpeed: Double? = nil
        if let loc = location {
            // 1) Only accept when Core-Location reports a valid Doppler speed (>=0)
            if loc.speed >= 0 {
                let hdopOK = loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy < 15 // metres
                // 2) Hard floor on reported speed – tiny residuals are treated as zero
                let speedOK = loc.speed > 0.2 // ~0.4 mph

                // 3) Reject improbable jumps when the device shows no acceleration
                let prevSpeed = fusedSpeedMps
                let accMagInstant = sqrt(userAcc.x * userAcc.x + userAcc.y * userAcc.y + userAcc.z * userAcc.z)
                let unrealisticJump = abs(loc.speed - prevSpeed) > 3.0 && accMagInstant < 0.05 // >6.7 mph step with <0.05 g

                if hdopOK && speedOK && !unrealisticJump {
                    gpsSpeed = loc.speed
                }
            }
        }
        
        // Feed everything through the estimator (dead-reckoning + GPS fusion).
        let (spd, dist) = estimator.processSample(timestamp: now,
                                                  gpsSpeed: gpsSpeed,
                                                  acceleration: userAcc,
                                                  rotationRate: rotation)

        // Simple stationary detector to clamp tiny residuals to exactly 0.
        let accMag = sqrt(userAcc.x * userAcc.x + userAcc.y * userAcc.y + userAcc.z * userAcc.z)
        let rotMag = sqrt(rotation.x * rotation.x + rotation.y * rotation.y + rotation.z * rotation.z)
        let isStationaryCandidate = accMag < 0.03 && rotMag < 0.05 && (gpsSpeed ?? 0) < 0.2
        if isStationaryCandidate {
            stationaryFrames += 1
            if stationaryFrames > 20 { // ≈0.4 s at 50 Hz
                estimator.reset()
            }
        } else {
            stationaryFrames = 0
        }

        // Step detection (very crude – sufficient for dev-time sanity checks)
        let stepHit = userAcc.z > 1.2

        // Marshal output back to the main thread so SwiftUI updates smoothly.
        DispatchQueue.main.async {
            self.fusedSpeedMps      = spd
            self.fusedDistanceMeters = dist
            if stepHit { self.stepCount += 1 }
            if let loc = location {
                self.fusedLocation = loc
                if loc.course >= 0 { self.fusedHeading = loc.course }
            }
        }
    }
}
