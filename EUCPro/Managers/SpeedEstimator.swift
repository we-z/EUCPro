import Foundation
import simd

/// A minimal 1-D Kalman filter that fuses high-rate accelerometer data with slower, noisy GPS Doppler speed.
/// State vector x = [ v, b ] where
///  v – true forward speed (m/s)
///  b – accelerometer bias (m/s²)
/// The process model:
///   vₖ₊₁ = vₖ + (aₖ - bₖ)·dt
///   bₖ₊₁ = bₖ         (bias random walk ~ σ_q)
/// Measurement model:
///   z = v (GPS Doppler)
struct SpeedEstimator {
    // MARK: Public output
    private(set) var speed: Double = 0 // m/s

    // MARK: Kalman state
    private var bias: Double = 0
    private var P: simd_double2x2 = simd_double2x2(diagonal: SIMD2(1, 1)) // covariance

    // Tunable noise variances
    private let accelNoise: Double = 0.4      // σ_a  (m/s²) white-noise accel uncertainty
    private let gpsNoise: Double = 1.5        // σ_r  (m/s) GPS Doppler SD (~±3 mph)
    private let biasDrift: Double = 0.01      // σ_q  bias random walk (m/s²)

    mutating func predict(accelMeasured a: Double, dt: Double) {
        // State prediction
        speed += (a - bias) * dt
        // Covariance prediction: P = F P Fᵀ + Q
        // F = [[1, -dt], [0, 1]]
        let F = simd_double2x2(rows: [SIMD2(1, -dt), SIMD2(0, 1)])
        let Q = simd_double2x2(rows: [SIMD2(accelNoise * accelNoise * dt * dt, 0),
                                      SIMD2(0, biasDrift * biasDrift * dt)])
        P = F * P * F.transpose + Q
    }

    mutating func update(gpsSpeed z: Double) {
        // Measurement update using z = v + noise
        let H = SIMD2<Double>(1, 0) // measurement matrix
        let R = gpsNoise * gpsNoise
        let y = z - speed // innovation
        // S = H P Hᵀ + R (scalar)
        let S = P[0,0] + R
        // Kalman gain K = P Hᵀ / S (2x1 vector)
        let K0 = P[0,0] / S
        let K1 = P[1,0] / S
        // Update state
        speed += K0 * y
        bias  += K1 * y
        // Update covariance: P = (I - K H) P
        let I_KH = simd_double2x2(rows: [SIMD2(1 - K0, -K0 * 0),
                                         SIMD2(-K1, 1 - K1 * 0)])
        P = I_KH * P
    }

    mutating func reset() {
        speed = 0
        bias  = 0
        P = simd_double2x2(diagonal: SIMD2(1, 1))
    }
} 