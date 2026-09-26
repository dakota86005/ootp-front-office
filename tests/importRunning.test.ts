import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
import express from 'express';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import type { AddressInfo } from 'node:net';
import { api, importState, IMPORT_RUNNING } from '../server/api.js';
import { loadConfig, saveConfig } from '../server/config.js';

/**
 * One import at a time. Choosing a save (`POST /api/config`) or asking for an import (`POST /api/import`) while one is
 * running is refused with a 409 and a plain sentence; it never starts a second import writing the same database, and
 * never changes the chosen save underneath the running one.
 */
describe('while an import is running', () => {
  let base = '';
  let close = (): void => {};
  let exportDir = '';
  const before = loadConfig();

  beforeAll(async () => {
    exportDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pennant-import-running-'));
    fs.writeFileSync(path.join(exportDir, 'zz_running.csv'), 'id\n1\n');
    const app = express();
    app.use(express.json());
    app.use('/api', api);
    const server = app.listen(0, '127.0.0.1');
    await new Promise((resolve) => server.once('listening', resolve));
    base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
    close = () => {
      server.closeAllConnections();
      server.close();
    };
  });

  afterEach(() => {
    importState.importing = false;
    saveConfig(before);
  });

  afterAll(() => {
    close();
    fs.rmSync(exportDir, { recursive: true, force: true });
  });

  const post = (route: string, body?: unknown) =>
    fetch(`${base}/api/${route}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });

  it('choosing a save is refused, and the running import and the chosen save are left alone', async () => {
    saveConfig({ csvDir: exportDir, saveName: 'Running' });
    importState.importing = true;
    const res = await post('config', { csvDir: path.join(exportDir, 'other'), saveName: 'Other' });
    expect(res.status).toBe(409);
    expect(await res.json()).toEqual({ error: IMPORT_RUNNING });
    expect(importState.importing).toBe(true);
    await new Promise((resolve) => setImmediate(resolve));
    expect(importState.importing).toBe(true);
    expect(loadConfig().saveName).toBe('Running');
  });

  it('asking for another import is refused', async () => {
    saveConfig({ csvDir: exportDir, saveName: 'Running' });
    importState.importing = true;
    const res = await post('import');
    expect(res.status).toBe(409);
    expect(await res.json()).toEqual({ error: IMPORT_RUNNING });
  });

  it('says so in plain words', () => {
    expect(IMPORT_RUNNING).not.toMatch(/409|importState|csv/i);
  });
});
