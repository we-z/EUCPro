import SwiftUI
import Charts

struct LapTimerView: View {
    @ObservedObject var viewModel: LapViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speedUnit") private var speedUnitRaw: String = SpeedUnit.kmh.rawValue
    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnitRaw) ?? .mph }
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 28) {
                Spacer()
                Text(String(format: "%.1f", unit.convert(mps: viewModel.currentSpeed)))
                    .font(.system(size: 100, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .animation(.easeOut(duration: 0.15), value: viewModel.currentSpeed)
                Text(unit.label.uppercased())
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text(String(format: "Lap %.2f s", viewModel.currentLapTime))
                    .font(.title2)

                if viewModel.predictiveLap > 0 {
                    Text(String(format: "Pred %.2f s", viewModel.predictiveLap))
                        .foregroundColor(.orange)
                }
                List {
                    ForEach(Array(viewModel.completedLaps.enumerated()), id: \ .offset) { idx, lap in
                        HStack {
                            Text("Lap \(idx+1)")
                            Spacer()
                            Text(String(format: "%.2f", lap))
                        }
                    }
                }
                .frame(maxHeight: 200)
                Spacer()
            }
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
        .background(Color.black.opacity(0.95).ignoresSafeArea())
        .onAppear {
            LocationManager.shared.start()
            MotionManager.shared.start()
        }
    }
} 