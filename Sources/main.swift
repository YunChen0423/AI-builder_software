import AppKit
import SwiftUI

final class AirPanel: NSPanel { override var canBecomeKey: Bool { false }; override var canBecomeMain: Bool { false } }

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel(testing: (CommandLine.arguments.contains("--snapshot") || CommandLine.arguments.contains("--interaction-smoke")))
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow!
    private var sculpture: SculptureView!
    private var overlay: AirPanel!
    private var effects: [(AirPanel, FireworksView)] = []
    private var roamTimer: Timer?
    private var roamStart = 0.0
    private var draggedUntil = 0.0
    private var rightClickRegion = RightClickRegion()
    private var rightClickMonitor: Any?
    private var contextMenuOpen = false
    private var motionClock = 0.0
    private var lastRoamUpdate = 0.0
    private var keyMonitor: Any?
    private var localKeyMonitor: Any?
    private var stage = NSRect.zero
    private var pathOffset = CGPoint.zero
    private var activeMotionStyle: MotionStyle = .bounce
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "wind", accessibilityDescription: "气间 AirPause")
        statusItem.button?.toolTip = "右键偏好设置 · 左键休息控制"
        statusItem.button?.target = self; statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        settingsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        settingsWindow.title = "气间 · 偏好设置"; settingsWindow.titlebarAppearsTransparent = true
        settingsWindow.backgroundColor = NSColor(hex: 0xF7F9FC)
        settingsWindow.contentView = NSHostingView(rootView: SettingsView(model: model, onHeightChange: { [weak self] height in
            self?.settingsWindow.setContentSize(NSSize(width: 360, height: height))
        }))
        settingsWindow.isReleasedWhenClosed = false; settingsWindow.delegate = self
        settingsWindow.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        overlay = AirPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 480), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        overlay.isOpaque = false; overlay.backgroundColor = .clear; overlay.hasShadow = false
        overlay.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        overlay.hidesOnDeactivate = false
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlay.isReleasedWhenClosed = false
        sculpture = SculptureView(); sculpture.model = model
        sculpture.contextAction = { [weak self] _ in self?.showControlMenu(at: NSEvent.mouseLocation) }
        // A mouse-only global monitor needs no keyboard monitoring or accessibility grant.
        rightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
            guard let self, self.model.session.phase == .resting else { return }
            let point = NSEvent.mouseLocation, now = ProcessInfo.processInfo.systemUptime
            guard self.rightClickRegion.contains(point, now: now) else { return }
            if CommandLine.arguments.contains("--interaction-smoke") {
                try? "globalRightClick=true\n".write(toFile: "/tmp/airpause-context-event.txt", atomically: true, encoding: .utf8)
            }
            DispatchQueue.main.async { self.showControlMenu(at: point) }
        }
        sculpture.dragEnded = { [weak self] in
            guard let self else { return }
            self.draggedUntil = ProcessInfo.processInfo.systemUptime + 15
            self.pathOffset = self.overlay.frame.origin
            self.roamStart = self.draggedUntil; self.motionClock = 0
        }
        overlay.contentView = sculpture
        model.onPhase = { [weak self] phase in self?.changePhase(phase) }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                if self?.settingsWindow.isVisible == true { self?.settingsWindow.orderOut(nil); return nil }
                if self?.model.session.phase == .resting { self?.finishRest(); return nil }
            }
            return event
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.model.session.phase == .resting { self?.finishRest() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if CommandLine.arguments.contains("--snapshot") { snapshot(); return }
        // Startup remains completely quiet. Preferences are only shown on demand.
        if CommandLine.arguments.contains("--preferences") { openSettings() }
        if CommandLine.arguments.contains("--demo") { startRest() }
        if CommandLine.arguments.contains("--smoke") { smoke() }
        if CommandLine.arguments.contains("--interaction-smoke") {
            model.preferences.roaming = false
            startRest(); openSettings()
            let point = CGPoint(x: overlay.frame.minX - 60, y: overlay.frame.midY)
            let info: [String: Double] = ["x": point.x, "y": point.y]
            if let data = try? JSONSerialization.data(withJSONObject: info) { try? data.write(to: URL(fileURLWithPath: "/tmp/airpause-context-point.json")) }
        }
        if CommandLine.arguments.contains("--bridge-smoke") {
            model.toggleBridge()
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { NSApp.terminate(nil) }
        }
    }
    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { openSettings(); return }
        let menu = NSMenu()
        menu.addItem(item("偏好设置…", #selector(openSettings), ""))
        menu.addItem(.separator())
        menu.addItem(item("现在休息一下", #selector(startRest), ""))
        menu.addItem(item("结束休息", #selector(finishRest), ""))
        menu.addItem(item("5 分钟后再提醒", #selector(snooze), ""))
        menu.addItem(.separator())
        menu.addItem(item("暂停 / 恢复提醒", #selector(pause), ""))
        menu.addItem(item("退出气间", #selector(quit), ""))
        if let button = statusItem.button { NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent!, for: button) }
    }
    private func item(_ title: String, _ selector: Selector, _ key: String) -> NSMenuItem { let m = NSMenuItem(title: title, action: selector, keyEquivalent: key); m.target = self; return m }
    @objc func openSettings() {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let safe = screen.visibleFrame
            let x = min(max(safe.minX, mouse.x - 180), safe.maxX - settingsWindow.frame.width)
            let y = min(max(safe.minY, mouse.y - settingsWindow.frame.height - 10), safe.maxY - settingsWindow.frame.height)
            settingsWindow.setFrameOrigin(CGPoint(x: x, y: y))
        }
        settingsWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func startRest() { model.startRest() }
    @objc func finishRest() { model.finish() }
    @objc func snooze() { model.snooze() }
    @objc func pause() { model.pause() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings(); return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown(); stopVisuals()
        if let rightClickMonitor { NSEvent.removeMonitor(rightClickMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
    }
    private func stopVisuals() {
        roamTimer?.invalidate(); roamTimer = nil
        overlay.orderOut(nil)
        sculpture.resetAnimation()
        for (panel, view) in effects { view.stop(); panel.orderOut(nil) }
        effects.removeAll()
    }
    @objc private func screensChanged() { changePhase(model.session.phase) }
    private func changePhase(_ phase: SessionPhase) {
        stopVisuals()
        guard phase == .resting else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        stage = screen.visibleFrame
        roamStart = ProcessInfo.processInfo.systemUptime; draggedUntil = 0
        lastRoamUpdate = roamStart; rightClickRegion.reset(); motionClock = 0
        activeMotionStyle = model.preferences.motionStyle
        let size = overlay.frame.size
        pathOffset = CGPoint(x: stage.midX - size.width / 2, y: stage.minY + 25)
        overlay.setFrameOrigin(pathOffset)
        rightClickRegion.track(overlay.frame, now: roamStart)
        // An independent transparent window for every display, with mouse events passed through.
        for display in NSScreen.screens {
            let panel = AirPanel(contentRect: display.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.level = .floating; panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            let view = FireworksView(); view.model = model; panel.contentView = view
            effects.append((panel, view)); panel.orderFrontRegardless(); view.start()
        }
        overlay.ignoresMouseEvents = true
        overlay.orderFrontRegardless()
        roamTimer = Timer.scheduledTimer(withTimeInterval: 1 / 45, repeats: true) { [weak self] _ in self?.roam() }
        RunLoop.main.add(roamTimer!, forMode: .common)
    }
    private func roam() {
        for (panel, _) in effects {
            if model.preferences.fireworks { if !panel.isVisible { panel.orderFrontRegardless() } }
            else if panel.isVisible { panel.orderOut(nil) }
        }
        let now = ProcessInfo.processInfo.systemUptime
        let delta = max(0, min(0.1, now - lastRoamUpdate)); lastRoamUpdate = now
        sculpture.displayIfNeeded()
        let pointer = NSEvent.mouseLocation
        if NSEvent.pressedMouseButtons == 0 {
            overlay.ignoresMouseEvents = !sculpture.containsScreenPoint(pointer, hotZone: false)
        }
        rightClickRegion.track(overlay.frame, now: now)
        if contextMenuOpen || NSEvent.pressedMouseButtons != 0 {
            roamStart += delta
            return
        }
        if activeMotionStyle != model.preferences.motionStyle {
            activeMotionStyle = model.preferences.motionStyle
            pathOffset = overlay.frame.origin; roamStart = now; motionClock = 0
        }
        guard model.preferences.roaming, model.preferences.motionStyle != .inPlace, now >= draggedUntil else { return }
        motionClock += delta * (0.15 + model.response.energy * 1.3 + model.response.bass * 0.4 + model.response.beat * 0.3)
        let t = motionClock
        let size = overlay.frame.size
        let travelX = max(0, stage.width - size.width), travelY = max(0, stage.height - size.height)
        let point = motionPosition(style: model.preferences.motionStyle, time: t, intensity: model.preferences.intensity)
        let envelope = min(1, t / 1.2)
        let x = stage.minX + travelX * point.x
        let y = stage.minY + travelY * point.y
        let origin = CGPoint(x: pathOffset.x + (x - pathOffset.x) * envelope,
                             y: pathOffset.y + (y - pathOffset.y) * envelope)
        overlay.setFrameOrigin(CGPoint(x: min(max(origin.x, stage.minX), stage.maxX - size.width),
                                       y: min(max(origin.y, stage.minY), stage.maxY - size.height)))
    }
    private func controlMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("结束休息", #selector(finishRest), ""))
        menu.addItem(item("偏好设置…", #selector(openSettings), ""))
        menu.addItem(.separator())
        menu.addItem(item("退出气间", #selector(quit), ""))
        return menu
    }
    private func showControlMenu(at point: CGPoint) {
        guard model.session.phase == .resting, !contextMenuOpen else { return }
        contextMenuOpen = true; sculpture.setInteractionPaused(true)
        // Activate before opening our menu, closing another app's transient context menu.
        NSApp.activate(ignoringOtherApps: true)
        controlMenu().popUp(positioning: nil, at: point, in: nil)
        contextMenuOpen = false; sculpture.setInteractionPaused(false)
    }
    private func smoke() {
        let quietStart = !settingsWindow.isVisible && !overlay.isVisible && effects.isEmpty
        startRest()
        var peak = 0.0
        let sampler = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in peak = max(peak, self.model.music.meter()) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            sampler.invalidate()
            let shown = self.overlay.isVisible && !self.settingsWindow.isVisible
            let fullscreen = self.effects.count == NSScreen.screens.count && self.effects.allSatisfy { panel, _ in
                panel.ignoresMouseEvents && NSScreen.screens.contains(where: { $0.frame == panel.frame })
            }
            let now = ProcessInfo.processInfo.systemUptime
            let outsideBody = CGPoint(x: self.overlay.frame.minX - 70, y: self.overlay.frame.midY)
            self.rightClickRegion.track(self.overlay.frame, now: now)
            let wideRegion = self.rightClickRegion.contains(outsideBody, now: now)
            let hoveringKeepsMoving = !self.sculpture.interactionPaused
            let menuActions = self.controlMenu().items.compactMap { $0.action }
            let menuReady = menuActions.contains(#selector(self.finishRest)) && menuActions.contains(#selector(self.openSettings))
            let musicPhase = self.model.response.phase, hueTravel = self.model.response.hueTravel
            self.finishRest()
            let hidden = !self.overlay.isVisible && self.effects.isEmpty
            let result = "quietStartup=\(quietStart) restVisible=\(shown) fullscreenClickThrough=\(fullscreen) workHidden=\(hidden) wideRightClickRegion=\(wideRegion) hoverNeverPauses=\(hoveringKeepsMoving) contextActions=\(menuReady) globalMonitor=\(self.rightClickMonitor != nil) audioPeak=\(peak) musicPhase=\(musicPhase) hueTravel=\(hueTravel)\n"
            try? result.write(toFile: "/tmp/airpause-smoke.txt", atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }
    private func save(_ view: NSView, _ path: String) {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
    }
    private func snapshot() {
        openSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            if let view = self.settingsWindow.contentView { self.save(view, "/tmp/airpause-preferences-v2.png") }
            self.model.geometryExpanded = true
            self.model.session.startRest(seconds: 60)
            self.model.energy = 0.85
            self.model.response.energy = 0.85; self.model.response.bass = 0.7
            self.model.response.treble = 0.6; self.model.response.beat = 0.65
            self.model.response.phase = 3; self.model.response.hueTravel = 0.4
            self.changePhase(.resting)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if let view = self.settingsWindow.contentView { self.save(view, "/tmp/airpause-geometry-settings.png") }
                if let (_, fx) = self.effects.first {
                    fx.prepareSnapshot()
                    self.save(fx, "/tmp/airpause-fireworks-v2.png")
                }
                var fitted = true
                let originalStyle = self.model.preferences.motionStyle
                for style in MotionStyle.allCases {
                    self.model.preferences.motionStyle = style
                    for frame in 0..<24 {
                        self.sculpture.forcedTime = Double(frame) * 0.41
                        self.sculpture.needsDisplay = true; self.sculpture.displayIfNeeded()
                        let safe = self.sculpture.bounds.insetBy(dx: 60, dy: 60)
                        fitted = fitted && safe.contains(self.sculpture.lastPaintBounds)
                    }
                }
                self.model.preferences.motionStyle = originalStyle
                try? "allMotionFramesFit=\(fitted)\n".write(toFile: "/tmp/airpause-bounds.txt", atomically: true, encoding: .utf8)
                self.sculpture.forcedTime = 10.5
                self.save(self.sculpture, "/tmp/airpause-inflated-v2.png")
                self.sculpture.forcedTime = 10.82
                self.save(self.sculpture, "/tmp/airpause-deflated-v2.png")
                NSApp.terminate(nil)
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
