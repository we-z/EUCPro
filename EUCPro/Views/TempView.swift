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
    @State private var isDragging = false
        @State private var numbers = (0...10).map { _ in
            Int.random(in: 0...10)
        }
        
        var body: some View {
            Chart {
                ForEach(Array(zip(numbers, numbers.indices)), id: \.0) { number, index in
                    LineMark(
                        x: .value("Index", index),
                        y: .value("Value", number)
                    )
                    .foregroundStyle(isDragging ? .red : .blue)
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { _ in isDragging = true }
                    .onEnded { _ in isDragging = false }
            )
        }
}

#Preview {
    TempView()
}
