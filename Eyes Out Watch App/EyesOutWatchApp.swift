//
//  EyesOutWatchApp.swift
//  Eyes Out Watch App
//

import SwiftUI

@main
struct EyesOutWatchApp: App {
    @State private var model = WatchTrafficModel()

    var body: some Scene {
        WindowGroup {
            WatchContentView(model: model)
                .onAppear { model.start() }
        }
    }
}
