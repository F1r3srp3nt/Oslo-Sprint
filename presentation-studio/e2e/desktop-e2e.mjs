// End-to-end test of the PACKAGED desktop app (electron-builder output), driven by Playwright.
//
// What it does (no development server is running; the test checks the dev ports are free first):
//   launch → own window → renderer isolation → missing-credentials guidance → import images (native
//   dialog) → template deck → edit/reorder → save project (native dialog) → Save again (no dialog) →
//   new → reopen → export .pptx (validated with python-pptx and LibreOffice) → presentation mode →
//   in-app keys (against MOCK providers) → startup-error page → second launch focuses the first →
//   quit → backend port closed and no app processes left.
//
// Native dialogs are answered by replacing dialog.showOpenDialog/showSaveDialog inside the running
// app's main process (Playwright electronApp.evaluate). The app contains no test hooks for this.
//
// Usage: npm run desktop:pack (Linux: electron-builder --dir), then npm run test:desktop.
// Env: STUDIO_APP=/path/to/executable to test another build; DISPLAY must be set (use xvfb-run on Linux).
import { _electron as electron } from 'playwright';
import { execFileSync, spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createConnection } from 'node:net';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import JSZip from 'jszip';
import { startMockProviders } from './mock-providers.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = join(root, 'test-output', 'desktop');
rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });
const shots = join(out, 'screenshots');
mkdirSync(shots, { recursive: true });

function defaultExecutable() {
  if (process.platform === 'darwin') return join(root, 'release', 'mac-arm64', 'Presentation Studio.app', 'Contents', 'MacOS', 'Presentation Studio');
  return join(root, 'release', 'linux-unpacked', 'presentation-studio');
}
const executable = process.env.STUDIO_APP || defaultExecutable();
assert.ok(existsSync(executable), `Packaged app not found at ${executable}. Run npm run desktop:pack first.`);
// Chromium refuses to run as root without --no-sandbox (containers only). STUDIO_EXTRA_ARGS e.g. "--password-store=gnome-libsecret".
const args = [...(process.getuid?.() === 0 ? ['--no-sandbox'] : []), ...(process.env.STUDIO_EXTRA_ARGS ?? '').split(' ').filter(Boolean)];
const sample = (f) => join(root, 'samples', f);
const ANTHROPIC_KEY = 'desktop-e2e-anthropic-key-0001';
const ELEVEN_KEY = 'desktop-e2e-elevenlabs-key-0001';

const results = [];
const step = async (name, fn) => {
  try {
    await fn();
    results.push({ name, ok: true });
    console.log(`  ✓ ${name}`);
  } catch (e) {
    results.push({ name, ok: false, error: String(e?.message ?? e) });
    console.log(`  ✕ ${name}\n    ${String(e?.stack ?? e).split('\n').slice(0, 5).join('\n    ')}`);
    throw e;
  }
};
const portOpen = (port) =>
  new Promise((resolve) => {
    const s = createConnection({ host: '127.0.0.1', port }, () => {
      s.destroy();
      resolve(true);
    });
    s.on('error', () => resolve(false));
  });
const appProcesses = () => {
  try {
    return execFileSync('pgrep', ['-f', executable], { encoding: 'utf8' }).trim().split('\n').filter(Boolean);
  } catch {
    return [];
  }
};

/** Make the next native open/save dialog in the app answer with these paths. Counts calls. */
async function answerDialogs(app, { open, save }) {
  await app.evaluate(({ dialog }, { open, save }) => {
    globalThis.__dialogCalls = globalThis.__dialogCalls ?? { open: 0, save: 0 };
    if (open) dialog.showOpenDialog = async () => (globalThis.__dialogCalls.open++, { canceled: false, filePaths: open });
    if (save) dialog.showSaveDialog = async () => (globalThis.__dialogCalls.save++, { canceled: false, filePath: save });
  }, { open, save });
}
const dialogCalls = (app) => app.evaluate(() => globalThis.__dialogCalls);

