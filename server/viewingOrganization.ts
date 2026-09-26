import { db, tableExists } from './db.js';
import type { Integer } from './contract/primitives.js';
import { loadSettings } from './settings.js';

/**
 * Whose organization a view is about (AGENTS.md: resolve the configured organization, then the human-managed OOTP
 * organization). One resolver for the server and every client: the player card's "our view", the trade desk, and the
 * Mac app's current club (served on `GET /api/settings`), so no client re-implements the rule.
 */
export type ViewingSource = 'requested' | 'configured' | 'human';

/** The organization whose view this is, and how it was found; null when none can be. */
export function viewingOrganization(requested: unknown): { id: number; source: ViewingSource } | null {
  const asked = Number(requested);
  if (requested !== undefined && requested !== '' && Number.isInteger(asked) && asked > 0) return { id: asked, source: 'requested' };
  const configured = loadSettings().defaultOrgId;
  if (typeof configured === 'number' && configured > 0) return { id: configured, source: 'configured' };
  if (!tableExists('teams')) return null;
  try {
    const human = db.prepare(`SELECT team_id FROM teams WHERE human_team = 1 LIMIT 1`).get() as { team_id: number } | undefined;
    return human ? { id: human.team_id, source: 'human' } : null;
  } catch {
    return null;
  }
}

/**
 * The club the app is about when nothing names one: the configured organization, else the one the save's human
 * manages; null when neither is known. A configured id is taken as configured even when the club list no longer has it
 * (the server's rule for every view), so a client shows that club as not found rather than quietly switching clubs.
 */
export interface CurrentOrganization {
  id: Integer;
  source: 'configured' | 'human';
}

export function currentOrganization(): CurrentOrganization | null {
  const found = viewingOrganization(undefined);
  if (!found || found.source === 'requested') return null;
  return { id: found.id, source: found.source };
}
