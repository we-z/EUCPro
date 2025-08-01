import SwiftUI
import CoreLocation
import Charts

class MotionLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var displayLink: CADisplayLink?

    @Published var smoothedSpeed: Double = 0.0
    @Published var gpsSpeed: Double = 0.0

    @Published var smoothedSpeedHistory: [(time: TimeInterval, value: Double)] = []
    @Published var gpsSpeedHistory: [(time: TimeInterval, value: Double)] = []

    private var startTime: TimeInterval = Date().timeIntervalSince1970
    private var lastGPSSpeedMps: Double = 0.0
    private var filteredSpeedMps: Double = 0.0

    override init() {
        super.init()
        setupLocation()
        setupUpdateLoop()
    }

    private func relativeTime() -> TimeInterval {
        return Date().timeIntervalSince1970 - startTime
    }

    private func setupLocation() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let gpsSpeedMps = max(location.speed, 0)
        lastGPSSpeedMps = gpsSpeedMps

        let mph = gpsSpeedMps * 2.23694
        let t = relativeTime()

        DispatchQueue.main.async {
            self.gpsSpeed = mph
            self.gpsSpeedHistory.append((t, mph))
        }
    }

    private func setupUpdateLoop() {
        displayLink = CADisplayLink(target: self, selector: #selector(updateSmoothedSpeed))
        displayLink?.preferredFramesPerSecond = 100
        displayLink?.add(to: .main, forMode: .default)
    }

    @objc private func updateSmoothedSpeed() {
        // Low-pass filter
        let alpha = 0.1
        filteredSpeedMps = alpha * lastGPSSpeedMps + (1 - alpha) * filteredSpeedMps

        let mph = max(0, filteredSpeedMps * 2.23694)
        let t = relativeTime()

        DispatchQueue.main.async {
            self.smoothedSpeed = mph
            self.smoothedSpeedHistory.append((t, mph))
        }
    }
}

struct TempView: View {
    @StateObject private var manager = MotionLocationManager()

    var body: some View {
        VStack(spacing: 24) {
            VStack {
                Text("Live Speed")
                    .font(.headline)
                Text(String(format: "%.2f MPH", manager.smoothedSpeed))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading) {
                Text("Smoothed Speed (MPH)")
                    .font(.headline)
                Chart {
                    ForEach(manager.smoothedSpeedHistory, id: \.time) { point in
                        LineMark(x: .value("Time", point.time),
                                 y: .value("Speed", point.value))
                    }
                }
                .frame(height: 150)
            }

            VStack(alignment: .leading) {
                Text("GPS Speed (MPH)")
                    .font(.headline)
                Chart {
                    ForEach(manager.gpsSpeedHistory, id: \.time) { point in
                        LineMark(x: .value("Time", point.time),
                                 y: .value("Speed", point.value))
                    }
                }
                .frame(height: 150)
            }
        }
        .padding()
    }
}

#Preview {
    TempView()
}
