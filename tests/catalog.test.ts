import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { db } from '../server/db.js';
import { loadConfig, saveConfig } from '../server/config.js';
import { majorLeagueClubs } from '../server/org.js';
import { buildCatalog, servedDepartments, servedGlossary, servedStats } from '../server/presentation/catalog.js';
import { REACT_ONLY_TERMS } from '../server/presentation/glossary.js';
import { clubPalette, derivePalette, toHex } from '../server/presentation/palette.js';
import { define } from '../src/glossary';
import { BATTING_STATS, CONTACT_STATS, FIELDING_STATS, PITCHING_STATS } from '../src/stats';
import { derivePalette as reactPalette } from '../src/theme';
import { IDS } from './fixture';

/**
 * `GET /api/v2/catalog` (SWIFTUI_REBUILD.md section 4.2): the glossary and stat catalog both clients read, each club's
 * palette as the Mac app is served it, and the departments with their heads from the save's staff. Built on the fixture
 * league, whose front office has a general manager and an assistant (tests/fixture.ts).
 */

describe('the glossary and the stat catalog are one copy for both clients', () => {
  it('serves every term the React app defines, with the same words, but the React-only ones', () => {
    const served = servedGlossary();
    expect(served.length).toBeGreaterThan(60);
    for (const entry of served) expect(define(entry.display), entry.display).toBe(entry.text);
    for (const term of REACT_ONLY_TERMS) {
      expect(define(term), `${term} is still the React app's`).toBeDefined();
      expect(served.map((e) => e.display)).not.toContain(term);
    }
  });

  it('serves every stat the React app offers, with its label, words, format and direction', () => {
    const served = servedStats();
    const react = [
      ...BATTING_STATS.map((d) => ({ d, group: 'batting' })), ...PITCHING_STATS.map((d) => ({ d, group: 'pitching' })),
      ...FIELDING_STATS.map((d) => ({ d, group: 'fielding' })), ...CONTACT_STATS.map((d) => ({ d, group: 'contact' })),
    ];
    expect(served).toHaveLength(react.length);
    for (const { d, group } of react) {
      expect(served).toContainEqual({ key: d.key, group, display: d.label, text: d.desc, format: d.format, section: d.section, lowerIsBetter: d.lowerIsBetter === true });
    }
  });
});

