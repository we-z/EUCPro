import Foundation
import CoreMotion

// Simple 1-D speed & distance estimator fusing GPS Doppler and accelerometer data.
// All units are SI (m/s, m, s).
final class SpeedEstimator {
    // Public output
    private(set) var speed: Double = 0   // m/s
    private(set) var distance: Double = 0 // m

    // Kalman state
    private var speedVariance: Double = 0.1
    private var lastTimestamp: TimeInterval?

    // Helpers
    private var stationaryFrames = 0
    private var consecutiveHighAccFrames = 0
    private let minFramesForAccel = 2

    // Tunables
    private let processNoiseVar: Double = 0.5
    private let gpsNoiseVar: Double = 0.2
    private let accelThreshold: Double = 0.05 // g
    private let accelGain: Double = 1.2
    private let driftDecay: Double = 0.99

    func reset() {
        speed = 0
        distance = 0
        speedVariance = 0.1
        lastTimestamp = nil
        stationaryFrames = 0
        consecutiveHighAccFrames = 0
    }

    /// Update estimator with latest sensor frame.
    /// - Parameters:
    ///   - timestamp: seconds since Unix epoch
    ///   - gpsSpeed: Doppler speed (m/s) or nil when unavailable
    ///   - acceleration: user acceleration (g)
    ///   - rotationRate: angular velocity (rad/s)
    @discardableResult
    func processSample(timestamp: TimeInterval,
                       gpsSpeed: Double?,
                       acceleration: CMAcceleration,
                       rotationRate: CMRotationRate) -> (speed: Double, distance: Double) {
        guard let last = lastTimestamp else {
            lastTimestamp = timestamp
            if let g = gpsSpeed, g >= 0 { speed = g }
            return (speed, distance)
        }
        let dt = timestamp - last
        guard dt > 0 else { return (speed, distance) }
        lastTimestamp = timestamp

        // Magnitudes
        let accMag = sqrt(acceleration.x*acceleration.x + acceleration.y*acceleration.y + acceleration.z*acceleration.z)
        let rotMag = sqrt(rotationRate.x*rotationRate.x + rotationRate.y*rotationRate.y + rotationRate.z*rotationRate.z)

        // Stationary detection (zero-velocity update)
        let stopped = accMag < 0.03 && rotMag < 0.05 && (gpsSpeed ?? 0) < 0.2
        if stopped { stationaryFrames += 1 } else { stationaryFrames = 0 }
        if stationaryFrames > 15 {
            speed = 0
            speedVariance = 0.01
            return (speed, distance)
        }

        // Dead-reckoning control input
        if accMag > accelThreshold && rotMag < 2.0 {
            consecutiveHighAccFrames += 1
        } else {
            consecutiveHighAccFrames = 0
        }
        var controlA: Double = 0
        if consecutiveHighAccFrames >= minFramesForAccel {
            controlA = (accMag - accelThreshold) * 9.80665 * accelGain
        }

        // Kalman predict
        let speedPred = speed + controlA * dt
        let q = processNoiseVar * dt * dt
        var varPred = speedVariance + q

        var speedUpd = speedPred

        // Kalman update with GPS
        if let g = gpsSpeed, g >= 0 {
            let innovation = g - speedPred
            let innovationVar = varPred + gpsNoiseVar
            let k = varPred / innovationVar
            speedUpd = speedPred + k * innovation
            varPred = (1 - k) * varPred
        }

        // Drift decay when no inputs
        if controlA == 0 && gpsSpeed == nil {
            speedUpd *= pow(driftDecay, dt * 50)
        }

        // Clamp jitter
        if abs(speedUpd) < 0.3 { speedUpd = 0 }

        // Commit
        speed = speedUpd
        speedVariance = max(varPred, 0.0001)
        distance += speed * dt
        return (speed, distance)
    }
}