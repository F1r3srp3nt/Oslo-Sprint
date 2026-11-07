import Foundation
import RelayCore

// Guided-setup model for ElevenLabs: links, permissions, readiness checks and plain-language
// problems. Pure and platform independent so it can be tested without a UI.
//
// Every link and instruction below was checked against elevenlabs.io on 2026-11-07:
//   - API keys: https://elevenlabs.io/docs/help-center/technical/how-do-i-authorize-myself-using-an-api-key
//     ("click Developers in the left sidebar, then select the API Keys tab"; the full key is
//     only visible when first created; keys are restricted by default).
//   - Dashboard key page: https://elevenlabs.io/app/api/api-keys (linked from the ElevenAPI quickstart).
//   - Permission identifiers: https://elevenlabs.io/docs/api-reference/service-accounts/api-keys/create
//   - Voice IDs: https://elevenlabs.io/docs/help-center/technical/how-do-i-find-the-voice-id-of-my-voices-via-the-website-and-api
//     (My Voices → More actions (three dots) → Copy voice ID).
//   - Default voices: https://elevenlabs.io/docs/help-center/product/voices/my-voices/how-do-i-access-eleven-labs-default-voices
//   - Errors: https://elevenlabs.io/docs/eleven-api/resources/errors

public enum ProviderLinks {
    public static let elevenLabsAPIKeys = URL(string: "https://elevenlabs.io/app/api/api-keys")!
    public static let elevenLabsMyVoices = URL(string: "https://elevenlabs.io/app/voice-lab")!
    public static let elevenLabsVoiceLibrary = URL(string: "https://elevenlabs.io/app/voice-library")!
    public static let elevenLabsSubscription = URL(string: "https://elevenlabs.io/app/subscription")!
    public static let elevenLabsAuthenticationDocs = URL(string: "https://elevenlabs.io/docs/api-reference/authentication")!
    public static let elevenLabsErrorDocs = URL(string: "https://elevenlabs.io/docs/eleven-api/resources/errors")!
    public static let elevenLabsModelDocs = URL(string: "https://elevenlabs.io/docs/overview/models")!
    /// Organiser-provided registration page for the Wybe Night Shift challenge.
    public static let wybeRegistration = URL(string: "https://nightshift-board.wybe.me/join")!

    public static let all: [URL] = [elevenLabsAPIKeys, elevenLabsMyVoices, elevenLabsVoiceLibrary, elevenLabsSubscription,
                                    elevenLabsAuthenticationDocs, elevenLabsErrorDocs, elevenLabsModelDocs, wybeRegistration]
}

/// API-key permissions (ElevenLabs identifiers) for the requests Relay actually makes.
public enum ElevenLabsPermission: String, CaseIterable, Sendable {
    /// POST /v1/speech-to-text — push-to-talk transcription.
    case speechToText = "speech_to_text"
    /// POST /v1/text-to-speech/{voice_id} — spoken replies and the voice test.
    case textToSpeech = "text_to_speech"
    /// GET /v1/user — only the optional account check.
    case userRead = "user_read"

    public var label: String {
        switch self {
        case .speechToText: return "Speech to Text"
        case .textToSpeech: return "Text to Speech"
        case .userRead: return "User (read)"
        }
    }

    public var usedFor: String {
        switch self {
        case .speechToText: return "push-to-talk and Test speech input"
        case .textToSpeech: return "spoken replies and Test voice"
        case .userRead: return "the account check only (optional)"
        }
    }

    public var required: Bool { self != .userRead }
}

/// What Relay was doing when a problem happened; used to give the right next step.
public enum SetupContext: Sendable, Equatable {
    case accountCheck, speechInput, speechOutput

    var permission: ElevenLabsPermission {
        switch self {
        case .accountCheck: return .userRead
        case .speechInput: return .speechToText
        case .speechOutput: return .textToSpeech
        }
    }
}

/// A user-facing explanation: what happened, what to do, and the provider's own words.
public struct SetupProblem: Equatable, Sendable {
    public let title: String
    public let nextStep: String
    /// Provider message and request ID, if any (already redacted).
    public let providerDetail: String?
    /// Link that helps fix it, if there is one.
    public let link: URL?

    public init(title: String, nextStep: String, providerDetail: String? = nil, link: URL? = nil) {
        self.title = title
        self.nextStep = nextStep
        self.providerDetail = providerDetail
        self.link = link
    }

