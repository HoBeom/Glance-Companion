//
//  AppState.swift
//  ReminderSync
//
//  Manages application-wide state including onboarding.
//

import SwiftUI

@Observable
final class AppState {
    // MARK: - Onboarding

    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }

    // MARK: - Sync Settings

    var useDemoData: Bool = false

    // MARK: - Display Config (persisted)

    var displayConfig: DisplayConfig = {
        if let data = UserDefaults.standard.data(forKey: "displayConfig"),
           let config = try? JSONDecoder().decode(DisplayConfig.self, from: data) {
            return config
        }
        return DisplayConfig()
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(displayConfig) {
                UserDefaults.standard.set(data, forKey: "displayConfig")
            }
        }
    }

    // MARK: - Methods

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
    }
}
