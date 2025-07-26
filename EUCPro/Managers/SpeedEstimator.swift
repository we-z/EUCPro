import Foundation
import CoreMotion

/// Estimates device linear speed in metres-per-second by combining
/// GPS Doppler speed with dead-reckoning from the accelerometer.
///
/// The estimator purposely keeps its maths simple – we rely on GPS to keep the
/// solution bounded while using inertial sensors to smooth the gaps between
/// GPS samples and to detect when the device is truly stationary.
final class SpeedEstimator {
    /// Latest estimated speed (m/s)
    private var speed: Double = 0
    /// Integrated distance travelled (m)
    private(set) var distance: Double = 0
    /// Timestamp of the previous sensor frame (s)
    private var lastTimestamp: TimeInterval?

    /// Weighting factor applied to GPS whenever a fresh fix is available.
    /// `gpsWeight = 0.25` means the new solution is 25 % GPS and 75 % inertial.
    private let gpsWeight: Double
    /// Minimum acceleration (in g) that we treat as genuine vehicle acceleration.
    /// Increased to better reject sensor noise and micro-vibrations.
    private let accelThreshold: Double = 0.08

    /// Small decay to slowly bleed off velocity drift when no acceleration present.
    /// Lower value → quicker bleed-off.
    private let driftDecay: Double = 0.95

    /// Counts successive frames with significant acceleration. Helps to ensure the
    /// device is *really* accelerating in a persistent direction rather than just
    /// experiencing a one-off spike.
    private var consecutiveHighAccFrames: Int = 0

    init(gpsWeight: Double = 0.6) {
        self.gpsWeight = gpsWeight
    }

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

        // 1a) Track consecutive frames of "good" acceleration so that fleeting
        // spikes (e.g. a quick phone tap) don't integrate into large speed.
        if accMag > accelThreshold && rotMag < 2.0 {
            consecutiveHighAccFrames += 1
        } else {
            consecutiveHighAccFrames = 0
        }

        // 1b) Only integrate when we have seen at least 2 successive frames
        // above the threshold (≈40 ms at 50 Hz). This is long enough to filter
        // out most impulse noise yet short enough to capture genuine vehicle
        // acceleration.
        if consecutiveHighAccFrames >= 2 {
            // Subtract the threshold so we integrate *excess* acceleration –
            // anything below the threshold is treated as zero.
            let netAcc = (accMag - accelThreshold) * 9.80665 // m/s²
            speed += netAcc * dt
        } else {
            // Mild exponential decay prevents speed drifting forever.
            speed *= pow(driftDecay, dt * 50) // normalise to 50 Hz baseline
        }

        // 2) Fuse with GPS when available.
        if let g = gpsSpeed, g >= 0 {
            speed = gpsWeight * g + (1.0 - gpsWeight) * speed
        }

        // 3) Clip unphysical negatives and small jitter.
        if speed < 0.03 { speed = 0 } // ≈0.07 mph

        // 4) Integrate distance.
        distance += speed * dt
        return (speed, distance)
    }
}
