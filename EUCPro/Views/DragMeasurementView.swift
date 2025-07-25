import SwiftUI

struct DragMeasurementView: View {
    @ObservedObject var viewModel: DragViewModel
    @Environment(\.dismiss) var dismiss
    
    @AppStorage("speedUnit") private var speedUnitRaw: String = SpeedUnit.mph.rawValue
    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnitRaw) ?? .mph }
    var body: some View {
        VStack(spacing: 24) {
            Text("Speed: \(unit == .mph ? viewModel.currentSpeed : viewModel.currentSpeed * 1.60934, specifier: "%.1f") \(unit.label)")
                .font(.largeTitle)
            Text("Distance: \(viewModel.distance, specifier: "%.1f") m")
            Text("Time: \(viewModel.elapsed, specifier: "%.2f") s")
            if let metrics = viewModel.finishedMetrics {
                List {
                    ForEach(metrics.sorted(by: { $0.key < $1.key }), id: \ .key) { key, value in
                        HStack {
                            Text(key)
                            Spacer()
                            Text(String(format: "%.2f", value))
                        }
                    }
                }
                Button("Done") { dismiss() }
            } else {
                Button("Stop") { viewModel.manualStop(); dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .navigationTitle("Drag Run")
        .onAppear {
            LocationManager.shared.start()
            MotionManager.shared.start()
        }
        .onDisappear { viewModel.stop() }
    }
} 