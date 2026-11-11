/**
 * The only operations the sandboxed renderer can ask the main process for.
 * Each handler checks that the request comes from the app's own top-level page,
 * validates its input, and never lets the renderer choose a file-system path:
 * paths always come from a native dialog the user answered.
 */
import { app, BrowserWindow, dialog, ipcMain, shell, type IpcMainInvokeEvent } from 'electron';
import { readFile, rename, stat, writeFile } from 'node:fs/promises';
import { basename, extname, join } from 'node:path';
import { z } from 'zod';
import type { SettingsStore } from './settings';

export type MenuCommand = 'new' | 'open' | 'save' | 'saveAs' | 'importImages' | 'exportPptx' | 'present' | 'setup';

interface IpcDeps {
  isAppUrl(url: string): boolean;
  getSettings(): SettingsStore;
  onSettingsChanged(): void;
  retryStartup(win: BrowserWindow): Promise<void>;
  log(msg: string): void;
}

const MB = 1024 * 1024;
const LIMITS = { project: 1024 * MB, image: 25 * MB, export: 2048 * MB, images: 50 };

const EXPORT_KINDS = {
  pptx: { label: 'PowerPoint presentation', ext: 'pptx' },
  zip: { label: 'PowerPoint + narration (ZIP)', ext: 'zip' },
} as const;

const Bytes = z.instanceof(Uint8Array);
const FileName = z.string().max(200);
const SaveProjectSchema = z.object({ bytes: Bytes, suggestedName: FileName, saveAs: z.boolean() }).strict();
const ExportSchema = z.object({ kind: z.enum(['pptx', 'zip']), bytes: Bytes, suggestedName: FileName }).strict();

/** Most recently opened/saved project file per window, so "Save" can write without asking again. */
const projectPaths = new Map<number, string>();

