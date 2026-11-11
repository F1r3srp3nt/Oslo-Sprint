/**
 * Platform layer. In the desktop app (Electron), file operations go through
 * native dialogs via the preload bridge; in a browser (web/dev mode) they use
 * file inputs and downloads. The rest of the UI calls these helpers only.
 */
import { downloadBytes } from './images';

export type MenuCommand = 'new' | 'open' | 'save' | 'saveAs' | 'importImages' | 'exportPptx' | 'present' | 'setup';

export interface CredentialStatus {
  storage: 'keychain' | 'session-only';
  storeName: string;
  anthropic: { saved: boolean };
  elevenlabs: { saved: boolean };
  anthropicModel: string;
  ttsModel: string;
  sttModel: string;
}

export interface CredentialUpdate {
  anthropicKey?: string | null;
  elevenlabsKey?: string | null;
  anthropicModel?: string;
  ttsModel?: string;
  sttModel?: string;
}

interface DesktopBridge {
  isDesktop: true;
  appInfo(): Promise<{ version: string; platform: string; packaged: boolean; secureStorage: boolean }>;
  getCredentials(): Promise<CredentialStatus>;
  setCredentials(update: CredentialUpdate): Promise<{ ok: true; status: CredentialStatus } | { ok: false; error: string }>;
  newProject(): Promise<void>;
  openProject(): Promise<{ canceled: true } | { canceled: false; name: string; bytes: Uint8Array } | { canceled: false; error: string }>;
  saveProject(bytes: Uint8Array, suggestedName: string, saveAs: boolean): Promise<{ canceled: true } | { canceled: false; name: string }>;
  saveExport(kind: 'pptx' | 'zip', bytes: Uint8Array, suggestedName: string): Promise<{ canceled: true } | { canceled: false; name: string }>;
  importImages(): Promise<{ files: { name: string; mime: string; bytes: Uint8Array }[]; rejected: { name: string; reason: string }[] }>;
  showLogs(): Promise<void>;
  onMenu(callback: (cmd: MenuCommand) => void): () => void;
}

export const desktop: DesktopBridge | undefined = (window as unknown as { studioDesktop?: DesktopBridge }).studioDesktop;
export const isDesktop = Boolean(desktop?.isDesktop);

/** Returns the saved file name, or null if the user cancelled. */
export async function saveProjectFile(bytes: Uint8Array, suggestedName: string, saveAs: boolean): Promise<string | null> {
  if (desktop) {
    const r = await desktop.saveProject(bytes, suggestedName, saveAs);
    return r.canceled ? null : r.name;
  }
  downloadBytes(bytes, suggestedName, 'application/zip');
  return suggestedName;
}

export async function saveExportFile(kind: 'pptx' | 'zip', bytes: Uint8Array, suggestedName: string): Promise<string | null> {
  if (desktop) {
    const r = await desktop.saveExport(kind, bytes, suggestedName);
    return r.canceled ? null : r.name;
  }
  const type = kind === 'pptx' ? 'application/vnd.openxmlformats-officedocument.presentationml.presentation' : 'application/zip';
  downloadBytes(bytes, suggestedName, type);
  return suggestedName;
}

/** Native image picker (desktop). Returns File objects so the normal import path validates them. */
export async function pickImagesNative(): Promise<{ files: File[]; rejected: string[] }> {
  if (!desktop) return { files: [], rejected: [] };
  const r = await desktop.importImages();
  return {
    files: r.files.map((f) => new File([f.bytes as Uint8Array<ArrayBuffer>], f.name, { type: f.mime })),
    rejected: r.rejected.map((x) => `${x.name}: ${x.reason}`),
  };
}
