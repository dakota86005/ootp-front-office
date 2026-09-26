import fs from 'node:fs';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { DATA_DIR } from '../server/config.js';
import { currentOrganization, viewingOrganization } from '../server/viewingOrganization.js';
import { IDS } from './fixture';

/**
 * The current club, served to the Mac app on `GET /api/settings` so no client re-implements the rule: the configured
 * organization, else the one the save's human manages (AGENTS.md). One resolver for every view (`viewingOrganization`).
 */
const settingsFile = path.join(DATA_DIR, 'settings.json');
let saved: string | null = null;

beforeEach(() => {
  saved = fs.existsSync(settingsFile) ? fs.readFileSync(settingsFile, 'utf8') : null;
});
afterEach(() => {
  if (saved === null) fs.rmSync(settingsFile, { force: true });
  else fs.writeFileSync(settingsFile, saved);
});

const configure = (defaultOrgId: number | null): void => {
  const current = fs.existsSync(settingsFile) ? JSON.parse(fs.readFileSync(settingsFile, 'utf8')) : {};
  fs.writeFileSync(settingsFile, JSON.stringify({ ...current, defaultOrgId }));
};

describe('the current organization', () => {
  it('is the human-managed club when none is configured', () => {
    configure(null);
    expect(currentOrganization()).toEqual({ id: IDS.mlbTeam, source: 'human' });
  });

  it('is the configured club when one is', () => {
    configure(IDS.otherMlbTeam);
    expect(currentOrganization()).toEqual({ id: IDS.otherMlbTeam, source: 'configured' });
  });

  it('keeps a configured club the league no longer has, as every view does, rather than switching clubs', () => {
    configure(9999);
    expect(currentOrganization()).toEqual({ id: 9999, source: 'configured' });
    expect(viewingOrganization(undefined)).toEqual({ id: 9999, source: 'configured' });
  });

  it('is never a requested club: nothing names one here', () => {
    configure(null);
    expect(currentOrganization()?.source).not.toBe('requested');
  });
});
