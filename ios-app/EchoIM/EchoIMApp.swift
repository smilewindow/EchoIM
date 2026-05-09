//
//  EchoIMApp.swift
//  EchoIM
//
//  Created by 许宇勤 on 4/16/26.
//

import SwiftUI

@main
struct EchoIMApp: App {
    let container: AppContainer

    init() {
        let shouldReset = CommandLine.arguments.contains("-uitest-reset-keychain")
        container = AppContainer(resetKeychainOnLaunch: shouldReset)
        container.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
    }
}
