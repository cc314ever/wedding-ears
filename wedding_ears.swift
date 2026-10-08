import Foundation
import AVFoundation
import ScreenCaptureKit
import Speech

// wedding_ears — a live listener for a guest's own Mac.
//
// Captures what the Mac is playing (ScreenCaptureKit system audio, no microphone),
// feeds it straight into Apple's on-device speech recognition, one transcriber per
// language, and writes the words to timestamped text files as they are said.
// Nothing leaves the machine. Built 2026-10-08 by Just Claude is Fine (JC, with
// Alice) for the Samhain wedding in Empyrius, after Alexander's point in the
// Laughing Circle: for many of us the words only arrive if they arrive as text.
//
// Engine: on macOS 26 and newer, Apple's SpeechAnalyzer/SpeechTranscriber (the new
// one: long-form, better, and it downloads a language itself the first time it is
// asked for). On macOS 13–15 it falls back to SFSpeechRecognizer, which needs the
// language added by hand under Keyboard → Dictation.
//
//   wedding_ears <outdir> <lang>[,<lang>...] [names.txt] [fixes.txt]
//   e.g.  wedding_ears ~/Wedding/2026-10-31 fr_FR,en_US names.txt fixes.txt
//
// Output in <outdir>:
//   <lang>.txt      one line per spoken segment: "HH:MM:SS  text"
//   <lang>.live     the sentence being recognized right now (overwritten)
//   audio.caf       the captured sound, kept beside the text
//   live.html       the last lines, big, refreshing itself (open it in a browser)
//   ears.log        what the program did
//
// Needs, once per Mac: System Settings → Privacy & Security → Screen & System
// Audio Recording → allow the terminal app; and Speech Recognition for it.
// The stream must play in an app that has a window (a browser, a player).

// ---------- arguments ----------
let args = CommandLine.arguments.dropFirst()
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: wedding_ears <outdir> <lang>[,<lang>] [names.txt] [fixes.txt]\n".data(using: .utf8)!)
    exit(2)
}
let outDir = URL(fileURLWithPath: (args.first! as NSString).expandingTildeInPath)
let langs = args.dropFirst().first!.split(separator: ",").map { String($0) }
var names: [String] = []
if args.count >= 3 {
    let p = (args.dropFirst(2).first! as NSString).expandingTildeInPath
    if let s = try? String(contentsOfFile: p, encoding: .utf8) {
        names = s.split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}
var fixes: [(String, String)] = []
do {
    let fixPath = args.count >= 4 ? (args.dropFirst(3).first! as NSString).expandingTildeInPath
        : (args.count >= 3 ? (URL(fileURLWithPath: (args.dropFirst(2).first! as NSString).expandingTildeInPath).deletingLastPathComponent().appendingPathComponent("fixes.txt").path) : "")
    if !fixPath.isEmpty, let f = try? String(contentsOfFile: fixPath, encoding: .utf8) {
        for line in f.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("#") { continue }
            let parts = l.components(separatedBy: "=>")
            if parts.count == 2 { fixes.append((parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces))) }
        }
    }
}
func fixed(_ t: String) -> String {
    var out = t
    for (wrong, right) in fixes {
        // whole words only, so "Hugin => Huginn" leaves "Huginn" alone
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: wrong) + "(?![\\p{L}\\p{N}])"
        if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out),
                                              withTemplate: NSRegularExpression.escapedTemplate(for: right))
        }
    }
    return out
}
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let logURL = outDir.appendingPathComponent("ears.log")
let stamp: () -> String = {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: Date())
}
let logLock = NSLock()
func log(_ s: String) {
    logLock.lock(); defer { logLock.unlock() }
    let line = "\(stamp())  \(s)\n"
    FileHandle.standardError.write(line.data(using: .utf8)!)
    if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
    else { try? line.write(to: logURL, atomically: true, encoding: .utf8) }
}
func append(_ url: URL, _ s: String) {
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(s.data(using: .utf8)!); h.closeFile() }
    else { try? s.write(to: url, atomically: true, encoding: .utf8) }
}

