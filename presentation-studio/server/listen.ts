/**
 * Starts the API on the loopback interface. Port 0 lets the OS pick a free
 * port, so the desktop app never conflicts with another program (or another
 * copy of itself). close() also destroys open keep-alive sockets so shutdown
 * is immediate.
 */
import type { Server } from 'node:http';
import type { Socket } from 'node:net';
import type { RequestListener } from 'node:http';
import { createServer } from 'node:http';

export interface RunningServer {
  port: number;
  url: string;
  close(): Promise<void>;
}

export function listenLoopback(handler: RequestListener, port = 0, host = '127.0.0.1'): Promise<RunningServer> {
  return new Promise((resolve, reject) => {
    const server: Server = createServer(handler);
    const sockets = new Set<Socket>();
    server.on('connection', (s) => {
      sockets.add(s);
      s.on('close', () => sockets.delete(s));
    });
    server.once('error', reject);
    server.listen(port, host, () => {
      const addr = server.address();
      if (!addr || typeof addr === 'string') return reject(new Error('Server has no TCP address.'));
      resolve({
        port: addr.port,
        url: `http://${host}:${addr.port}`,
        close: () =>
          new Promise<void>((done) => {
            for (const s of sockets) s.destroy();
            server.close(() => done());
          }),
      });
    });
  });
}
