import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import RelayCore

// ElevenLabs REST adapters (speech input/output only — never reasoning).
//
// Contract source: ElevenLabs' official Python SDK (github.com/elevenlabs/elevenlabs-python,
// generated from ElevenLabs' API definition), read on 2026-11-07 because elevenlabs.io was not
// reachable from the build environment. Verify against https://elevenlabs.io/docs before
// relying on details beyond these:
//   Auth:  header `xi-api-key`
//   Base:  https://api.elevenlabs.io
//   STT:   POST /v1/speech-to-text            multipart: model_id (required), file, language_code (optional)
//          response JSON: text, language_code, language_probability, words
//   TTS:   POST /v1/text-to-speech/{voice_id}?output_format=mp3_44100_128
//          JSON: text, model_id, (language_code — not supported by multilingual_v2 models)
//          response: audio bytes
//   Check: GET  /v1/user

public struct ElevenLabsConfiguration: Codable, Sendable, Equatable {
    public var baseURL: URL
    public var speechToTextModel: String
    public var textToSpeechModel: String
    /// Must be chosen by the user (from their ElevenLabs voice library). Empty = speech output unconfigured.
    public var voiceID: String
    public var outputFormat: String

    /// Voice ID used in ElevenLabs' own SDK README examples. Offered as a starting point only.
    public static let documentationExampleVoiceID = "JBFqnCBsd6RMkjVDRZzb"

    public init(baseURL: URL = URL(string: "https://api.elevenlabs.io")!, speechToTextModel: String = "scribe_v2",
                textToSpeechModel: String = "eleven_multilingual_v2", voiceID: String = "",
                outputFormat: String = "mp3_44100_128") {
        self.baseURL = baseURL
        self.speechToTextModel = speechToTextModel
        self.textToSpeechModel = textToSpeechModel
        self.voiceID = voiceID
        self.outputFormat = outputFormat
    }
}

public enum ElevenLabsError: Error, Equatable, CustomStringConvertible {
    case missingAPIKey
    case missingVoiceID
    case unauthorized
    case rateLimited
    case invalidRequest(String)
    case server(Int)
    case unexpectedStatus(Int, String)
    case decoding(String)
    case transport(String)

    public var description: String {
        switch self {
        case .missingAPIKey: return "No ElevenLabs API key saved (Settings)"
        case .missingVoiceID: return "No ElevenLabs voice ID set (Settings)"
        case .unauthorized: return "ElevenLabs rejected the API key (401)"
        case .rateLimited: return "ElevenLabs rate limit or quota reached (429)"
        case let .invalidRequest(message): return "ElevenLabs rejected the request: \(message)"
        case let .server(status): return "ElevenLabs service error (\(status))"
        case let .unexpectedStatus(status, message): return "Unexpected ElevenLabs response \(status): \(message)"
        case let .decoding(message): return "Could not read ElevenLabs response: \(message)"
        case let .transport(message): return message
        }
    }
}

/// Shared HTTP plumbing for the ElevenLabs adapters.
public struct ElevenLabsClient: Sendable {
    public let configuration: ElevenLabsConfiguration
    private let transport: HTTPTransport
    private let apiKey: @Sendable () -> String?
    private let redactor: Redactor

    public init(configuration: ElevenLabsConfiguration, transport: HTTPTransport = URLSessionTransport(),
                redactor: Redactor = .shared, apiKey: @escaping @Sendable () -> String?) {
        self.configuration = configuration
        self.transport = transport
        self.redactor = redactor
        self.apiKey = apiKey
    }

    public var hasAPIKey: Bool { !(apiKey() ?? "").isEmpty }

    func request(path: String, method: String, query: [URLQueryItem] = []) throws -> URLRequest {
        guard let key = apiKey(), !key.isEmpty else { throw ElevenLabsError.missingAPIKey }
        redactor.register(secret: key)
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        return request
    }