    public static let microphoneDenied = SetupProblem(
        title: "Microphone access is off for Relay",
        nextStep: "Turn Relay on in System Settings › Privacy & Security › Microphone, then try again. Typing still works.")

    public static func recording(_ reason: String) -> SetupProblem {
        SetupProblem(title: "Could not record", nextStep: reason)
    }

    public init(_ error: ElevenLabsError, context: SetupContext) {
        let permission = context.permission
        switch error {
        case .missingAPIKey:
            self.init(title: "No API key saved", nextStep: "Complete step 1: create a key and save it to the Keychain.",
                      link: ProviderLinks.elevenLabsAPIKeys)
        case .missingVoiceID:
            self.init(title: "No voice ID set", nextStep: "Complete step 2: copy a voice ID from My Voices.",
                      link: ProviderLinks.elevenLabsMyVoices)
        case let .invalidVoiceID(reason):
            self.init(title: "The voice ID field is not a voice ID", nextStep: "Fix the voice ID: \(reason)",
                      link: ProviderLinks.elevenLabsMyVoices)
        case let .network(message):
            self.init(title: "Could not reach ElevenLabs",
                      nextStep: "Check the internet connection and try again. Relay cannot tell whether the request reached ElevenLabs.",
                      providerDetail: message)
        case let .decoding(message):
            self.init(title: "ElevenLabs answered in an unexpected format",
                      nextStep: "Try again. If it keeps happening, the API may have changed; check the ElevenLabs docs.",
                      providerDetail: message, link: ProviderLinks.elevenLabsErrorDocs)
        case let .rejected(r):
            let detail = Self.detail(r)
            switch r.kind {
            case .invalidCredentials:
                self.init(title: "ElevenLabs did not accept this API key (HTTP \(r.httpStatus))",
                          nextStep: "Check that the whole key was pasted. ElevenLabs shows a key in full only once, so if in doubt create a new key, then use Replace. Deleted, disabled or expired keys are also refused.",
                          providerDetail: detail, link: ProviderLinks.elevenLabsAPIKeys)
            case .missingPermission:
                let extra = context == .accountCheck
                    ? " This permission is only needed for the account check; speech can work without it, so you can skip this check and use Test voice / Test speech input instead."
                    : ""
                self.init(title: "The key is valid but lacks the \(permission.label) permission",
                          nextStep: "In ElevenLabs › Developers › API Keys, open the key's More actions (…) › Edit and enable \(permission.label) (\(permission.rawValue)), or create a new key with it.\(extra)",
                          providerDetail: detail, link: ProviderLinks.elevenLabsAPIKeys)
            case .accessDenied:
                self.init(title: "ElevenLabs refused access (HTTP \(r.httpStatus))",
                          nextStep: "The response does not say exactly why. Check the key's restrictions (permissions, IP allowlist) and your workspace access, using the message below.",
                          providerDetail: detail, link: ProviderLinks.elevenLabsAPIKeys)
            case .planRestriction:
                self.init(title: "Not available on the current ElevenLabs plan",
                          nextStep: "Choose a different model or format under Models, or check your plan.",
                          providerDetail: detail, link: ProviderLinks.elevenLabsSubscription)
            case .voiceUnavailable:
                self.init(title: "This voice can't be used with your account",
                          nextStep: "Copy the voice ID again from My Voices (More actions › Copy voice ID). The example voice may not be available to every account.",
                          providerDetail: detail, link: ProviderLinks.elevenLabsMyVoices)
            case .modelUnavailable:
                self.init(title: "The selected model isn't available",
                          nextStep: "Under Models, go back to the recommended default, or check ElevenLabs' model list.",
                          providerDetail: detail, link: ProviderLinks.elevenLabsModelDocs)
            case .creditsExhausted:
                self.init(title: "Not enough ElevenLabs credits",
                          nextStep: "Check usage and credits on your ElevenLabs subscription page. A key can also have its own credit limit (Developers › API Keys).",
                          providerDetail: detail, link: ProviderLinks.elevenLabsSubscription)
            case .rateLimited:
                self.init(title: "ElevenLabs is busy or rate-limiting requests",
                          nextStep: "Wait a moment and try again. Plans also limit how many requests run at once.",
                          providerDetail: detail)
            case .invalidRequest:
                self.init(title: "ElevenLabs rejected the request (HTTP \(r.httpStatus))",
                          nextStep: "Check the model and format under Models (Advanced). The provider message below has the details.",
                          providerDetail: detail, link: ProviderLinks.elevenLabsErrorDocs)
            case .serverError:
                self.init(title: "ElevenLabs had a server problem (HTTP \(r.httpStatus))",
                          nextStep: "This is on ElevenLabs' side. Try again later.", providerDetail: detail)
            case .unrecognised:
                self.init(title: "Unexpected response from ElevenLabs (HTTP \(r.httpStatus))",
                          nextStep: "Relay can't tell the cause from this response. See the message below.",
                          providerDetail: detail, link: ProviderLinks.elevenLabsErrorDocs)
            }
        }
    }

