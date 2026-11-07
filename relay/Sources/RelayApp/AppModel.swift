import AppKit
import Foundation
import RelayAdapters
import RelayCore
import SwiftUI
import UniformTypeIdentifiers

/// Holds the current Wybe stop signal so non-isolated code (the assistant's stop tool) can trip it.
final class StopController: @unchecked Sendable {
    private let lock = NSLock()
    private var signal = StopSignal()

    func fresh() -> StopSignal {
        lock.lock(); defer { lock.unlock() }
        signal = StopSignal()
        return signal
    }

    func stop(reason: String) {
        lock.lock(); let current = signal; lock.unlock()
        current.stop(reason: reason)
    }
}

/// UI state for the whole app. All behaviour lives in RelayCore / RelayAdapters; this class
/// only wires them to SwiftUI, the microphone and the speaker.
@MainActor
final class AppModel: ObservableObject {
    // MARK: Core
    let log = InMemoryEventLog()
    private(set) var runtime: AssistantRuntime!
    @Published var interactions: [Interaction] = []
    @Published var tasks: [RelayTask] = []
    @Published var training: TrainingSnapshot?
    @Published var logEntries: [LogEvent] = []
    @Published var notice: String?
    @Published var reasonerName = ""

    // MARK: Voice
    @Published private(set) var voice = VoiceSession()
    @Published var transcriptDraft = ""
    @Published var recordingStartedAt: Date?
    @Published var autoSpeak: Bool { didSet { UserDefaults.standard.set(autoSpeak, forKey: Keys.autoSpeak) } }
    @Published var sendLanguageHint: Bool { didSet { UserDefaults.standard.set(sendLanguageHint, forKey: Keys.languageHint) } }
    @Published var microphoneDenied = false
    private let recorder = AudioRecorder()
    private let player = AudioPlayer()
    private var speechTask: Task<Void, Never>?
    private var talkHeld = false

    // MARK: ElevenLabs
    private let credentials: CredentialStore = KeychainCredentialStore()
    @Published var elevenLabs: ElevenLabsConfiguration { didSet { persistConfiguration(); refreshSpeechStatus() } }
    @Published var apiKeyDisplay = "Not set"
    @Published var connectionStatus: SpeechServiceStatus = .unconfigured { didSet { refreshSpeechStatus() } }

    // MARK: Wybe (simulation only in this milestone)
    @Published var wybeRunning = false
    @Published var wybeObservation: Observation?
    @Published var wybeDecision = ""
    @Published var wybeRecords: [ActionRecord] = []
    @Published var wybeReports: [RunReport] = []
    @Published var wybeSeed = 1
    @Published var wybeShifts = 3
    @Published var wybeFaults = "typical"
    @Published var wybePacing = 0.15
    private let stopController = StopController()
    private var wybeTask: Task<Void, Never>?

