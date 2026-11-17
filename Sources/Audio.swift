import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import ApplicationServices

final class SystemAudio: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let lock = NSLock()
    private var features = AudioFeatures()
    private var analyzer = PCMFeatures()
    private var lastSample = 0.0
    private var generation = 0
    var onError: ((String) -> Void)?
    func read() -> AudioFeatures {
        lock.lock(); defer { lock.unlock() }
        return ProcessInfo.processInfo.systemUptime - lastSample < 0.5 ? features : AudioFeatures()
    }
    func start() {
        stop()
        generation += 1
        let token = generation
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard token == generation, let display = content.displays.first else { return }
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.width = 2; config.height = 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                config.capturesAudio = true; config.excludesCurrentProcessAudio = true
                config.sampleRate = 48000; config.channelCount = 2
                if #available(macOS 15.0, *) { config.captureMicrophone = false }
                let next = SCStream(filter: filter, configuration: config, delegate: self)
                try next.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "airpause.audio"))
                stream = next
                try await next.startCapture()
                if token != generation { try? await next.stopCapture() }
            } catch {
                if token == generation { onError?("系统音频未连接：请允许「屏幕与系统音频录制」，然后重试。") }
            }
        }
    }
    func stop() {
        generation += 1
        if let old = stream { Task { try? await old.stopCapture() } }
        stream = nil
        lock.lock(); features = AudioFeatures(); analyzer = PCMFeatures(); lastSample = 0; lock.unlock()
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            guard self.stream === stream else { return }
            self.onError?("系统音频已断开；形象保持轻缓呼吸，可在音乐设置中重试。")
        }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        try? sampleBuffer.withAudioBufferList { buffers, retained in
            guard let desc = sampleBuffer.formatDescription?.audioStreamBasicDescription,
                  let format = AVAudioFormat(standardFormatWithSampleRate: desc.mSampleRate, channels: desc.mChannelsPerFrame),
                  let pcm = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: buffers.unsafePointer),
                  let channels = pcm.floatChannelData, pcm.frameLength > 0 else { return }
            let n = Int(pcm.frameLength)
            var mono = [Float](repeating: 0, count: n)
            for c in 0..<Int(format.channelCount) {
                for i in 0..<n { mono[i] += channels[c][i] / Float(format.channelCount) }
            }
            lock.lock()
            features = analyzer.analyze(mono, sampleRate: format.sampleRate)
            lastSample = ProcessInfo.processInfo.systemUptime
            lock.unlock()
            _ = retained
        }
    }
}

final class LocalAudioFeatures {
    private let queue = DispatchQueue(label: "airpause.local-features", qos: .userInitiated)
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var result = AudioFeatures()
    private var updated = 0.0
    private var pending = false
    init(url: URL) { queue.async { self.file = try? AVAudioFile(forReading: url) } }
    func sample(at time: Double) -> AudioFeatures {
        lock.lock()
        let output = ProcessInfo.processInfo.systemUptime - updated < 0.5 ? result : AudioFeatures()
        let request = !pending; if request { pending = true }
        lock.unlock()
        if request {
            queue.async {
                var features = AudioFeatures()
                if let file = self.file,
                   let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 2048) {
                    file.framePosition = min(max(0, AVAudioFramePosition(time * file.processingFormat.sampleRate)), max(0, file.length - 1))
                    if (try? file.read(into: buffer, frameCount: 2048)) != nil,
                       let channels = buffer.floatChannelData, buffer.frameLength > 0 {
                        let n = Int(buffer.frameLength), count = Int(buffer.format.channelCount)
                        var mono = [Float](repeating: 0, count: n)
                        for c in 0..<count { for i in 0..<n { mono[i] += channels[c][i] / Float(count) } }
                        var analyzer = PCMFeatures()
                        features = analyzer.analyze(mono, sampleRate: buffer.format.sampleRate)
                    }
                }
                self.lock.lock(); self.result = features; self.updated = ProcessInfo.processInfo.systemUptime; self.pending = false; self.lock.unlock()
            }
        }
        return output
    }
}

