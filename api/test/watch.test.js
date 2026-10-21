/* The Apple Watch app's view of a profile (api/watch.js): the workout in progress with the first
   exercise still to do, the last finished one and the body weight, small enough to fetch every
   few seconds, and nothing else of the document. */
import test from 'node:test';
import assert from 'node:assert/strict';
import { watchSummary, exerciseName } from '../watch.js';
import { LIBRARY } from '../coach/core/library.js';

const lib = LIBRARY[0];

test('the workout in progress: names, sets, and the first exercise with a set to do', () => {
  const S = {
    unit: 'kg', restSec: 120,
    customEx: [{ id: 'own1', n: 'My machine row' }],
    active: {
      name: 'Push', start: 1000,
      entries: [
        { id: lib.id, sets: [{ w: 60, r: 8, done: true, at: 5 }, { w: 60, r: 8, done: true }] },
        { id: 'own1', sets: [{ w: 40, r: 10, done: true }, { w: 40, r: 10 }] },
        { id: 'cardio', sets: [{ min: 8, speed: 6 }] },
      ],
    },
    workouts: [{ name: 'Old', d: '2026-10-01', start: 1, vol: 100, entries: [{ sets: [{ done: true }] }] },
      { name: 'Legs', d: '2026-10-18', start: 9, vol: 5000, entries: [{ sets: [{ done: true }, { done: true }, {}] }] }],
    bodyweight: [{ d: '2026-10-19', w: 72.4 }, { d: '2026-10-20', w: 71.7 }, { d: '2026-10-02', w: 73 }],
    health: new Array(1000).fill({ type: 'steps', v: 1 }),
  };
  const w = watchSummary(S);
  assert.equal(w.unit, 'kg');
  assert.equal(w.restSec, 120);
  assert.equal(w.active.name, 'Push');
  assert.deepEqual(w.active.entries.map(e => e.name), [lib.n, 'My machine row', 'cardio']);
  assert.deepEqual(w.active.entries[1].sets, [{ done: true, w: 40, r: 10 }, { done: false, w: 40, r: 10 }]);
  assert.deepEqual(w.active.entries[2].sets, [{ done: false, min: 8 }]);
  assert.equal(w.active.current, 1);
  assert.deepEqual(w.last, { name: 'Legs', d: '2026-10-18', vol: 5000, sets: 2 });
  assert.deepEqual(w.weight, { d: '2026-10-20', w: 71.7 });
  assert.ok(JSON.stringify(w).length < 2000, 'a few kilobytes, nothing of the health data');
});

test('no workout running, nothing logged: nulls, and the defaults', () => {
  assert.deepEqual(watchSummary({}), { unit: 'kg', restSec: 90, active: null, last: null, weight: null });
  assert.equal(watchSummary({ unit: 'lb' }).unit, 'lb');
  assert.equal(watchSummary({ active: { entries: [{ id: 'x', sets: [{ done: true }] }] } }).active.current, -1);
});

test('an exercise with no name anywhere is shown by its id', () => {
  assert.equal(exerciseName({}, 'zz-unknown'), 'zz-unknown');
});
