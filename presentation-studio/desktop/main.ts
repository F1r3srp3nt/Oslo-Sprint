/**
 * Presentation Studio desktop app (Electron main process).
 *
 * - Runs the existing Express backend inside this process on 127.0.0.1 with an
 *   OS-assigned port, so there is no separate server to start, no port
 *   conflicts and nothing left running after quit.
 * - Every API request must carry a per-launch token. Only this app's window
 *   gets it (added by the main process), so other programs and web pages can't
 *   use the loopback API or spend the user's provider credits.
 * - The renderer is sandboxed with context isolation and no Node access. It can
 *   only reach the narrow, validated operations in ipc.ts.
 * - Provider keys come from in-app Setup and are stored with safeStorage
 *   (Keychain on macOS). No .env file is read and no developer keys are bundled.
 */
import { app, BrowserWindow, dialog, Menu, nativeTheme, session, shell, systemPreferences, type MenuItemConstructorOptions } from 'electron';
import { randomBytes } from 'node:crypto';
import { appendFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createApp, type StudioApp } from '../server/app';
import { loadConfig, type ServerConfig } from '../server/config';
import { listenLoopback, type RunningServer } from '../server/listen';
import { SettingsStore } from './settings';
import { registerIpc, type MenuCommand } from './ipc';

const here = dirname(fileURLToPath(import.meta.url));
/** Shown when the built-in server cannot start or the renderer crashes. Shipped next to this file. */
const STARTUP_PAGE = join(here, 'startup.html');
const APP_NAME = 'Presentation Studio';
/** Hosts the app may open in the user's browser (setup guides and provider docs). */
const EXTERNAL_HOSTS = new Set(['platform.claude.com', 'elevenlabs.io', 'docs.claude.com']);

app.setName(APP_NAME);
// Test/CI only: isolate the profile. Never set by the packaged app itself.
if (process.env.PRESENTATION_STUDIO_USER_DATA) app.setPath('userData', process.env.PRESENTATION_STUDIO_USER_DATA);

let backend: { app: StudioApp; server: RunningServer; token: string } | null = null;
let settings: SettingsStore | null = null;
let mainWindow: BrowserWindow | null = null;
let backendClosed = false;

function logLine(msg: string) {
  // Diagnostics only: never keys, request bodies or project content.
  try {
    const dir = join(app.getPath('userData'), 'logs');
    mkdirSync(dir, { recursive: true });
    appendFileSync(join(dir, 'main.log'), `${new Date().toISOString()} ${msg}\n`);
  } catch {
    /* logging must never break the app */
  }
  if (!app.isPackaged) console.log(msg);
}

function serverConfig(store: SettingsStore): ServerConfig {
  const env: Record<string, string> = {
    ...store.toEnv(),
    // Test/CI only: point providers at local mock servers.
    ANTHROPIC_BASE_URL: process.env.PRESENTATION_STUDIO_ANTHROPIC_BASE_URL ?? '',
    ELEVENLABS_BASE_URL: process.env.PRESENTATION_STUDIO_ELEVENLABS_BASE_URL ?? '',
  };
  const base = loadConfig(env, { readDotenv: false });
  return { ...base, mode: 'desktop', production: true, staticDir: join(here, '..', 'dist') };
}

async function startBackend(): Promise<void> {
  settings ??= new SettingsStore();
  const token = randomBytes(32).toString('hex');
  const studio = createApp(serverConfig(settings), { apiToken: token, log: logLine });
  const server = await listenLoopback(studio);
  backend = { app: studio, server, token };
  backendClosed = false;
  logLine(`backend listening on ${server.url} (pid ${process.pid})`);

  // Add the token to API requests from this app's own windows only.
  session.defaultSession.webRequest.onBeforeSendHeaders({ urls: [`${server.url}/api/*`] }, (details, callback) => {
    callback({ requestHeaders: { ...details.requestHeaders, 'X-Studio-Token': token } });
  });
}

async function stopBackend(): Promise<void> {
  if (!backend || backendClosed) return;
  backendClosed = true;
  await backend.server.close();
  logLine('backend stopped');
}

