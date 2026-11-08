import express, { type NextFunction, type Request, type Response } from 'express';
import multer from 'multer';
import { timingSafeEqual } from 'node:crypto';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { z } from 'zod';
import { setupHint, type ServerConfig } from './config';
import { ApiError } from './errors';
import { createAnthropicGenerator, mapAnthropicError, type Generator } from './generation';
import { ElevenLabsClient, type FetchLike } from './elevenlabs';
import type { ProviderStatus } from '../src/shared/apiTypes';
import { BriefSchema, LAYOUT_IDS } from '../src/shared/model';
import { OutlineSchema, OutlineSlideSchema, SlideContentSchema, ImageNoteSchema } from '../src/shared/generationSchemas';

export interface AppDeps {
  /** Fixed generator (tests). When undefined, one is created from the config's Anthropic settings. */
  generator?: Generator | null;
  fetchImpl?: FetchLike;
  log?: (msg: string) => void;
  /**
   * Required on every /api request as the X-Studio-Token header (desktop app). The Electron
   * main process adds it to requests from its own window, so other local programs and web
   * pages cannot call the API (or spend the user's credits) through the loopback port.
   */
  apiToken?: string;
}

/** Content Security Policy for the desktop renderer: everything local; https media only for ElevenLabs voice samples. */
export const DESKTOP_CSP = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' blob: data:",
  "media-src 'self' blob: https:",
  "font-src 'self'",
  "connect-src 'self'",
  "object-src 'none'",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'",
].join('; ');

function sameToken(a: string, b: string): boolean {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}

const ImageSchema = z.object({
  id: z.string().min(1).max(64),
  name: z.string().max(300),
  caption: z.string().max(2000),
  preferredSlide: z.number().int().positive().nullable(),
  mediaType: z.enum(['image/jpeg', 'image/png', 'image/webp']),
  data: z.string().min(1).max(8_000_000),
});
const OutlineRequestSchema = z.object({ brief: BriefSchema, images: z.array(ImageSchema).max(20) });
const SlideRequestSchema = z.object({
  brief: BriefSchema,
  outline: OutlineSchema,
  index: z.number().int().nonnegative(),
  planned: OutlineSlideSchema,
  images: z.array(ImageSchema).max(20),
  imageNotes: z.array(ImageNoteSchema),
  current: SlideContentSchema.optional(),
  instruction: z.string().max(2000).optional(),
  deckTitles: z.array(z.string()).optional(),
  assetIds: z.array(z.string()).max(200),
});
const TtsSchema = z.object({ voiceId: z.string().min(1).max(64), text: z.string().max(40000), modelId: z.string().max(64).optional() });

function parseBody<T>(schema: z.ZodType<T>, body: unknown): T {
  const r = schema.safeParse(body);
  if (!r.success) {
    throw new ApiError(400, 'bad_request', 'The request was not in the expected format.', false, undefined, r.error.issues.slice(0, 5).map((i) => `${i.path.join('.')}: ${i.message}`));
  }
  return r.data;
}

type Handler = (req: Request, res: Response) => Promise<void>;
const wrap = (fn: Handler) => (req: Request, res: Response, next: NextFunction) => fn(req, res).catch(next);

export type StudioApp = ReturnType<typeof express> & {
  /** Replace provider settings (keys, models) without restarting; resets verification status. */
  reconfigure(next: ServerConfig): void;
  providerStatus(): ProviderStatus;
};

interface ProviderState {
  config: ServerConfig;
  generator: Generator | null;
  eleven: ElevenLabsClient;
  status: ProviderStatus;
}