// ---------- speech permission ----------
let authSem = DispatchSemaphore(value: 0)
SFSpeechRecognizer.requestAuthorization { _ in authSem.signal() }
authSem.wait()
guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
    log("speech recognition permission denied (System Settings → Privacy & Security → Speech Recognition)"); exit(1)
}

// ---------- one Ear per language ----------
// An Ear owns the text files for a language and takes transcript pieces in.
// Two engines can drive it.
final class Ear {
    let lang: String
    let txt: URL, live: URL
    var current = ""          // text in flight
    var currentStart = ""     // clock when its first words arrived
    var committed: [String] = []
    var lastResult = Date()
    let lock = NSLock()
    init(lang: String) {
        self.lang = lang
        txt = outDir.appendingPathComponent("\(lang).txt")
        live = outDir.appendingPathComponent("\(lang).live")
    }
    private func commit(_ s: String) {
        let t = fixed(s.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !t.isEmpty, committed.last != t else { currentStart = ""; return }
        committed.append(t)
        append(txt, "\(currentStart.isEmpty ? stamp() : currentStart)  \(t)\n")
        currentStart = ""
    }
    // a piece of text that is still changing
    func partial(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        lastResult = Date()
        if current.isEmpty && !text.isEmpty { currentStart = stamp() }
        current = text
        try? (fixed(text) + "\n").write(to: live, atomically: true, encoding: .utf8)
    }
    // a finished piece of text
    func final(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        lastResult = Date()
        if currentStart.isEmpty { currentStart = stamp() }
        commit(text); current = ""
        try? "\n".write(to: live, atomically: true, encoding: .utf8)
    }
    func flush() { lock.lock(); commit(current); current = ""; lock.unlock() }
}

// ---------- engine A: SpeechAnalyzer (macOS 26+) ----------
@available(macOS 26.0, *)
final class AnalyzerEngine {
    let ear: Ear
    let locale: Locale
    var analyzer: SpeechAnalyzer?
    var transcriber: SpeechTranscriber?
    var input: AsyncStream<AnalyzerInput>.Continuation?
    var format: AVAudioFormat?
    var converter: AVAudioConverter?
    var started = false

    init(ear: Ear, locale: Locale) { self.ear = ear; self.locale = locale }

    func start() async -> Bool {
        let t = SpeechTranscriber(locale: locale,
                                  transcriptionOptions: [],
                                  reportingOptions: [.volatileResults],
                                  attributeOptions: [.audioTimeRange])
        // make sure the language is on the machine; download it if not
        if let req = try? await AssetInventory.assetInstallationRequest(supporting: [t]) {
            let t0 = Date()
            do { try await req.downloadAndInstall() } catch { log("\(ear.lang): language download failed: \(error)"); return false }
            if Date().timeIntervalSince(t0) > 2 { log("\(ear.lang): language model downloaded (first time only)") }
        }
        let a = SpeechAnalyzer(modules: [t])
        if !names.isEmpty {
            let ctx = AnalysisContext()
            ctx.contextualStrings = [AnalysisContext.ContextualStringsTag("names"): names]
            try? await a.setContext(ctx)
        }
        guard let fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t]) else {
            log("\(ear.lang): no audio format"); return false
        }
        format = fmt
        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        input = cont
        do { try await a.start(inputSequence: stream) } catch { log("\(ear.lang): analyzer start failed: \(error)"); return false }
        analyzer = a; transcriber = t; started = true
        // results arrive on their own task
        Task { [weak self] in
            guard let self = self else { return }
            do {
                for try await r in t.results {
                    let text = String(r.text.characters)
                    if r.isFinal { self.ear.final(text) } else { self.ear.partial(text) }
                }
            } catch { log("\(self.ear.lang): results ended: \(error)") }
        }
        return true
    }

    func feed(_ pcm: AVAudioPCMBuffer) {
        guard started, let fmt = format else { return }
        var buf = pcm
        if pcm.format != fmt {
            if converter == nil { converter = AVAudioConverter(from: pcm.format, to: fmt) }
            guard let conv = converter else { return }
            let ratio = fmt.sampleRate / pcm.format.sampleRate
            let cap = AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: cap) else { return }
            var consumed = false
            var err: NSError?
            conv.convert(to: out, error: &err) { _, status in
                if consumed { status.pointee = .noDataNow; return nil }
                consumed = true; status.pointee = .haveData; return pcm
            }
            if err != nil { return }
            buf = out
        }
        input?.yield(AnalyzerInput(buffer: buf))
    }
}

