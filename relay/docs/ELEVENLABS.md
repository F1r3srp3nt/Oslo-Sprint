# ElevenLabs — speech input and output

ElevenLabs is used **only** to turn speech into text and text into speech. It is not Relay's
reasoning engine; interpretation is done by `RuleBasedReasoner` and the procedure answerer.

## Contract source

`elevenlabs.io` was blocked by the build environment's network policy, so the documentation
site could not be read. The contract was taken from ElevenLabs' **official Python SDK**
(`github.com/elevenlabs/elevenlabs-python`, `src/elevenlabs/…`), which is generated from
ElevenLabs' API definition, read on 2026-11-07:

| Use | Request | Notes |
|---|---|---|
| Auth | header `xi-api-key: <key>` | `core/client_wrapper.py` |
| Base URL | `https://api.elevenlabs.io` | `environment.py` (regional variants exist) |
| Transcribe | `POST /v1/speech-to-text`, multipart: `model_id` (required), `file`, optional `language_code` | response: `text`, `language_code`, `language_probability`, `words` |
| Speak | `POST /v1/text-to-speech/{voice_id}?output_format=mp3_44100_128`, JSON `text`, `model_id` | `language_code` is "not supported for multilingual_v2 models", so Relay leaves it out for them |
| Check key | `GET /v1/user` | used by "Test connection" |

Defaults: `scribe_v2` (as in the SDK's examples), `eleven_multilingual_v2`, `mp3_44100_128`.
All three can be changed in Settings. Voice ID: the user must enter one. The button "Use
docs example voice" fills in `JBFqnCBsd6RMkjVDRZzb`, the voice used in ElevenLabs' own README
examples. **Check these details against https://elevenlabs.io/docs before the demo.**

The official Swift SDK (`elevenlabs-swift-sdk`) targets Conversational AI agents over
LiveKit/WebRTC, not plain STT/TTS. Relay therefore calls the REST API with `URLSession` and
adds no dependency.

## What was exercised

- **Real ElevenLabs requests: none.** There was no API key and no network route.
- Request building, response parsing, error mapping (401/422/429/5xx), redaction of error
  bodies and "send nothing without a key/voice" were all tested against a fake transport
  (`Tests/RelayAdaptersTests/ElevenLabsAdapterTests.swift`).

## States shown in the app

| State | Meaning |
|---|---|
| Not configured — text only | No key in the Keychain. The push-to-talk button is disabled. |
| Key saved — not verified | A key is stored; no request has succeeded yet. |
| Checking… | `GET /v1/user` is in flight. |
| Connected (verified) | A real request succeeded (connection test, transcription or speech). |
| Failed: … | The last request failed, and the error is shown. Text input keeps working. |

## Credentials

- Entered in Settings and stored in the **macOS Keychain** (generic password, service
  `com.oslosprint.relay`, account `elevenlabs.api-key`, this device only).
- Relay reads only that item. It never searches other apps' credentials or environment
  variables.
- Every loaded key is registered with the `Redactor`, so it is removed from log entries,
  error messages and exports. Pattern rules also catch `xi-api-key:`, `Bearer …`,
  `api_key=…` and `sk_…`-style strings.
- `scripts/check-no-secrets.sh` checks tracked files before committing.

## Privacy and cost

Audio is captured only while the push-to-talk button is held. It is saved to a temporary
`.m4a` file, sent to `POST /v1/speech-to-text` and deleted afterwards. Reply text is sent to
text-to-speech only when speech output is configured. Spoken text is capped at 1,200
characters per request.
