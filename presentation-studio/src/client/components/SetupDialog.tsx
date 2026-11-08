import { useEffect, useState } from 'react';
import type { ProviderStatus } from '../../shared/apiTypes';
import { api, describeError } from '../api';
import { desktop, isDesktop, type CredentialStatus, type CredentialUpdate } from '../desktop';
import type { ErrInfo } from '../generation';
import { ErrorBox } from './Inspector';
import { Modal } from './Modal';

function Chip({ state, yes, no, unknown }: { state: boolean | null; yes: string; no: string; unknown?: string }) {
  const cls = state === true ? 'ok' : state === false ? 'bad' : 'idle';
  return <span className={`status-chip ${cls}`}>{state === true ? yes : state === false ? no : unknown ?? 'Not checked'}</span>;
}

/** Desktop only: write-only key field. The saved key is never shown again or sent back to this page. */
function KeyForm({
  provider,
  creds,
  onChange,
}: {
  provider: 'anthropic' | 'elevenlabs';
  creds: CredentialStatus;
  onChange: (update: CredentialUpdate) => Promise<string | null>;
}) {
  const [value, setValue] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const saved = creds[provider].saved;
  const field = provider === 'anthropic' ? 'anthropicKey' : 'elevenlabsKey';
  const run = async (update: CredentialUpdate) => {
    setBusy(true);
    setError(await onChange(update));
    setBusy(false);
    setValue('');
  };
  return (
    <div className="key-form" data-testid={`key-form-${provider}`}>
      <label className="field compact">
        <span>{saved ? 'Replace API key' : 'API key'}</span>
        <input
          type="password"
          autoComplete="off"
          spellCheck={false}
          value={value}
          placeholder={saved ? '•••••••• saved' : provider === 'anthropic' ? 'sk-ant-…' : 'Paste your ElevenLabs key'}
          onChange={(e) => setValue(e.target.value)}
          data-testid={`key-input-${provider}`}
        />
      </label>
      <div className="row gap-s">
        <button className="btn small primary" disabled={busy || !value.trim()} onClick={() => run({ [field]: value })} data-testid={`key-save-${provider}`}>
          {busy ? 'Saving…' : 'Save key'}
        </button>
        {saved && (
          <button className="btn small ghost danger" disabled={busy} onClick={() => run({ [field]: null })} data-testid={`key-remove-${provider}`}>
            Remove key
          </button>
        )}
      </div>
      {error && <div className="alert error small">{error}</div>}
      <p className="muted small">
        {creds.storage === 'keychain'
          ? `Saved encrypted on this computer (protected by your ${creds.storeName}). It is only sent to the provider, never shown again, and never written into projects or exports.`
          : 'This system has no secure key storage, so the key is kept only until you quit Presentation Studio.'}
      </p>
    </div>
  );
}

function ModelField({ label, value, onSave }: { label: string; value: string; onSave: (v: string) => Promise<string | null> }) {
  const [v, setV] = useState(value);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => setV(value), [value]);
  return (
    <div className="model-field">
      <label className="field compact">
        <span>{label}</span>
        <div className="row gap-s">
          <input value={v} onChange={(e) => setV(e.target.value)} spellCheck={false} />
          <button className="btn small" disabled={v.trim() === value || !v.trim()} onClick={async () => setError(await onSave(v.trim()))}>
            Save
          </button>
        </div>
      </label>
      {error && <div className="alert error small">{error}</div>}
    </div>
  );
}