// ---------- engine B: SFSpeechRecognizer (macOS 13–15) ----------
final class LegacyEngine {
    let ear: Ear
    let recognizer: SFSpeechRecognizer
    var request: SFSpeechAudioBufferRecognitionRequest?
    var task: SFSpeechRecognitionTask?
    var requestStarted = Date()
    var gen = 0
    let lock = NSLock()

    init?(ear: Ear, locale: Locale) {
        guard let r = SFSpeechRecognizer(locale: locale), r.isAvailable, r.supportsOnDeviceRecognition else { return nil }
        self.ear = ear; self.recognizer = r
        r.queue = OperationQueue()
        start()
    }
    func start() {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        req.addsPunctuation = true
        if !names.isEmpty { req.contextualStrings = names }
        request = req; requestStarted = Date()
        gen += 1; let myGen = gen
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            guard myGen == self.gen else { return }
            if let r = result {
                let text = r.bestTranscription.formattedString
                // the on-device recognizer starts a fresh segment at a pause: the text shrinks
                self.ear.lock.lock(); let cur = self.ear.current; self.ear.lock.unlock()
                if text.count + 12 < cur.count { self.ear.final(cur) }
                if r.isFinal { self.ear.final(text); self.restart() } else { self.ear.partial(text) }
            }
            if let e = error {
                let msg = "\(e)"
                if !msg.contains("canceled") && !msg.contains("No speech") { log("\(self.ear.lang): \(msg)") }
                self.ear.flush(); self.restart()
            }
        }
    }
    func restart() {
        request?.endAudio(); task = nil; request = nil
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.lock.lock(); defer { self?.lock.unlock() }
            self?.start()
        }
    }
    func tick() {
        lock.lock(); defer { lock.unlock() }
        let age = Date().timeIntervalSince(requestStarted)
        ear.lock.lock(); let quiet = Date().timeIntervalSince(ear.lastResult); let busy = !ear.current.isEmpty; ear.lock.unlock()
        if (busy && quiet > 1.2) || (age > 55 && quiet > 1.5) || age > 120 { ear.flush(); restart() }
    }
    func feed(_ buf: AVAudioPCMBuffer) {
        lock.lock(); let r = request; lock.unlock()
        r?.append(buf)
    }
}

// ---------- audio capture ----------
final class Sink: NSObject, SCStreamOutput, SCStreamDelegate {
    var feeders: [(AVAudioPCMBuffer) -> Void] = []
    var file: AVAudioFile?
    var frames: Int64 = 0
    var peak: Float = 0
    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sb.isValid, let fd = sb.formatDescription, let asbd = fd.audioStreamBasicDescription else { return }
        let fmt = AVAudioFormat(standardFormatWithSampleRate: asbd.mSampleRate, channels: asbd.mChannelsPerFrame)!
        let n = AVAudioFrameCount(sb.numSamples)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n) else { return }
        pcm.frameLength = n
        var abl = AudioBufferList(); var block: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sb, bufferListSizeNeededOut: nil, bufferListOut: &abl,
            bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &block) == noErr else { return }
        let src = UnsafeMutableAudioBufferListPointer(&abl)
        for (ch, buf) in src.enumerated() where ch < Int(fmt.channelCount) {
            guard let data = buf.mData else { continue }
            let p = data.assumingMemoryBound(to: Float.self)
            let dst = pcm.floatChannelData![ch]
            let count = min(Int(n), Int(buf.mDataByteSize) / 4)
            for i in 0..<count { dst[i] = p[i]; if abs(p[i]) > peak { peak = abs(p[i]) } }
        }
        if file == nil {
            file = try? AVAudioFile(forWriting: outDir.appendingPathComponent("audio.caf"), settings: fmt.settings)
        }
        try? file?.write(from: pcm)
        frames += Int64(n)
        for f in feeders { f(pcm) }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { log("capture stopped: \(error)") }
}

// ---------- build the ears ----------
let ears = langs.map { Ear(lang: $0) }
var analyzerEngines: [AnyObject] = []
var legacyEngines: [LegacyEngine] = []
let sink = Sink()

