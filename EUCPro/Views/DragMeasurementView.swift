import SwiftUI

struct DragMeasurementView: View {
    @ObservedObject var viewModel: DragViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Speed: \(viewModel.currentSpeed, specifier: "%.1f") mph")
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