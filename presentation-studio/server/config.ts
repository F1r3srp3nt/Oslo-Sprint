/**
 * Server configuration. In web/dev mode it comes from environment variables
 * (.env in presentation-studio/). In the desktop app it is built from the
 * in-app settings (see desktop/settings.ts) and never reads a .env file.
 * Keys stay in this process. They are never sent to the renderer, written to
 * project files or exports, or logged.
 */
import { config as loadDotenv } from 'dotenv';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

export interface ServerConfig {
  port: number;
  host: string;
  production: boolean;
  rootDir: string;
  /** 'desktop' when embedded in the Electron app; changes setup hints and enables the API token. */
  mode: 'web' | 'desktop';
  /** Built renderer (Vite output) served in production and desktop mode. */
  staticDir: string;
  generation: {
    provider: 'anthropic' | 'none';
    apiKey: string | null;
    /** Override for the Anthropic API base URL (tests only); null = SDK default. */
    baseUrl: string | null;
    model: string;
    effort: 'low' | 'medium' | 'high' | 'xhigh' | 'max';
    refusalFallback: boolean;
  };
  elevenlabs: {
    apiKey: string | null;
    baseUrl: string;
    ttsModel: string;
    sttModel: string;
  };
}

function clean(v: string | undefined): string | null {
  const s = (v ?? '').trim();
  if (!s || /^(your|replace|changeme|xxx|<)/i.test(s)) return null;
  return s;
}

/** Where the user goes to add or fix a key, per mode. */
export function setupHint(mode: ServerConfig['mode'], provider: 'anthropic' | 'elevenlabs'): string {
  if (mode === 'desktop') return `Open Setup (the AI / Voice button in the top bar) and save your ${provider === 'anthropic' ? 'Anthropic' : 'ElevenLabs'} API key.`;
  return provider === 'anthropic'
    ? 'Add ANTHROPIC_API_KEY to presentation-studio/.env and restart the server.'
    : 'Add ELEVENLABS_API_KEY to presentation-studio/.env and restart the server.';
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env, opts: { readDotenv?: boolean } = {}): ServerConfig {
  if (opts.readDotenv !== false) loadDotenv({ path: join(root, '.env'), quiet: true });
  const anthropicKey = clean(env.ANTHROPIC_API_KEY);
  const requested = (env.GENERATION_PROVIDER ?? '').trim().toLowerCase();
  const provider: 'anthropic' | 'none' = requested === 'none' ? 'none' : anthropicKey ? 'anthropic' : 'none';
  const effort = (env.ANTHROPIC_EFFORT ?? 'medium').trim() as ServerConfig['generation']['effort'];
  return {
    port: Number(env.PORT ?? 8787),
    host: env.HOST ?? '127.0.0.1',
    production: env.NODE_ENV === 'production',
    rootDir: root,
    mode: 'web',
    staticDir: join(root, 'dist'),
    generation: {
      provider,
      apiKey: provider === 'anthropic' ? anthropicKey : null,
      baseUrl: (env.ANTHROPIC_BASE_URL ?? '').trim() || null,
      model: (env.ANTHROPIC_MODEL ?? '').trim() || 'claude-opus-5-5',
      effort: ['low', 'medium', 'high', 'xhigh', 'max'].includes(effort) ? effort : 'medium',
      refusalFallback: (env.ANTHROPIC_REFUSAL_FALLBACK ?? 'default').trim().toLowerCase() !== 'off',
    },
    elevenlabs: {
      apiKey: clean(env.ELEVENLABS_API_KEY),
      baseUrl: ((env.ELEVENLABS_BASE_URL ?? '').trim() || 'https://api.elevenlabs.io').replace(/\/+$/, ''),
      ttsModel: (env.ELEVENLABS_TTS_MODEL ?? '').trim() || 'eleven_multilingual_v2',
      sttModel: (env.ELEVENLABS_STT_MODEL ?? '').trim() || 'scribe_v2',
    },
  };
}