function safeName(name: string, ext: string): string {
  const base = basename(name).replace(/[\\/:*?"<>|\x00-\x1f]/g, '-').replace(/^\.+/, '').trim().slice(0, 120) || 'Presentation';
  return base.toLowerCase().endsWith(`.${ext}`) ? base : `${base}.${ext}`;
}

function withExt(path: string, ext: string): string {
  return extname(path).toLowerCase() === `.${ext}` ? path : `${path}.${ext}`;
}

async function writeAtomic(path: string, bytes: Uint8Array) {
  const tmp = `${path}.saving-${process.pid}`;
  await writeFile(tmp, bytes);
  await rename(tmp, path);
}

export function sniffImage(bytes: Uint8Array): 'image/png' | 'image/jpeg' | 'image/webp' | null {
  const b = bytes;
  if (b.length > 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return 'image/png';
  if (b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'image/jpeg';
  if (b.length > 12 && String.fromCharCode(...b.subarray(0, 4)) === 'RIFF' && String.fromCharCode(...b.subarray(8, 12)) === 'WEBP') return 'image/webp';
  return null;
}

export function registerIpc(deps: IpcDeps) {
  /** Registers a handler that only answers the app's own top-level page. */
  const handle = <T>(channel: string, fn: (event: IpcMainInvokeEvent, win: BrowserWindow, arg: unknown) => Promise<T> | T) => {
    ipcMain.handle(channel, async (event, arg) => {
      const frame = event.senderFrame;
      const win = BrowserWindow.fromWebContents(event.sender);
      if (!frame || frame !== event.sender.mainFrame || !deps.isAppUrl(frame.url) || !win) {
        deps.log(`ipc ${channel}: rejected sender`);
        throw new Error('Not allowed.');
      }
      return fn(event, win, arg);
    });
  };

  handle('studio:app:info', () => ({
    version: app.getVersion(),
    platform: process.platform,
    packaged: app.isPackaged,
    secureStorage: deps.getSettings().secure,
  }));

  handle('studio:credentials:get', () => deps.getSettings().status());

  handle('studio:credentials:set', (_e, _w, arg) => {
    try {
      const status = deps.getSettings().update(arg);
      deps.onSettingsChanged();
      deps.log('settings updated'); // never log values
      return { ok: true as const, status };
    } catch (err) {
      const message = err instanceof z.ZodError ? err.issues.map((i) => i.message).join(' ') : err instanceof Error ? err.message : 'Could not save settings.';
      return { ok: false as const, error: message };
    }
  });

  handle('studio:project:new', (_e, win) => {
    projectPaths.delete(win.webContents.id);
  });

  handle('studio:project:open', async (_e, win) => {
    const r = await dialog.showOpenDialog(win, {
      title: 'Open Presentation Studio project',
      properties: ['openFile'],
      filters: [{ name: 'Presentation Studio project', extensions: ['pstudio'] }],
    });
    if (r.canceled || !r.filePaths[0]) return { canceled: true as const };
    const path = r.filePaths[0];
    const info = await stat(path);
    if (info.size > LIMITS.project) return { canceled: false as const, error: 'This file is larger than 1 GB and cannot be opened.' };
    const bytes = new Uint8Array(await readFile(path));
    projectPaths.set(win.webContents.id, path);
    return { canceled: false as const, name: basename(path), bytes };
  });

  handle('studio:project:save', async (_e, win, arg) => {
    const { bytes, suggestedName, saveAs } = SaveProjectSchema.parse(arg);
    if (bytes.byteLength > LIMITS.project) throw new Error('Project is larger than 1 GB.');
    let path = saveAs ? undefined : projectPaths.get(win.webContents.id);
    if (!path) {
      const r = await dialog.showSaveDialog(win, {
        title: 'Save project',
        defaultPath: join(app.getPath('documents'), safeName(suggestedName, 'pstudio')),
        filters: [{ name: 'Presentation Studio project', extensions: ['pstudio'] }],
        properties: ['createDirectory', 'showOverwriteConfirmation'],
      });
      if (r.canceled || !r.filePath) return { canceled: true as const };
      path = withExt(r.filePath, 'pstudio');
    }
    await writeAtomic(path, bytes);
    projectPaths.set(win.webContents.id, path);
    return { canceled: false as const, name: basename(path) };
  });

  handle('studio:export:save', async (_e, win, arg) => {
    const { kind, bytes, suggestedName } = ExportSchema.parse(arg);
    if (bytes.byteLength > LIMITS.export) throw new Error('Export is larger than 2 GB.');
    const k = EXPORT_KINDS[kind];
    const r = await dialog.showSaveDialog(win, {
      title: kind === 'pptx' ? 'Export PowerPoint' : 'Export PowerPoint and narration',
      defaultPath: join(app.getPath('documents'), safeName(suggestedName, k.ext)),
      filters: [{ name: k.label, extensions: [k.ext] }],
      properties: ['createDirectory', 'showOverwriteConfirmation'],
    });
    if (r.canceled || !r.filePath) return { canceled: true as const };
    const path = withExt(r.filePath, k.ext);
    await writeAtomic(path, bytes);
    return { canceled: false as const, name: basename(path) };
  });

  handle('studio:images:import', async (_e, win) => {
    const r = await dialog.showOpenDialog(win, {
      title: 'Import images',
      properties: ['openFile', 'multiSelections'],
      filters: [{ name: 'Images (PNG, JPEG, WebP)', extensions: ['png', 'jpg', 'jpeg', 'webp'] }],
    });
    if (r.canceled) return { files: [], rejected: [] };
    const files: { name: string; mime: string; bytes: Uint8Array }[] = [];
    const rejected: { name: string; reason: string }[] = [];
    for (const path of r.filePaths.slice(0, LIMITS.images)) {
      const name = basename(path);
      const info = await stat(path);
      if (info.size > LIMITS.image) {
        rejected.push({ name, reason: 'larger than 25 MB' });
        continue;
      }
      const bytes = new Uint8Array(await readFile(path));
      const mime = sniffImage(bytes);
      if (!mime) rejected.push({ name, reason: 'not a PNG, JPEG or WebP image' });
      else files.push({ name, mime, bytes });
    }
    if (r.filePaths.length > LIMITS.images) rejected.push({ name: `${r.filePaths.length - LIMITS.images} more`, reason: `only ${LIMITS.images} images per import` });
    return { files, rejected };
  });

  handle('studio:app:show-logs', () => {
    shell.showItemInFolder(join(app.getPath('userData'), 'logs', 'main.log'));
  });

  handle('studio:startup:retry', (_e, win) => deps.retryStartup(win));
  handle('studio:app:quit', () => app.quit());
}
