import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';
import { HINT_MAX, basis, cell, claim, row, servedValue, unknownValue, type BasisInput } from '../server/presentation/claim.js';

/**
 * The presentation contract's authoring rules (BEHAVIOR_CASES.md "Pennant for Mac", `v2Contract.test.ts`; D-056, D-018):
 * a claim always carries its basis, "not known" is a list of sentences, a lean is stated or null, a help tag is at most
 * about 75 characters. The live payloads are held to the jargon list and their shapes in `contract.test.ts`.
 */

const source = { department: 'frontOffice' as const, specialist: 'Data status', asOf: null, gameDate: '2040-5-9' };
const plain: BasisInput = { because: [{ label: 'Runs', value: '612' }], source, unknown: [], wouldChange: [], lean: null, certainty: 'fact' };

describe('a claim always carries its basis', () => {
  it('cannot be built without a basis made by basis(), which the type system refuses', () => {
    // Compiled with the real compiler: a claim with no basis, or with a hand-written one, does not type-check
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pennant-claim-types-'));
    const file = path.join(dir, 'attempt.ts');
    const builder = path.join(process.cwd(), 'server', 'presentation', 'claim.js').replaceAll('\\', '/');
    fs.writeFileSync(
      file,
      [
        `import { claim } from '${builder}';`,
        `claim({ text: 'No basis', tone: 'neutral' });`,
        `claim({ text: 'Hand-written basis', tone: 'neutral', basis: { because: [], source: { department: 'farm', specialist: 'x', asOf: null, gameDate: null }, unknown: [], wouldChange: [], lean: null, certainty: 'fact' } });`,
        '',
      ].join('\n'),
    );
    try {
      const program = ts.createProgram([file], {
        target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext, moduleResolution: ts.ModuleResolutionKind.Bundler,
        strict: true, noEmit: true, skipLibCheck: true, types: ['node'],
      });
      const errors = ts.getPreEmitDiagnostics(program).filter((d) => d.file?.fileName === file);
      const lines = errors.map((d) => d.file!.getLineAndCharacterOfPosition(d.start!).line + 1);
      expect(lines, errors.map((d) => ts.flattenDiagnosticMessageText(d.messageText, ' ')).join('\n')).toEqual([2, 3]);
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it('asks for "not known", "would change if" and the lean every time, and refuses a lean left out', () => {
    expect(() => basis({ ...plain, lean: undefined as never })).toThrow(/lean must be stated/);
    expect(() => basis({ ...plain, unknown: undefined as never })).toThrow(/list of sentences/);
    expect(() => basis({ ...plain, wouldChange: undefined as never })).toThrow(/list of sentences/);
  });

  it('keeps "not known" a list of sentences: an empty list means nothing is missing, and no sentence is blank', () => {
    const built = basis({ ...plain, unknown: ['The transaction log could not be read.'] });
    expect(built.unknown).toEqual(['The transaction log could not be read.']);
    expect(basis(plain).unknown).toEqual([]);
    expect(() => basis({ ...plain, unknown: [''] })).toThrow(/empty/);
    expect(() => basis({ ...plain, unknown: ['Same.', 'Same.'] })).toThrow(/repeats/);
  });

  it('states a lean beside the neutral reading, or null; never an absent field', () => {
    const lean = basis({ ...plain, lean: { neutral: 'Worth about 2 wins to any club.', why: ['Your club pays for defense.'] } });
    expect(lean.lean).toEqual({ neutral: 'Worth about 2 wins to any club.', why: ['Your club pays for defense.'] });
    const none = claim({ text: 'Current', tone: 'good', basis: basis(plain) });
    expect(JSON.parse(JSON.stringify(none)).basis).toHaveProperty('lean', null);
  });

  it('serves an OOTP game date as the export wrote it, never re-typed as a calendar date', () => {
    const built = claim({ text: 'Current', tone: 'good', basis: basis(plain) });
    expect(built.basis.source.gameDate).toBe('2040-5-9');
  });
});

describe('the shown strings are checked as they are built', () => {
  it('holds a help tag to one line of at most about 75 characters', () => {
    expect(HINT_MAX).toBe(75);
    expect(() => claim({ text: 'A line', tone: 'neutral', basis: basis(plain), hint: 'x'.repeat(76) })).toThrow(/at most 75/);
    expect(claim({ text: 'A line', tone: 'neutral', basis: basis(plain), hint: 'x'.repeat(75) }).hint).toHaveLength(75);
  });

  it('refuses an empty line, a range that does not hold its value, and a place outside its "of N"', () => {
    expect(() => claim({ text: ' ', tone: 'neutral', basis: basis(plain) })).toThrow(/empty/);
    expect(() => servedValue(5, 'wins', '5 wins', { low: 6, high: 8 })).toThrow(/outside its range/);
    expect(() => claim({ text: 'Power', tone: 'neutral', basis: basis(plain), place: { rank: 31, of: 30, tiedWith: 0 } })).toThrow(/not inside/);
    expect(() => claim({ text: 'Power', tone: 'neutral', basis: basis(plain), place: { rank: 29, of: 30, tiedWith: 2 } })).toThrow(/does not fit/);
    expect(claim({ text: 'Power', tone: 'neutral', basis: basis(plain), place: { rank: 3, of: 30, tiedWith: 1 } }).place).toEqual({ rank: 3, of: 30, tiedWith: 1 });
  });

  it('serves an unknown value as null with its sentence, never a zero', () => {
    const value = unknownValue('dollars', 'Not in the export');
    expect(value).toEqual({ n: null, unit: 'dollars', display: 'Not in the export' });
    expect(() => servedValue(Number.NaN, 'wins', 'NaN')).toThrow(/not a number/);
  });

  it('builds a row with a cell and a sort key for every column, unknown sorting as null', () => {
    const built = row('r1', { name: cell('Club 1'), wins: cell('Not known', { tone: 'unknown' }) }, { name: 'Club 1', wins: null });
    expect(built).toEqual({ id: 'r1', cells: { name: { display: 'Club 1' }, wins: { display: 'Not known', tone: 'unknown' } }, sort: { name: 'Club 1', wins: null } });
    expect(() => row('r2', { name: cell('Club 2') }, { name: 'Club 2', wins: 3 } as never)).toThrow(/every column/);
    expect(() => row('r3', { wins: cell('3') }, { wins: Number.NaN })).toThrow(/sorts as null/);
  });
});
