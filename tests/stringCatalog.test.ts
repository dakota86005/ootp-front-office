import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import { describe, expect, it } from 'vitest';
import { BANNED_JARGON, BANNED_VERDICTS, bannedIn } from './bannedJargon';

/**
 * The Mac app's String Catalogs hold only structural labels (menu, tab, column and section names, D-055, D-056), and
 * they read in the GM's plain words: every key and every translation passes the same banned-jargon and verdict lists
 * as the server's `/v2` text (`tests/bannedJargon.ts`).
 */
const catalogs = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', 'macos'], { encoding: 'utf8' })
  .split('\n')
  .filter((file) => file.endsWith('.xcstrings'));

interface Catalog {
  sourceLanguage: string;
  strings: Record<string, { localizations?: Record<string, { stringUnit?: { value?: string } }> }>;
}

/** Every key and every localized value in a catalog. */
function catalogStrings(file: string): string[] {
  const catalog = JSON.parse(fs.readFileSync(file, 'utf8')) as Catalog;
  return Object.entries(catalog.strings).flatMap(([key, entry]) => [
    key,
    ...Object.values(entry.localizations ?? {}).flatMap((l) => (l.stringUnit?.value ? [l.stringUnit.value] : [])),
  ]);
}

describe('the Mac app\'s String Catalogs', () => {
  it('finds the app\'s catalog', () => {
    expect(catalogs).toContain('macos/Pennant/Localizable.xcstrings');
  });

  it.each(catalogs)('%s: no banned jargon or verdict word', (file) => {
    const offending = catalogStrings(file)
      .map((text) => ({ text, patterns: bannedIn(text, [BANNED_JARGON, BANNED_VERDICTS]).map(String) }))
      .filter(({ patterns }) => patterns.length > 0);
    expect(offending).toEqual([]);
  });
});

/**
 * The structural labels the Swift sources write, the way SwiftUI looks them up: a string literal given to `Text`,
 * `Button`, `Label`, `Section` and the other labelled views, a `title:`, a `LocalizedStringResource`, either side of a
 * ternary, or a `case` returning a label. `Text(verbatim:)` (served text) is not one; SF Symbol names are skipped.
 */
function structuralLiterals(source: string): string[] {
  const code = source.replace(/\/\/[^\n]*/g, '');
  const lit = '"((?:[^"\\\\\\n]|\\\\.)*)"';
  const patterns = [
    new RegExp(`\\b(?:Text|Button|Label|Section|LabeledContent|Tab|CommandMenu|Window|Picker|TextField|Toggle|ContentUnavailableView|confirmationDialog|item|row)\\(\\s*${lit}`, 'g'),
    new RegExp(`\\btitle: ${lit}`, 'g'),
    new RegExp(`LocalizedStringResource = ${lit}`, 'g'),
    new RegExp(`\\? ${lit} : ${lit}`, 'g'),
    new RegExp(`\\bcase [^\\n"]*: ${lit}`, 'g'),
  ];
  const symbol = /^[a-z0-9]+(\.[a-z0-9]+)+$/;
  const found = new Set<string>();
  for (const pattern of patterns) {
    for (const match of code.matchAll(pattern)) {
      for (const text of match.slice(1)) if (text && !symbol.test(text)) found.add(text);
    }
  }
  return [...found];
}

describe('the Mac app\'s structural labels', () => {
  const sources = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', 'macos'], { encoding: 'utf8' })
    .split('\n')
    .filter((file) => file.endsWith('.swift') && (file.startsWith('macos/Pennant/') || /^macos\/Packages\/[^/]+\/Sources\//.test(file)));
  const keys = new Set(Object.keys((JSON.parse(fs.readFileSync('macos/Pennant/Localizable.xcstrings', 'utf8')) as Catalog).strings));

  it('finds labels to check, so the check cannot pass vacuously', () => {
    expect(sources.flatMap((file) => structuralLiterals(fs.readFileSync(file, 'utf8'))).length).toBeGreaterThan(50);
  });

  // The packages' views look their labels up in the app's bundle, so every label lives in the app's one catalog
  it.each(sources)('%s: every label is in the app\'s String Catalog', (file) => {
    const missing = structuralLiterals(fs.readFileSync(file, 'utf8')).filter((text) => !keys.has(text));
    expect(missing).toEqual([]);
  });
});
