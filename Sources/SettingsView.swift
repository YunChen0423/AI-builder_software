import SwiftUI
import ApplicationServices

/// One small preferences sheet. No dashboard, navigation, preview or device console.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    var onHeightChange: (CGFloat) -> Void = { _ in }
    private let accent = Color(NSColor(hex: 0x236BFF))
    private let muted = Color.secondary
    private var externalMusic: Bool { ![MusicSource.builtIn, .local].contains(model.preferences.source) }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("休息提醒").font(.system(size: 12, weight: .medium))
                Spacer()
                Toggle("", isOn: $model.preferences.autoReminder).labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            HStack {
                Text("工作").foregroundStyle(muted)
                Stepper(value: $model.preferences.workMinutes, in: 1...120, step: 1) { Text("\(Int(model.preferences.workMinutes)) 分钟").monospacedDigit() }
                Spacer(minLength: 14)
                Text("休息").foregroundStyle(muted)
                Stepper(value: $model.preferences.restMinutes, in: 0.25...15, step: 0.25) { Text("\(String(format: "%g", model.preferences.restMinutes)) 分钟").monospacedDigit() }
            }.font(.system(size: 11))
            Divider()
            row("音乐") {
                Picker("音乐", selection: $model.preferences.source) {
                    Text("内置音乐").tag(MusicSource.builtIn)
                    Text("本地歌曲").tag(MusicSource.local)
                    Text("Apple Music").tag(MusicSource.appleMusic)
                    Text("网易云音乐").tag(MusicSource.netease)
                    Text("Spotify").tag(MusicSource.spotify)
                }.labelsHidden().onChange(of: model.preferences.source) { _ in model.replay(); resize() }
            }
            if model.preferences.source == .local {
                HStack {
                    Text(model.preferences.localPath.isEmpty ? "尚未选择歌曲" : URL(fileURLWithPath: model.preferences.localPath).lastPathComponent).foregroundStyle(muted).lineLimit(1)
                    Spacer()
                    Button("选择…") { model.chooseMusic() }
                }.font(.system(size: 11))
            }
            if externalMusic {
                TextField("喜欢的歌单链接（选填）", text: $model.preferences.playlist).textFieldStyle(.roundedBorder)
                HStack {
                    Button("允许自动播放") { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }
                    Button("连接音乐声音") { model.music.requestCapture() }
                }.font(.system(size: 10))
            } else {
                row("音量") { Slider(value: $model.preferences.volume, in: 0...1).accessibilityLabel("音量") }
            }
            Divider()
            row("色调") {
                HStack(spacing: 12) {
                    ForEach(Palette.allCases, id: \.self) { palette in
                        Button { model.preferences.palette = palette } label: {
                            Circle().fill(LinearGradient(colors: paletteColors(palette).map(Color.init), startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 27, height: 27)
                                .overlay(Circle().stroke(.white, lineWidth: 3).padding(2))
                                .overlay(Circle().stroke(model.preferences.palette == palette ? accent : .clear, lineWidth: 1.5))
                        }.buttonStyle(.plain).help([Palette.iris: "电光紫", .sunrise: "炽热橙", .lagoon: "酸性绿", .pearl: "RGB 霓虹"][palette]!)
                    }
                    Spacer(minLength: 0)
                }
            }
            row("亮度") { Slider(value: $model.preferences.brightness, in: 0...1).accessibilityLabel("灯光亮度") }
            row("动感") {
                VStack(spacing: 2) {
                    Slider(value: $model.preferences.intensity, in: 0...1).accessibilityLabel("动作强度")
                    HStack { Text("柔和"); Spacer(); Text("尽兴") }.font(.system(size: 9)).foregroundStyle(muted)
                }
            }
            row("烟花") {
                Picker("烟花形态", selection: $model.preferences.fireworkStyle) {
                    ForEach(FireworkStyle.allCases, id: \.self) { style in Text(style.title).tag(style) }
                }.labelsHidden().disabled(!model.preferences.fireworks)
            }
            DisclosureGroup("几何参数", isExpanded: $model.geometryExpanded) {
                VStack(spacing: 10) {
                    Picker("粒子元素", selection: $model.preferences.particleElement) {
                        ForEach(ParticleElement.allCases, id: \.self) { element in Text(element.title).tag(element) }
                    }
                    HStack(spacing: 16) {
                        parameter("扩散", $model.preferences.particleSpread)
                        parameter("旋转", $model.preferences.particleSpin)
                    }
                    HStack(spacing: 16) {
                        parameter("密度", $model.preferences.particleDensity)
                        parameter("拖尾", $model.preferences.particleTrail)
                    }
                }.padding(.top, 8)
            }.font(.system(size: 11)).onChange(of: model.geometryExpanded) { _ in resize() }
            row("运动") {
                Picker("运动方式", selection: $model.preferences.motionStyle) {
                    ForEach(MotionStyle.allCases, id: \.self) { style in Text(style.title).tag(style) }
                }.labelsHidden()
            }
            HStack {
                Toggle("满屏烟花", isOn: $model.preferences.fireworks)
                Spacer()
                Toggle("桌面游走", isOn: $model.preferences.roaming)
            }.toggleStyle(.checkbox)
        }
        .font(.system(size: 12))
        .padding(22).frame(width: 360)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(NSColor(hex: 0xF7F9FC)))
        .tint(accent).preferredColorScheme(.light).onAppear { resize() }
    }
    private func resize() { onHeightChange((externalMusic ? 510 : (model.preferences.source == .local ? 500 : 460)) + (model.geometryExpanded ? 145 : 0)) }
    private func parameter(_ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue * 100))").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: 0...1).accessibilityLabel(title)
        }.font(.system(size: 10))
    }
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 15) {
            Text(label).foregroundStyle(muted).frame(width: 34, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