let setupSem = DispatchSemaphore(value: 0)
Task {
    for ear in ears {
        var ok = false
        if #available(macOS 26.0, *) {
            let eng = AnalyzerEngine(ear: ear, locale: Locale(identifier: ear.lang))
            if await eng.start() {
                analyzerEngines.append(eng)
                sink.feeders.append { eng.feed($0) }
                log("\(ear.lang): on-device (SpeechAnalyzer)")
                ok = true
            }
        }
        if !ok {
            if let eng = LegacyEngine(ear: ear, locale: Locale(identifier: ear.lang)) {
                legacyEngines.append(eng)
                sink.feeders.append { eng.feed($0) }
                log("\(ear.lang): on-device (SFSpeechRecognizer; add the language under Keyboard → Dictation if it ever goes missing)")
            } else {
                log("\(ear.lang): no on-device recognizer for this language on this Mac")
            }
        }
    }
    setupSem.signal()
}
setupSem.wait()
guard !sink.feeders.isEmpty else { log("no recognizer could start"); exit(1) }
log("listening in \(langs.joined(separator: " + ")) with \(names.count) names and \(fixes.count) fixes → \(outDir.path)")

// ---------- start capture ----------
let contentSem = DispatchSemaphore(value: 0)
var content: SCShareableContent?
SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { c, err in
    if let err = err { log("screen/audio permission: \(err.localizedDescription)") }
    content = c; contentSem.signal()
}
contentSem.wait()
guard let display = content?.displays.first else {
    log("no display: allow this terminal under Screen & System Audio Recording, then restart the terminal"); exit(1)
}
let cfg = SCStreamConfiguration()
cfg.capturesAudio = true
cfg.excludesCurrentProcessAudio = true
cfg.sampleRate = 48000
cfg.channelCount = 1
cfg.width = 2; cfg.height = 2
cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg, delegate: sink)
try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: DispatchQueue(label: "audio"))
let startSem = DispatchSemaphore(value: 0)
stream.startCapture { err in if let err = err { log("capture start: \(err)") }; startSem.signal() }
startSem.wait()

// ---------- the page for the humans ----------
func writePage() {
    var body = ""
    for e in ears {
        e.lock.lock()
        let lines = e.committed.suffix(6)
        let cur = fixed(e.current)
        e.lock.unlock()
        body += "<h2>\(e.lang)</h2>"
        for l in lines { body += "<p>\(l.replacingOccurrences(of: "<", with: "&lt;"))</p>" }
        if !cur.isEmpty { body += "<p class=live>\(cur.replacingOccurrences(of: "<", with: "&lt;"))</p>" }
    }
    let html = """
    <!doctype html><meta charset=utf-8><meta http-equiv=refresh content=1><title>wedding ears</title>
    <style>body{background:#111;color:#eee;font:28px/1.4 -apple-system,Helvetica,sans-serif;margin:24px}
    h2{font-size:16px;color:#999;margin:18px 0 4px;text-transform:uppercase;letter-spacing:.1em}
    p{margin:6px 0}.live{color:#f0c060}</style>
    \(body)
    """
    try? html.write(to: outDir.appendingPathComponent("live.html"), atomically: true, encoding: .utf8)
}

// ---------- stop cleanly on Ctrl-C ----------
signal(SIGINT) { _ in
    for e in ears { e.flush() }
    sink.file = nil
    log("stopped; \(Int(Double(sink.frames)/48000.0)) s of audio, peak \(String(format: "%.2f", sink.peak))")
    exit(0)
}

var lastPeakLog = Date()
var pageTick = 0
while true {
    Thread.sleep(forTimeInterval: 0.3)
    for e in legacyEngines { e.tick() }
    pageTick += 1
    if pageTick % 3 == 0 { writePage() }
    if Date().timeIntervalSince(lastPeakLog) > 30 {
        log("audio \(Int(Double(sink.frames)/48000.0))s, peak so far \(String(format: "%.2f", sink.peak))\(sink.peak < 0.001 ? "  (SILENCE: is the stream playing in a window?)" : "")")
        lastPeakLog = Date()
    }
}
