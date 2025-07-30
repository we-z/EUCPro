import SwiftUI
import CoreLocation
import Charts
import Combine

struct DragMeasurementView: View {
    @ObservedObject var viewModel: DragViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speedUnit") private var speedUnitRaw: String = SpeedUnit.kmh.rawValue
    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnitRaw) ?? .mph }
    @StateObject private var fusion = SensorFusionManager.shared
    @StateObject private var motion = MotionManager.shared

    // Data model for charting live sensor values
    private struct SensorPoint: Identifiable {
        let id = UUID()
        let time: Double // seconds since start
        let value: Double
    }

    @State private var accelPoints: [SensorPoint] = []
    @State private var gpsPoints: [SensorPoint] = []
    @State private var cancellables: Set<AnyCancellable> = []

    var body: some View {
        VStack {
            ScrollView {
                VStack {
                    Text(String(format: "%.1f", unit.convert(mps: viewModel.currentSpeed)))
                        .font(.system(size: 120))
                        .monospacedDigit()
                    Text(unit.label.uppercased())
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    // Live sensor charts
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
                    Spacer()
                }
                
            }
            Button {
                viewModel.manualStop()
                dismiss()
            } label: {
                Text("STOP")
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

            // Live data collection
            // Accelerometer
            motion.$userAcceleration
                .receive(on: DispatchQueue.main)
                .sink { acc in
                    let mag = sqrt(acc.x * acc.x + acc.y * acc.y + acc.z * acc.z)
                    let point = SensorPoint(time: viewModel.elapsed, value: mag)
                    accelPoints.append(point)
                    if accelPoints.count > 300 { accelPoints.removeFirst() }
                }
                .store(in: &cancellables)

            // GPS speed
            LocationManager.shared.$currentLocation
                .compactMap { $0 }
                .receive(on: DispatchQueue.main)
                .sink { loc in
                    let speedMps = max(0, loc.speed) // -1 means invalid
                    let value = unit.convert(mps: speedMps)
                    let point = SensorPoint(time: viewModel.elapsed, value: value)
                    gpsPoints.append(point)
                    if gpsPoints.count > 300 { gpsPoints.removeFirst() }
                }
                .store(in: &cancellables)
        }
        .onDisappear {
            viewModel.stop()
            SensorFusionManager.shared.stop()
        }
    }
}

struct DragMeasurementView_Previews: PreviewProvider {
    static var previews: some View {
        DragMeasurementView(viewModel: DragViewModel(startSpeed: 0, targetSpeed: 20))
    }
} 
