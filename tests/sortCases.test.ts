import fs from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';

/**
 * The unknown-last comparator's shared cases (D-056): `contract/fixtures/sort-cases.json`, run here against a
 * TypeScript reference and in PennantKit's Swift tests (`UnknownLastTests`) against the Mac app's comparator, so the
 * two clients order a served table the same way. A null key is unknown and sorts last in both directions.
 */
type Key = number | string | null;
type Direction = 'ascending' | 'descending';
interface SortCase {
  name: string;
  direction: Direction;
  rows: Array<[string, Key]>;
  expected: string[];
}

const file = path.join(process.cwd(), 'contract', 'fixtures', 'sort-cases.json');
const { cases } = JSON.parse(fs.readFileSync(file, 'utf8')) as { cases: SortCase[] };

/** Known keys: numbers by value, strings by UTF-16 code units (JavaScript's `<`), every number before every string. */
function less(a: number | string, b: number | string): boolean {
  if (typeof a === 'number' && typeof b === 'number') return a < b;
  if (typeof a === 'number') return true;
  if (typeof b === 'number') return false;
  return a < b;
}

/** Whether `a` sorts strictly before `b`: unknown never does, and is preceded by every known key. */
function precedes(a: Key, b: Key, direction: Direction): boolean {
  if (a === null) return false;
  if (b === null) return true;
  return direction === 'ascending' ? less(a, b) : less(b, a);
}

/** Stable: equal keys keep the served order. */
function sortIds(rows: Array<[string, Key]>, direction: Direction): string[] {
  return rows
    .map((row, index) => ({ row, index }))
    .sort((x, y) => (precedes(x.row[1], y.row[1], direction) ? -1 : precedes(y.row[1], x.row[1], direction) ? 1 : x.index - y.index))
    .map(({ row }) => row[0]);
}

describe('the unknown-last comparator (shared cases)', () => {
  it('has cases in both directions, with unknown keys in each', () => {
    expect(cases.some((c) => c.direction === 'ascending' && c.rows.some(([, key]) => key === null))).toBe(true);
    expect(cases.some((c) => c.direction === 'descending' && c.rows.some(([, key]) => key === null))).toBe(true);
  });

  it.each(cases.map((c) => [c.name, c] as const))('%s', (_name, c) => {
    expect(sortIds(c.rows, c.direction)).toEqual(c.expected);
  });
});