export function createApp(initial: ServerConfig, deps: AppDeps = {}): StudioApp {
  const log = deps.log ?? ((m: string) => console.log(m));
  const mode = initial.mode;

  const build = (config: ServerConfig): ProviderState => {
    const generator: Generator | null =
      deps.generator !== undefined
        ? deps.generator
        : config.generation.provider === 'anthropic'
          ? createAnthropicGenerator(config.generation, undefined, config.mode)
          : null;
    const eleven = new ElevenLabsClient(config.elevenlabs, deps.fetchImpl, config.mode);
    return {
      config,
      generator,
      eleven,
      status: {
        generation: {
          provider: generator ? 'anthropic' : 'none',
          configured: Boolean(generator),
          model: generator ? config.generation.model : null,
          verified: null,
          verifiedAt: null,
          lastError: null,
        },
        elevenlabs: {
          configured: eleven.configured,
          verified: null,
          verifiedAt: null,
          lastError: null,
          ttsModel: config.elevenlabs.ttsModel,
          sttModel: config.elevenlabs.sttModel,
          checks: [],
          credits: null,
        },
      },
    };
  };
  let state = build(initial);

  const app = express() as StudioApp;
  app.reconfigure = (next) => {
    state = build({ ...next, mode });
  };
  app.providerStatus = () => structuredClone(state.status);
  app.disable('x-powered-by');
  app.use((_req, res, next) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    if (mode === 'desktop') res.setHeader('Content-Security-Policy', DESKTOP_CSP);
    next();
  });
  if (deps.apiToken) {
    const token = deps.apiToken;
    app.use('/api', (req, _res, next) => {
      const sent = req.get('x-studio-token') ?? '';
      if (!sameToken(sent, token)) return next(new ApiError(403, 'forbidden', 'This request did not come from the Presentation Studio window.', false));
      next();
    });
  }
  app.use('/api', express.json({ limit: '60mb' }));
  const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 50 * 1024 * 1024, files: 1 } });

  app.get('/api/status', (_req, res) => {
    res.json(state.status);
  });

  // ---- Generation ---------------------------------------------------------
  const requireGenerator = () => {
    if (!state.generator) {
      throw new ApiError(503, 'generation_not_configured', 'No AI provider is configured.', false, `Use template mode, or: ${setupHint(mode, 'anthropic')}`);
    }
    return state.generator;
  };

  app.post('/api/generation/verify', wrap(async (_req, res) => {
    const g = requireGenerator();
    const { status } = state;
    try {
      await g.verify();
      Object.assign(status.generation, { verified: true, verifiedAt: new Date().toISOString(), lastError: null });
    } catch (err) {
      const e = mapAnthropicError(err, mode);
      Object.assign(status.generation, { verified: false, verifiedAt: new Date().toISOString(), lastError: e.message });
    }
    res.json(status);
  }));

  app.post('/api/generate/outline', wrap(async (req, res) => {
    const g = requireGenerator();
    const body = parseBody(OutlineRequestSchema, req.body);
    log(`[generate] outline: ${body.images.length} image(s), ${body.brief.slideCount} slide(s)`);
    const result = await g.outline(body);
    Object.assign(state.status.generation, { verified: true, verifiedAt: new Date().toISOString(), lastError: null });
    res.json(result);
  }));

  app.post('/api/generate/slide', wrap(async (req, res) => {
    const g = requireGenerator();
    const body = parseBody(SlideRequestSchema, req.body);
    if (!LAYOUT_IDS.includes(body.planned.layout)) throw new ApiError(400, 'bad_request', 'Unknown layout.', false);
    log(`[generate] slide ${body.index + 1}${body.current ? ' (regenerate)' : ''}`);
    const { assetIds, ...slideReq } = body;
    res.json(await g.slide(slideReq, assetIds));
  }));

  // ---- ElevenLabs -----------------------------------------------------------
  app.post('/api/elevenlabs/verify', wrap(async (_req, res) => {
    const { eleven, status } = state;
    const checks: ProviderStatus['elevenlabs']['checks'] = [];
    let ok = true;
    let lastError: string | null = null;
    try {
      const voices = await eleven.listVoices();
      checks.push({ name: 'API key accepted and voices readable', ok: true, detail: `${voices.length} voice(s) available.` });
    } catch (err) {
      const e = err instanceof ApiError ? err : new ApiError(500, 'unknown', 'Unexpected error.', true);
      ok = false;
      lastError = `${e.message}${e.hint ? ` ${e.hint}` : ''}`;
      checks.push({ name: 'API key accepted and voices readable', ok: false, detail: lastError });
    }
    status.elevenlabs.credits = null;
    if (ok) {
      try {
        status.elevenlabs.credits = await eleven.subscription();
        checks.push({ name: 'Credit balance readable (optional)', ok: true, detail: 'Shown below.' });
      } catch (err) {
        const e = err as ApiError;
        checks.push({ name: 'Credit balance readable (optional)', ok: false, detail: e.code === 'elevenlabs_permission' ? 'The key lacks "User (read)". Not required; credits just cannot be shown.' : e.message });
      }
      checks.push({ name: 'Speech to Text / Text to Speech', ok: null, detail: 'Not tested: each test call would use credits. Checked on first use.' });
    }
    Object.assign(status.elevenlabs, { configured: eleven.configured, verified: ok, verifiedAt: new Date().toISOString(), lastError, checks });
    res.json(status);
  }));

  app.get('/api/elevenlabs/voices', wrap(async (_req, res) => {
    res.json({ voices: await state.eleven.listVoices() });
  }));

  app.post('/api/elevenlabs/tts', wrap(async (req, res) => {
    const body = parseBody(TtsSchema, req.body);
    log(`[elevenlabs] text-to-speech: ${body.text.length} characters`);
    const out = await state.eleven.textToSpeech(body.voiceId, body.text, body.modelId);
    res.setHeader('Content-Type', out.mime);
    res.setHeader('X-Narration-Model', out.model);
    res.setHeader('X-Narration-Characters', String(body.text.length));
    res.send(Buffer.from(out.audio));
  }));

  app.post('/api/elevenlabs/transcribe', upload.single('audio'), wrap(async (req, res) => {
    const file = req.file;
    if (!file || file.size === 0) throw new ApiError(400, 'bad_request', 'No recording was received.', false, 'Record again.');
    log(`[elevenlabs] speech-to-text: ${Math.round(file.size / 1024)} KB`);
    const lang = typeof req.body?.languageCode === 'string' && /^[a-z]{2,3}$/.test(req.body.languageCode) ? req.body.languageCode : undefined;
    res.json(await state.eleven.speechToText(file.buffer, file.mimetype, file.originalname || 'brief.webm', lang));
  }));

  app.use('/api', (_req, _res, next) => next(new ApiError(404, 'not_found', 'Unknown API route.', false)));

  // ---- Static client (production build) -------------------------------------
  const dist = initial.staticDir ?? join(initial.rootDir, 'dist');
  if ((initial.production || mode === 'desktop') && existsSync(dist)) {
    app.use(express.static(dist));
    app.get(/^(?!\/api\/).*/, (_req, res) => res.sendFile(join(dist, 'index.html')));
  }

  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    let e: ApiError;
    if (err instanceof ApiError) e = err;
    else if (err instanceof multer.MulterError) e = new ApiError(413, 'too_large', 'The recording is too large.', false, 'Record a shorter brief (under 50 MB).');
    else if ((err as { type?: string })?.type === 'entity.too.large') e = new ApiError(413, 'too_large', 'The request is too large.', false, 'Use fewer or smaller images.');
    else if ((err as { type?: string })?.type === 'entity.parse.failed') e = new ApiError(400, 'bad_request', 'The request body is not valid JSON.', false);
    else e = mapAnthropicError(err, mode);
    // Log the code and message only; never request bodies or headers (they can contain user content or keys).
    log(`[error] ${e.status} ${e.code}: ${e.message}`);
    const { status } = state;
    if (status.elevenlabs.configured && e.code.startsWith('elevenlabs_') && ['elevenlabs_auth', 'elevenlabs_permission', 'elevenlabs_credits'].includes(e.code)) {
      status.elevenlabs.lastError = e.message;
    }
    res.status(e.status).json(e.toBody());
  });

  return app;
}
