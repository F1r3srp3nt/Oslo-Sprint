/**
 * Desktop settings and credentials.
 *
 * Provider keys are encrypted with Electron's safeStorage before they touch
 * disk. On macOS safeStorage keeps its encryption key in the user's Keychain.
 * When the OS offers no secure storage (for example Linux without a keyring,
 * where Electron would fall back to a hard-coded "basic_text" key), keys are
 * kept in memory for this session only and are never written to disk.
 *
 * Keys flow one way: the renderer can set or clear them, but can only read
 * whether a key is saved, never its value.
 */
import { app, safeStorage } from 'electron';
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { z } from 'zod';

export const MODEL_DEFAULTS = {
  anthropicModel: 'claude-opus-5-5',
  ttsModel: 'eleven_multilingual_v2',
  sttModel: 'scribe_v2',
} as const;

const ModelName = z.string().trim().regex(/^[A-Za-z0-9._:-]{1,80}$/, 'Model names use letters, digits, dot, dash, underscore or colon.');

const FileSchema = z.object({
  version: z.literal(1),
  anthropicModel: ModelName.default(MODEL_DEFAULTS.anthropicModel),
  ttsModel: ModelName.default(MODEL_DEFAULTS.ttsModel),
  sttModel: ModelName.default(MODEL_DEFAULTS.sttModel),
  /** base64 of safeStorage.encryptString(key) */
  secrets: z.object({ anthropic: z.string().optional(), elevenlabs: z.string().optional() }).default({}),
});
type SettingsFile = z.infer<typeof FileSchema>;

export type ProviderId = 'anthropic' | 'elevenlabs';

export interface CredentialStatus {
  /** keychain: saved encrypted on disk. session-only: the OS has no secure store, keys last until quit. */
  storage: 'keychain' | 'session-only';
  /** Human name of the secure store, e.g. "macOS Keychain". */
  storeName: string;
  anthropic: { saved: boolean };
  elevenlabs: { saved: boolean };
  anthropicModel: string;
  ttsModel: string;
  sttModel: string;
}

/** Shape the renderer may send. undefined = keep, null or "" = remove. */
export const CredentialUpdateSchema = z
  .object({
    anthropicKey: z.string().max(512).nullable().optional(),
    elevenlabsKey: z.string().max(512).nullable().optional(),
    anthropicModel: ModelName.optional(),
    ttsModel: ModelName.optional(),
    sttModel: ModelName.optional(),
  })
  .strict();
export type CredentialUpdate = z.infer<typeof CredentialUpdateSchema>;

const KEY_PATTERN = /^[\x21-\x7e]{10,512}$/; // printable ASCII, no spaces

export function validateKey(provider: ProviderId, key: string): string {
  const k = key.trim();
  if (!KEY_PATTERN.test(k)) {
    throw new Error(`That does not look like an ${provider === 'anthropic' ? 'Anthropic' : 'ElevenLabs'} API key (10–512 visible characters, no spaces).`);
  }
  return k;
}

export class SettingsStore {
  private file: SettingsFile;
  private readonly path: string;
  private readonly session = new Map<ProviderId, string>();
  readonly secure: boolean;

  constructor(dir = app.getPath('userData')) {
    mkdirSync(dir, { recursive: true });
    this.path = join(dir, 'settings.json');
    this.secure = safeStorage.isEncryptionAvailable() && !(process.platform === 'linux' && safeStorage.getSelectedStorageBackend() === 'basic_text');
    this.file = this.read();
  }

  private read(): SettingsFile {
    if (!existsSync(this.path)) return FileSchema.parse({ version: 1 });
    try {
      return FileSchema.parse(JSON.parse(readFileSync(this.path, 'utf8')));
    } catch {
      // A damaged settings file must not stop the app from starting; keep a copy for diagnosis.
      try {
        renameSync(this.path, `${this.path}.damaged-${Date.now()}`);
      } catch {
        /* ignore */
      }
      return FileSchema.parse({ version: 1 });
    }
  }

  private write() {
    const tmp = `${this.path}.tmp`;
    writeFileSync(tmp, JSON.stringify(this.file, null, 2), { mode: 0o600 });
    renameSync(tmp, this.path);
  }

  getKey(provider: ProviderId): string | null {
    if (!this.secure) return this.session.get(provider) ?? null;
    const enc = this.file.secrets[provider];
    if (!enc) return null;
    try {
      return safeStorage.decryptString(Buffer.from(enc, 'base64'));
    } catch {
      return null; // Keychain item removed or access denied: treat as not set.
    }
  }

  status(): CredentialStatus {
    return {
      storage: this.secure ? 'keychain' : 'session-only',
      storeName: process.platform === 'darwin' ? 'macOS Keychain' : process.platform === 'win32' ? 'Windows data protection' : 'system keyring',
      anthropic: { saved: this.getKey('anthropic') !== null },
      elevenlabs: { saved: this.getKey('elevenlabs') !== null },
      anthropicModel: this.file.anthropicModel,
      ttsModel: this.file.ttsModel,
      sttModel: this.file.sttModel,
    };
  }

  update(raw: unknown): CredentialStatus {
    const u = CredentialUpdateSchema.parse(raw);
    const apply = (provider: ProviderId, value: string | null | undefined) => {
      if (value === undefined) return;
      if (value === null || value.trim() === '') {
        this.session.delete(provider);
        delete this.file.secrets[provider];
        return;
      }
      const key = validateKey(provider, value);
      if (this.secure) this.file.secrets[provider] = safeStorage.encryptString(key).toString('base64');
      else this.session.set(provider, key);
    };
    apply('anthropic', u.anthropicKey);
    apply('elevenlabs', u.elevenlabsKey);
    if (u.anthropicModel) this.file.anthropicModel = u.anthropicModel;
    if (u.ttsModel) this.file.ttsModel = u.ttsModel;
    if (u.sttModel) this.file.sttModel = u.sttModel;
    this.write();
    return this.status();
  }

  /** Environment-style values for loadConfig(). Never includes anything from a .env file. */
  toEnv(): Record<string, string> {
    return {
      ANTHROPIC_API_KEY: this.getKey('anthropic') ?? '',
      ANTHROPIC_MODEL: this.file.anthropicModel,
      ELEVENLABS_API_KEY: this.getKey('elevenlabs') ?? '',
      ELEVENLABS_TTS_MODEL: this.file.ttsModel,
      ELEVENLABS_STT_MODEL: this.file.sttModel,
    };
  }
}
