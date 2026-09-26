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
