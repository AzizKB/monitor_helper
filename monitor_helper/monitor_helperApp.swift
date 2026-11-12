//
//  monitor_helperApp.swift
//  monitor_helper
//
//  Created by Abdulaziz Bandar on 27/07/2026.
//

import SwiftUI

@main
struct monitor_helperApp: App {
    var body: some Scene {
        WindowGroup {
            // Hosted unit tests exercise models without starting live Auth/API tasks.
            if NSClassFromString("XCTestCase") != nil
                || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
                || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil {
                Color.clear
            } else {
                ContentView()
            }
        }
    }
}