    private static func detail(_ r: ElevenLabsRejection) -> String? {
        var parts: [String] = []
        if let code = r.code { parts.append(code) }
        if !r.message.isEmpty { parts.append("“\(r.message)”") }
        if let id = r.requestID { parts.append("request \(id)") }
        return parts.isEmpty ? nil : "ElevenLabs: " + parts.joined(separator: " · ")
    }
}

/// State of one readiness check.
public enum CheckState: Equatable, Sendable {
    case notChecked
    case checking
    case passed(at: Date, detail: String)
    /// Partly OK, needs a decision or action (e.g. key recognised but missing an optional permission).
    case attention(SetupProblem)
    case failed(SetupProblem)

    public var isPassed: Bool { if case .passed = self { return true } else { return false } }
    public var problem: SetupProblem? {
        switch self {
        case let .attention(p), let .failed(p): return p
        default: return nil
        }
    }
}

public enum MicrophonePermission: String, Sendable, Equatable {
    case notDetermined, granted, denied, restricted, unknown

    public var label: String {
        switch self {
        case .notDetermined: return "Not asked yet"
        case .granted: return "Allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted by system policy"
        case .unknown: return "Unknown"
        }
    }
}

public enum SetupEvent: Sendable {
    case keySaved
    case keyRemoved
    case voiceIDChanged(isSet: Bool)
    /// Speech recognition model changed: earlier input results no longer apply.
    case speechInputSettingsChanged
    /// Speech generation model or output format changed.
    case speechOutputSettingsChanged
    case microphone(MicrophonePermission)
    case accountCheckStarted
    case accountCheckFinished(Result<Void, ElevenLabsError>, at: Date)
    case speechInputStarted
    /// A transcription request finished (explicit test or real push-to-talk use).
    case speechInputFinished(Result<String, ElevenLabsError>, at: Date)
    /// Recording itself failed before anything was sent (e.g. microphone denied).
    case speechInputBlocked(SetupProblem)
    case speechOutputStarted
    case speechOutputFinished(Result<Void, ElevenLabsError>, at: Date)
}

/// The five separate readiness facts shown in Settings.
///
/// Invariants (tested):
/// - Saving a key verifies nothing: all request-based checks return to "not checked".
/// - A passed account check never marks speech input or output as tested.
/// - Changing a model, format or voice resets only the checks it affects.
public struct ElevenLabsReadiness: Equatable, Sendable {
    public private(set) var keySaved: Bool
    public private(set) var voiceIDSet: Bool
    public private(set) var account: CheckState = .notChecked
    public private(set) var speechInput: CheckState = .notChecked
    public private(set) var speechOutput: CheckState = .notChecked
    public private(set) var microphone: MicrophonePermission = .unknown

    public init(keySaved: Bool, voiceIDSet: Bool) {
        self.keySaved = keySaved
        self.voiceIDSet = voiceIDSet
    }

