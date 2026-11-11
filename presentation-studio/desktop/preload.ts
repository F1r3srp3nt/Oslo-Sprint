/**
 * The renderer's only bridge to the desktop shell. It exposes named functions
 * (never ipcRenderer itself), each mapped to one validated handler in ipc.ts.
 */
import { contextBridge, ipcRenderer } from 'electron';

type MenuCommand = 'new' | 'open' | 'save' | 'saveAs' | 'importImages' | 'exportPptx' | 'present' | 'setup';

const api = {
  isDesktop: true as const,
  appInfo: () => ipcRenderer.invoke('studio:app:info'),
  getCredentials: () => ipcRenderer.invoke('studio:credentials:get'),
  setCredentials: (update: unknown) => ipcRenderer.invoke('studio:credentials:set', update),
  newProject: () => ipcRenderer.invoke('studio:project:new'),
  openProject: () => ipcRenderer.invoke('studio:project:open'),
  saveProject: (bytes: Uint8Array, suggestedName: string, saveAs: boolean) => ipcRenderer.invoke('studio:project:save', { bytes, suggestedName, saveAs }),
  saveExport: (kind: 'pptx' | 'zip', bytes: Uint8Array, suggestedName: string) => ipcRenderer.invoke('studio:export:save', { kind, bytes, suggestedName }),
  importImages: () => ipcRenderer.invoke('studio:images:import'),
  showLogs: () => ipcRenderer.invoke('studio:app:show-logs'),
  retryStartup: () => ipcRenderer.invoke('studio:startup:retry'),
  quit: () => ipcRenderer.invoke('studio:app:quit'),
  onMenu: (callback: (cmd: MenuCommand) => void) => {
    const listener = (_e: unknown, cmd: MenuCommand) => callback(cmd);
    ipcRenderer.on('studio:menu', listener);
    return () => {
      ipcRenderer.removeListener('studio:menu', listener);
    };
  },
};

contextBridge.exposeInMainWorld('studioDesktop', api);
