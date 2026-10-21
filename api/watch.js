/* What the Apple Watch app shows (watch/), read from a profile in a few kilobytes: the profile's
 * whole document runs to megabytes with health data, too much for a watch to fetch every few
 * seconds. Read-only: the watch shows the workout running on the phone or in the browser, keeps a
 * rest timer and reads the heart rate itself; it never writes the profile.
 *
 *   unit, restSec          the profile's weight unit and default rest
 *   active                 the workout in progress, or null: its name, start and each exercise with
 *                          its sets ({ w, r, min, s, done }), and `current`, the first exercise
 *                          with a set still to do
 *   last                   the last finished workout: name, day, volume, sets done
 *   weight                 the last body weight logged: { d, w }
 */
import { libraryName } from './coach/core/library.js';

const MAX_ENTRIES = 40, MAX_SETS = 30;
const num = v => (typeof v === 'number' && Number.isFinite(v) ? v : null);
const text = (v, max = 80) => (typeof v === 'string' ? v.slice(0, max) : '');

/** An exercise's name: the person's own exercise first, then the catalogue's. */
export function exerciseName(S, id) {
  const own = (Array.isArray(S?.customEx) ? S.customEx : []).find(e => e && String(e.id) === String(id));
  return text(own?.n || own?.name) || libraryName(id) || libraryName(String(id)) || libraryName(Number(id)) || String(id ?? '');
}

const setOf = s => {
  const out = { done: !!s?.done };
  for (const [k, from] of [['w', 'w'], ['r', 'r'], ['min', 'min'], ['s', 'sec'], ['s', 'secs']]) {
    const v = num(s?.[from]);
    if (v != null && !(k in out)) out[k] = v;
  }
  return out;
};

function activeOf(S) {
  const A = S?.active;
  if (!A || !Array.isArray(A.entries)) return null;
  const entries = A.entries.slice(0, MAX_ENTRIES).map(e => ({
    id: String(e?.id ?? ''),
    name: exerciseName(S, e?.id),
    sets: (Array.isArray(e?.sets) ? e.sets : []).slice(0, MAX_SETS).map(setOf),
  }));
  const current = entries.findIndex(e => e.sets.some(s => !s.done));
  return { name: text(A.name), start: num(A.start), entries, current };
}

function lastOf(S) {
  const ws = Array.isArray(S?.workouts) ? S.workouts : [];
  let w = null;
  for (const x of ws) if (x && (!w || (num(x.start) || 0) > (num(w.start) || 0))) w = x;
  if (!w) return null;
  const sets = (Array.isArray(w.entries) ? w.entries : []).reduce((n, e) => n + (Array.isArray(e?.sets) ? e.sets.filter(s => s?.done).length : 0), 0);
  return { name: text(w.name), d: text(w.d, 10), vol: num(w.vol), sets };
}

function weightOf(S) {
  const bw = Array.isArray(S?.bodyweight) ? S.bodyweight : [];
  let b = null;
  for (const x of bw) if (x && num(x.w) != null && (!b || String(x.d) > String(b.d))) b = x;
  return b ? { d: text(b.d, 10), w: b.w } : null;
}

export function watchSummary(S) {
  return {
    unit: S?.unit === 'lb' ? 'lb' : 'kg',
    restSec: num(S?.restSec) ?? 90,
    active: activeOf(S),
    last: lastOf(S),
    weight: weightOf(S),
  };
}
