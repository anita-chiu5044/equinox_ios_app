//
//  ContentView.swift
//  Equinox
//
//  Created by 邱奕馨 on 2026/6/10.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        RootView()
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
