/**
 * The one way to author a `Claim`, a `Row` or a `Cell` (D-056, SWIFTUI_REBUILD.md section 4.1).
 *
 * - `claim()` takes only a basis made by `basis()` (a branded type), so a claim without a basis cannot be written: an
 *   object literal typed as `Claim` still compiles, which is why every author goes through here and
 *   `tests/presentationBoundary.test.ts` holds that nothing under `server/presentation/` builds one any other way.
 * - `basis()` asks for "not known", "would change if" and the lean every time, with no default: an author says `[]`
 *   (nothing is missing) or `null` (no lean) on purpose, and an absent field is never read as either (D-018).
 * - Every sentence is checked as it is built: none empty, a help tag at most `HINT_MAX` characters, a range that holds
 *   its value, a place inside its "of N". A breach throws: it is an authoring defect, never something to show.
 *
 * Presentation authors words about what the specialists decided; it decides nothing (D-001). Nothing here reads the
 * database.
 */
import type {
  Basis, BasisLine, BasisSource, Cell, Certainty, Claim, Lean, Place, Row, ServedValue, Target, Tone, Unit,
} from '../contract/presentation.js';

declare const builtBasis: unique symbol;

/** A basis made by `basis()`: the only kind `claim()` takes. The brand exists only in the type; the JSON is a `Basis`. */
export type BuiltBasis = Basis & { readonly [builtBasis]: true };

/** The HIG's help tag: one line, at most about 75 characters (SWIFTUI_REBUILD.md section 3.3). */
export const HINT_MAX = 75;

export interface BasisInput {
  because: readonly BasisLine[];
  source: BasisSource;
  /** What is not known, as sentences; `[]` only when nothing is missing. Required, so it is never left out by accident. */
  unknown: readonly string[];
  /** What would change the reading, as sentences; `[]` when nothing named would. */
  wouldChange: readonly string[];
  /** The philosophy's lean beside the neutral reading, or `null` for none. */
  lean: Lean | null;
  certainty: Certainty;
  stamp?: string;
}

export interface ClaimInput {
  text: string;
  tone: Tone;
  basis: BuiltBasis;
  hint?: string;
  value?: ServedValue;
  place?: Place;
  links?: readonly Target[];
}

class AuthoringError extends Error {
  constructor(message: string) {
    super(`Presentation authoring defect: ${message}`);
    this.name = 'AuthoringError';
  }
}

function sentence(text: string, what: string): string {
  if (typeof text !== 'string' || text.trim() === '') throw new AuthoringError(`${what} is empty`);
  if (text !== text.trim()) throw new AuthoringError(`${what} has spaces around it: "${text}"`);
  return text;
}

function sentences(list: readonly string[], what: string): string[] {
  if (!Array.isArray(list)) throw new AuthoringError(`${what} must be a list of sentences`);
  const out = list.map((s, i) => sentence(s, `${what}[${i}]`));
  if (new Set(out).size !== out.length) throw new AuthoringError(`${what} repeats a sentence`);
  return out;
}

/** A hint, checked against the help tag's length. */
function hintOf(hint: string | undefined, what: string): string | undefined {
  if (hint === undefined) return undefined;
  sentence(hint, what);
  if (hint.length > HINT_MAX) throw new AuthoringError(`${what} is ${hint.length} characters; a help tag is at most ${HINT_MAX}: "${hint}"`);
  return hint;
}

/** A basis: why a claim says what it says, who answered, what is not known and how it is called. */
export function basis(input: BasisInput): BuiltBasis {
  const because = input.because.map((line, i) => ({
    label: sentence(line.label, `because[${i}].label`),
    value: sentence(line.value, `because[${i}].value`),
  }));
  const source: BasisSource = {
    department: input.source.department,
    specialist: sentence(input.source.specialist, 'source.specialist'),
    asOf: input.source.asOf,
    gameDate: input.source.gameDate,
  };
  if (input.source.sample !== undefined) source.sample = sentence(input.source.sample, 'source.sample');
  let lean: Lean | null = null;
  if (input.lean !== null) {
    if (input.lean === undefined) throw new AuthoringError('lean must be stated: a lean, or null for none');
    lean = { neutral: sentence(input.lean.neutral, 'lean.neutral'), why: sentences(input.lean.why, 'lean.why') };
  }
  const out: Basis = {
    because,
    source,
    unknown: sentences(input.unknown, 'unknown'),
    wouldChange: sentences(input.wouldChange, 'wouldChange'),
    lean,
    certainty: input.certainty,
  };
  if (input.stamp !== undefined) out.stamp = sentence(input.stamp, 'stamp');
  return out as BuiltBasis;
}

