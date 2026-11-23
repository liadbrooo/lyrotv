import SwiftUI
import AppKit
import AVKit
import AVFoundation
import UniformTypeIdentifiers
import Combine

private let accent = Color(red: 0.42, green: 0.76, blue: 1)
private func clock(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let n = Int(min(seconds, 35999999))
    return n >= 3600 ? String(format: "%d:%02d:%02d", n/3600, n/60%60, n%60) : String(format: "%d:%02d", n/60, n%60)
}
struct Media: Codable, Identifiable, Equatable {
    let url: URL
    var id: URL { url }
    var name: String { url.isFileURL ? url.deletingPathExtension().lastPathComponent : (url.lastPathComponent.isEmpty ? (url.host ?? "Stream") : url.lastPathComponent) }
}
struct Cue {
    let start: Double
    let end: Double
    let text: String
}
func parseCaptions(_ source: String) -> [Cue] {
    func time(_ raw: String) -> Double? {
        let parts = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":")
        let nums = parts.compactMap { Double($0) }
        guard nums.count == parts.count, (2...3).contains(nums.count), nums.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        return nums.reduce(0) { $0 * 60 + $1 }
    }
    let lines = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
    var result: [Cue] = []
    var i = 0
    while i < lines.count {
        let sides = lines[i].components(separatedBy: "-->")
        if sides.count == 2, let start = time(sides[0]), let token = sides[1].split(whereSeparator: \.isWhitespace).first, let end = time(String(token)), end > start {
            i += 1
            var body: [String] = []
            while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                body.append(lines[i].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)); i += 1
            }
            if !body.isEmpty { result.append(Cue(start: start, end: end, text: body.joined(separator: "\n"))) }
        } else { i += 1 }
    }
    return result.sorted { $0.start < $1.start }
}

