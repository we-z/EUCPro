import Foundation
import CoreLocation
import Combine

final class LapViewModel: ObservableObject {
    let track: Track
    @Published var currentSpeed: Double = 0
    @Published var currentLapTime: Double = 0
    @Published var completedLaps: [Double] = []
    @Published var predictiveLap: Double = 0
    
    private var startLocation: CLLocation
    private var lastCrossTime: Date?
    private var cancellables = Set<AnyCancellable>()
    private var speedPoints: [SpeedPoint] = []
    
    init(track: Track) {
        self.track = track
        self.startLocation = track.startFinishLocation()
        subscribe()
    }
    
    private func subscribe() {
        let locManager = LocationManager.shared
        locManager.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.handle(location: location)
            }
            .store(in: &cancellables)
    }
    
    private func handle(location: CLLocation) {
        currentSpeed = max(location.speed, 0) * 2.23694
        if let last = lastCrossTime {
            currentLapTime = Date().timeIntervalSince(last)
        }
        let distanceToStart = location.distance(from: startLocation)
        if distanceToStart < 10 {
            if let last = lastCrossTime, Date().timeIntervalSince(last) > 5 {
                completedLaps.append(Date().timeIntervalSince(last))
                lastCrossTime = Date()
                predictiveLap = predictive()
            } else if lastCrossTime == nil {
                lastCrossTime = Date()
            }
        }
        if lastCrossTime != nil {
            let distance = location.distance(from: startLocation)
            speedPoints.append(SpeedPoint(timestamp: Date(), speed: location.speed, distance: distance))
        }
    }
    
    private func predictive() -> Double {
        guard let lastLap = completedLaps.last else { return 0 }
        let avg = completedLaps.reduce(0, +) / Double(completedLaps.count)
        if currentLapTime == 0 { return avg }
        let ratio = currentLapTime / lastLap
        return avg * ratio
    }
    
    func finishSession() {
        guard !completedLaps.isEmpty else { return }
        let metrics: [String: Double] = [
            "Best Lap": completedLaps.min() ?? 0,
            "Average Lap": completedLaps.reduce(0, +)/Double(completedLaps.count),
            "Total Laps": Double(completedLaps.count)
        ]
        let run = Run(type: .lap,
                      title: track.name + " " + DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short),
                      metrics: metrics,
                      speedData: speedPoints,
                      trackName: track.name)
        DataStore.shared.add(run: run)
    }
} 