final class MusicController {
    private var player: AVAudioPlayer?
    private var localFeatures: LocalAudioFeatures?
    let system = SystemAudio()
    var message = "内置原创节奏 · 无需音乐账户"
    private var externalGeneration = 0
    func stop() {
        externalGeneration += 1
        player?.stop(); player = nil; localFeatures = nil; system.stop()
        // An external player belongs to the user. Never send a blind play/pause toggle on exit.
    }
    func play(_ p: Preferences) {
        stop()
        if p.source == .builtIn || p.source == .local {
            let url = p.source == .builtIn ? Bundle.main.url(forResource: "LittleIntermission", withExtension: "wav") : URL(fileURLWithPath: p.localPath)
            guard let url else { message = "未找到音乐，请重新选择音频文件。"; return }
            do {
                let next = try AVAudioPlayer(contentsOf: url)
                next.isMeteringEnabled = true; next.numberOfLoops = -1; next.volume = Float(p.volume)
                guard next.play() else { message = "音频无法播放，请选择其他文件。"; return }
                player = next; localFeatures = LocalAudioFeatures(url: url)
                message = p.source == .builtIn ? "正在播放 · Little Intermission / 原创循环" : "正在播放 · \(url.lastPathComponent)"
            } catch { message = "无法读取音乐文件，请重新选择。\(error.localizedDescription)" }
            return
        }
        if CGPreflightScreenCaptureAccess() { system.start() }
        else { message = "播放器已请求打开；允许系统音频后才能随真实音乐变化。" }
        openExternal(p)
    }
    func features() -> AudioFeatures {
        if let player, player.isPlaying {
            if let localFeatures { return localFeatures.sample(at: player.currentTime) }
            player.updateMeters()
            return AudioFeatures(level: min(1, sqrt(pow(10, Double(player.averagePower(forChannel: 0)) / 20)) * 1.35))
        }
        return system.read()
    }
    func meter() -> Double { features().level }
    func setVolume(_ value: Double) { player?.volume = Float(value) }
    func requestCapture() { system.start(); message = "正在连接系统音频；如有权限提示，请允许后重试。" }

    private func openExternal(_ p: Preferences) {
        let identifier: String
        switch p.source {
        case .appleMusic: identifier = "com.apple.Music"
        case .netease: identifier = "com.netease.163music"
        case .spotify: identifier = "com.spotify.client"
        default: return
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
            message = "这台 Mac 尚未安装所选播放器，可以先用内置音乐或本地文件。"; return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        let token = externalGeneration
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                guard token == self.externalGeneration else { return }
                if error != nil { self.message = "播放器打开失败，请手动启动后重试。"; return }
                if !p.playlist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    guard let url = Self.playlistURL(p.playlist, source: p.source) else {
                        self.message = "歌单链接与播放器不匹配，请检查音乐设置。"; return
                    }
                    NSWorkspace.shared.open(url)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    guard token == self.externalGeneration else { return }
                    self.targetedPlay(identifier)
                }
            }
        }
    }
    static func playlistURL(_ text: String, source: MusicSource) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", let host = url.host?.lowercased() else { return nil }
        let domain: String
        switch source { case .appleMusic: domain = "music.apple.com"; case .netease: domain = "music.163.com"; case .spotify: domain = "open.spotify.com"; default: return nil }
        return host == domain ? url : nil
    }
    private func targetedPlay(_ id: String) {
        let token = externalGeneration
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else {
            message = "已打开播放器；请点播放，或在音乐设置中允许辅助功能以自动播放。"; return
        }
        // Query only this player's menus; no global media keys and no shell / AppleScript interpolation.
        DispatchQueue.global(qos: .userInitiated).async {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.3)
            func get(_ e: AXUIElement, _ attr: String) -> CFTypeRef? {
                var value: CFTypeRef?
                return AXUIElementCopyAttributeValue(e, attr as CFString, &value) == .success ? value : nil
            }
            var items: [(String, AXUIElement)] = []
            var visited = 0
            func walk(_ e: AXUIElement, _ depth: Int) {
                guard depth < 6, visited < 250 else { return }; visited += 1
                if let role = get(e, kAXRoleAttribute) as? String, role == kAXMenuItemRole,
                   (get(e, kAXEnabledAttribute) as? Bool) == true,
                   let title = get(e, kAXTitleAttribute) as? String {
                    items.append((title.replacingOccurrences(of: " ", with: "").lowercased(), e))
                }
                if let children = get(e, kAXChildrenAttribute) as? [AXUIElement] { children.forEach { walk($0, depth + 1) } }
            }
            if let menu = get(element, kAXMenuBarAttribute) { walk(menu as! AXUIElement, 0) }
            var result = "播放器未提供播放菜单，请在播放器中选择歌曲。"
            if items.contains(where: { ["暂停", "pause"].contains($0.0) }) { result = "播放器菜单显示正在播放 · 等待真实音频" }
            else if let item = items.first(where: { ["播放", "play", "播放/暂停", "play/pause"].contains($0.0) }) {
                let sent = DispatchQueue.main.sync {
                    token == self.externalGeneration && AXUIElementPerformAction(item.1, kAXPressAction as CFString) == .success
                }
                if sent { result = "已发送播放请求 · 等待真实音频" }
            }
            DispatchQueue.main.async { if token == self.externalGeneration { self.message = result } }
        }
    }
}