final class Player: ObservableObject {
    static let shared = Player()
    let engine = AVPlayer()
    @Published var queue: [Media] = []
    @Published var recent: [Media] = []
    @Published var current: Media?
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var playing = false
    @Published var buffering = false
    @Published var volume = 0.8 { didSet { engine.volume = Float(volume); defaults.set(volume, forKey: "volume") } }
    @Published var muted = false { didSet { engine.isMuted = muted } }
    @Published var speed = 1.0
    @Published var loop = false
    @Published var shuffle = false
    @Published var error: String?
    @Published var caption = ""
    @Published var captionFile: String?
    @Published var fill = false
    @Published var sidebar = true
    @Published var info = false
    @Published var size = CGSize.zero
    @Published var status = "Bereit"
    @Published var urlDialog = false
    @Published var resume = true { didSet { defaults.set(resume, forKey: "resume") } }
    @Published var autoplay = true { didSet { defaults.set(autoplay, forKey: "autoplay") } }
    @Published var autoHide = true { didSet { defaults.set(autoHide, forKey: "autoHide") } }
    @Published var captionsEnabled = true
    private let defaults = UserDefaults.standard
    private var marks: [String: Double] = [:]
    private var cues: [Cue] = []
    private var periodic: Any?
    private var endObserver: NSObjectProtocol?
    private var timer: Timer?
    private var pendingResume: Double?
    private var tick = 0
    private var failed = false
    init() {
        if let data = defaults.data(forKey: "recent"), let saved = try? JSONDecoder().decode([Media].self, from: data) { recent = saved }
        marks = defaults.dictionary(forKey: "positions") as? [String: Double] ?? [:]
        if defaults.object(forKey: "volume") != nil { volume = defaults.double(forKey: "volume") }
        resume = defaults.object(forKey: "resume") as? Bool ?? true
        autoplay = defaults.object(forKey: "autoplay") as? Bool ?? true
        autoHide = defaults.object(forKey: "autoHide") as? Bool ?? true
        engine.volume = Float(volume)
        engine.actionAtItemEnd = .pause
        periodic = engine.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.15, preferredTimescale: 600), queue: .main) { [weak self] t in self?.refresh(t.seconds) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in self?.refresh(self?.engine.currentTime().seconds ?? 0) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            guard let self = self, let ended = note.object as? AVPlayerItem, ended === self.engine.currentItem else { return }
            self.finished()
        }
    }
    deinit {
        if let periodic = periodic { engine.removeTimeObserver(periodic) }
        if let endObserver = endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timer?.invalidate()
    }
    func refresh(_ seconds: Double) {
        guard let item = engine.currentItem else { return }
        if seconds.isFinite && seconds >= 0 && abs(position - seconds) > 0.01 { position = seconds }
        let d = item.duration.seconds
        let newDuration = d.isFinite && d > 0 ? d : 0
        if duration != newDuration { duration = newDuration }
        let newPlaying = engine.rate != 0
        if playing != newPlaying { playing = newPlaying }
        let newBuffering = engine.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if buffering != newBuffering { buffering = newBuffering }
        if size != item.presentationSize { size = item.presentationSize }
        if item.status == .failed && !failed {
            failed = true
            error = item.error?.localizedDescription ?? "Dieses Medium kann nicht abgespielt werden."
        }
        if item.status == .readyToPlay, let p = pendingResume, duration > 0 {
            pendingResume = nil
            if p > 3 && p < duration - 5 { seek(p) }
        }
        let newStatus = failed ? "Wiedergabefehler" : (item.status == .unknown ? "Wird geladen" : (buffering ? "Puffert …" : (playing ? "Wiedergabe" : "Pausiert")))
        if status != newStatus { status = newStatus }
        let nextCaption = captionsEnabled ? (cues.first { $0.start <= position && position < $0.end }?.text ?? "") : ""
        if caption != nextCaption { caption = nextCaption }
        tick += 1
        if tick % 25 == 0, playing, pendingResume == nil { savePosition() }
    }
    func savePosition() {
        guard let current = current, current.url.isFileURL, position.isFinite, pendingResume == nil, duration > 0 else { return }
        marks[current.url.absoluteString] = position >= duration - 3 ? 0 : position
        defaults.set(marks, forKey: "positions")
    }
    func chooseFiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true; p.canChooseDirectories = false
        p.allowedContentTypes = [.movie, .audiovisualContent, .mpeg4Movie, .quickTimeMovie, .audio]
        p.allowsOtherFileTypes = true
        if p.runModal() == .OK { add(p.urls, playFirst: true) }
    }
    func add(_ urls: [URL], playFirst: Bool) {
        let valid = urls.filter { u in u.isFileURL || ["http","https"].contains(u.scheme?.lowercased() ?? "") }
        guard let first = valid.first else { return }
        for url in valid where !queue.contains(where: { $0.url == url }) { queue.append(Media(url: url)) }
        if playFirst || current == nil { open(Media(url: first)) }
    }
    func openURL(_ raw: String) {
        guard let u = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)), ["http","https"].contains(u.scheme?.lowercased() ?? ""), u.host != nil else {
            error = "Bitte eine gültige HTTP- oder HTTPS-Medienadresse eingeben."; return
        }
        add([u], playFirst: true)
    }
    func open(_ media: Media) {
        if current == media, engine.currentItem != nil, !failed { engine.playImmediately(atRate: Float(speed)); return }
        savePosition()
        if media.url.isFileURL && !FileManager.default.fileExists(atPath: media.url.path) { error = "Die Datei wurde verschoben oder gelöscht."; return }
        engine.pause()
        current = media; position = 0; duration = 0; size = .zero; failed = false; error = nil
        caption = ""; cues = []; captionFile = nil; status = "Wird geladen"
        pendingResume = resume && media.url.isFileURL ? marks[media.url.absoluteString] : nil
        if !queue.contains(media) { queue.append(media) }
        if media.url.isFileURL {
            recent.removeAll { $0 == media }; recent.insert(media, at: 0); recent = Array(recent.prefix(50))
            if let data = try? JSONEncoder().encode(recent) { defaults.set(data, forKey: "recent") }
        }
        engine.replaceCurrentItem(with: AVPlayerItem(url: media.url))
        engine.playImmediately(atRate: Float(speed))
    }
    func toggle() {
        guard current != nil else { chooseFiles(); return }
        if engine.timeControlStatus != .paused { engine.pause(); savePosition() }
        else {
            if duration > 0 && position >= duration - 0.15 { seek(0) }
            engine.playImmediately(atRate: Float(speed))
        }
        playing = engine.rate != 0
    }
    func seek(_ target: Double) {
        guard target.isFinite, duration > 0 else { return }
        let t = min(max(0, target), duration)
        position = t
        engine.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func setSpeed(_ rate: Double) {
        speed = rate
        if engine.timeControlStatus != .paused { engine.rate = Float(rate) }
    }
    func step(_ delta: Int) {
        engine.pause(); engine.currentItem?.step(byCount: delta)
    }
    func next(_ direction: Int = 1) {
        guard !queue.isEmpty else { return }
        if shuffle && direction > 0, let other = queue.filter({ $0 != current }).randomElement() { open(other); return }
        let i = current.flatMap { queue.firstIndex(of: $0) } ?? (direction > 0 ? -1 : queue.count)
        let n = i + direction
        if queue.indices.contains(n) { open(queue[n]) }
    }
    private func finished() {
        savePosition()
        if loop { seek(0); engine.playImmediately(atRate: Float(speed)) }
        else if autoplay { next() }
    }
    func remove(_ media: Media) { queue.removeAll { $0 == media } }
    func clearHistory() {
        recent = []; marks = [:]
        defaults.removeObject(forKey: "recent"); defaults.removeObject(forKey: "positions")
    }
    func loadCaptions() {
        guard current != nil else { error = "Öffne zuerst ein Video."; return }
        let p = NSOpenPanel(); p.allowsMultipleSelection = false
        p.allowedContentTypes = [.plainText]; p.allowsOtherFileTypes = true
        if p.runModal() == .OK, let url = p.url {
            do {
                let data = try Data(contentsOf: url)
                let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
                let parsed = parseCaptions(raw ?? "")
                guard !parsed.isEmpty else { error = "Keine gültigen SRT-/VTT-Untertitel gefunden."; return }
                cues = parsed; captionFile = url.lastPathComponent; captionsEnabled = true
            } catch { self.error = error.localizedDescription }
        }
    }
    func unloadCaptions() { cues = []; caption = ""; captionFile = nil }
    func snapshot() {
        guard let media = current, media.url.isFileURL else { error = "Standbilder sind für lokale Videodateien verfügbar."; return }
        let time = engine.currentTime()
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = media.name + "-frame.png"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: media.url))
        generator.appliesPreferredTrackTransform = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let cg = try generator.copyCGImage(at: time, actualTime: nil)
                guard let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                try png.write(to: destination, options: .atomic)
            } catch { DispatchQueue.main.async { self.error = error.localizedDescription } }
        }
    }
    func fullScreen() { NSApp.keyWindow?.toggleFullScreen(nil) }
}
struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer
    let fill: Bool
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
        view.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }
}
struct ToolButton: View {
    let symbol: String
    let label: String
    var active = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                .foregroundStyle(active ? accent : Color.white.opacity(0.86))
                .frame(width: 34, height: 34)
                .background(hover ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).onHover { inside in withAnimation(.easeOut(duration: 0.13)) { hover = inside } }.help(label).accessibilityLabel(label)
    }
}
struct Root: View {
    @ObservedObject var p: Player
    @Environment(\.accessibilityReduceMotion) var reduced
    @State private var tab = 0
    @State private var search = ""
    @State private var dragging = false
    @State private var scrub = 0.0
    @State private var controlsVisible = true
    @State private var hoverTransport = false
    @State private var lastActivity = Date()
    @State private var drop = false
    @State private var address = ""
    private var animation: Animation? { reduced ? nil : .easeInOut(duration: 0.22) }
    private var showTransport: Bool { !p.autoHide || !p.playing || controlsVisible || hoverTransport || dragging || p.current == nil }
    var body: some View {
        HStack(spacing: 0) {
            if p.sidebar { sidePanel.frame(width: 250).transition(.move(edge: .leading).combined(with: .opacity)); Divider().overlay(.white.opacity(0.06)) }
            VStack(spacing: 0) {
                header
                ZStack(alignment: .bottom) {
                    Color.black
                    if p.current != nil {
                        VideoSurface(player: p.engine, fill: p.fill)
                        if p.buffering { ProgressView().controlSize(.large).tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity) }
                        if !p.caption.isEmpty {
                            Text(p.caption).font(.system(size: 22, weight: .semibold)).multilineTextAlignment(.center).padding(.horizontal, 16).padding(.vertical, 7)
                                .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 7)).padding(.bottom, showTransport ? 110 : 28).allowsHitTesting(false)
                        }
                    } else { empty }
                    if showTransport {
                        transport
                            .onHover { hoverTransport = $0; lastActivity = Date() }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if drop { RoundedRectangle(cornerRadius: 12).strokeBorder(accent, style: StrokeStyle(lineWidth: 2, dash: [8])).padding(12).allowsHitTesting(false) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .onContinuousHover { phase in
                    switch phase {
                    case .active(_):
                        lastActivity = Date()
                        if !controlsVisible { withAnimation(animation) { controlsVisible = true } }
                    case .ended: break
                    }
                }
                
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $drop) { providers in
                    for (i, provider) in providers.enumerated() {
                        _ = provider.loadObject(ofClass: NSURL.self) { url, _ in
                            if let url = url as? NSURL { DispatchQueue.main.async { p.add([url as URL], playFirst: i == 0) } }
                        }
                    }
                    return !providers.isEmpty
                }
                if p.info && p.current != nil { details.transition(.move(edge: .bottom).combined(with: .opacity)) }
                
            }
        }
        .background(Color(red: 0.065, green: 0.075, blue: 0.095))
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .frame(minWidth: 760, minHeight: 490)
        .onReceive(Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()) { now in
            if controlsVisible && p.playing && p.autoHide && !hoverTransport && !dragging && now.timeIntervalSince(lastActivity) > 3 {
                withAnimation(animation) { controlsVisible = false }
            }
        }
        .onChange(of: p.current) { _ in lastActivity = Date(); controlsVisible = true }
        .animation(animation, value: p.sidebar).animation(animation, value: p.info).animation(animation, value: p.playing)
        .alert("Lyro Motion", isPresented: Binding(get: { p.error != nil }, set: { if !$0 { p.error = nil } })) { Button("OK") { p.error = nil } } message: { Text(p.error ?? "") }
        .sheet(isPresented: $p.urlDialog) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Netzwerkstream öffnen").font(.title2.bold())
                Text("Direkte HTTP(S)-Adresse, beispielsweise MP4 oder HLS (.m3u8).").foregroundStyle(.secondary)
                TextField("https://…", text: $address).textFieldStyle(.roundedBorder)
                HStack { Spacer(); Button("Abbrechen") { p.urlDialog = false }.keyboardShortcut(.cancelAction); Button("Öffnen") { p.urlDialog = false; p.openURL(address); address = "" }.keyboardShortcut(.defaultAction) }
            }.padding(24).frame(width: 460)
        }
    }
    var header: some View {
        HStack(spacing: 8) {
            ToolButton(symbol: "sidebar.left", label: "Mediathek ein-/ausblenden", active: p.sidebar) { p.sidebar.toggle() }
            VStack(alignment: .leading, spacing: 3) {
                Text(p.current?.name ?? "Lyro Motion").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(p.current == nil ? "DEIN KINO. DEIN MAC." : p.status.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
            }
            Spacer()
            ToolButton(symbol: "folder", label: "Dateien öffnen") { p.chooseFiles() }
            ToolButton(symbol: "link", label: "Netzwerkstream") { p.urlDialog = true }
            ToolButton(symbol: "info.circle", label: "Medieninformationen", active: p.info) { p.info.toggle() }
            ToolButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Vollbild") { p.fullScreen() }
        }.padding(.horizontal, 14).padding(.vertical, 9)
    }
    var empty: some View {
        VStack(spacing: 19) {
            ZStack {
                RoundedRectangle(cornerRadius: 25).fill(LinearGradient(colors: [accent.opacity(0.22), Color.indigo.opacity(0.13)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 96, height: 96)
                Image(systemName: "play.rectangle.fill").font(.system(size: 43, weight: .light)).foregroundStyle(accent)
            }
            Text("Alles bereit für dein nächstes Video.").font(.system(size: 25, weight: .semibold))
            Text("Dateien hierher ziehen oder direkt vom Mac öffnen.").font(.system(size: 13)).foregroundStyle(.secondary)
            Button { p.chooseFiles() } label: {
                Label("Video öffnen", systemImage: "plus").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 21).padding(.vertical, 12)
                    .foregroundStyle(.black).background(accent, in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain)
            Button("Netzwerkstream öffnen") { p.urlDialog = true }.buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 12))
            Text("⌘ O  ·  Dateien öffnen").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    var sidePanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                Image(systemName: "play.square.stack").font(.system(size: 24, weight: .semibold)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("LYRO").font(.system(size: 11, weight: .heavy)).tracking(3)
                    Text("Motion").font(.system(size: 20, weight: .semibold))
                }
                Spacer()
            }.padding(.top, 18)
            Picker("Mediathek", selection: $tab) { Text("Warteschlange").tag(0); Text("Verlauf").tag(1) }.pickerStyle(.segmented).labelsHidden()
            TextField("Suchen", text: $search).textFieldStyle(.roundedBorder)
            HStack {
                Text(tab == 0 ? "WIEDERGABELISTE" : "ZULETZT GEÖFFNET").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                Spacer()
                Text(String(tab == 0 ? p.queue.count : p.recent.count)).font(.caption).foregroundStyle(.secondary)
            }
            let items = (tab == 0 ? p.queue : p.recent).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(items) { m in
                        Button { p.open(m) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: p.current == m ? "waveform" : (m.url.isFileURL ? "film" : "globe"))
                                    .font(.system(size: 15)).foregroundStyle(p.current == m ? accent : .secondary).frame(width: 30, height: 36)
                                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(m.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text(m.url.isFileURL ? m.url.pathExtension.uppercased() : "STREAM").font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if p.current == m { Circle().fill(accent).frame(width: 6, height: 6) }
                            }.padding(6).background(p.current == m ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).contextMenu {
                            Button("Abspielen") { p.open(m) }
                            if tab == 0 { Button("Entfernen") { p.remove(m) } }
                            if m.url.isFileURL { Button("Im Finder anzeigen") { NSWorkspace.shared.activateFileViewerSelecting([m.url]) } }
                        }
                    }
                    if items.isEmpty { Text(search.isEmpty ? "Noch keine Medien." : "Keine Treffer.").font(.caption).foregroundStyle(.secondary).padding(.top, 24) }
                }
            }
            Divider()
            HStack {
                Button { p.chooseFiles() } label: { Label("Hinzufügen", systemImage: "plus") }.buttonStyle(.plain).foregroundStyle(accent)
                Spacer()
                if tab == 1 { Button("Löschen") { p.clearHistory() }.buttonStyle(.plain).foregroundStyle(.secondary) }
            }.font(.caption)
            Text("LYRO MOTION   /   1.0").font(.system(size: 9, design: .monospaced)).tracking(1.2).foregroundStyle(.tertiary)
        }.padding(15).background(Color(red: 0.09, green: 0.105, blue: 0.13))
    }
    var transport: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text(clock(dragging ? scrub : p.position)).frame(width: 52, alignment: .leading)
                Slider(value: Binding(get: { dragging ? scrub : min(p.position, max(p.duration, 1)) }, set: { if dragging { scrub = $0 } else { p.seek($0) } }), in: 0...max(p.duration, 1), onEditingChanged: { active in
                    if active { scrub = p.position; dragging = true } else { dragging = false; p.seek(scrub) }
                }).tint(accent).disabled(p.duration <= 0).accessibilityLabel("Wiedergabeposition")
                Text(p.duration > 0 ? clock(p.duration) : "–:––").frame(width: 52, alignment: .trailing)
            }.font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ToolButton(symbol: "shuffle", label: "Zufällige Reihenfolge", active: p.shuffle) { p.shuffle.toggle() }
                ToolButton(symbol: "repeat", label: "Video wiederholen", active: p.loop) { p.loop.toggle() }
                Spacer(minLength: 3)
                ToolButton(symbol: "backward.end.fill", label: "Vorheriges Video") { p.next(-1) }
                ToolButton(symbol: "gobackward.10", label: "10 Sekunden zurück") { p.seek(p.position-10) }
                Button { p.toggle() } label: {
                    Image(systemName: p.playing ? "pause.fill" : "play.fill").font(.system(size: 21, weight: .semibold)).frame(width: 48, height: 48)
                        .foregroundStyle(.black).background(accent, in: Circle())
                }.buttonStyle(.plain).help("Wiedergabe / Pause").accessibilityLabel(p.playing ? "Pause" : "Wiedergabe")
                ToolButton(symbol: "goforward.10", label: "10 Sekunden vor") { p.seek(p.position+10) }
                ToolButton(symbol: "forward.end.fill", label: "Nächstes Video") { p.next() }
                Spacer(minLength: 3)
                Menu {
                    ForEach([0.25,0.5,0.75,1,1.25,1.5,1.75,2,3], id: \.self) { rate in Button(String(format: "%g×",rate)) { p.setSpeed(rate) } }
                } label: { Text(String(format: "%g×", p.speed)).font(.system(size: 12, weight: .semibold)) }.menuStyle(.borderlessButton).fixedSize().help("Wiedergabegeschwindigkeit")
                Menu {
                    Button("SRT / VTT öffnen …") { p.loadCaptions() }
                    Toggle("Externe Untertitel anzeigen", isOn: $p.captionsEnabled)
                    Button("Externe Untertitel entfernen") { p.unloadCaptions() }.disabled(p.captionFile == nil)
                    Divider()
                    if let group = p.engine.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .legible), let item = p.engine.currentItem {
                        Button("Eingebettete Untertitel aus") { item.select(nil, in: group) }
                        ForEach(Array(group.options.enumerated()), id: \.offset) { pair in Button(pair.element.displayName) { item.select(pair.element, in: group) } }
                    }
                    if let group = p.engine.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .audible), let item = p.engine.currentItem {
                        Divider()
                        ForEach(Array(group.options.enumerated()), id: \.offset) { pair in Button("Audio: " + pair.element.displayName) { item.select(pair.element, in: group) } }
                    }
                } label: { Image(systemName: "captions.bubble").font(.system(size: 16)) }.menuStyle(.borderlessButton).fixedSize().help("Untertitel und Tonspuren")
                ToolButton(symbol: p.fill ? "rectangle.expand.vertical" : "aspectratio", label: "Bildgröße", active: p.fill) { p.fill.toggle() }
                ToolButton(symbol: p.muted || p.volume == 0 ? "speaker.slash" : "speaker.wave.2", label: "Stumm schalten", active: p.muted) { p.muted.toggle() }
                Slider(value: $p.volume, in: 0...1).tint(accent).frame(width: 63).accessibilityLabel("Lautstärke")
            }
        }.padding(.horizontal, 17).padding(.vertical, 10).background(.ultraThinMaterial)
    }
    var details: some View {
        HStack(spacing: 18) {
            Label(p.current?.url.isFileURL == true ? "Lokale Datei" : "Netzwerk", systemImage: "film")
            if p.size.width > 0 { Text("\(Int(p.size.width)) × \(Int(p.size.height))") }
            Text("Dauer: " + clock(p.duration))
            if let c = p.captionFile { Text(c).lineLimit(1) }
            Spacer()
            Button("Standbild sichern") { p.snapshot() }.buttonStyle(.bordered)
        }.font(.caption).foregroundStyle(.secondary).padding(12).background(.white.opacity(0.05))
    }
}
struct Preferences: View {
    @ObservedObject var p: Player
    var body: some View {
        Form {
            Section("Wiedergabe") {
                Toggle("Lokale Videos an letzter Position fortsetzen", isOn: $p.resume)
                Toggle("Nächstes Video automatisch abspielen", isOn: $p.autoplay)
                Toggle("Steuerung während der Wiedergabe ausblenden", isOn: $p.autoHide)
            }
            Section("Datenschutz") {
                Text("Der Verlauf bleibt auf diesem Mac. Netzwerkstreams verbinden sich direkt mit ihrer Quelle.").foregroundStyle(.secondary)
                Button("Verlauf und Wiedergabepositionen löschen", role: .destructive) { p.clearHistory() }
            }
        }.padding(24).frame(width: 470, height: 250)
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) { Player.shared.add(urls, playFirst: true) }
    func applicationWillTerminate(_ notification: Notification) { Player.shared.savePosition() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
@main struct LyroMotionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var p = Player.shared
    var body: some Scene {
        WindowGroup("Lyro Motion") { Root(p: p) }.defaultSize(width: 1150, height: 720)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("Dateien öffnen …") { p.chooseFiles() }.keyboardShortcut("o")
                    Button("Netzwerkstream öffnen …") { p.urlDialog = true }.keyboardShortcut("u")
                }
                CommandMenu("Wiedergabe") {
                    Button("Wiedergabe / Pause") { p.toggle() }.keyboardShortcut(.space, modifiers: [])
                    Button("10 Sekunden zurück") { p.seek(p.position-10) }.keyboardShortcut(.leftArrow, modifiers: [])
                    Button("10 Sekunden vor") { p.seek(p.position+10) }.keyboardShortcut(.rightArrow, modifiers: [])
                    Button("Vorheriges Video") { p.next(-1) }.keyboardShortcut(.leftArrow, modifiers: [.command])
                    Button("Nächstes Video") { p.next() }.keyboardShortcut(.rightArrow, modifiers: [.command])
                    Divider()
                    Button("Ein Bild zurück") { p.step(-1) }.keyboardShortcut(",", modifiers: [])
                    Button("Ein Bild vor") { p.step(1) }.keyboardShortcut(".", modifiers: [])
                    Button("Stumm") { p.muted.toggle() }.keyboardShortcut("m", modifiers: [.shift,.command])
                    Button("Lauter") { p.volume = min(1,p.volume+0.05) }.keyboardShortcut(.upArrow, modifiers: [])
                    Button("Leiser") { p.volume = max(0,p.volume-0.05) }.keyboardShortcut(.downArrow, modifiers: [])
                    Divider()
                    Button("Untertitel öffnen …") { p.loadCaptions() }.keyboardShortcut("s", modifiers: [.shift,.command])
                    Button("Standbild speichern …") { p.snapshot() }.keyboardShortcut("p", modifiers: [.shift,.command])
                    Button("Vollbild") { p.fullScreen() }.keyboardShortcut("f", modifiers: [.control,.command])
                }
            }
        Settings { Preferences(p: p) }
    }
}
