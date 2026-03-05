//
//  Glance_CompanionApp.swift
//  Glance Companion
//


import SwiftUI
import AppIntents

@main
struct Glance_CompanionApp: App {
    @State private var appState = AppState()
    @State private var bleManager = BLEManager()
    @State private var calendarManager = CalendarManager()
    @State private var tickTickManager = TickTickManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.hasCompletedOnboarding {
                    MainView(
                        bleManager: bleManager,
                        calendarManager: calendarManager,
                        tickTickManager: tickTickManager,
                        appState: $appState
                    )
                } else {
                    OnboardingView(
                        calendarManager: calendarManager,
                        onComplete: {
                            appState.completeOnboarding()
                        }
                    )
                }
            }
            .task {
                // Register shared instances so SyncGlanceIntent can access them
                AppDependencyManager.shared.add(dependency: bleManager)
                AppDependencyManager.shared.add(dependency: calendarManager)
                AppDependencyManager.shared.add(dependency: tickTickManager)
                AppDependencyManager.shared.add(dependency: appState)
            }
        }
        .onOpenURL { url in
            // TickTick OAuth2 콜백 처리
            if url.scheme == "glancecompanion" {
                Task { await tickTickManager.handleCallback(url: url) }
            }
        }
    }
}
