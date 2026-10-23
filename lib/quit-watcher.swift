// A tiny accessory app that lets macOS quit a LaunchAgent Chrome (issue #298).
// Chrome started by launchd ignores the quit Apple Event that macOS sends on
// restart, shut down, and log out, so the restart stops with "Google Chrome
// failed to quit". This app is asked to quit too; it then sends SIGUSR1 to the
// relay (bin/dotfiles-quit-relay, whose PID is argument 1), which sends SIGTERM
// to Chrome. It also reacts to NSWorkspace.willPowerOffNotification, and exits
// by itself when the relay is gone.
import AppKit

let relay: pid_t = CommandLine.arguments.count > 1 ? pid_t(CommandLine.arguments[1]) ?? 0 : 0

func notifyRelay() {
    if relay > 0 { kill(relay, SIGUSR1) }
}

final class QuitDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        notifyRelay()
        return .terminateNow
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = QuitDelegate()
app.delegate = delegate
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
) { _ in notifyRelay() }
Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
    if relay <= 0 || kill(relay, 0) != 0 { exit(0) }
}
app.run()
