import SwiftUI

struct DragMeasurementView: View {
    @ObservedObject var viewModel: DragViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speedUnit") private var speedUnitRaw: String = SpeedUnit.mph.rawValue
    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnitRaw) ?? .mph }
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 32) {
                Spacer()
                Text(String(format: "%.1f", unit == .mph ? viewModel.currentSpeed : viewModel.currentSpeed * 1.60934))
                    .font(.system(size: 120, weight: .heavy))
                    .monospacedDigit()
                Text(unit.label.uppercased())
                    .font(.title2)
                    .foregroundColor(.secondary)

                HStack(spacing: 40) {
                    VStack {
                        Text(String(format: "%.2f", unit.convert(distanceMeters: viewModel.distance)))
                            .font(.title)
                            .monospacedDigit()
                        Text(unit.distanceLabel)
                            .foregroundColor(.secondary)
                    }
                    VStack {
                        Text(String(format: "%.2f", viewModel.elapsed))
                            .font(.title)
                            .monospacedDigit()
                        Text("s")
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
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
        }
        .onDisappear { viewModel.stop() }
    }
} 
