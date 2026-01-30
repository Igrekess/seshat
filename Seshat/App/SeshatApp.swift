import SwiftUI
import AppKit

/// Delegate pour gérer le cycle de vie de l'application
final class SeshatAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // Décharger les modèles MLX de la mémoire
        ChandraMLXService.shared.unloadModel()
        QwenAnalysisService.shared.unloadModel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct SeshatApp: App {
    @NSApplicationDelegateAdaptor(SeshatAppDelegate.self) var appDelegate

    @State private var appState = AppState()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @State private var showSplashScreen = true

    var body: some Scene {
        WindowGroup {
            Group {
                if showSplashScreen {
                    SplashScreenView {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showSplashScreen = false
                        }
                    }
                } else {
                    ContentView()
                        .environment(appState)
                        .frame(minWidth: 1000, minHeight: 700)
                        .sheet(isPresented: $showOnboarding) {
                            OnboardingView {
                                hasCompletedOnboarding = true
                                showOnboarding = false
                            }
                        }
                        .onAppear {
                            // Afficher l'onboarding si modèles non téléchargés
                            if !hasCompletedOnboarding || !ModelDownloadService.shared.allRequiredModelsDownloaded {
                                showOnboarding = true
                            }
                        }
                }
            }
            .frame(minWidth: showSplashScreen ? 500 : 1000, minHeight: showSplashScreen ? 450 : 700)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Importer une image...") {
                    appState.showImportDialog = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Exporter en PDF...") {
                    appState.showExportDialog = true
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(appState.currentCopy == nil || appState.analysisResult == nil)
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
