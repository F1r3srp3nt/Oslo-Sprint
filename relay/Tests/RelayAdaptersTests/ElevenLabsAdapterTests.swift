import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import RelayAdapters
@testable import RelayCore

final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    var status = 200
    var body = Data()

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock(); requests.append(request); lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
        return (body, response)
    }

    var sent: [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
}

final class ElevenLabsAdapterTests: XCTestCase {
    let key = "sk_testkey0123456789abcdefABCDEF"

    func client(_ transport: FakeTransport, key: String?, voice: String = "VoiceABC123", redactor: Redactor = Redactor()) -> ElevenLabsClient {
        ElevenLabsClient(configuration: ElevenLabsConfiguration(voiceID: voice), transport: transport,
                         redactor: redactor, apiKey: { key })
    }

    func testTranscriptionRequestMatchesDocumentedContract() async throws {
        let transport = FakeTransport()
        transport.body = Data(#"{"language_code":"pol","language_probability":0.98,"text":" dalej ","words":[]}"#.utf8)
        let transcriber = ElevenLabsTranscriber(client: client(transport, key: key))
        let transcript = try await transcriber.transcribe(audio: Data([1, 2, 3]), filename: "ptt.m4a",
                                                          mimeType: "audio/mp4", languageHint: "pl")
        XCTAssertEqual(transcript.text, "dalej")
        XCTAssertEqual(transcript.languageCode, "pol")
        XCTAssertTrue(transcript.provider.contains("scribe_v2"))

        let request = try XCTUnwrap(transport.sent.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.elevenlabs.io/v1/speech-to-text")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), key)
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data; boundary="))
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"model_id\"\r\n\r\nscribe_v2"))
        XCTAssertTrue(body.contains("name=\"language_code\"\r\n\r\npl"))
        XCTAssertTrue(body.contains("name=\"file\"; filename=\"ptt.m4a\""))
    }

    func testSynthesisRequestMatchesDocumentedContract() async throws {
        let transport = FakeTransport()
        transport.body = Data([0xFF, 0xFB, 0x90])
        let synthesizer = ElevenLabsSynthesizer(client: client(transport, key: key))
        let audio = try await synthesizer.synthesize(text: "Krok 1", languageCode: "pl")
        XCTAssertEqual(audio.data, Data([0xFF, 0xFB, 0x90]))
        let request = try XCTUnwrap(transport.sent.first)
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.elevenlabs.io/v1/text-to-speech/VoiceABC123?output_format=mp3_44100_128")
        let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
        XCTAssertEqual(json["text"], "Krok 1")
        XCTAssertEqual(json["model_id"], "eleven_multilingual_v2")
        XCTAssertNil(json["language_code"], "not supported for multilingual_v2 per the API definition")
    }

    func testMissingCredentialsSendNothing() async {
        let transport = FakeTransport()
        let transcriber = ElevenLabsTranscriber(client: client(transport, key: nil))
        do {
            _ = try await transcriber.transcribe(audio: Data(), filename: "a.m4a", mimeType: "audio/mp4", languageHint: nil)
            XCTFail("expected missingAPIKey")
        } catch { XCTAssertEqual(error as? ElevenLabsError, .missingAPIKey) }
        let synthesizer = ElevenLabsSynthesizer(client: client(transport, key: key, voice: ""))
        do {
            _ = try await synthesizer.synthesize(text: "x", languageCode: nil)
            XCTFail("expected missingVoiceID")
        } catch { XCTAssertEqual(error as? ElevenLabsError, .missingVoiceID) }
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testVerifyNeverFakesAConnection() async {
        let transport = FakeTransport()
        let noKey = await client(transport, key: nil).verify()
        XCTAssertEqual(noKey, .unconfigured)
        XCTAssertTrue(transport.sent.isEmpty)

        transport.status = 401
        transport.body = Data(#"{"detail":{"status":"invalid_api_key","message":"Invalid API key"}}"#.utf8)
        let rejected = await client(transport, key: key).verify()
        XCTAssertEqual(rejected, .failed("ElevenLabs rejected the API key (401)"))

        transport.status = 200
        let fixed = Date(timeIntervalSince1970: 1)
        let ok = await client(transport, key: key).verify(now: { fixed })
        XCTAssertEqual(ok, .connected(verifiedAt: fixed))
        XCTAssertEqual(transport.sent.last?.url?.path, "/v1/user")
    }

    func testErrorBodiesAreRedacted() async {
        let transport = FakeTransport()
        transport.status = 422
        transport.body = Data("{\"detail\":{\"message\":\"bad header xi-api-key: \(key)\"}}".utf8)
        let synthesizer = ElevenLabsSynthesizer(client: client(transport, key: key))
        do {
            _ = try await synthesizer.synthesize(text: "x", languageCode: nil)
            XCTFail("expected error")
        } catch {
            let text = String(describing: error)
            XCTAssertFalse(text.contains(key), text)
            XCTAssertTrue(text.contains(Redactor.placeholder))
        }
    }

    func testRateLimitAndServerErrorsAreDistinct() async {
        let transport = FakeTransport()
        let synthesizer = ElevenLabsSynthesizer(client: client(transport, key: key))
        transport.status = 429
        do { _ = try await synthesizer.synthesize(text: "x", languageCode: nil); XCTFail() }
        catch { XCTAssertEqual(error as? ElevenLabsError, .rateLimited) }
        transport.status = 503
        do { _ = try await synthesizer.synthesize(text: "x", languageCode: nil); XCTFail() }
        catch { XCTAssertEqual(error as? ElevenLabsError, .server(503)) }
    }

    func testVoiceIDCannotInjectPath() async {
        let transport = FakeTransport()
        let synthesizer = ElevenLabsSynthesizer(client: client(transport, key: key, voice: "../v1/user"))
        do { _ = try await synthesizer.synthesize(text: "x", languageCode: nil); XCTFail() }
        catch { XCTAssertTrue(String(describing: error).contains("voice ID")) }
        XCTAssertTrue(transport.sent.isEmpty)
    }
}

final class CredentialTests: XCTestCase {
    func testSaveRegistersSecretWithRedactorAndMasks() throws {
        let store = InMemoryCredentialStore()
        let redactor = Redactor()
        let secret = "sk_abcdefghijklmnopqrstuvwxyz123456"
        try CredentialAccess.save("  \(secret)\n", account: CredentialAccount.elevenLabsAPIKey, to: store, redactor: redactor)
        XCTAssertEqual(try store.read(CredentialAccount.elevenLabsAPIKey), secret, "whitespace trimmed")
        XCTAssertEqual(redactor.redact("using \(secret)"), "using \(Redactor.placeholder)")
        XCTAssertEqual(CredentialAccess.masked(secret), "••••••••3456")
        XCTAssertEqual(CredentialAccess.masked(nil), "Not set")
        XCTAssertThrowsError(try CredentialAccess.save("   ", account: "x", to: store, redactor: redactor))
        try store.delete(CredentialAccount.elevenLabsAPIKey)
        XCTAssertNil(CredentialAccess.load(CredentialAccount.elevenLabsAPIKey, from: store, redactor: redactor))
    }

    func testLoggingAKeyThroughTheEventLogNeverStoresIt() throws {
        let store = InMemoryCredentialStore()
        let redactor = Redactor()
        let log = InMemoryEventLog(redactor: redactor)
        let secret = "plain-looking-secret-value"
        try CredentialAccess.save(secret, account: CredentialAccount.elevenLabsAPIKey, to: store, redactor: redactor)
        log.record(.settings, .info, "Saved key \(secret)")
        XCTAssertFalse(log.exportJSONLines().contains(secret))
    }
}
