import Foundation
import CoreMotion

/// Estimates device linear speed in metres-per-second by combining
/// GPS Doppler speed with dead-reckoning from the accelerometer.
///
/// The estimator purposely keeps its maths simple – we rely on GPS to keep the
/// solution bounded while using inertial sensors to smooth the gaps between
/// GPS samples and to detect when the device is truly stationary.
final class SpeedEstimator {
    // MARK: – Kalman filter state (1-D velocity model)
    /// Current best estimate of speed (m/s)
    private var speed: Double = 0
    /// Variance (square of standard deviation) of the current speed estimate.
    private var speedVariance: Double = 4 // (m/s)² – start with fairly high uncertainty

    // MARK: – Public outputs
    /// Integrated distance travelled (m)
    private(set) var distance: Double = 0

    // MARK: – Time bookkeeping
    private var lastTimestamp: TimeInterval?

    // MARK: – Noise / filter tuning constants
    /// Minimum acceleration (in g) that we treat as genuine vehicle acceleration.
    /// Increased to better reject sensor noise and micro-vibrations.
    private let accelThreshold: Double = 0.08

    /// Variance of the accelerometer-derived speed change per second² (process noise).
    /// Larger value means we trust acceleration less → Kalman leans on GPS more.
    private let processNoiseVariance: Double = 5.0

    /// Variance of GPS speed measurement noise (m/s)². Typical consumer GPS speed σ ≈ 0.5 m/s.
    private let gpsMeasurementVariance: Double = 0.25

    /// Small decay to slowly bleed off velocity drift when no acceleration *or* GPS updates arrive.
    private let driftDecay: Double = 0.95

    /// Counts successive frames with significant acceleration. Helps to ensure the
    /// device is *really* accelerating in a persistent direction rather than just
    /// experiencing a one-off spike.
    private var consecutiveHighAccFrames: Int = 0

    /// Gain applied to net acceleration when integrating into speed. < 1 to reduce
    /// tendency to overshoot.
    private let accelIntegrationGain: Double = 0.35

    /// Frames in a row that satisfy strict stationary criteria.
    private var stationaryFrames: Int = 0

    init() {}

    /// Resets the estimator to an initial zero-state.
    func reset() {
        speed = 0
        distance = 0
        lastTimestamp = nil
    }

    /// Processes a single fused sensor frame.
    /// - Parameters:
    ///   - timestamp: Wall-clock time the sample was taken (seconds).
    ///   - gpsSpeed: Latest GPS Doppler speed (m/s). Pass `nil` when the fix is unavailable or invalid (<0).
    ///   - acceleration: Device-frame user acceleration (g).
    ///   - rotationRate: Device-frame angular rate (rad/s).
    /// - Returns: Tuple containing the updated speed and cumulative distance (both in SI units).
    @discardableResult
    func processSample(timestamp: TimeInterval,
                       gpsSpeed: Double?,
                       acceleration: CMAcceleration,
                       rotationRate: CMRotationRate) -> (speed: Double, distance: Double) {
        // Bootstrap timestamp so we have a ∆t for integration.
        guard let lastTs = lastTimestamp else {
            lastTimestamp = timestamp
            if let g = gpsSpeed, g >= 0 { speed = g }
            return (speed, distance)
        }
        let dt = timestamp - lastTs
        lastTimestamp = timestamp
        guard dt > 0 else { return (speed, distance) }

        // 1) Dead-reckoning from linear acceleration.
        // Only integrate when the acceleration magnitude exceeds a small threshold
        // and the phone is NOT being vigorously shaken (high rotation).
        let accMag = sqrt(acceleration.x * acceleration.x +
                          acceleration.y * acceleration.y +
                          acceleration.z * acceleration.z)
        let rotMag = sqrt(rotationRate.x * rotationRate.x +
                          rotationRate.y * rotationRate.y +
                          rotationRate.z * rotationRate.z)

        // --- Stationary detection (Zero-velocity update) ---
        let isStationaryCandidate = accMag < 0.03 && rotMag < 0.05 && (gpsSpeed ?? 0) < 0.2
        if isStationaryCandidate {
            stationaryFrames += 1
        } else {
            stationaryFrames = 0
        }

        // If the device has been stationary for >0.3 s (≈15 frames at 50 Hz),
        // force the Kalman state to a perfect zero with very small variance.
        if stationaryFrames > 15 {
            speed = 0
            speedVariance = 0.01
            // We still update timestamp & return distance unchanged.
            return (speed, distance)
        }

        // 1a) Track consecutive frames of "good" acceleration so that fleeting
        // spikes (e.g. a quick phone tap) don't integrate into large speed.
        if accMag > accelThreshold && rotMag < 2.0 {
            consecutiveHighAccFrames += 1
        } else {
            consecutiveHighAccFrames = 0
        }

        var controlAccel: Double = 0 // (m/s²)
        if consecutiveHighAccFrames >= 3 { // need ~60 ms of sustained acceleration
            // Subtract the threshold so we integrate *excess* acceleration –
            // anything below the threshold is treated as zero.
            controlAccel = (accMag - accelThreshold) * 9.80665 * accelIntegrationGain
        }

        // --- Kalman PREDICT step ---
        // State transition: v_k = v_(k-1) + a * dt
        let speedPred = speed + controlAccel * dt
        // Error covariance prediction: P_k = P_(k-1) + Q
        // Scale Q by dt² since integration of acceleration (m/s²) over dt gives speed.
        let q = processNoiseVariance * dt * dt
        var speedVarPred = speedVariance + q

        var speedUpdated = speedPred

        // --- Kalman UPDATE step (only if GPS available) ---
        if let g = gpsSpeed, g >= 0 {
            let r = gpsMeasurementVariance
            let innovation = g - speedPred
            let innovationVar = speedVarPred + r
            let kalmanGain = speedVarPred / innovationVar

            speedUpdated = speedPred + kalmanGain * innovation
            speedVarPred = (1 - kalmanGain) * speedVarPred
        }

        // 3) Optional bleed-off when *neither* control input nor GPS updates are present.
        if controlAccel == 0 && gpsSpeed == nil {
            speedUpdated *= pow(driftDecay, dt * 50)
        }

        // 4) Clip negatives & jitter.
        if abs(speedUpdated) < 0.05 { speedUpdated = 0 }

        // Commit
        speed = speedUpdated
        speedVariance = max(speedVarPred, 0.0001) // keep strictly positive

        // 5) Integrate distance.
        distance += speed * dt
        return (speed, distance)
    }
}
