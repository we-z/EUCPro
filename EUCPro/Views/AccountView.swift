import SwiftUI

struct AccountView: View {
    @AppStorage("speedUnit") private var speedUnitRaw: String = SpeedUnit.mph.rawValue
    private var speedUnit: SpeedUnit {
        get { SpeedUnit(rawValue: speedUnitRaw) ?? .mph }
        set { speedUnitRaw = newValue.rawValue }
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Speed Units", selection: $speedUnitRaw) {
                    ForEach(SpeedUnit.allCases) { unit in
                        Text(unit.label).tag(unit.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .animation(.default, value: speedUnitRaw)
            }
            .navigationTitle("Account")
        }
    }
}

#Preview {
    AccountView()
} 