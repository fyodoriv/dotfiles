// chrome-dock-guard: hand the user's Chrome click to the user's Chrome.
//
// The launchd agent Chromes (port 9223, plus the temp-browser) run the real
// Google Chrome.app headless, so macOS registers them as com.google.Chrome.
// A Dock click, Cmd-Tab, or `open -a "Google Chrome"` can then activate one
// of them. It has no window, so Chrome looks stuck.
//
// This watcher listens for app activations (no polling). When an automation
// Chrome becomes active, it activates the user's Chrome, or starts it with
// `open -n -a` when it is not running. It never hides, quits, or touches the
// agent Chromes.
//
// A headed agent Chrome (for example one left open so the user can finish a
// sign-in) has a visible window. It keeps focus; only a windowless one hands
// off.
//
// A watcher started early in login can stay alive but never get another
// workspace event (seen 2026-10-25: two days deaf, Dock clicks ignored). A
// 15 s self-check reads the front window owner from the window server. When
// that owner changed twice with no activation event in between, the event
// stream is dead: the watcher exits 75 and launchd starts a fresh one.
//
// Usage: chrome-dock-guard                          run the watcher (LaunchAgent)
//        chrome-dock-guard --classify ARGV          print "automation" or "user"
//        chrome-dock-guard --decide WINDOWS ARGV    print "hand-off" or "keep"
//        chrome-dock-guard --stale PREV CUR EVENTS  print "stale" or "ok"

import AppKit
import Darwin

let chromeBundleID = "com.google.Chrome"
let chromeAppPath = ProcessInfo.processInfo.environment["DOTFILES_CHROME_APP"]
  ?? "/Applications/Google Chrome.app"
let automationMarkers = ["--headless", "--remote-debugging-port", "--remote-debugging-pipe"]

func isAutomation(_ argv: [String]) -> Bool {
  argv.dropFirst().contains { arg in automationMarkers.contains { arg.hasPrefix($0) } }
}

func shouldHandOff(argv: [String], onScreenWindows: Int) -> Bool {
  isAutomation(argv) && onScreenWindows == 0
}

// The front window owner moved from one real app to another, but no
// activation event arrived in that time.
func isStale(previousOwner: Int32, currentOwner: Int32, eventsSince: Int) -> Bool {
  previousOwner > 0 && currentOwner > 0 && previousOwner != currentOwner && eventsSince == 0
}

// The pid that owns the top normal (layer 0) on-screen window, or 0.
func frontWindowOwner() -> Int32 {
  guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]]
  else { return 0 }
  let top = windows.first { ($0[kCGWindowLayer as String] as? Int) == 0 }
  return top?[kCGWindowOwnerPID as String] as? Int32 ?? 0
}

// Count the pid's normal (layer 0) windows that are on screen now.
func onScreenWindowCount(_ pid: pid_t) -> Int {
  guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
    as? [[String: Any]]
  else { return 0 }
  return windows.filter {
    ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
  }.count
}

// Read a process's argv with sysctl KERN_PROCARGS2 (same data as `ps -o command`).
func processArguments(_ pid: pid_t) -> [String]? {
  var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
  var size = 0
  guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }
  var buffer = [UInt8](repeating: 0, count: size)
  guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
  let argc = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
  var index = 4
  while index < size, buffer[index] != 0 { index += 1 }  // executable path
  while index < size, buffer[index] == 0 { index += 1 }  // padding
  var args: [String] = []
  while args.count < argc, index < size {
    let start = index
    while index < size, buffer[index] != 0 { index += 1 }
    args.append(String(decoding: buffer[start..<index], as: UTF8.self))
    index += 1
  }
  return args
}

func log(_ message: String) {
  let stamp = ISO8601DateFormatter().string(from: Date())
  FileHandle.standardOutput.write("\(stamp) chrome-dock-guard: \(message)\n".data(using: .utf8)!)
}

if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "--classify" {
  print(isAutomation(Array(CommandLine.arguments.dropFirst(2))) ? "automation" : "user")
  exit(0)
}
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--decide",
   let windows = Int(CommandLine.arguments[2]) {
  let argv = Array(CommandLine.arguments.dropFirst(3))
  print(shouldHandOff(argv: argv, onScreenWindows: windows) ? "hand-off" : "keep")
  exit(0)
}
if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "--stale",
   let previous = Int32(CommandLine.arguments[2]), let current = Int32(CommandLine.arguments[3]),
   let events = Int(CommandLine.arguments[4]) {
  print(isStale(previousOwner: previous, currentOwner: current, eventsSince: events) ? "stale" : "ok")
  exit(0)
}
if CommandLine.arguments.count > 1 {
  FileHandle.standardError.write("chrome-dock-guard: unknown arguments \(CommandLine.arguments.dropFirst())\n".data(using: .utf8)!)
  exit(2)
}

