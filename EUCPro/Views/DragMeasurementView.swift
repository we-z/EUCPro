import SwiftUI
import CoreLocation

struct DragMeasurementView: View {
    @ObservedObject var viewModel: DragViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speedUnit") private var speedUnitRaw: String = SpeedUnit.kmh.rawValue
    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnitRaw) ?? .mph }
    @StateObject private var fusion = SensorFusionManager.shared
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 32) {
                Spacer()
                Text(String(format: "%.1f", unit.convert(mps: viewModel.currentSpeed)))
                    .font(.system(size: 180))
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
            // Debug sensor info
            VStack {
                Text(String(format: "Fused Speed: %.2f m/s (%.2f mph)", fusion.fusedSpeedMps, fusion.fusedSpeedMps*2.23694))
                if let loc = fusion.fusedLocation {
                    Text(String(format: "Fused Lat: %.5f  Lon: %.5f", loc.coordinate.latitude, loc.coordinate.longitude))
                    Text(String(format: "Alt: %.1f m  HAcc: %.1f", loc.altitude, loc.horizontalAccuracy))
                }
                Text(String(format: "Heading: %.1f°", fusion.fusedHeading))
                Text("Steps: \(fusion.stepCount)")
            }
            .font(.caption)
            .padding(.horizontal)
            .padding(.bottom, 80)
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
        }
        .onDisappear {
            viewModel.stop()
            SensorFusionManager.shared.stop()
        }
    }
} 