    public mutating func apply(_ event: SetupEvent) {
        switch event {
        case .keySaved:
            keySaved = true
            account = .notChecked; speechInput = .notChecked; speechOutput = .notChecked
        case .keyRemoved:
            keySaved = false
            account = .notChecked; speechInput = .notChecked; speechOutput = .notChecked
        case let .voiceIDChanged(isSet):
            voiceIDSet = isSet
            speechOutput = .notChecked
        case .speechInputSettingsChanged:
            speechInput = .notChecked
        case .speechOutputSettingsChanged:
            speechOutput = .notChecked
        case let .microphone(permission):
            microphone = permission
        case .accountCheckStarted:
            account = .checking
        case let .accountCheckFinished(result, at):
            switch result {
            case .success:
                account = .passed(at: at, detail: "ElevenLabs accepted the key (GET /v1/user). This does not test speech.")
            case let .failure(error):
                let problem = SetupProblem(error, context: .accountCheck)
                // Authenticated but missing user_read: the key itself is recognised.
                account = error.rejection?.kind == .missingPermission ? .attention(problem) : .failed(problem)
            }
        case .speechInputStarted:
            speechInput = .checking
        case let .speechInputFinished(result, at):
            switch result {
            case let .success(text):
                let heard = text.isEmpty ? "the request worked, but no words were detected" : "heard “\(text.prefix(80))”"
                speechInput = .passed(at: at, detail: "Transcription worked: \(heard).")
            case let .failure(error):
                speechInput = .failed(SetupProblem(error, context: .speechInput))
            }
        case let .speechInputBlocked(problem):
            speechInput = .failed(problem)
        case .speechOutputStarted:
            speechOutput = .checking
        case let .speechOutputFinished(result, at):
            switch result {
            case .success: speechOutput = .passed(at: at, detail: "ElevenLabs generated audio with this voice.")
            case let .failure(error): speechOutput = .failed(SetupProblem(error, context: .speechOutput))
            }
        }
    }

    /// Status for the push-to-talk path, derived only from transcription results.
    public var transcriberStatus: SpeechServiceStatus {
        guard keySaved else { return .unconfigured }
        switch speechInput {
        case let .passed(at, _): return .connected(verifiedAt: at)
        case let .failed(p), let .attention(p): return .failed(p.title)
        case .checking: return .checking
        case .notChecked: return .configuredUnverified
        }
    }

    /// Status for spoken replies, derived only from speech-generation results.
    public var synthesizerStatus: SpeechServiceStatus {
        guard keySaved, voiceIDSet else { return .unconfigured }
        switch speechOutput {
        case let .passed(at, _): return .connected(verifiedAt: at)
        case let .failed(p), let .attention(p): return .failed(p.title)
        case .checking: return .checking
        case .notChecked: return .configuredUnverified
        }
    }

    /// One-line summary for the sidebar.
    public var summary: String {
        if !keySaved { return "Speech not set up — typing works" }
        let input = speechInput.isPassed ? "input ✓" : "input untested"
        let output = !voiceIDSet ? "no voice" : (speechOutput.isPassed ? "output ✓" : "output untested")
        if speechInput.problem != nil || speechOutput.problem != nil { return "Speech: needs attention" }
        return "Speech: \(input), \(output)"
    }
}

/// Plain-language model choices. IDs verified at https://elevenlabs.io/docs/overview/models and
/// the speech-to-text / text-to-speech references (2026-11-07).
public struct ModelChoice: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let note: String

    public static let speechRecognition: [ModelChoice] = [
        ModelChoice(id: "scribe_v2", name: "Scribe v2 (recommended)", note: "ElevenLabs' current speech-to-text model (90+ languages)."),
        ModelChoice(id: "scribe_v1", name: "Scribe v1", note: "Previous generation."),
    ]

    /// Language coverage from https://elevenlabs.io/docs/overview/models (2026-11-07): Flash v2.5
    /// supports all Multilingual v2 languages plus Hungarian, Norwegian and Vietnamese, so it is the
    /// only option here covering all three training languages (English, Norwegian, Polish).
    public static let speechGeneration: [ModelChoice] = [
        ModelChoice(id: "eleven_flash_v2_5", name: "Flash v2.5 (recommended for Relay)",
                    note: "Fast, and ElevenLabs lists it at half the price per character. Speaks English, Norwegian and Polish."),
        ModelChoice(id: "eleven_multilingual_v2", name: "Multilingual v2",
                    note: "The API's own default and very stable, but Norwegian is not among its 29 languages."),
        ModelChoice(id: "eleven_v3", name: "Eleven v3",
                    note: "Expressive previous-generation model, 70+ languages; can be slower."),
    ]

    /// Only MP3 formats: Relay plays replies with the system MP3 decoder.
    public static let outputFormats: [ModelChoice] = [
        ModelChoice(id: "mp3_44100_128", name: "MP3, 44.1 kHz, 128 kbps (recommended)", note: "The API's default. Good quality on all plans."),
        ModelChoice(id: "mp3_22050_32", name: "MP3, 22 kHz, 32 kbps", note: "Smaller and faster to download; lower quality."),
    ]
}
