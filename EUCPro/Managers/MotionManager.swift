import Foundation
import CoreMotion
import Combine

final class MotionManager: ObservableObject {
    static let shared = MotionManager()
    
    private let motionManager = CMMotionManager()
    
    @Published var userAcceleration: CMAcceleration = CMAcceleration(x: 0, y: 0, z: 0)
    @Published var rotationRate: CMRotationRate = CMRotationRate(x: 0, y: 0, z: 0)
    
    private init() {
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
    }
    
    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            if let motion = motion {
                self?.userAcceleration = motion.userAcceleration
                self?.rotationRate = motion.rotationRate
            }
        }
    }
    
    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
} 