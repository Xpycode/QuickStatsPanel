import AppKit
import Combine
import Sparkle

/// One updater for the app. Sparkle owns its preferences and installation flow.
/// Initialization does not start checks; AppDelegate starts it after app launch.
@MainActor
final class UpdaterController: NSObject, ObservableObject, NSMenuItemValidation {
    static let shared = UpdaterController()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var startupError: String?
    @Published private(set) var isStarted = false
    var beforeCheck: (() -> Void)?

    private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

    private override init() {
        super.init()
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$automaticallyChecksForUpdates)
    }

    func start() {
        guard !isStarted else { return }
        do {
            try controller.updater.start()
            isStarted = true
            startupError = nil
        } catch {
            startupError = "Updates could not start. Please download the latest version from the website."
            NSLog("Sparkle startup failed: %@", error.localizedDescription)
        }
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard isStarted else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
    }

    @objc func checkForUpdates(_ sender: Any?) {
        guard isStarted, canCheckForUpdates else { return }
        beforeCheck?()
        controller.checkForUpdates(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        isStarted && canCheckForUpdates
    }
}
