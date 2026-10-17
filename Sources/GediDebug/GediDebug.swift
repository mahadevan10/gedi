import AVFoundation
import Foundation
import GediCore
import GediSystem

/// `gedi-debug <command>`: exercise one subsystem at a time without the UI.
@main
struct GediDebug {
    static let usage = """
    usage: gedi-debug <command>
      persona                         print the built-in persona (setup copies it to Application Support)
      install-speech [locale]         download Apple's speech model (default ml-IN)
      transcribe <file> [locale]      transcribe an audio file
      say <text> [--out file.wav]     speak Malayalam text with Piper (or save the WAV)
      comment <activity> [--model m]  ask the LLM for an unprompted comment
      reply <utterance> [activity] [--model m]   ask the LLM to answer the user
      activity [seconds]              print the classified frontmost activity every 2 s
      listen [seconds]                live mic: print transcripts and wake/utterance events
      record [clip-id]                record clips.json lines that have no audio yet (or re-record one)
    """

    @MainActor
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else { fail(usage) }
        let command = args.removeFirst()
        do {
            var config = try GediConfig.load(from: GediPaths.configFile)
            if let i = args.firstIndex(of: "--model"), i + 1 < args.count {
                config.model = args[i + 1]
                args.removeSubrange(i...(i + 1))
            }
            switch command {
            case "persona": print(Persona.defaultText)
            case "install-speech": try await installSpeech(args.first ?? config.localeID)
            case "transcribe": try await transcribe(args, config)
            case "say": try await say(args, config)
            case "comment": try await comment(args, config)
            case "reply": try await reply(args, config)
            case "activity": try await activity(Double(args.first ?? "") ?? 30)
            case "listen": try await listen(Double(args.first ?? "") ?? 60, config)
            case "record": try await record(args.first)
            default: fail(usage)
            }
        } catch {
            fail("error: \(error)")
        }
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }

    static func installSpeech(_ locale: String) async throws {
        try await SpeechModels.ensureInstalled(localeID: locale)
        print("speech model installed for \(locale)")
    }

    static func transcribe(_ args: [String], _ config: GediConfig) async throws {
        guard let path = args.first else { fail(usage) }
        let start = Date()
        let text = try await SpeechModels.transcribe(file: URL(fileURLWithPath: path), localeID: args.dropFirst().first ?? config.localeID)
        print(text)
        print(String(format: "(%.2fs)", Date().timeIntervalSince(start)))
    }

    @MainActor
    static func say(_ args: [String], _ config: GediConfig) async throws {
        var args = args
        var out: String?
        if let i = args.firstIndex(of: "--out"), i + 1 < args.count {
            out = args[i + 1]
            args.removeSubrange(i...(i + 1))
        }
        guard let text = args.first else { fail(usage) }
        let server = PiperServer(config: config)
        try await server.start()
        let start = Date()
        let wav = try await server.client.synthesize(text)
        print(String(format: "synthesised %d bytes in %.2fs", wav.count, Date().timeIntervalSince(start)))
        if let out {
            try wav.write(to: URL(fileURLWithPath: out))
            print("wrote \(out)")
        } else {
            try await AudioOut().play(data: wav)
        }
        server.stop()
    }

    static func brain(_ config: GediConfig) throws -> GediBrain {
        let clips = try ClipLibrary.load(from: GediPaths.clipsDir)
        let persona = Persona.load(from: GediPaths.personaFile)
        return GediBrain(model: config.chatModel(),
                         builder: PromptBuilder(persona: persona, clips: clips.clips))
    }

    static func comment(_ args: [String], _ config: GediConfig) async throws {
        guard let activity = args.first else { fail(usage) }
        let start = Date()
        let r = try await brain(config).comment(activity: activity)
        print(String(format: "[%@, %.1fs] %@", config.model, Date().timeIntervalSince(start), String(describing: r)))
    }

    static func reply(_ args: [String], _ config: GediConfig) async throws {
        guard let utterance = args.first else { fail(usage) }
        let activity = args.dropFirst().first ?? "Now: Visual Studio Code (for 5 min straight)"
        let start = Date()
        let r = try await brain(config).reply(to: utterance, activity: activity)
        print(String(format: "[%@, %.1fs] %@", config.model, Date().timeIntervalSince(start), String(describing: r)))
    }

    @MainActor
    static func activity(_ seconds: Double) async throws {
        let probe = ActivityProbe()
        var log = ActivityLog()
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let snap = probe.snapshot() {
                let a = ActivityClassifier.classify(snap)
                log.record(a, at: Date())
                print("\(a.kind.rawValue)\t\(a.name)\t\(a.detail ?? "")\t\(snap.url ?? "")")
            }
            try await Task.sleep(for: .seconds(2))
        }
        print("---\n" + log.summary(now: Date()).promptText())
    }

    /// Walks clips.json: shows each line, records it from the mic, plays it back, keep or redo.
    @MainActor
    static func record(_ only: String?) async throws {
        let dir = GediPaths.clipsDir
        // Read the manifest directly: ClipLibrary.load drops clips whose audio is missing, which are the ones we want.
        let all = try JSONDecoder().decode([ClipInfo].self, from: Data(contentsOf: dir.appendingPathComponent("clips.json")))
        let todo = all.filter { clip in
            only.map { clip.id == $0 } ?? !FileManager.default.fileExists(atPath: dir.appendingPathComponent(clip.file).path)
        }
        if todo.isEmpty { print(only.map { "no clip with id \($0)" } ?? "every clip already has audio") }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1]
        for (n, clip) in todo.enumerated() {
            let url = dir.appendingPathComponent(clip.file)
            // Record to a temp file so a skipped re-record never touches the existing clip.
            let take = FileManager.default.temporaryDirectory.appendingPathComponent("gedi-take.m4a")
            var keep = false
            while !keep {
                print("\n[\(n + 1)/\(todo.count)] \(clip.id)  (\(clip.use))\n    \(clip.text)")
                print("Enter = record, s = skip, q = quit")
                let cmd = readLine()
                if cmd == "q" { return }
                if cmd == "s" { break }
                let rec = try AVAudioRecorder(url: take, settings: settings)
                guard rec.record() else { fail("could not start recording (microphone permission for this terminal?)") }
                print("● recording… Enter to stop")
                _ = readLine()
                rec.stop()
                try await AudioOut().play(url: take)
                print("Enter = keep, r = redo")
                keep = readLine() != "r"
            }
            if keep {
                try? FileManager.default.removeItem(at: url)
                try FileManager.default.moveItem(at: take, to: url)
            }
        }
    }

    @MainActor
    static func listen(_ seconds: Double, _ config: GediConfig) async throws {
        let session = ListenSessionBox(ListenSession(
            matcher: WakeWordMatcher(wakeWords: config.wakeWords),
            silence: config.silenceSeconds, followUpWindow: config.followUpSeconds))
        let mic = LiveTranscriber()
        try await mic.start(localeID: config.localeID, onResult: { text, isFinal in
            Task { @MainActor in
                print(isFinal ? "FINAL    \(text)" : "partial  \(text)")
                if let e = session.value.heard(text, isFinal: isFinal, at: Date()) { print(">>> \(e)") }
            }
        }, onStop: { error in
            Task { @MainActor in print("recogniser stopped: \(String(describing: error))") }
        })
        print("listening for \(Int(seconds)) s, say \"gedeee\" then a sentence…")
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let e = session.value.tick(at: Date()) {
                print(">>> \(e)")
                if case .utterance = e { session.value.speakingEnded(at: Date()) }  // no reply here; open follow-up
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        await mic.stop()
    }
}

/// Lets the mic callback and the tick loop share one ListenSession on the main actor.
@MainActor
final class ListenSessionBox {
    var value: ListenSession
    init(_ value: ListenSession) { self.value = value }
}
