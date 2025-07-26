//
//  EUCProApp.swift
//  EUCPro
//
//  Created by Wheezy Capowdis on 7/24/25.
//

import SwiftUI

@main
struct EUCProApp: App {
    // Request location permission as soon as the app launches so that views relying on
    // `LocationManager.shared.currentLocation` (e.g. track creation, lap timing) have
    // access to location data without additional user interaction.
    init() {
        LocationManager.shared.requestAuthorization()
    }
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