    func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ElevenLabsError.transport(redactor.redact(String(describing: error)))
        }
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw ElevenLabsError.unauthorized
        case 429: throw ElevenLabsError.rateLimited
        case 400, 422: throw ElevenLabsError.invalidRequest(errorMessage(data))
        case 500..<600: throw ElevenLabsError.server(response.statusCode)
        default: throw ElevenLabsError.unexpectedStatus(response.statusCode, errorMessage(data))
        }
    }

    /// Extracts a short, redacted message from an error body without assuming its exact shape.
    func errorMessage(_ data: Data) -> String {
        var message = String(decoding: data.prefix(400), as: UTF8.self)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = json["detail"] as? [String: Any], let m = detail["message"] as? String { message = m }
            else if let detail = json["detail"] as? String { message = detail }
            else if let m = json["message"] as? String { message = m }
        }
        return String(redactor.redact(message).prefix(200))
    }

    /// Makes one real, inexpensive request (GET /v1/user). Only a 2xx response yields `.connected`.
    public func verify(now: @Sendable () -> Date = { Date() }) async -> SpeechServiceStatus {
        do {
            _ = try await send(try request(path: "v1/user", method: "GET"))
            return .connected(verifiedAt: now())
        } catch ElevenLabsError.missingAPIKey {
            return .unconfigured
        } catch {
            return .failed(String(describing: error))
        }
    }
}

public struct ElevenLabsTranscriber: SpeechTranscriber {
    public let client: ElevenLabsClient
    public init(client: ElevenLabsClient) { self.client = client }

    public var providerName: String { "ElevenLabs Speech to Text (\(client.configuration.speechToTextModel))" }

    public func transcribe(audio: Data, filename: String, mimeType: String, languageHint: String?) async throws -> Transcript {
        var request = try client.request(path: "v1/speech-to-text", method: "POST")
        var form = MultipartForm()
        form.addField("model_id", client.configuration.speechToTextModel)
        if let languageHint, !languageHint.isEmpty { form.addField("language_code", languageHint) }
        form.addFile("file", filename: filename, mimeType: mimeType, data: audio)
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.body()
        let data = try await client.send(request)
        struct Response: Decodable { let text: String; let language_code: String? }
        do {
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            return Transcript(text: decoded.text.trimmingCharacters(in: .whitespacesAndNewlines),
                              languageCode: decoded.language_code, provider: providerName)
        } catch {
            throw ElevenLabsError.decoding("expected a JSON object with a 'text' field")
        }
    }
}

public struct ElevenLabsSynthesizer: SpeechSynthesizer {
    public let client: ElevenLabsClient
    public init(client: ElevenLabsClient) { self.client = client }

    public var providerName: String { "ElevenLabs Text to Speech (\(client.configuration.textToSpeechModel))" }

    public func synthesize(text: String, languageCode: String?) async throws -> SynthesizedAudio {
        let voice = client.configuration.voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !voice.isEmpty else { throw ElevenLabsError.missingVoiceID }
        guard voice.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            throw ElevenLabsError.invalidRequest("voice ID may only contain letters and digits")
        }
        var request = try client.request(path: "v1/text-to-speech/\(voice)", method: "POST",
                                         query: [URLQueryItem(name: "output_format", value: client.configuration.outputFormat)])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        var body: [String: String] = ["text": text, "model_id": client.configuration.textToSpeechModel]
        // Per the API definition, language_code is not supported for multilingual_v2 models.
        if let languageCode, !client.configuration.textToSpeechModel.contains("multilingual_v2") {
            body["language_code"] = languageCode
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let data = try await client.send(request)
        guard !data.isEmpty else { throw ElevenLabsError.decoding("empty audio") }
        return SynthesizedAudio(data: data, mimeType: "audio/mpeg")
    }
}

/// multipart/form-data encoder.
public struct MultipartForm: Sendable {
    public let boundary: String
    private var parts: [Data] = []

    public init(boundary: String = "relay-\(UUID().uuidString)") { self.boundary = boundary }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public mutating func addField(_ name: String, _ value: String) {
        var part = Data()
        part.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        parts.append(part)
    }

    public mutating func addFile(_ name: String, filename: String, mimeType: String, data: Data) {
        var part = Data()
        part.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
        part.append(data)
        part.append(Data("\r\n".utf8))
        parts.append(part)
    }

    public func body() -> Data {
        var data = Data()
        for part in parts { data.append(part) }
        data.append(Data("--\(boundary)--\r\n".utf8))
        return data
    }
}
