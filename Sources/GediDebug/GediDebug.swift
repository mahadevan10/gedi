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
        return GediBrain(model: OllamaClient(baseURL: config.ollamaURL, model: config.model),
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