const mocks = await startMockProviders({ anthropicKey: ANTHROPIC_KEY, elevenKey: ELEVEN_KEY });
const userData = mkdtempSync(join(tmpdir(), 'presentation-studio-e2e-'));
const env = {
  ...process.env,
  PRESENTATION_STUDIO_USER_DATA: userData,
  // Providers point at local MOCK servers; keys are entered through the app's own Setup dialog below.
  PRESENTATION_STUDIO_ANTHROPIC_BASE_URL: mocks.anthropicUrl,
  PRESENTATION_STUDIO_ELEVENLABS_BASE_URL: mocks.elevenUrl,
};
// Make sure nothing from a developer shell leaks into the app.
for (const k of ['ANTHROPIC_API_KEY', 'ELEVENLABS_API_KEY', 'ANTHROPIC_BASE_URL', 'ELEVENLABS_BASE_URL']) delete env[k];

let app;
let win;
let backendPort;
let keyStorage;
let failed = false;
const pptxPath = join(out, 'exported.pptx');
const projectPath = join(out, 'saved-project.pstudio');

try {
  console.log(`Packaged app: ${executable}`);
  await step('no development server is running (ports 5173, 8787 free)', async () => {
    assert.equal(await portOpen(5173), false, 'Vite dev server is running');
    assert.equal(await portOpen(8787), false, 'API dev server is running');
    assert.deepEqual(appProcesses(), [], 'an instance of the app is already running');
  });

  await step('launches and opens its own window served by the built-in backend', async () => {
    app = await electron.launch({ executablePath: executable, args, env, timeout: 60000 });
    win = await app.firstWindow();
    await win.waitForSelector('.topbar', { timeout: 30000 });
    assert.equal(await win.title(), 'Presentation Studio');
    const url = new URL(win.url());
    assert.equal(url.hostname, '127.0.0.1');
    backendPort = Number(url.port);
    assert.ok(backendPort > 0 && backendPort !== 8787 && backendPort !== 5173, `ephemeral port, got ${backendPort}`);
    const appInfo = await app.evaluate(({ app, BrowserWindow }) => ({ name: app.getName(), packaged: app.isPackaged, windows: BrowserWindow.getAllWindows().length }));
    assert.deepEqual(appInfo, { name: 'Presentation Studio', packaged: true, windows: 1 });
    await win.screenshot({ path: join(shots, '01-launch.png') });
  });

  await step('renderer has no Node access; API refuses requests without the launch token', async () => {
    const r = await win.evaluate(() => ({
      require: typeof window.require,
      process: typeof window.process,
      bridge: Object.keys(window.studioDesktop ?? {}).sort(),
    }));
    assert.equal(r.require, 'undefined');
    assert.equal(r.process, 'undefined');
    assert.deepEqual(r.bridge, ['appInfo', 'getCredentials', 'importImages', 'isDesktop', 'newProject', 'onMenu', 'openProject', 'quit', 'retryStartup', 'saveExport', 'saveProject', 'setCredentials', 'showLogs']);
    const outside = await fetch(`http://127.0.0.1:${backendPort}/api/status`);
    assert.equal(outside.status, 403, 'API must reject callers outside the app window');
    const inside = await win.evaluate(async () => (await fetch('/api/status')).status);
    assert.equal(inside, 200);
  });

  await step('missing provider keys: setup guidance shown, manual work not blocked', async () => {
    await win.click('[data-testid=open-setup]');
    const dialogText = await win.getByRole('dialog', { name: 'Setup & providers' }).innerText();
    assert.match(dialogText, /Both providers are optional/);
    assert.match(dialogText, /Paste it below and click Save key/);
    assert.doesNotMatch(dialogText, /\.env/);
    assert.equal(await win.locator('[data-testid=key-input-anthropic]').count(), 1);
    assert.equal(await win.locator('[data-testid=key-input-elevenlabs]').count(), 1);
    await win.screenshot({ path: join(shots, '02-setup-no-keys.png') });
    await win.keyboard.press('Escape');
    await win.click('[data-testid=step-brief]');
    assert.equal(await win.isDisabled('[data-testid=generate-ai]'), true);
    assert.match(await win.locator('.spoken').innerText(), /not configured/);
    await win.click('[data-testid=step-sources]');
  });

  await step('import images through the native file dialog (non-images rejected)', async () => {
    const fake = join(out, 'not-really-an-image.png');
    writeFileSync(fake, 'this is text, not a PNG');
    await answerDialogs(app, { open: [sample('fjordlight-harbour-wide.png'), sample('bike-station-portrait.jpg'), sample('workshop-notes-square.webp'), fake] });
    await win.click('.dropzone');
    await win.locator('[data-testid=gallery-item]').nth(2).waitFor();
    assert.equal(await win.locator('[data-testid=gallery-item]').count(), 3);
    await win.getByText(/not-really-an-image\.png: not a PNG, JPEG or WebP image/).waitFor();
    await win.screenshot({ path: join(shots, '03-images.png') });
  });

  await step('build a template deck and edit, add and reorder slides', async () => {
    await win.click('[data-testid=step-brief]');
    await win.fill('[data-testid=topic]', 'Desktop test deck (synthetic)');
    await win.fill('[data-testid=brief]', 'Stations near ferry stops\nOpen question: winter use\nStart with one district');
    await win.fill('[data-testid=slide-count]', '5');
    await win.click('[data-testid=generate-template]');
    await win.locator('[data-testid=slide-thumb]').nth(4).waitFor();
    await win.locator('[data-testid=slide-thumb] .thumb-select').nth(1).click();
    await win.fill('[data-testid=field-title]', 'Edited in the desktop app');
    await win.fill('[data-testid=field-notes]', 'Desktop speaker notes.');
    await win.click('[data-testid=add-slide]');
    await win.getByRole('menuitem', { name: 'Key takeaway' }).click();
    await win.fill('[data-testid=field-title]', 'Added in the desktop app');
    await win.getByRole('button', { name: 'Move slide 2 down' }).click({ force: true });
    const labels = await win.locator('[data-testid=slide-thumb] .thumb-select').evaluateAll((els) => els.map((e) => e.getAttribute('aria-label')));
    assert.equal(labels.length, 6);
    assert.match(labels[2], /Edited in the desktop app/);
    // Layout holds at the window size the OS gave us (CI runners often have small screens, which leaves the
    // window at its 1100x700 minimum): no sideways overflow, and the title field stays usable.
    const layout = await win.evaluate(() => {
      const box = (sel) => document.querySelector(sel);
      return {
        width: window.innerWidth,
        topbar: box('.topbar').scrollWidth - box('.topbar').clientWidth,
        slideList: box('.slide-list').scrollWidth - box('.slide-list').clientWidth,
        title: box('[data-testid=project-title]').getBoundingClientRect().width,
      };
    });
    console.log(`    layout at ${layout.width}px: ${JSON.stringify(layout)}`);
    assert.equal(layout.topbar, 0, 'top bar overflows sideways');
    assert.equal(layout.slideList, 0, 'slide list overflows sideways');
    assert.ok(layout.title >= 120, `title field too narrow (${layout.title}px)`);
    await win.screenshot({ path: join(shots, '04-editor.png') });
  });

  await step('save project through the native save dialog; Save again writes without asking', async () => {
    await answerDialogs(app, { save: projectPath });
    await win.click('[data-testid=save-project]');
    await win.getByText(/Saved saved-project\.pstudio/).first().waitFor();
    const zip = await JSZip.loadAsync(readFileSync(projectPath));
    assert.ok(zip.file('project.json'));
    const before = (await dialogCalls(app)).save;
    await win.fill('[data-testid=project-title]', 'Desktop test deck, saved twice');
    await win.click('[data-testid=save-project]');
    await win.waitForTimeout(500);
    assert.equal((await dialogCalls(app)).save, before, 'second Save must not show the dialog');
    const again = JSON.parse(await (await JSZip.loadAsync(readFileSync(projectPath))).file('project.json').async('string'));
    assert.equal(again.title, 'Desktop test deck, saved twice');
  });

  await step('new project, then reopen the saved project through the native open dialog', async () => {
    win.once('dialog', (d) => d.accept());
    await win.click('text=New');
    await win.waitForTimeout(300);
    assert.equal(await win.locator('[data-testid=gallery-item]').count(), 0);
    await answerDialogs(app, { open: [projectPath] });
    await win.click('[data-testid=open-project]');
    await win.locator('[data-testid=slide-thumb]').nth(5).waitFor();
    assert.equal(await win.inputValue('[data-testid=project-title]'), 'Desktop test deck, saved twice');
    await win.locator('[data-testid=slide-thumb] .thumb-select').nth(2).click();
    assert.equal(await win.inputValue('[data-testid=field-title]'), 'Edited in the desktop app');
    assert.equal(await win.inputValue('[data-testid=field-notes]'), 'Desktop speaker notes.');
  });

  await step('export an editable .pptx through the native save dialog', async () => {
    await answerDialogs(app, { save: pptxPath });
    await win.click('[data-testid=export]');
    await win.click('[data-testid=export-pptx]');
    await win.getByText(/PowerPoint exported: exported\.pptx/).waitFor();
    const report = execFileSync('python3', [join(root, 'scripts', 'inspect-pptx.py'), pptxPath], { encoding: 'utf8' });
    writeFileSync(join(out, 'exported.pptx.txt'), report);
    assert.match(report, /slides: 6/);
    assert.match(report, /Edited in the desktop app/);
    assert.match(report, /notes: 'Desktop speaker notes\.'/);
    assert.match(report, /image .*image\/png \(1000, 1000\)/, 'WebP exported as PNG');
    if (process.env.STUDIO_SKIP_LIBREOFFICE !== '1') {
      execFileSync('soffice', ['--headless', '--convert-to', 'pdf', '--outdir', out, pptxPath], { stdio: 'ignore', timeout: 120000 });
      assert.ok(existsSync(join(out, 'exported.pdf')), 'LibreOffice converted the export');
    }
  });

  await step('presentation mode opens and closes', async () => {
    await win.click('[data-testid=present]');
    await win.locator('.present').waitFor();
    // Presentation starts at the selected slide (slide 3 here).
    await win.getByText('3 / 6').waitFor();
    await win.keyboard.press('ArrowRight');
    await win.getByText('4 / 6').waitFor();
    await win.screenshot({ path: join(shots, '05-present.png') });
    await win.keyboard.press('Escape');
    await win.waitForTimeout(300);
    assert.equal(await win.locator('.present').count(), 0);
  });

  await step('in-app provider keys (MOCK providers): save, verify, never readable or written in plain text', async () => {
    await win.click('[data-testid=open-setup]');
    await win.fill('[data-testid=key-input-anthropic]', 'short');
    await win.click('[data-testid=key-save-anthropic]');
    await win.getByText(/does not look like an Anthropic API key/).waitFor();
    await win.fill('[data-testid=key-input-anthropic]', ANTHROPIC_KEY);
    await win.click('[data-testid=key-save-anthropic]');
    await win.fill('[data-testid=key-input-elevenlabs]', ELEVEN_KEY);
    await win.click('[data-testid=key-save-elevenlabs]');
    await win.locator('[data-testid=key-remove-elevenlabs]').waitFor();
    const dialog = win.getByRole('dialog', { name: 'Setup & providers' });
    await dialog.getByRole('button', { name: 'Verify connection' }).first().click();
    await dialog.getByText('Verified').first().waitFor();
    await win.click('[data-testid=verify-elevenlabs]');
    await dialog.getByText(/Credits used 1,234 \/ 100,000/).waitFor();
    await win.screenshot({ path: join(shots, '06-setup-keys.png') });
    const creds = await win.evaluate(() => window.studioDesktop.getCredentials());
    assert.equal(JSON.stringify(creds).includes(ANTHROPIC_KEY), false, 'renderer can read a key');
    assert.deepEqual([creds.anthropic.saved, creds.elevenlabs.saved], [true, true]);
    const settings = readFileSync(join(userData, 'settings.json'), 'utf8');
    assert.equal(settings.includes(ANTHROPIC_KEY) || settings.includes(ELEVEN_KEY), false, 'key written in plain text');
    keyStorage = creds.storage;
    console.log(`    key storage on this system: ${creds.storage}`);
    await win.keyboard.press('Escape');
    await win.click('[data-testid=step-brief]');
    assert.equal(await win.isDisabled('[data-testid=generate-ai]'), false, 'AI generation available after saving a key');
  });

  await step('startup-error page renders inside the app (CSP-hashed script runs)', async () => {
    const page = await app.evaluate(async ({ app, BrowserWindow }) => {
      const w = new BrowserWindow({ show: false, webPreferences: { sandbox: true, contextIsolation: true } });
      const file = `${app.getAppPath()}/desktop-dist/startup.html`;
      await w.loadFile(file, { query: { error: 'Simulated failure for the test', log: '/tmp/x.log' } });
      const text = await w.webContents.executeJavaScript('document.getElementById("error").textContent');
      w.destroy();
      return text;
    });
    assert.equal(page, 'Simulated failure for the test');
  });

  await step('second launch hands over to the running app (one backend only)', async () => {
    const second = spawn(executable, args, { env, stdio: 'ignore' });
    const code = await new Promise((resolve) => second.on('exit', resolve));
    assert.equal(code, 0);
    assert.equal(await win.title(), 'Presentation Studio');
    assert.equal(await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows().length), 1);
  });

  await step('quitting stops the backend and leaves no processes', async () => {
    assert.equal(await portOpen(backendPort), true);
    const pid = app.process().pid;
    await app.close();
    app = null;
    for (let i = 0; i < 50 && appProcesses().length; i++) await new Promise((r) => setTimeout(r, 100));
    assert.deepEqual(appProcesses(), [], 'app processes still running after quit');
    assert.equal(await portOpen(backendPort), false, 'backend port still open after quit');
    let alive = true;
    try {
      process.kill(pid, 0);
    } catch {
      alive = false;
    }
    assert.equal(alive, false);
    const log = readFileSync(join(userData, 'logs', 'main.log'), 'utf8');
    assert.match(log, /backend stopped/);
    assert.equal(log.includes(ANTHROPIC_KEY) || log.includes(ELEVEN_KEY), false, 'key in log');
  });

  await step('relaunch: keys persist encrypted with secure storage, and are gone after quit without it', async () => {
    app = await electron.launch({ executablePath: executable, args, env, timeout: 60000 });
    win = await app.firstWindow();
    await win.waitForSelector('.topbar', { timeout: 30000 });
    const creds = await win.evaluate(() => window.studioDesktop.getCredentials());
    const status = await win.evaluate(async () => (await fetch('/api/status')).json());
    const settings = JSON.parse(readFileSync(join(userData, 'settings.json'), 'utf8'));
    if (keyStorage === 'keychain') {
      assert.deepEqual([creds.anthropic.saved, creds.elevenlabs.saved], [true, true]);
      assert.equal(status.generation.configured, true);
      assert.ok(settings.secrets.anthropic && !settings.secrets.anthropic.includes(ANTHROPIC_KEY), 'encrypted secret stored');
      console.log('    keys survived the restart, stored encrypted');
    } else {
      assert.deepEqual([creds.anthropic.saved, creds.elevenlabs.saved], [false, false]);
      assert.equal(status.generation.configured, false);
      assert.deepEqual(settings.secrets, {});
      console.log('    no secure storage: keys were kept for the session only, as designed');
    }
    assert.equal(creds.anthropicModel, 'claude-opus-5-5');
    await app.close();
    app = null;
  });
} catch {
  failed = true;
  if (win) await win.screenshot({ path: join(shots, 'failure.png') }).catch(() => undefined);
} finally {
  if (app) await app.close().catch(() => undefined);
  await mocks.close();
  rmSync(userData, { recursive: true, force: true });
  const ok = results.filter((r) => r.ok).length;
  writeFileSync(join(out, 'results.json'), JSON.stringify({ executable, results }, null, 2));
  console.log(`\n${ok}/${results.length} desktop steps passed. Artifacts: ${out}`);
  process.exitCode = failed || ok !== results.length ? 1 : 0;
}