function backendOrigin(): string | null {
  return backend ? backend.server.url : null;
}

function isAppUrl(url: string): boolean {
  const origin = backendOrigin();
  if (origin && (url === origin || url.startsWith(`${origin}/`))) return true;
  return url.split('?')[0] === pathToFileURL(STARTUP_PAGE).href;
}

function openExternalIfAllowed(url: string) {
  try {
    const u = new URL(url);
    if (u.protocol === 'https:' && EXTERNAL_HOSTS.has(u.hostname)) void shell.openExternal(u.toString());
    else logLine(`blocked external URL (${u.protocol}//${u.hostname})`);
  } catch {
    /* not a URL */
  }
}

function hardenSession() {
  const s = session.defaultSession;
  // Only the microphone, only for the app's own page, only audio (spoken brief).
  s.setPermissionRequestHandler((wc, permission, callback, details) => {
    const audioOnly = permission === 'media' && (details as { mediaTypes?: string[] }).mediaTypes?.every((t) => t === 'audio');
    if (!audioOnly || !isAppUrl(wc.getURL())) return callback(false);
    if (process.platform === 'darwin') {
      systemPreferences
        .askForMediaAccess('microphone')
        .then(callback)
        .catch(() => callback(false));
    } else callback(true);
  });
  s.setPermissionCheckHandler((wc, permission) => permission === 'media' && Boolean(wc && isAppUrl(wc.getURL())));
  // Files are written through native save dialogs (ipc.ts), never as silent downloads.
  s.on('will-download', (event) => event.preventDefault());
}

function createWindow(): BrowserWindow {
  const win = new BrowserWindow({
    title: APP_NAME,
    width: 1440,
    height: 900,
    minWidth: 1100,
    minHeight: 700,
    show: false,
    backgroundColor: '#060d1c',
    webPreferences: {
      preload: join(here, 'preload.cjs'),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      webSecurity: true,
      spellcheck: false,
      devTools: !app.isPackaged,
    },
  });
  win.once('ready-to-show', () => win.show());
  win.webContents.on('will-navigate', (event, url) => {
    if (!isAppUrl(url)) {
      event.preventDefault();
      openExternalIfAllowed(url);
    }
  });
  win.webContents.setWindowOpenHandler(({ url }) => {
    openExternalIfAllowed(url);
    return { action: 'deny' };
  });
  // The editor warns before closing with unsaved changes; Electron turns that into this event.
  win.webContents.on('will-prevent-unload', (event) => {
    const choice = dialog.showMessageBoxSync(win, {
      type: 'warning',
      buttons: ['Discard changes and close', 'Keep editing'],
      defaultId: 1,
      cancelId: 1,
      message: 'This presentation has unsaved changes.',
      detail: 'Save it with File › Save Project first if you want to keep your changes.',
    });
    if (choice === 0) event.preventDefault();
  });
  win.webContents.on('render-process-gone', (_e, details) => {
    logLine(`renderer gone: ${details.reason}`);
    if (details.reason !== 'clean-exit') void showStartupError(win, `The editor window stopped unexpectedly (${details.reason}). Unsaved changes in this window are lost.`);
  });
  win.on('closed', () => {
    if (mainWindow === win) mainWindow = null;
  });
  return win;
}

async function showStartupError(win: BrowserWindow, message: string) {
  await win.loadFile(STARTUP_PAGE, {
    query: { error: message, log: join(app.getPath('userData'), 'logs', 'main.log') },
  });
  win.show();
}

async function openMainWindow() {
  const win = createWindow();
  mainWindow = win;
  try {
    if (!backend || backendClosed) await startBackend();
    await win.loadURL(`${backendOrigin()}/`);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    logLine(`startup failed: ${msg}`);
    await showStartupError(win, `The built-in server could not start: ${msg}`);
  }
}

function sendMenu(cmd: MenuCommand) {
  const win = BrowserWindow.getFocusedWindow() ?? mainWindow;
  if (win && backendOrigin() && win.webContents.getURL().startsWith(backendOrigin()!)) win.webContents.send('studio:menu', cmd);
}

