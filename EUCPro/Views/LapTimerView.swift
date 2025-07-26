import SwiftUI
import Charts
import Combine

struct LapTimerView: View {
    @ObservedObject var viewModel: LapViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speedUnit") private var speedUnitRaw: String = SpeedUnit.kmh.rawValue
    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnitRaw) ?? .mph }
    
    @StateObject private var motion = MotionManager.shared
    @StateObject private var fusion = SensorFusionManager.shared
    
    // Data model for chart points
    private struct SensorPoint: Identifiable {
        let id = UUID()
        let time: Double // seconds since current lap start
        let value: Double
    }
    
    @State private var accelPoints: [SensorPoint] = []
    @State private var gpsPoints: [SensorPoint] = []
    @State private var cancellables: Set<AnyCancellable> = []
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 32) {
                // MARK: Live speed display
                Text(String(format: "%.1f", unit.convert(mps: viewModel.currentSpeed)))
                    .font(.system(size: 180))
                    .monospacedDigit()
                Text(unit.label.uppercased())
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                // MARK: Lap metrics
                HStack(spacing: 40) {
                    VStack {
                        Text(String(format: "%.2f", viewModel.currentLapTime))
                            .font(.title)
                            .monospacedDigit()
                        Text("Lap s")
                            .foregroundColor(.secondary)
                    }
                    if viewModel.predictiveLap > 0 {
                        VStack {
                            Text(String(format: "%.2f", viewModel.predictiveLap))
                                .font(.title)
                                .monospacedDigit()
                            Text("Pred s")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // MARK: Live sensor charts
                VStack(alignment: .leading, spacing: 16) {
                    Text("Acceleration (G)")
                        .font(.caption.bold())
                    Chart(accelPoints) { point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("G", point.value)
                        )
                        .interpolationMethod(.linear)
                    }
                    .frame(height: 120)
                    .chartXAxisLabel("Time (s)")
                    .chartYAxisLabel("Acceleration (G)")
                    
                    Text("GPS Speed (\(unit.label))")
                        .font(.caption.bold())
                    Chart(gpsPoints) { point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Speed", point.value)
                        )
                        .interpolationMethod(.linear)
                    }
                    .frame(height: 120)
                    .chartXAxisLabel("Time (s)")
                    .chartYAxisLabel("Speed (\(unit.label))")
                }
                .padding()
                
                // MARK: Completed laps list
                List {
                    ForEach(Array(viewModel.completedLaps.enumerated()), id: \.offset) { idx, lap in
                        HStack {
                            Text("Lap \(idx + 1)")
                            Spacer()
                            Text(String(format: "%.2f", lap))
                        }
                    }
                }
                .frame(maxHeight: 200)
                
                Spacer()
            }
            // MARK: Finish button
            Button {
                viewModel.finishSession()
                dismiss()
            } label: {
                Text("FINISH")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .padding(.horizontal)
            }
        }
        .onAppear {
            LocationManager.shared.start()
            MotionManager.shared.start()
            SensorFusionManager.shared.start()
            
            // Accelerometer stream
            motion.$userAcceleration
                .receive(on: DispatchQueue.main)
                .sink { acc in
                    let mag = sqrt(acc.x * acc.x + acc.y * acc.y + acc.z * acc.z)
                    let point = SensorPoint(time: viewModel.currentLapTime, value: mag)
                    accelPoints.append(point)
                    if accelPoints.count > 300 { accelPoints.removeFirst() }
                }
                .store(in: &cancellables)
            
            // GPS speed stream
            LocationManager.shared.$currentLocation
                .compactMap { $0 }
                .receive(on: DispatchQueue.main)
                .sink { loc in
                    let speedMps = max(0, loc.speed) // -1 means invalid
                    let value = unit.convert(mps: speedMps)
                    let point = SensorPoint(time: viewModel.currentLapTime, value: value)
                    gpsPoints.append(point)
                    if gpsPoints.count > 300 { gpsPoints.removeFirst() }
                }
                .store(in: &cancellables)
        }
        .onDisappear {
            SensorFusionManager.shared.stop()
            MotionManager.shared.stop()
            LocationManager.shared.stop()
        }
    }
} 