function placeOf(place: Place | undefined): Place | undefined {
  if (!place) return undefined;
  const whole = (n: number) => Number.isInteger(n) && n >= 0;
  if (!whole(place.rank) || !whole(place.of) || !whole(place.tiedWith) || (place.overlap !== undefined && !whole(place.overlap))) {
    throw new AuthoringError(`a place is counted in whole clubs: ${JSON.stringify(place)}`);
  }
  if (place.of < 1 || place.rank < 1 || place.rank > place.of) throw new AuthoringError(`place ${place.rank} is not inside "of ${place.of}"`);
  if (place.rank + place.tiedWith > place.of) throw new AuthoringError(`place ${place.rank} tied with ${place.tiedWith} does not fit in ${place.of}`);
  return { ...place };
}

function valueOf(value: ServedValue | undefined): ServedValue | undefined {
  if (!value) return undefined;
  sentence(value.display, 'value.display');
  const { n, low, high } = value;
  if (n !== null && !Number.isFinite(n)) throw new AuthoringError(`value ${n} is not a number; an unknown value is null`);
  if ((low === undefined) !== (high === undefined)) throw new AuthoringError('a range has both ends or neither');
  if (low !== undefined && high !== undefined) {
    if (!Number.isFinite(low) || !Number.isFinite(high) || low > high) throw new AuthoringError(`range ${low} to ${high} is not a range`);
    if (n !== null && (n < low || n > high)) throw new AuthoringError(`the most likely value ${n} is outside its range ${low} to ${high}`);
  }
  const out: ServedValue = { n, unit: value.unit, display: value.display };
  if (low !== undefined && high !== undefined) {
    out.low = low;
    out.high = high;
  }
  return out;
}

/** One visible line with its basis. */
export function claim(input: ClaimInput): Claim {
  if (!input.basis) throw new AuthoringError('a claim needs its basis');
  const out: Claim = {
    text: sentence(input.text, 'text'),
    tone: input.tone,
    basis: input.basis,
    links: [...(input.links ?? [])],
  };
  const hint = hintOf(input.hint, 'hint');
  if (hint !== undefined) out.hint = hint;
  const value = valueOf(input.value);
  if (value) out.value = value;
  const place = placeOf(input.place);
  if (place) out.place = place;
  return out;
}

/** A served number. */
export function servedValue(n: number, unit: Unit, display: string, range?: { low: number; high: number }): ServedValue {
  return valueOf({ n, unit, display, ...(range ?? {}) })!;
}

/** A value the evidence cannot give: null, with the sentence the app shows in its place (never a zero or a dash). */
export function unknownValue(unit: Unit, display: string): ServedValue {
  return valueOf({ n: null, unit, display })!;
}

/** One table cell. */
export function cell(display: string, extra: { tone?: Tone; hint?: string; claimRef?: string } = {}): Cell {
  const out: Cell = { display: sentence(display, 'cell.display') };
  if (extra.tone !== undefined) out.tone = extra.tone;
  const hint = hintOf(extra.hint, 'cell.hint');
  if (hint !== undefined) out.hint = hint;
  if (extra.claimRef !== undefined) out.claimRef = sentence(extra.claimRef, 'cell.claimRef');
  return out;
}

/** One table row: a cell and a sort key for every column, the same columns in both. */
export function row<K extends string>(
  id: string,
  cells: Record<K, Cell>,
  sort: Record<K, number | string | null>,
  rowClaim?: Claim,
): Row<K> {
  const cellKeys = Object.keys(cells).sort();
  const sortKeys = Object.keys(sort).sort();
  if (cellKeys.join('|') !== sortKeys.join('|')) {
    throw new AuthoringError(`row ${id}: every column needs a cell and a sort key (cells ${cellKeys.join(', ')}; sort ${sortKeys.join(', ')})`);
  }
  for (const [key, value] of Object.entries(sort) as Array<[string, unknown]>) {
    if (value !== null && typeof value !== 'string' && !(typeof value === 'number' && Number.isFinite(value))) {
      throw new AuthoringError(`row ${id}: sort key ${key} is ${String(value)}; an unknown sorts as null`);
    }
  }
  const out: Row<K> = { id: sentence(id, 'row.id'), cells, sort };
  if (rowClaim) out.claim = rowClaim;
  return out;
}