export function SetupDialog({ status, onStatus, onClose }: { status: ProviderStatus | null; onStatus: (s: ProviderStatus) => void; onClose: () => void }) {
  const [busy, setBusy] = useState<'gen' | 'el' | null>(null);
  const [err, setErr] = useState<ErrInfo | null>(null);
  const [creds, setCreds] = useState<CredentialStatus | null>(null);

  useEffect(() => {
    if (desktop) void desktop.getCredentials().then(setCreds);
  }, []);

  /** Saves settings in the desktop shell, which re-configures the built-in server; returns an error message or null. */
  const saveCredentials = async (update: CredentialUpdate): Promise<string | null> => {
    if (!desktop) return 'Not available in the browser.';
    const r = await desktop.setCredentials(update);
    if (!r.ok) return r.error;
    setCreds(r.status);
    try {
      onStatus(await api.status());
    } catch (e) {
      setErr(describeError(e));
    }
    return null;
  };

  const verify = async (which: 'gen' | 'el') => {
    setBusy(which);
    setErr(null);
    try {
      onStatus(which === 'gen' ? await api.verifyGeneration() : await api.verifyElevenLabs());
    } catch (e) {
      setErr(describeError(e));
    } finally {
      setBusy(null);
    }
  };
  const g = status?.generation;
  const el = status?.elevenlabs;

  return (
    <Modal title="Setup & providers" onClose={onClose} wide>
      {!status &&
        (isDesktop ? (
          <div className="alert error">The built-in server is not responding. Quit and reopen Presentation Studio.</div>
        ) : (
          <div className="alert error">
            Cannot reach the local server. Start it with <code>npm run dev</code> in <code>presentation-studio/</code>.
          </div>
        ))}
      {isDesktop && (
        <p className="muted small setup-intro">
          Both providers are optional. Without them you can still import images, build a deck from a template, edit, present, save and export PowerPoint.
        </p>
      )}
      {err && <ErrorBox err={err} />}
      <div className="setup-grid">
        <section className="card">
          <div className="card-head">
            <h3>Slide generation · Anthropic</h3>
          </div>
          <div className="status-rows">
            <div>
              Key configured <Chip state={g ? g.configured : null} yes="Yes" no="No" />
            </div>
            <div>
              Connection verified <Chip state={g?.configured ? g.verified : null} yes="Verified" no="Failed" unknown={g?.configured ? 'Not checked' : '—'} />
            </div>
            {g?.model && (
              <div>
                Model <code>{g.model}</code>
              </div>
            )}
          </div>
          {g?.lastError && <div className="alert error small">{g.lastError}</div>}
          <button className="btn small" disabled={!g?.configured || busy !== null} onClick={() => verify('gen')}>
            {busy === 'gen' ? 'Checking…' : 'Verify connection'}
          </button>
          <p className="muted small">Verifying looks up the model and does not generate anything.</p>
          <h4>Set up</h4>
          <ol className="small">
            <li>
              Create an API key in the Claude Console:{' '}
              <a href="https://platform.claude.com/settings/keys" target="_blank" rel="noreferrer">
                platform.claude.com/settings/keys
              </a>
              .
            </li>
            {isDesktop ? (
              <li>Paste it below and click <b>Save key</b>, then <b>Verify connection</b>.</li>
            ) : (
              <>
                <li>
                  Put it in <code>presentation-studio/.env</code> as <code>ANTHROPIC_API_KEY=…</code> (copy <code>.env.example</code>).
                </li>
                <li>Restart the server, then click <b>Verify connection</b>.</li>
              </>
            )}
          </ol>
          {creds && (
            <>
              <KeyForm provider="anthropic" creds={creds} onChange={saveCredentials} />
              <ModelField label="Model" value={creds.anthropicModel} onSave={(v) => saveCredentials({ anthropicModel: v })} />
            </>
          )}
          <p className="muted small">
            When you generate, your brief and downscaled copies of your images go to Anthropic. API usage is billed to that key. Without a key, template mode, editing and
            export still work.
          </p>
        </section>

        <section className="card">
          <div className="card-head">
            <h3>Voice · ElevenLabs</h3>
            <span className="pill small">optional</span>
          </div>
          <div className="status-rows">
            <div>
              Key configured <Chip state={el ? el.configured : null} yes="Yes" no="No" />
            </div>
            <div>
              Connection verified <Chip state={el?.configured ? el.verified : null} yes="Verified" no="Failed" unknown={el?.configured ? 'Not checked' : '—'} />
            </div>
            {el && (
              <div className="block">
                Models: <code>{el.sttModel}</code> speech-to-text · <code>{el.ttsModel}</code> narration
              </div>
            )}
            {el?.credits && (
              <div>
                Credits used {el.credits.used.toLocaleString()} / {el.credits.limit.toLocaleString()} ({el.credits.tier})
                {el.credits.resetsAt && <span className="muted"> · resets {new Date(el.credits.resetsAt).toLocaleDateString()}</span>}
              </div>
            )}
          </div>
          {el?.checks && el.checks.length > 0 && (
            <ul className="checks small">
              {el.checks.map((c, i) => (
                <li key={i} className={c.ok === null ? 'untested' : c.ok ? 'ok' : 'bad'}>
                  {c.ok === null ? '○' : c.ok ? '✓' : '✕'} {c.name} — <span className="muted">{c.detail}</span>
                </li>
              ))}
            </ul>
          )}
          {el?.lastError && !el.checks.length && <div className="alert error small">{el.lastError}</div>}
          <button className="btn small" disabled={!el?.configured || busy !== null} onClick={() => verify('el')} data-testid="verify-elevenlabs">
            {busy === 'el' ? 'Checking…' : 'Verify connection'}
          </button>
          <p className="muted small">Verifying lists voices and reads your credit balance; it does not use credits.</p>
          <h4>Set up</h4>
          <ol className="small">
            <li>
              Sign in at{' '}
              <a href="https://elevenlabs.io/app" target="_blank" rel="noreferrer">
                elevenlabs.io
              </a>{' '}
              and open{' '}
              <a href="https://elevenlabs.io/app/settings/api-keys" target="_blank" rel="noreferrer">
                Settings → API keys
              </a>
              . Create a key.
            </li>
            <li>
              If you restrict the key, allow <b>Text to Speech</b>, <b>Speech to Text</b> and reading <b>Voices</b>. Reading <b>User</b> is optional (it lets the app show your
              credit balance). Consider setting a credit limit on the key.
            </li>
            {isDesktop ? (
              <li>Paste it below and click <b>Save key</b>.</li>
            ) : (
              <li>
                Put it in <code>presentation-studio/.env</code> as <code>ELEVENLABS_API_KEY=…</code> and restart the server. The key stays on the server: it is never sent to
                the browser, saved in projects or exports, or logged.
              </li>
            )}
            <li>
              Click <b>Verify connection</b>. Then pick a voice under <b>Narration</b>. To use other voices, add them to <i>My Voices</i> from the{' '}
              <a href="https://elevenlabs.io/app/voice-library" target="_blank" rel="noreferrer">
                Voice Library
              </a>
              .
            </li>
          </ol>
          {creds && (
            <>
              <KeyForm provider="elevenlabs" creds={creds} onChange={saveCredentials} />
              <ModelField label="Narration model" value={creds.ttsModel} onSave={(v) => saveCredentials({ ttsModel: v })} />
              <ModelField label="Transcription model" value={creds.sttModel} onSave={(v) => saveCredentials({ sttModel: v })} />
            </>
          )}
          <p className="muted small">
            <b>Credits:</b> speech-to-text (spoken brief) and text-to-speech (narration) both use ElevenLabs credits. The app always asks before sending audio or text.
            Docs:{' '}
            <a href="https://elevenlabs.io/docs/api-reference/authentication" target="_blank" rel="noreferrer">
              authentication
            </a>
            ,{' '}
            <a href="https://elevenlabs.io/docs/overview/models" target="_blank" rel="noreferrer">
              models
            </a>
            .
          </p>
        </section>
      </div>
    </Modal>
  );
}