describe('each club\'s palette, as the Mac app is served it', () => {
  it('is the React app\'s palette, as hex tokens in both modes', () => {
    expect(reactPalette).toBe(derivePalette);
    const colors = { bg: '#0c2340', fg: '#ffffff', secondary: '#bd3039', cap: '#0c2340' };
    for (const mode of ['light', 'dark'] as const) {
      const css = derivePalette(colors, mode);
      const served = clubPalette(colors, mode);
      expect(served.accent).toBe(toHex(css['--accent']));
      expect(served.team).toBe(toHex(css['--team']));
      for (const [token, value] of Object.entries(served)) expect(value, token).toMatch(/^#[0-9a-f]{6}$/);
    }
  });

  it('writes an hsl() colour as the hex it is', () => {
    expect(toHex('hsl(0, 100%, 50%)')).toBe('#ff0000');
    expect(toHex('hsl(120, 100%, 25%)')).toBe('#008000');
    expect(toHex('#ABCDEF')).toBe('#abcdef');
    expect(() => toHex('red')).toThrow();
  });

  it('gives a club with no colours in the export the default palette, never a guess of its own', () => {
    expect(clubPalette({ bg: null, fg: null, secondary: null, cap: null }, 'dark')).toEqual(clubPalette(null, 'dark'));
  });
});

describe('the departments and their heads, from the save\'s staff', () => {
  it('lists the nine departments in the sidebar\'s order, with the Mac app\'s ids', () => {
    expect(servedDepartments(IDS.mlbTeam).map((d) => d.id)).toEqual([
      'frontOffice', 'majorLeague', 'farm', 'scouting', 'trades', 'finance', 'medical', 'league', 'philosophy',
    ]);
  });

  it('names the person in a seat the save fills, with the seat in words', () => {
    const departments = servedDepartments(IDS.mlbTeam);
    const front = departments.find((d) => d.id === 'frontOffice')!;
    expect(front.head).toEqual({ name: 'Web Ivey', role: 'general manager', coachId: 901 });
    expect(front.preparedBy.display).toBe('Prepared by Web Ivey, general manager');
    expect(departments.find((d) => d.id === 'trades')!.head).toMatchObject({ name: 'Del Faraday', role: 'assistant general manager' });
  });

  it('says a seat the save leaves empty is empty, and never makes up a name', () => {
    const medical = servedDepartments(IDS.mlbTeam).find((d) => d.id === 'medical')!;
    expect(medical.head).toBeNull();
    expect(medical.preparedBy).toMatchObject({ display: 'Prepared by the medical staff', tone: 'unknown' });
    expect(medical.preparedBy.hint).toMatch(/names no head trainer/);
    // With no club known at all, nobody is named anywhere
    expect(servedDepartments(null).every((d) => d.head === null)).toBe(true);
  });
});

describe('each club\'s record and logo', () => {
  const previous = loadConfig();
  let saveRoot = '';
  afterEach(() => {
    saveConfig(previous);
    if (saveRoot) fs.rmSync(saveRoot, { recursive: true, force: true });
    saveRoot = '';
  });

  it('writes the record as the export has it, and says so when the export has none', () => {
    const catalog = buildCatalog(majorLeagueClubs(), IDS.mlbTeam);
    const ours = catalog.clubs.find((c) => c.teamId === IDS.mlbTeam)!;
    const row = db.prepare('SELECT w, l FROM team_record WHERE team_id = ?').get(IDS.mlbTeam) as { w: number; l: number } | undefined;
    if (row) expect(ours.record.display).toBe(`${row.w}–${row.l}`);
    db.exec('ALTER TABLE team_record RENAME TO zz_team_record');
    try {
      const without = buildCatalog(majorLeagueClubs(), IDS.mlbTeam).clubs.find((c) => c.teamId === IDS.mlbTeam)!;
      expect(without.record).toMatchObject({ display: 'No record in the export yet', tone: 'unknown' });
    } finally {
      db.exec('ALTER TABLE zz_team_record RENAME TO team_record');
    }
  });

  it('points at the logo only when the save holds one', () => {
    expect(buildCatalog(majorLeagueClubs(), IDS.mlbTeam).clubs.every((c) => c.logo === null)).toBe(true);
    saveRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'pennant-logo-'));
    const csv = path.join(saveRoot, 'Test.lg', 'import_export', 'csv');
    const logos = path.join(saveRoot, 'Test.lg', 'news', 'html', 'images', 'team_logos');
    fs.mkdirSync(csv, { recursive: true });
    fs.mkdirSync(logos, { recursive: true });
    fs.writeFileSync(path.join(logos, 'club.png'), 'png');
    saveConfig({ ...previous, csvDir: csv, saveName: 'Test' });
    // The fixture's export has no logo column; an export without it has no logos to point at
    expect(buildCatalog(majorLeagueClubs(), IDS.mlbTeam).clubs.every((c) => c.logo === null)).toBe(true);
    db.exec('ALTER TABLE teams ADD COLUMN logo_file_name TEXT');
    db.prepare('UPDATE teams SET logo_file_name = ? WHERE team_id = ?').run('club.png', IDS.mlbTeam);
    try {
      const clubs = buildCatalog(majorLeagueClubs(), IDS.mlbTeam).clubs;
      expect(clubs.find((c) => c.teamId === IDS.mlbTeam)!.logo).toMatch(new RegExp(`^/api/logo/${IDS.mlbTeam}\\?v=[a-z0-9]+$`));
      expect(clubs.filter((c) => c.teamId !== IDS.mlbTeam).every((c) => c.logo === null)).toBe(true);
    } finally {
      db.exec('ALTER TABLE teams DROP COLUMN logo_file_name');
    }
  });
});
