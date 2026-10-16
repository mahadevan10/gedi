import AppKit
import GediCore
import GediSystem
import os

private let log = Logger(subsystem: "com.mahadevan.gedi", category: "app")

/// Wires everything together:
///   every 5 s    → read frontmost app/tab → ActivityLog
///   every 0.25 s → ListenSession.tick, and a timed comment when CommentPolicy says so
///   mic results  → ListenSession → wake chime / reply to the user
@MainActor
final class GediController {
    private let config: GediConfig
    private let stage = StageModel()
    private var overlay: OverlayController?
    private var menu: StatusMenu?
    private let piper: PiperServer
    private let voice: GediVoice
    private let brain: GediBrain
    private let probe = ActivityProbe()
    private var activityLog = ActivityLog()
    private var listen: ListenSession
    private let mic = LiveTranscriber()
    private let policy: CommentPolicy
    private var quiet = CommentPolicy.State()
    private var commentInFlight = false
    private var replyInFlight = false
    private var speaking = false
    private var lastSpokeAt = Date()
    private var timers: [Timer] = []

    init() throws {
        config = try GediConfig.load(from: GediPaths.configFile)
        let clips: ClipLibrary
        do {
            clips = try ClipLibrary.load(from: GediPaths.clipsDir)
        } catch {
            log.error("clips.json is malformed, ignoring clips: \(String(describing: error), privacy: .public)")
            clips = .empty(at: GediPaths.clipsDir)
        }
        piper = PiperServer(config: config)
        voice = GediVoice(piper: piper.client, clips: clips)
        brain = GediBrain(
            model: OllamaClient(baseURL: config.ollamaURL, model: config.model),
            builder: PromptBuilder(persona: Persona.load(from: GediPaths.personaFile), clips: clips.clips))
        listen = ListenSession(
            matcher: WakeWordMatcher(wakeWords: config.wakeWords),
            silence: config.silenceSeconds, followUpWindow: config.followUpSeconds)
        policy = CommentPolicy(interval: config.commentIntervalSeconds)
    }

    func start() {
        let overlay = OverlayController(stage: stage)
        overlay.show()
        self.overlay = overlay
        menu = StatusMenu(
            onMuteChanged: { [weak self] muted in self?.quiet.muted = muted },
            onCommentNow: { [weak self] in Task { await self?.comment() } })
        show("ഗഡി എത്തീട്ടാ.", for: 4)
        timers.append(Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleActivity() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        })
        sampleActivity()
        lastSpokeAt = Date()
        Task { await startServices() }
    }

    func shutdown() {
        timers.forEach { $0.invalidate() }
        piper.stop()
    }

    // MARK: services

    private func startServices() async {
        do {
            try await piper.start()
        } catch {
            log.error("piper: \(String(describing: error), privacy: .public)")
            show("Piper start aayilla. scripts/setup.sh run cheyy.", for: 10)
        }
        await startMic()
    }

    private func startMic() async {
        do {
            try await mic.start(
                localeID: config.localeID,
                onResult: { [weak self] text, isFinal in
                    Task { @MainActor in self?.heard(text, isFinal: isFinal) }
                },
                onStop: { [weak self] error in
                    Task { @MainActor in self?.micStopped(error) }
                })
            log.info("listening (\(self.config.localeID, privacy: .public))")
        } catch {
            log.error("mic: \(String(describing: error), privacy: .public)")
            show("മൈക്ക് കിട്ടിയില്ല ഗഡീ.", for: 8)
        }
    }

    /// The recogniser stream ended (error or system interruption): restart it.
    private func micStopped(_ error: Error?) {
        log.error("recogniser stopped: \(String(describing: error), privacy: .public); restarting")
        Task {
            await mic.stop()
            try? await Task.sleep(for: .seconds(2))
            await startMic()
        }
    }

    // MARK: loop

    private func sampleActivity() {
        guard let snap = probe.snapshot() else { return }
        activityLog.record(ActivityClassifier.classify(snap), at: Date())
        quiet.inCall = activityLog.current(now: Date())?.kind == .call
    }

    private func tick() {
        let now = Date()
        if let event = listen.tick(at: now) { handle(event) }
        quiet.conversing = listen.phase != .idle
        quiet.busy = commentInFlight || replyInFlight || speaking
        if policy.isDue(now: now, lastSpokeAt: lastSpokeAt, state: quiet) {
            Task { await comment() }
        }
    }

    private func heard(_ text: String, isFinal: Bool) {
        // Shows how the recogniser spells things, for wake-word calibration.
        if isFinal, !text.isEmpty { log.info("heard: \(text, privacy: .public)") }
        if let event = listen.heard(text, isFinal: isFinal, at: Date()) { handle(event) }
    }

    private func handle(_ event: ListenEvent) {
        switch event {
        case .wake:
            log.info("wake")
            NSSound(named: "Tink")?.play()
            stage.bubble = "പറ ഗഡീ…"
        case .utterance(let text):
            log.info("utterance: \(text, privacy: .public)")
            stage.bubble = "ഹ്മ്…"
            Task { await reply(to: text) }
        case .gaveUp:
            if stage.bubble == "പറ ഗഡീ…" { stage.bubble = nil }
            Task { await brain.endConversation() }
        }
    }

    // MARK: talking

    private var activityText: String {
        activityLog.summary(now: Date()).promptText()
    }

    private func comment() async {
        guard !commentInFlight, !replyInFlight, !speaking else { return }
        commentInFlight = true
        defer {
            commentInFlight = false
            lastSpokeAt = Date()
        }
        do {
            guard let r = try await brain.comment(activity: activityText), r.speak else { return }
            // The user may have started talking to Gedi while the model was thinking.
            guard listen.phase == .idle else { return }
            await speak(r)
        } catch {
            log.error("comment: \(String(describing: error), privacy: .public)")
        }
    }

    private func reply(to text: String) async {
        replyInFlight = true
        defer {
            replyInFlight = false
            lastSpokeAt = Date()
        }
        do {
            if let r = try await brain.reply(to: text, activity: activityText), r.speak {
                await speak(r)
                return
            }
        } catch {
            log.error("reply: \(String(describing: error), privacy: .public)")
            show("Ollama-ക്ക് എന്തോ പറ്റി ഗഡീ.", for: 6)
        }
        listen.speakingEnded(at: Date())  // nothing said; still open the follow-up window
    }

    private func speak(_ r: GediReply) async {
        while speaking { try? await Task.sleep(for: .milliseconds(100)) }
        speaking = true
        let text = voice.displayText(for: r)
        stage.bubble = text
        stage.setTalking(true)
        listen.speakingStarted()
        do {
            try await voice.say(r)
        } catch {
            log.error("speak: \(String(describing: error), privacy: .public)")
        }
        listen.speakingEnded(at: Date())
        stage.setTalking(false)
        speaking = false
        hideBubble(ifStill: text, after: 3)
    }

    private func show(_ text: String, for seconds: Double) {
        stage.bubble = text
        hideBubble(ifStill: text, after: seconds)
    }

    private func hideBubble(ifStill text: String, after seconds: Double) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if stage.bubble == text { stage.bubble = nil }
        }
    }
}
