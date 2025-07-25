import SwiftUI
import Charts

struct LapTimerView: View {
    @ObservedObject var viewModel: LapViewModel
    @Environment(\.dismiss) var dismiss
    @AppStorage("speedUnit") private var speedUnitRaw: String = SpeedUnit.mph.rawValue
    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnitRaw) ?? .mph }
    var body: some View {
        VStack(spacing: 16) {
            Text("Speed: \(unit == .mph ? viewModel.currentSpeed : viewModel.currentSpeed * 1.60934, specifier: "%.1f") \(unit.label)")
                .font(.title)
            Text("Lap Time: \(viewModel.currentLapTime, specifier: "%.2f") s")
            if viewModel.predictiveLap > 0 {
                Text("Predicted: \(viewModel.predictiveLap, specifier: "%.2f") s")
            }
            List {
                ForEach(Array(viewModel.completedLaps.enumerated()), id: \ .offset) { idx, lap in
                    HStack {
                        Text("Lap \(idx + 1)")
                        Spacer()
                        Text(String(format: "%.2f s", lap))
                    }
                }
            }
            Button("Finish Session") {
                viewModel.finishSession()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle(viewModel.track.name)
        .onAppear {
            LocationManager.shared.start()
            MotionManager.shared.start()
        }
    }
} 