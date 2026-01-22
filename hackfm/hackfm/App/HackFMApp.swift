//
//  HackFMApp.swift
//  HackFM
//
//  Main application entry point
//

import SwiftUI

@main
struct HackFMApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