    private enum Keys {
        static let config = "relay.elevenlabs.configuration"
        static let autoSpeak = "relay.speech.autoSpeak"
        static let languageHint = "relay.speech.languageHint"
    }

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Keys.config),
           let saved = try? JSONDecoder().decode(ElevenLabsConfiguration.self, from: data) {
            elevenLabs = saved
        } else {
            elevenLabs = ElevenLabsConfiguration()
        }
        autoSpeak = defaults.object(forKey: Keys.autoSpeak) as? Bool ?? true
        sendLanguageHint = defaults.object(forKey: Keys.languageHint) as? Bool ?? false

        let stopController = self.stopController
        runtime = AssistantRuntime(
            log: log,
            simulate: { [weak self] in
                guard let self else { return "Relay is closing." }
                return await self.runOneShiftForAssistant()
            },
            stopRunner: {
                stopController.stop(reason: "Stop requested from the assistant")
                return "Stop requested. The Wybe runner will not send any further actions."
            })

        log.addObserver { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.logEntries.append(event)
                    if self.logEntries.count > 3_000 { self.logEntries.removeFirst(self.logEntries.count - 3_000) }
                }
            }
        }

        if let key = CredentialAccess.load(CredentialAccount.elevenLabsAPIKey, from: credentials) {
            apiKeyDisplay = CredentialAccess.masked(key)
            connectionStatus = .configuredUnverified
        }
        refreshSpeechStatus()
        log.record(.settings, .info, "Relay started. Speech: \(connectionStatus.label)")
        Task { await refresh() }
    }

    // MARK: Refresh

    func refresh() async {
        interactions = await runtime.interactions
        tasks = await runtime.tasks.tasks
        training = await runtime.trainingSnapshot()
        reasonerName = await runtime.reasonerName
    }

    var attentionCount: Int { tasks.filter { $0.state == .needsAttention || $0.state == .awaitingApproval }.count }

    // MARK: Assistant

    func send(_ text: String, source: InputSource) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        stopSpeaking()
        Task {
            let interaction = await runtime.handle(HeardInput(text: clean, source: source))
            await refresh()
            if autoSpeak && source != .control { speak(interaction.reply) }
        }
    }

    func approve(_ interaction: Interaction) {
        Task {
            let result = await runtime.approve(interaction.id)
            await refresh()
            if autoSpeak, let reply = result?.reply { speak(reply) }
        }
    }

    func decline(_ interaction: Interaction) {
        Task {
            _ = await runtime.decline(interaction.id)
            await refresh()
        }
    }

    // MARK: Tasks

    func addTask(_ title: String) {
        Task {
            do { try await runtime.addTask(title: title) } catch { notice = String(describing: error) }
            await refresh()
        }
    }

    func transition(_ task: RelayTask, to state: TaskState) {
        Task {
            do { try await runtime.transitionTask(task.id, to: state, note: "Changed in Tasks view") }
            catch { notice = String(describing: error) }
            await refresh()
        }
    }

    // MARK: Training

    func loadProcedure(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let procedure = try Procedure.load(from: Data(contentsOf: url))
            Task {
                await runtime.load(procedure: procedure)
                await refresh()
            }
        } catch {
            notice = "Could not load procedure: \(error)"
            log.record(.warehouse, .failed, "Procedure load failed: \(error)")
        }
    }

    func restoreDemoProcedure() {
        Task {
            await runtime.load(procedure: DemoProcedure.procedure)
            await refresh()
        }
    }

    // MARK: Speech — status

    private var client: ElevenLabsClient {
        let store = credentials
        return ElevenLabsClient(configuration: elevenLabs, apiKey: {
            CredentialAccess.load(CredentialAccount.elevenLabsAPIKey, from: store)
        })
    }

    private func refreshSpeechStatus() {
        voice.transcriberStatus = connectionStatus
        let voiceMissing = elevenLabs.voiceID.trimmingCharacters(in: .whitespaces).isEmpty
        voice.synthesizerStatus = voiceMissing ? .unconfigured : connectionStatus
    }

    var speechOutputLabel: String {
        if case .unconfigured = connectionStatus { return SpeechServiceStatus.unconfigured.label }
        if elevenLabs.voiceID.trimmingCharacters(in: .whitespaces).isEmpty { return "No voice ID — text only" }
        return connectionStatus.label
    }

    func saveAPIKey(_ key: String) {
        do {
            try CredentialAccess.save(key, account: CredentialAccount.elevenLabsAPIKey, to: credentials)
            apiKeyDisplay = CredentialAccess.masked(key.trimmingCharacters(in: .whitespacesAndNewlines))
            connectionStatus = .configuredUnverified
            log.record(.settings, .info, "ElevenLabs API key saved to the macOS Keychain (not verified yet)")
        } catch {
            notice = "Could not save the key: \(error)"
            log.record(.settings, .failed, "Saving the ElevenLabs key failed: \(error)")
        }
    }

    func removeAPIKey() {
        do {
            try credentials.delete(CredentialAccount.elevenLabsAPIKey)
            apiKeyDisplay = "Not set"
            connectionStatus = .unconfigured
            log.record(.settings, .info, "ElevenLabs API key removed from the Keychain")
        } catch {
            notice = "Could not remove the key: \(error)"
        }
    }

    func testConnection() {
        guard client.hasAPIKey else { connectionStatus = .unconfigured; return }
        connectionStatus = .checking
        log.record(.speech, .attempted, "Checking ElevenLabs credentials (GET /v1/user)")
        let client = self.client
        Task {
            let status = await client.verify()
            connectionStatus = status
            switch status {
            case .connected: log.record(.speech, .succeeded, "ElevenLabs connection verified")
            case let .failed(reason): log.record(.speech, .failed, "ElevenLabs check failed: \(reason)")
            default: log.record(.speech, .info, "ElevenLabs status: \(status.label)")
            }
        }
    }

    private func noteSpeechError(_ error: Error) {
        if let e = error as? ElevenLabsError, e == .unauthorized || e == .missingAPIKey {
            connectionStatus = e == .missingAPIKey ? .unconfigured : .failed(e.description)
        }
    }

    // MARK: Speech — push to talk

    var isRecording: Bool { if case .recording = voice.state { return true } else { return false } }
    var isSpeaking: Bool { voice.state == .speaking }

    private var languageHint: String? {
        guard sendLanguageHint, let code = training?.language else { return nil }
        return code == "nb" ? "no" : code
    }

    func pressTalk() {
        guard voice.canRecord, !isRecording else { return }
        talkHeld = true
        stopSpeaking()
        Task {
            guard await AudioRecorder.requestPermission() else {
                microphoneDenied = true
                log.record(.speech, .failed, "Microphone permission denied — use text input or allow Relay in System Settings › Privacy & Security › Microphone")
                return
            }
            microphoneDenied = false
            guard talkHeld else { return } // released before permission resolved
            do {
                try recorder.start()
                try voice.handle(.pressTalk(at: Date()))
                recordingStartedAt = Date()
                log.record(.speech, .info, "Recording (push-to-talk)")
            } catch {
                recorder.cancel()
                log.record(.speech, .failed, "Could not start recording: \(error)")
                notice = "Could not start recording: \(error)"
            }
        }
    }

    func releaseTalk() {
        talkHeld = false
        guard isRecording else { return }
        recordingStartedAt = nil
        guard let recording = recorder.stop() else { return }
        try? voice.handle(.releaseTalk)
        guard recording.duration >= 0.3 else {
            try? FileManager.default.removeItem(at: recording.url)
            try? voice.handle(.transcriptionFailed("Recording too short — hold the button while speaking"))
            return
        }
        let transcriber = ElevenLabsTranscriber(client: client)
        let hint = languageHint
        log.record(.speech, .attempted, String(format: "Sending %.1fs of audio to %@", recording.duration, transcriber.providerName))
        Task {
            defer { try? FileManager.default.removeItem(at: recording.url) }
            do {
                let audio = try Data(contentsOf: recording.url)
                let transcript = try await transcriber.transcribe(audio: audio, filename: "push-to-talk.m4a",
                                                                  mimeType: "audio/mp4", languageHint: hint)
                connectionStatus = .connected(verifiedAt: Date())
                transcriptDraft = transcript.text
                log.record(.speech, .succeeded, "Transcript ready for review", details: ["provider": transcript.provider])
                try voice.handle(.transcriptReady(text: transcript.text, provider: transcript.provider))
            } catch {
                noteSpeechError(error)
                log.record(.speech, .failed, "Transcription failed: \(error)")
                try? voice.handle(.transcriptionFailed(String(describing: error)))
            }
        }
    }

    func submitTranscript() {
        guard case let .reviewing(original, provider) = voice.state else { return }
        let text = transcriptDraft
        try? voice.handle(.submitReview)
        transcriptDraft = ""
        send(text, source: .transcribed(provider: provider, edited: text != original))
    }

    func discardTranscript() {
        try? voice.handle(.discardReview)
        transcriptDraft = ""
        log.record(.speech, .info, "Transcript discarded")
    }

    func dismissVoiceError() { try? voice.handle(.dismissError) }

    // MARK: Speech — replies

    func speak(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, voice.canSpeak else { return }
        // Only start from idle or after an error; never interrupt recording or transcript review.
        do { try voice.handle(.startSpeaking) } catch { return }
        let synthesizer = ElevenLabsSynthesizer(client: client)
        let language = training?.language
        // Keep requests short; long replies are truncated for speech only (the text stays complete).
        let spoken = clean.count > 1_200 ? String(clean.prefix(1_200)) + "…" : clean
        log.record(.speech, .attempted, "Requesting speech from \(synthesizer.providerName)",
                   details: ["characters": String(spoken.count)])
        speechTask = Task {
            do {
                let audio = try await synthesizer.synthesize(text: spoken, languageCode: language)
                guard !Task.isCancelled, voice.state == .speaking else { return }
                try player.play(audio.data) { [weak self] in
                    guard let self else { return }
                    try? self.voice.handle(.finishedSpeaking)
                }
                connectionStatus = .connected(verifiedAt: Date())
                log.record(.speech, .succeeded, "Playing spoken reply")
            } catch is CancellationError {
                return
            } catch {
                noteSpeechError(error)
                log.record(.speech, .failed, "Speech output failed: \(error)")
                try? voice.handle(.speakingFailed(String(describing: error)))
            }
        }
    }

    func stopSpeaking() {
        speechTask?.cancel()
        speechTask = nil
        let wasSpeaking = isSpeaking
        player.stop()
        try? voice.handle(.stopSpeaking)
        if wasSpeaking { log.record(.speech, .info, "Playback stopped") }
    }

    // MARK: Wybe simulation

    private var selectedFaults: SimulatedNightShift.Faults {
        switch wybeFaults {
        case "none": return .none
        case "harsh": return .harsh
        default: return .typical
        }
    }

    func startSimulation() {
        guard !wybeRunning else { return }
        let stop = stopController.fresh()
        wybeRunning = true
        wybeRecords = []
        wybeReports = []
        wybeObservation = nil
        wybeDecision = ""
        let seed = UInt64(max(0, wybeSeed))
        let shifts = max(1, wybeShifts)
        let faults = selectedFaults
        let pacing = wybePacing
        wybeTask = Task { [weak self] in
            for index in 0..<shifts {
                if stop.isStopped { break }
                guard let self else { return }
                _ = await self.runShift(seed: seed + UInt64(index), faults: faults, pacing: pacing, stop: stop)
            }
            self?.wybeRunning = false
        }
    }

    func stopSimulation() {
        stopController.stop(reason: "Stop pressed in Wybe Runner")
        log.record(.wybe, .info, "Stop requested — no further actions will be sent", mode: .simulation)
    }

    private func runShift(seed: UInt64, faults: SimulatedNightShift.Faults, pacing: Double, stop: StopSignal) async -> RunReport {
        let simulator = SimulatedNightShift(configuration: .init(seed: seed, faults: faults))
        var configuration = RunnerConfiguration.simulation()
        configuration.minRequestInterval = pacing // visible pacing in the UI; the CLI runs unpaced
        let runner = AutonomousRunner(adapter: simulator, policy: SimulatedShiftPolicy(), configuration: configuration,
                                      log: log, stop: stop) { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.apply(event) }
            }
        }
        return await runner.run()
    }

    private func apply(_ event: RunnerEvent) {
        switch event {
        case let .observed(observation): wybeObservation = observation
        case let .decided(text): wybeDecision = text
        case let .recorded(record):
            wybeRecords.append(record)
            if wybeRecords.count > 1_000 { wybeRecords.removeFirst(wybeRecords.count - 1_000) }
        case let .finished(report): wybeReports.append(report)
        }
    }

    /// Used by the assistant's approved "run the simulation" request: one shift, unpaced.
    private func runOneShiftForAssistant() async -> String {
        guard !wybeRunning else { return "A Wybe run is already active; not starting another." }
        wybeRunning = true
        defer { wybeRunning = false }
        let stop = stopController.fresh()
        let report = await runShift(seed: UInt64(max(0, wybeSeed)), faults: selectedFaults, pacing: 0, stop: stop)
        return report.summary
    }

    var simulatedAverage: LabeledScore? {
        let scores = wybeReports.compactMap(\.score).filter { $0.mode == .simulation }
        guard !scores.isEmpty else { return nil }
        return LabeledScore(mode: .simulation, value: scores.map(\.value).reduce(0, +) / Double(scores.count),
                            source: "Relay simulator, \(scores.count) shift(s)")
    }

    // MARK: Activity export

    func exportLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "relay-activity.jsonl"
        panel.allowedContentTypes = [.json, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(log.exportJSONLines().utf8).write(to: url)
            log.record(.settings, .info, "Exported redacted activity log (\(log.entries().count) entries)")
        } catch {
            notice = "Export failed: \(error)"
        }
    }

    private func persistConfiguration() {
        if let data = try? JSONEncoder().encode(elevenLabs) { UserDefaults.standard.set(data, forKey: Keys.config) }
    }
}