function buildMenu() {
  const mac = process.platform === 'darwin';
  const template: MenuItemConstructorOptions[] = [
    ...(mac
      ? [
          {
            label: APP_NAME,
            submenu: [
              { role: 'about' as const },
              { type: 'separator' as const },
              { label: 'Setup && Providers…', accelerator: 'Cmd+,', click: () => sendMenu('setup') },
              { type: 'separator' as const },
              { role: 'hide' as const },
              { role: 'hideOthers' as const },
              { role: 'unhide' as const },
              { type: 'separator' as const },
              { role: 'quit' as const },
            ],
          },
        ]
      : []),
    {
      label: 'File',
      submenu: [
        { label: 'New Project', accelerator: 'CmdOrCtrl+N', click: () => sendMenu('new') },
        { label: 'Open Project…', accelerator: 'CmdOrCtrl+O', click: () => sendMenu('open') },
        { type: 'separator' },
        { label: 'Save Project', accelerator: 'CmdOrCtrl+S', click: () => sendMenu('save') },
        { label: 'Save Project As…', accelerator: 'Shift+CmdOrCtrl+S', click: () => sendMenu('saveAs') },
        { type: 'separator' },
        { label: 'Import Images…', accelerator: 'CmdOrCtrl+I', click: () => sendMenu('importImages') },
        { label: 'Export PowerPoint…', accelerator: 'CmdOrCtrl+E', click: () => sendMenu('exportPptx') },
        { type: 'separator' },
        { label: 'Present', accelerator: 'CmdOrCtrl+Enter', click: () => sendMenu('present') },
        ...(mac ? [] : [{ type: 'separator' as const }, { label: 'Setup && Providers…', click: () => sendMenu('setup') }, { role: 'quit' as const }]),
      ],
    },
    { role: 'editMenu' },
    {
      label: 'View',
      submenu: [
        { role: 'resetZoom' },
        { role: 'zoomIn' },
        { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' },
        ...(app.isPackaged ? [] : [{ type: 'separator' as const }, { role: 'reload' as const }, { role: 'toggleDevTools' as const }]),
      ],
    },
    { role: 'windowMenu' },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

// One running copy: a second launch focuses the existing window instead of starting a second backend.
if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => {
    const win = mainWindow ?? BrowserWindow.getAllWindows()[0];
    if (win) {
      if (win.isMinimized()) win.restore();
      win.focus();
    }
  });

  app.whenReady().then(async () => {
    nativeTheme.themeSource = 'dark';
    app.setAboutPanelOptions({ applicationName: APP_NAME, applicationVersion: app.getVersion(), copyright: 'Oslo Sprint 2026' });
    hardenSession();
    buildMenu();
    registerIpc({
      isAppUrl,
      getSettings: () => (settings ??= new SettingsStore()),
      onSettingsChanged: () => {
        if (backend && settings) backend.app.reconfigure(serverConfig(settings));
      },
      retryStartup: async (win) => {
        try {
          if (!backend || backendClosed) await startBackend();
          await win.loadURL(`${backendOrigin()}/`);
        } catch (err) {
          await showStartupError(win, `The built-in server could not start: ${err instanceof Error ? err.message : String(err)}`);
        }
      },
      log: logLine,
    });
    await openMainWindow();
    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) void openMainWindow();
    });
  });

  app.on('window-all-closed', () => {
    // macOS convention: the app stays in the Dock until quit. Elsewhere, closing the window quits.
    if (process.platform !== 'darwin') app.quit();
  });

  // Stop the backend before the process exits so no port or socket outlives the app.
  app.on('will-quit', (event) => {
    if (backend && !backendClosed) {
      event.preventDefault();
      // Windows are already closed at this point; exit once the server has released its port.
      void stopBackend().finally(() => app.exit(0));
    }
  });

  process.on('uncaughtException', (err) => logLine(`uncaught: ${err.stack ?? err.message}`));
  process.on('unhandledRejection', (err) => logLine(`unhandled rejection: ${String(err)}`));
}
