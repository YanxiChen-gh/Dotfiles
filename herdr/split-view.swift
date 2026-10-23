import Cocoa
import ApplicationServices
import Darwin

struct OpenerError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func title(_ element: AXUIElement) -> String { attribute(element, kAXTitleAttribute) as? String ?? "" }
func children(_ element: AXUIElement) -> [AXUIElement] { attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func fullscreen(_ element: AXUIElement) -> Bool { attribute(element, "AXFullScreen") as? Bool == true }

func frame(_ element: AXUIElement) -> CGRect {
    var point = CGPoint.zero
    var size = CGSize.zero
    if let value = attribute(element, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
    }
    if let value = attribute(element, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
        AXValueGetValue(value as! AXValue, .cgSize, &size)
    }
    return CGRect(origin: point, size: size)
}

func descendants(_ root: AXUIElement, depth: Int = 8) -> [AXUIElement] {
    guard depth > 0 else { return [] }
    return children(root).flatMap { [$0] + descendants($0, depth: depth - 1) }
}

func waitFor(_ message: String, _ predicate: () -> Bool) throws {
    let deadline = Date().addingTimeInterval(10)
    repeat {
        if predicate() { return }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline
    throw OpenerError(message)
}

func mouse(_ type: CGEventType, _ point: CGPoint) throws {
    guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
        throw OpenerError("Cannot create a native mouse event")
    }
    event.post(tap: .cghidEventTap)
}

let chromeScript = """
on run argv
    tell application "Google Chrome"
        if item 1 of argv is "create" then
            set w to make new window
            set URL of active tab of w to item 2 of argv
            activate
            return id of w as text
        end if
        set windowID to item 2 of argv as integer
        if not (exists window id windowID) then return "absent"
        set w to window id windowID
        if item 1 of argv is "exists" then return "present"
        if item 1 of argv is "tab" then
            set t to make new tab at end of tabs of w with properties {URL:item 3 of argv}
            set active tab index of w to count of tabs of w
        else if item 1 of argv is "navigate" then
            set URL of active tab of w to item 3 of argv
        else if item 1 of argv is "bounds" then
            set bounds of w to {item 3 of argv as integer, item 4 of argv as integer, item 5 of argv as integer, item 6 of argv as integer}
        end if
        set index of w to 1
        activate
        return "ok"
    end tell
end run
"""

func chrome(_ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", chromeScript, "--"] + arguments
    let output = Pipe(), errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    let error = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard process.terminationStatus == 0 else {
        throw OpenerError("Chrome Automation failed. Allow the launching terminal to control Google Chrome in System Settings > Privacy & Security > Automation. \(error.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

func windowList(onScreen: Bool) -> [[String: Any]] {
    CGWindowListCopyWindowInfo(onScreen ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
}

func windowFrame(_ info: [String: Any]) -> CGRect {
    guard let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return .zero }
    return CGRect(dictionaryRepresentation: bounds) ?? .zero
}

func sameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) < 3 && abs(a.minY - b.minY) < 3 && abs(a.width - b.width) < 3 && abs(a.height - b.height) < 3
}

struct SpaceLayout {
    let display: String
    let index: Int
    let count: Int
    let windows: [Int]
}

// These read-only SkyLight queries identify native Spaces without relying on changing terminal titles.
final class NativeSpaces {
    typealias Connection = @convention(c) () -> UInt32
    typealias CopySpaces = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    let library: UnsafeMutableRawPointer
    let connection: UInt32
    let copySpaces: CopySpaces

    init() throws {
        guard let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
            throw OpenerError("macOS SkyLight Space metadata is unavailable; native pairing was not attempted")
        }
        guard let connection = dlsym(library, "SLSMainConnectionID"),
              let copySpaces = dlsym(library, "SLSCopyManagedDisplaySpaces") else {
            dlclose(library)
            throw OpenerError("This macOS version lacks the read-only native Space queries required for safe targeting")
        }
        self.library = library
        self.connection = unsafeBitCast(connection, to: Connection.self)()
        self.copySpaces = unsafeBitCast(copySpaces, to: CopySpaces.self)
    }

    deinit { dlclose(library) }

    func layout(windowID: Int) -> SpaceLayout? {
        guard let displays = copySpaces(connection)?.takeRetainedValue() as? [[String: Any]] else { return nil }
        for display in displays {
            guard let identifier = display["Display Identifier"] as? String,
                  let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            for (index, space) in spaces.enumerated() {
                let manager = space["TileLayoutManager"] as? [String: Any]
                let tiles = manager?["TileSpaces"] as? [[String: Any]] ?? []
                let windows = tiles.compactMap { $0["TileWindowID"] as? Int }
                if windows.contains(windowID) {
                    return SpaceLayout(display: identifier, index: index, count: spaces.count, windows: windows)
                }
            }
        }
        return nil
    }
}

func run() throws {
    guard CommandLine.arguments.count == 2,
          let url = URL(string: CommandLine.arguments[1]),
          ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
          !CommandLine.arguments[1].unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || $0.value < 32 || $0.value == 127 }) else {
        throw OpenerError("Usage: herdr-split-view <absolute HTTP(S) URL>")
    }
    guard AXIsProcessTrusted() else {
        throw OpenerError("Accessibility permission is missing. Allow the launching terminal (WezTerm) in System Settings > Privacy & Security > Accessibility, then retry the link. No URL was opened.")
    }
    guard let terminal = NSWorkspace.shared.frontmostApplication,
          terminal.bundleIdentifier == "com.github.wez.wezterm" else {
        throw OpenerError("Ctrl-click from the originating WezTerm window. Refusing to choose a different terminal after focus has changed.")
    }
    let terminalApp = AXUIElementCreateApplication(terminal.processIdentifier)
    guard let focused = attribute(terminalApp, kAXFocusedWindowAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else {
        throw OpenerError("Cannot identify the focused WezTerm window. Check Accessibility permission.")
    }
    let terminalWindow = focused as! AXUIElement
    guard fullscreen(terminalWindow) else { throw OpenerError("Put the originating WezTerm window in native full-screen mode, then retry.") }
    let terminalFrame = frame(terminalWindow)
    let candidates = windowList(onScreen: true).filter {
        ($0[kCGWindowOwnerPID as String] as? Int32) == terminal.processIdentifier && sameFrame(windowFrame($0), terminalFrame)
    }
    guard candidates.count == 1, let terminalID = candidates[0][kCGWindowNumber as String] as? Int else {
        throw OpenerError("Cannot uniquely identify the visible originating terminal window. Retry with its full-screen Space visible.")
    }
    let spaces = try NativeSpaces()
    guard let originSpace = spaces.layout(windowID: terminalID) else {
        throw OpenerError("Cannot identify the terminal's native full-screen Space. This macOS Space metadata format may need an update.")
    }
    var displayCount: UInt32 = 0
    var displays = [CGDirectDisplayID](repeating: 0, count: 16)
    guard CGGetActiveDisplayList(16, &displays, &displayCount) == .success,
          let display = displays.prefix(Int(displayCount)).first(where: { CGDisplayBounds($0).contains(CGPoint(x: terminalFrame.midX, y: terminalFrame.midY)) }) else {
        throw OpenerError("Cannot identify the terminal display")
    }
    let screen = CGDisplayBounds(display)
    guard NSWorkspace.shared.urlForApplication(toOpen: url)?.lastPathComponent == "Google Chrome.app" else {
        throw OpenerError("Native Herdr pairing currently supports Google Chrome as the default HTTP(S) browser. The system default was not changed.")
    }

    let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state/herdr-split-view")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let lock = Darwin.open(directory.appendingPathComponent("lock").path, O_CREAT | O_RDWR, 0o600)
    guard lock >= 0 else { throw OpenerError("Cannot open the native pairing lock") }
    defer { Darwin.close(lock) }
    guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw OpenerError("Another Herdr link is arranging Split View. Retry when that operation finishes.") }
    let stateFile = directory.appendingPathComponent("windows.json")
    var state = (try? JSONDecoder().decode([String: [String: Int]].self, from: Data(contentsOf: stateFile))) ?? [:]
    let key = "\(terminal.processIdentifier):\(terminalID)"
    let previousBrowser = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.google.Chrome" }
    var browserID = state[key]?["browserPID"] == previousBrowser.map({ Int($0.processIdentifier) }) ? state[key]?["window"] : nil
    if let id = browserID, try chrome(["exists", String(id)]) == "absent" { browserID = nil }
    let marker = "about:blank#hs-\(UUID().uuidString.prefix(8))"
    let created = browserID == nil
    if browserID == nil {
        guard terminalFrame.width > screen.width * 0.95 else {
            throw OpenerError("The originating terminal is already paired with another window. Close that partner before retrying; it was not rearranged.")
        }
        guard let id = Int(try chrome(["create", marker])) else { throw OpenerError("Chrome did not return a window identifier") }
        browserID = id
        var browserPID: Int?
        try waitFor("Chrome did not register its new window with macOS") {
            browserPID = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.google.Chrome" }.map { Int($0.processIdentifier) }
            return browserPID != nil
        }
        state[key] = ["window": id, "browserPID": browserPID!]
        try JSONEncoder().encode(state).write(to: stateFile, options: .atomic)
    }
    let id = browserID!
    var browserProcess: NSRunningApplication?
    try waitFor("Google Chrome is not registered with macOS after opening its designated window") {
        browserProcess = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.google.Chrome" }
        return browserProcess != nil
    }
    let browser = browserProcess!
    let browserApp = AXUIElementCreateApplication(browser.processIdentifier)
    // The Chrome scripting window ID is not a Core Graphics window ID. Activate only our window to resolve its AX reference.
    _ = try chrome(["focus", String(id)])
    var browserWindow: AXUIElement?
    try waitFor("Cannot identify the designated Chrome window. Check Automation and Accessibility permissions.") {
        guard let value = attribute(browserApp, kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        browserWindow = (value as! AXUIElement)
        return true
    }
    let window = browserWindow!
    var browserWindowID: Int?
    try waitFor("Cannot uniquely identify the designated visible Chrome window") {
        let matches = windowList(onScreen: true).filter {
            ($0[kCGWindowOwnerPID as String] as? Int32) == browser.processIdentifier && sameFrame(windowFrame($0), frame(window))
        }
        guard matches.count == 1 else { return false }
        browserWindowID = matches[0][kCGWindowNumber as String] as? Int
        return browserWindowID != nil
    }
    func nativePair() -> Bool {
        guard let layout = spaces.layout(windowID: terminalID) else { return false }
        return layout.display == originSpace.display && layout.windows.count == 2 && layout.windows.contains(browserWindowID!)
    }
    func paired() -> Bool {
        let left = frame(terminalWindow), right = frame(window)
        let visibleWindows = windowList(onScreen: true)
        let browserVisible = visibleWindows.contains {
            ($0[kCGWindowOwnerPID as String] as? Int32) == browser.processIdentifier && sameFrame(windowFrame($0), right)
        }
        let terminalVisible = visibleWindows.contains { ($0[kCGWindowNumber as String] as? Int) == terminalID }
        return nativePair() && fullscreen(terminalWindow) && fullscreen(window) && browserVisible && terminalVisible
            && abs(left.minX - screen.minX) < 3 && abs(right.maxX - screen.maxX) < 3
            && left.width < screen.width * 0.95 && right.width < screen.width * 0.95
            && abs(right.minX - left.maxX) < 24 && left.height > screen.height * 0.8 && right.height > screen.height * 0.8
    }
    if paired() {
        _ = try chrome(["tab", String(id), CommandLine.arguments[1]])
        print("Reused native Split View")
        return
    }
    guard terminalFrame.width > screen.width * 0.95 else {
        throw OpenerError("The originating terminal is paired with another window. Close that partner before retrying; it was not rearranged.")
    }
    if fullscreen(window) {
        guard AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse) == .success else {
            throw OpenerError("Cannot take the designated browser out of its previous full-screen Space")
        }
        try waitFor("The designated browser did not leave its previous full-screen Space") { !fullscreen(window) }
    }
    if !created { _ = try chrome(["tab", String(id), marker]) }
    _ = try chrome(["bounds", String(id), String(Int(screen.minX + 40)), String(Int(screen.minY + 60)), String(Int(screen.minX + 940)), String(Int(screen.minY + 960))])
    try waitFor("The designated Chrome window did not reach the terminal display") { screen.contains(CGPoint(x: frame(window).midX, y: frame(window).midY)) }
    usleep(700_000)
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { throw OpenerError("Dock is not running") }
    let dockApp = AXUIElementCreateApplication(dock.processIdentifier)
    func missionControl() -> AXUIElement? { children(dockApp).first { title($0) == "Mission Control" } }
    guard missionControl() == nil else { throw OpenerError("Mission Control is already open. Exit it and Ctrl-click again.") }
    let launch = Process()
    launch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    launch.arguments = ["-a", "Mission Control"]
    try launch.run()
    launch.waitUntilExit()
    var mission: AXUIElement?
    defer {
        if missionControl() != nil {
            let escape = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)
            escape?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
        }
    }
    try waitFor("Mission Control did not open. Check Accessibility permission and retry.") { mission = missionControl(); return mission != nil }
    func terminalSpaceButton() -> AXUIElement? {
        guard let layout = spaces.layout(windowID: terminalID), layout.display == originSpace.display else { return nil }
        let bars = descendants(mission!).filter {
            title($0) == "Spaces Bar" && screen.contains(CGPoint(x: frame($0).midX, y: frame($0).midY))
        }
        guard bars.count == 1,
              let list = children(bars[0]).first(where: { attribute($0, kAXRoleAttribute) as? String == kAXListRole }) else { return nil }
        let buttons = children(list).filter { attribute($0, kAXRoleAttribute) as? String == kAXButtonRole }
        guard buttons.count == layout.count, buttons.indices.contains(layout.index) else { return nil }
        return buttons[layout.index]
    }
    var start = CGRect.zero, destination = CGRect.zero
    var stableSamples = 0
    try waitFor("Mission Control did not expose a unique designated browser thumbnail") {
        let thumbnails = descendants(mission!).filter { title($0).contains(marker) && attribute($0, kAXRoleAttribute) as? String == kAXButtonRole }
        guard thumbnails.count == 1 else { return false }
        let nextStart = frame(thumbnails[0])
        stableSamples = sameFrame(start, nextStart) ? stableSamples + 1 : 0
        start = nextStart
        return stableSamples >= 5
    }
    let from = CGPoint(x: start.midX, y: start.midY)
    try mouse(.mouseMoved, from)
    do {
        try mouse(.leftMouseDown, from)
        var held = true
        defer { if held { try? mouse(.leftMouseUp, from) } }
        var hoverOffset = 0.0
        stableSamples = 0
        // Resolve the drop target while dragging: leaving the Spaces Bar before a drag collapses and repositions it.
        try waitFor("Mission Control did not expose a unique, stable terminal Space; no window picker was accepted.") {
            hoverOffset = hoverOffset == 0 ? 1 : 0
            try? mouse(.leftMouseDragged, CGPoint(x: screen.midX + hoverOffset, y: screen.minY + 5))
            guard let target = terminalSpaceButton(), frame(target).height > 40 else { stableSamples = 0; return false }
            let nextDestination = frame(target)
            stableSamples = sameFrame(destination, nextDestination) ? stableSamples + 1 : 0
            destination = nextDestination
            return stableSamples >= 5
        }
        let to = CGPoint(x: destination.minX + destination.width * 0.8, y: destination.midY)
        try mouse(.leftMouseDragged, to)
        usleep(1_000_000)
        try mouse(.leftMouseUp, to)
        held = false
    }
    try waitFor("macOS did not pair the designated browser with the originating terminal in native Split View") { nativePair() }
    stableSamples = 0
    try waitFor("Mission Control did not finish presenting the new Split View Space") {
        guard let pair = terminalSpaceButton(), title(pair) == "WezTerm & Google Chrome" else { return false }
        let next = frame(pair)
        stableSamples = sameFrame(destination, next) ? stableSamples + 1 : 0
        destination = next
        return stableSamples >= 5
    }
    let enter = CGPoint(x: destination.midX, y: destination.midY)
    try mouse(.mouseMoved, enter)
    try mouse(.leftMouseDown, enter)
    try mouse(.leftMouseUp, enter)
    try waitFor("The new Split View Space could not be entered") { missionControl() == nil }
    try waitFor("The native Split View Space exists, but its window placement could not be verified") { paired() }
    _ = try chrome(["navigate", String(id), CommandLine.arguments[1]])
    print("Created native Split View")
}

do { try run() }
catch {
    FileHandle.standardError.write(Data("herdr-split-view: \(error)\n".utf8))
    exit(1)
}
