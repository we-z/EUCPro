import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var speed: Double = 0.0 // m/s
    @Published var course: Double = 0.0 // degrees
    @Published var altitude: Double = 0.0
    @Published var horizontalAccuracy: Double = 0.0
    
    private let locationManager = CLLocationManager()
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .automotiveNavigation
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        let bgModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        if bgModes?.contains("location") == true {
            locationManager.allowsBackgroundLocationUpdates = true
        }
        locationManager.pausesLocationUpdatesAutomatically = false
    }
    
    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func start() {
        locationManager.startUpdatingLocation()
    }
    
    func stop() {
        locationManager.stopUpdatingLocation()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            start()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.currentLocation = location
            self.speed = max(location.speed, 0)
            self.course = location.course
            self.altitude = location.altitude
            self.horizontalAccuracy = location.horizontalAccuracy
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
} 