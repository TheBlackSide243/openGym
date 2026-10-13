/* A question in the Coach's chat (the `ask` job): answered in words, with the recent sessions,
 * the session running on the phone, the split between planned and extra exercises, and the
 * body's numbers only when the question is about the body. */
import test from 'node:test';
import assert from 'node:assert/strict';
import { tempData } from './helpers.mjs';

tempData();
const payloadLib = await import('../coach/core/payload.js');
const { runPipeline } = await import('../coach/core/pipeline.js');
const { buildPromptParts } = await import('../coach/core/prompt.js');
const { validateAsk } = await import('../coach/core/validate.js');
const { SCHEMAS } = await import('../coach/core/schemas.js');

const set = (w, r, done = true) => ({ w, r, done });
const S = {
  unit: 'kg', lang: 'it',
  routines: [{ id: 'legs', name: 'Legs', ex: [{ id: '0001', sets: 3, reps: 8 }] }],
  week: { 2: ['legs'] },
  workouts: [{
    id: 'w1', d: '2026-10-06', name: 'Legs', start: 1, end: 3600001, routineIds: ['legs'], planEx: 1,
    entries: [
      { id: '0001', rid: 'legs', sets: [set(100, 8), set(100, 8), set(100, 7)] },
      { id: '0002', rid: 'legs', extra: true, sets: [set(40, 12), set(40, 12)] }
    ]
  }],
  bodyweight: [{ d: '2026-10-01', w: 80, t: 1 }],
  health: [
    { id: 'a', type: 'bodyFat', v: 18, u: '%', t: Date.parse('2026-09-01T07:00:00'), d: '2026-09-01', src: 'manual' },
    { id: 'b', type: 'bodyFat', v: 17, u: '%', t: Date.parse('2026-10-10T07:00:00'), d: '2026-10-10', src: 'manual' },
    { id: 'c', type: 'steps', v: 9000, u: 'count', t: Date.parse('2026-10-10T12:00:00'), d: '2026-10-10', src: 'apple-health', sid: 'steps:2026-10-10' }
  ],
  coach: { consent: { agreedAt: 1 }, chat: [{ role: 'user', kind: 'text', text: 'ciao' }, { role: 'coach', kind: 'text', text: 'Ciao!' }] }
};

test('ask payload: the question, the sessions with planned and extra work told apart, the chat so far', () => {
  const p = payloadLib.build(S, { handle: 'h'.repeat(16), kind: 'ask', note: 'Quanto recupero tra le serie?' });
  assert.equal(p.task, 'ask');
  assert.equal(p.question, 'Quanto recupero tra le serie?');
  const w = p.window.workouts[0];
  assert.deepEqual(w.summary, { plannedExercises: 1, plannedSets: 3, extraExercises: 1, extraSets: 2 });
  assert.equal(w.entries[1].extra, true);
  assert.equal(w.entries[0].extra, undefined);
  assert.deepEqual(p.conversation.map(c => c.who), ['user', 'coach']);
  assert.equal(p.library, undefined, 'an answer names no ids, so no library');
});

test('ask payload: health readings travel only for a question about the body', () => {
  const plain = payloadLib.build(S, { handle: 'h'.repeat(16), kind: 'ask', note: 'Meglio squat o pressa?' });
  assert.equal(plain.health, undefined);
  assert.equal(plain.bodyweight, undefined);
  const body = payloadLib.build(S, { handle: 'h'.repeat(16), kind: 'ask', note: 'Il mio grasso corporeo sta scendendo?' });
  assert.deepEqual(body.health.bodyFat, { latest: 17, on: '2026-10-10', monthAgo: 18, since: '2026-09-01' });
  assert.equal(body.health.steps.avgLast7, 9000);
  assert.ok(!JSON.stringify(body.health).includes('apple-health'), 'no source, no record ids');
});

test('a session without extras keeps exactly its old shape', () => {
  const S2 = { ...S, workouts: [{ ...S.workouts[0], entries: [S.workouts[0].entries[0]] }] };
  const p = payloadLib.build(S2, { handle: 'h'.repeat(16), kind: 'review' });
  assert.equal(p.window.workouts[0].summary, undefined);
});

test('ask payload: the running session the phone sent is bounded like a logged one', () => {
  const today = {
    name: 'Legs', minutes: 40, extraKey: 'dropped',
    entries: [{ id: '0001', note: 'private', sets: Array.from({ length: 80 }, () => set(100, 5)) }, { id: '0002', extra: true, sets: [set(30, 10, false)] }]
  };
  const p = payloadLib.build(S, { handle: 'h'.repeat(16), kind: 'ask', note: 'e adesso?', today });
  assert.equal(p.today.minutes, 40);
  assert.equal(p.today.entries[0].sets.length, 30);
  assert.equal(p.today.entries[1].extra, true);
  assert.ok(!JSON.stringify(p.today).includes('private'));
  assert.ok(!JSON.stringify(p.today).includes('dropped'));
  assert.equal(payloadLib.build(S, { handle: 'h'.repeat(16), kind: 'ask', note: 'x', today: 'nope' }).today, undefined);
});

test('asksAboutBody reads the body words of the app languages, and nothing else', () => {
  for (const q of ['How is my weight?', 'Dormo poco, è un problema?', 'Wie viel Körperfett?', 'Mon sommeil est mauvais ?', 'quanti passi?']) assert.ok(payloadLib.asksAboutBody(q), q);
  for (const q of ['How long should I rest?', 'Aggiungo un altro esercizio?', 'Meglio questo o quello?']) assert.ok(!payloadLib.asksAboutBody(q), q);
});

test('validateAsk: one answer, no changes', () => {
  assert.deepEqual(validateAsk({ coach_contract: 1, answer: '  Due minuti.  ' }), { ok: true, proposal: { answer: 'Due minuti.' } });
  assert.equal(validateAsk({ coach_contract: 1, answer: '' }).ok, false);
  assert.equal(validateAsk({ coach_contract: 1, answer: 'ok', changes: [{ type: 'sets' }] }).ok, false);
  assert.ok(SCHEMAS.ask.required.includes('answer'));
});

test('ask pipeline: the ask rules and schema reach the provider, and an answer comes back', async () => {
  const calls = [];
  const adapter = { spawns: false, async invoke(req) { calls.push(req); return { code: 0, text: JSON.stringify({ coach_contract: 1, answer: 'Due o tre minuti tra le serie pesanti.' }) }; } };
  const payload = payloadLib.build(S, { handle: 'h'.repeat(16), kind: 'ask', note: 'Quanto recupero?' });
  const r = await runPipeline({ adapter, cfg: {}, kind: 'ask', payload });
  assert.equal(r.ok, true);
  assert.equal(r.result.answer, 'Due o tre minuti tra le serie pesanti.');
  assert.match(calls[0].system, /# Task: answer a question/);
  assert.equal(calls[0].schema, SCHEMAS.ask);
  assert.match(buildPromptParts('review', payload, null).system, /`extra: true` was added during that session/);
});