final class Guard {
  private var lastStart = Date.distantPast
  private var frontmostObservation: NSKeyValueObservation?
  // Self-check state, owned by this Guard (process lifetime, main queue only).
  private var eventsSinceCheck = 0
  private var lastOwner: Int32 = 0
  private var staleChecks = 0

  func start() {
    // A headless Chrome becomes frontmost without ever posting
    // didActivateApplicationNotification, so watch frontmostApplication too.
    frontmostObservation = NSWorkspace.shared.observe(\.frontmostApplication, options: [.new]) {
      [weak self] _, change in
      guard let app = change.newValue ?? nil else { return }
      DispatchQueue.main.async { self?.handle(app) }
    }
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] note in
      guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      else { return }
      self?.handle(app)
    }
    log("watching activations of \(chromeBundleID)")
    // A windowless agent Chrome may already be in front when the guard starts.
    if let front = NSWorkspace.shared.frontmostApplication { handle(front) }
    lastOwner = frontWindowOwner()
    Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.selfCheck() }
  }

  private func selfCheck() {
    let owner = frontWindowOwner()
    if isStale(previousOwner: lastOwner, currentOwner: owner, eventsSince: eventsSinceCheck) {
      staleChecks += 1
      if staleChecks >= 2 {
        log("no activation events while the front app changed; exiting so launchd restarts the guard")
        exit(75)
      }
    } else if eventsSinceCheck > 0 {
      staleChecks = 0
    }
    lastOwner = owner
    eventsSinceCheck = 0
  }

  private let debug = ProcessInfo.processInfo.environment["DOTFILES_CHROME_DOCK_GUARD_DEBUG"] == "1"

  private func handle(_ app: NSRunningApplication) {
    eventsSinceCheck += 1
    if debug {
      log("activated \(app.bundleIdentifier ?? "nil") pid \(app.processIdentifier) argv \(processArguments(app.processIdentifier) ?? [])")
    }
    guard isAutomationChrome(app) else { return }
    raiseUserChrome(replacing: app, attempt: 1)
  }

  private func isAutomationChrome(_ app: NSRunningApplication) -> Bool {
    guard app.bundleIdentifier == chromeBundleID,
          let argv = processArguments(app.processIdentifier)
    else { return false }
    return shouldHandOff(argv: argv, onScreenWindows: onScreenWindowCount(app.processIdentifier))
  }

  private func raiseUserChrome(replacing app: NSRunningApplication, attempt: Int) {
    let userChrome = NSRunningApplication.runningApplications(withBundleIdentifier: chromeBundleID)
      .first { candidate in
        guard let args = processArguments(candidate.processIdentifier) else { return false }
        return !isAutomation(args)
      }
    if let userChrome {
      userChrome.activate(options: [.activateAllWindows])
      log("automation Chrome pid \(app.processIdentifier) frontmost; raised user Chrome pid \(userChrome.processIdentifier) (try \(attempt))")
      // The agent Chrome can grab the front again in the same click; re-check.
      guard attempt < 3 else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
        guard let self, let front = NSWorkspace.shared.frontmostApplication,
              self.isAutomationChrome(front)
        else { return }
        self.raiseUserChrome(replacing: front, attempt: attempt + 1)
      }
      return
    }
    // A cold start takes a few seconds; do not stack launches meanwhile.
    guard Date().timeIntervalSince(lastStart) > 10 else { return }
    lastStart = Date()
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-n", "-a", chromeAppPath]
    do {
      try open.run()
      log("automation Chrome pid \(app.processIdentifier) frontmost; started user Chrome")
    } catch {
      log("automation Chrome pid \(app.processIdentifier) frontmost; failed to start user Chrome: \(error)")
    }
  }
}

// Workspace activation notifications need an NSApplication connection to the
// window server; a bare RunLoop never receives them. `.prohibited` keeps the
// guard out of the Dock and Cmd-Tab.
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
let watcher = Guard()
watcher.start()
application.run()
