//
//  TickTickSection.swift
//  Glance Companion
//
//  SwiftUI section for connecting/disconnecting TickTick in the main settings UI.
//

import SwiftUI
import AuthenticationServices

struct TickTickSection: View {
    let tickTickManager: TickTickManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("TickTick", systemImage: "checkmark.circle")
                .font(.headline)

            if tickTickManager.isAuthenticated {
                authenticatedView
            } else {
                unauthenticatedView
            }

            if let error = tickTickManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Authenticated

    private var authenticatedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("TickTick 연결됨")
                    .fontWeight(.medium)
                Spacer()
                if tickTickManager.isLoading {
                    ProgressView().scaleEffect(0.8)
                }
            }

            if !tickTickManager.projects.isEmpty {
                Text("프로젝트 \(tickTickManager.projects.count)개 동기화 중")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                tickTickManager.signOut()
            } label: {
                Label("연결 해제", systemImage: "xmark.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Unauthenticated

    private var unauthenticatedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TickTick 계정을 연결하면 태스크가 X4에 표시됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                startOAuth()
            } label: {
                Label(
                    tickTickManager.isLoading ? "연결 중…" : "TickTick 연결하기",
                    systemImage: "link"
                )
                .font(.subheadline)
                .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .disabled(tickTickManager.isLoading)
        }
    }

    // MARK: - OAuth

    private func startOAuth() {
        guard let authURL = tickTickManager.buildAuthURL() else { return }

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "localhost"
        ) { callbackURL, error in
            guard let url = callbackURL else { return }
            Task { await tickTickManager.handleCallback(url: url) }
        }
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }
}
