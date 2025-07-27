//
//  TempView.swift
//  EUCPro
//
//  Created by Wheezy Capowdis on 7/27/25.
//

import SwiftUI
import Charts

struct DataPoint: Identifiable {
    var id = UUID()
    let x: Double
    let y: Double
}

let minGlobalX: Double = 0
let maxGlobalX: Double = 100

let data: [DataPoint] = (Int(minGlobalX) ..< Int(maxGlobalX)).map { DataPoint(x: Double($0), y: Double(arc4random()) / Double(UInt32.max)) }

struct TempView: View {
    @State private var minXValue = minGlobalX
    @State private var maxXValue = maxGlobalX

    @State var scale: CGFloat = 1.0
    @State var lastScaleValue: CGFloat = 1.0

    var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let delta = value.magnification / lastScaleValue
                lastScaleValue = value.magnification
                scale = scale * delta

                let globalWidth = maxGlobalX - minGlobalX
                let newWidth = 0.5 * (globalWidth - (globalWidth / scale))

                let newMinX = minGlobalX + newWidth
                if minGlobalX ... maxXValue ~= newMinX {
                    minXValue = newMinX
                }

                let newMaxX = maxGlobalX - newWidth
                if minXValue ... maxGlobalX ~= newMaxX {
                    maxXValue = newMaxX
                }
            }
            .onEnded { _ in
                lastScaleValue = 1.0
            }
    }

    var body: some View {
        VStack {
            Chart(data) {
                LineMark(
                    x: .value("x", $0.x),
                    y: .value("y", $0.y)
                )
                .lineStyle(StrokeStyle(lineWidth: 1))
            }
            .chartXScale(domain: minXValue ... maxXValue)

            .onTapGesture(count: 2) {
                minXValue = minGlobalX
                maxXValue = maxGlobalX
                scale = 1.0 // make sure to reset the scale here as well
            }
            .gesture(magnification)
            .padding(20)

            HStack(spacing: 20) {
                Text("Min: \(Int(minXValue))")
                Slider(value: $minXValue, in: minGlobalX ... maxXValue, step: 1)
            }
            .padding(.horizontal)

            HStack(spacing: 20) {
                Text("Max: \(Int(maxXValue))")
                Slider(value: $maxXValue, in: minXValue ... maxGlobalX, step: 1)
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    TempView()
}
