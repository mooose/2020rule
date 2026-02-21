import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            coordinator = try AppCoordinator()
            coordinator?.run()
        } catch {
            let alert = NSAlert()
            alert.messageText = "20-20-20 Rule konnte nicht gestartet werden"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutdown()
    }
}
