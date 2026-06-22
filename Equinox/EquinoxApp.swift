//
//  EquinoxApp.swift
//  Equinox
//
//  Created by 邱奕馨 on 2026/6/10.
//

import SwiftUI

@main
struct EquinoxApp: App {
    @StateObject private var appState = AppState()

    init() {
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
    }
}
