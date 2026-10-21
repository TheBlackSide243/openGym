// @vitest-environment happy-dom
// The note sheet is new JSX and nothing else mounts it, so a bad hook order, a missing import or
// a wrong store path would only surface on a real device. Render it through the real sheet stack
// and drive a save, so the wiring is checked and not just the shape of the module.
import { describe, expect, it, beforeEach, afterEach } from 'vitest'
import React, { act } from 'react'
import { createRoot } from 'react-dom/client'
import { useStore } from '../store/useStore.js'
import { useUI } from '../store/useUI.js'
import { exerciseNoteSheet, setNoteSheet, machineNoteSheet } from '../sheets.jsx'

const activeWith = entry => ({ id: 'w1', d: '2026-08-25', start: 1, routineId: 'r1', name: 'Push', entries: [entry] })

// Roots have to be torn down between tests: the sheet subscribes to the store, so a root left
// mounted reacts to the next test's setState — outside act(), which React rightly complains about.
const mounted = []

function renderSheet() {
  exerciseNoteSheet(0)
  const sheet = useUI.getState().sheets.at(-1)
  const host = document.createElement('div')
  document.body.appendChild(host)
  const root = createRoot(host)
  mounted.push(root)
  act(() => root.render(sheet.render(sheet_close(sheet))))
  return host
}
function renderSetNoteSheet(entryIdx = 0, setIdx = 0) {
  setNoteSheet(entryIdx, setIdx)
  const sheet = useUI.getState().sheets.at(-1)
  const host = document.createElement('div')
  document.body.appendChild(host)
  const root = createRoot(host)
  mounted.push(root)
  act(() => root.render(sheet.render(sheet_close(sheet))))
  return host
}
const sheet_close = sheet => () => useUI.getState().closeSheet(sheet.id)

const type = (el, value) => {
  const setter = Object.getOwnPropertyDescriptor(el.constructor.prototype, 'value').set
  setter.call(el, value)
  el.dispatchEvent(new Event('input', { bubbles: true }))
}

// Settings → Features → Machine settings: the line under an exercise opens this, and what is
// written is the exercise's standing note, so it is there again next week and in every routine.
describe('machine settings sheet', () => {
  beforeEach(() => {
    globalThis.IS_REACT_ACT_ENVIRONMENT = true
    useUI.setState({ sheets: [] })
    useStore.setState(s => ({ S: { ...s.S, exNotes: { squat: 'rack at 12' }, active: activeWith({ id: 'bench', sets: [] }) } }))
    document.body.innerHTML = ''
  })
  afterEach(() => { act(() => { mounted.splice(0).forEach(r => r.unmount()) }) })

  const open = exId => {
    machineNoteSheet(exId)
    const sheet = useUI.getState().sheets.at(-1)
    const host = document.createElement('div')
    document.body.appendChild(host)
    const root = createRoot(host)
    mounted.push(root)
    act(() => root.render(sheet.render(sheet_close(sheet))))
    return host
  }
  const save = host => act(() => { [...host.querySelectorAll('button')].find(b => /save/i.test(b.textContent)).click() })

  it('saves what is written on the exercise, and leaves the other exercises alone', () => {
    const host = open('bench')
    act(() => { type(host.querySelector('textarea'), '  seat height 5\nbackrest 3 ') })
    save(host)
    const S = useStore.getState().S
    expect(S.exNotes).toEqual({ bench: 'seat height 5\nbackrest 3', squat: 'rack at 12' })
    expect(S.active.entries[0].note).toBeUndefined()
    expect(useUI.getState().sheets).toHaveLength(0)
  })

  it('shows the photo of the machine, and Remove then Save takes it off the exercise only', () => {
    const photo = { kind: 'image', hash: 'a'.repeat(64), mime: 'image/webp', size: 1000, width: 800, height: 600, at: 1,
      poster: { hash: 'b'.repeat(64), mime: 'image/webp', size: 100, width: 240, height: 180 } }
    useStore.setState(s => ({ S: { ...s.S, exPhotos: { bench: photo, squat: photo } } }))
    const host = open('bench')
    expect(host.textContent).toContain('Photo of the machine')
    const remove = host.querySelector('button[aria-label="Remove"]')
    expect(remove).toBeTruthy()
    act(() => { remove.click() })
    save(host)
    const S = useStore.getState().S
    expect('bench' in S.exPhotos).toBe(false)
    expect(S.exPhotos.squat.hash).toBe('a'.repeat(64))
  })

  it('opens with what was written, and an emptied one is gone', () => {
    const host = open('squat')
    expect(host.querySelector('textarea').value).toBe('rack at 12')
    act(() => { type(host.querySelector('textarea'), '   ') })
    save(host)
    expect('squat' in useStore.getState().S.exNotes).toBe(false)
  })
})

describe('exercise note sheet', () => {
  beforeEach(() => {
    // React only treats act() as real when told it is in a test environment, and vitest shares
    // a worker across files — so set it per test rather than once at module scope.
    globalThis.IS_REACT_ACT_ENVIRONMENT = true
    useUI.setState({ sheets: [] })
    useStore.setState(s => ({
      S: { ...s.S, exNotes: {}, active: activeWith({ id: 'bench', sets: [] }) },
    }))
    document.body.innerHTML = ''
  })

  afterEach(() => {
    act(() => { mounted.splice(0).forEach(r => r.unmount()) })
  })

  it('renders the session note, the pin and the standing note', () => {
    const host = renderSheet()
    const areas = host.querySelectorAll('textarea')
    expect(areas).toHaveLength(2)
    // The pin cannot be set on an empty note — it would pin nothing.
    expect(host.querySelector('[role="switch"]').disabled).toBe(true)
  })

  it('saves the session note with its pin and the standing note separately', () => {
    const host = renderSheet()
    const [today, always] = host.querySelectorAll('textarea')
    act(() => { type(today, 'shoulder twinged'); type(always, 'seat at 4') })
    act(() => { host.querySelector('[role="switch"]').click() })
    const save = [...host.querySelectorAll('button')].find(b => /save/i.test(b.textContent))
    act(() => { save.click() })

    const S = useStore.getState().S
    expect(S.active.entries[0].note).toBe('shoulder twinged')
    expect(S.active.entries[0].notePin).toBe(true)
    // The standing note belongs to the exercise, not to today's entry.
    expect(S.exNotes.bench).toBe('seat at 4')
    expect(useUI.getState().sheets).toHaveLength(0)
  })

  it('clearing the session note drops the pin with it', () => {
    useStore.setState(s => ({
      S: { ...s.S, active: activeWith({ id: 'bench', sets: [], note: 'old', notePin: true }) },
    }))
    const host = renderSheet()
    const [today] = host.querySelectorAll('textarea')
    act(() => { type(today, '') })
    const save = [...host.querySelectorAll('button')].find(b => /save/i.test(b.textContent))
    act(() => { save.click() })
    const e = useStore.getState().S.active.entries[0]
    expect(e.note).toBeUndefined()
    expect(e.notePin).toBeUndefined()
  })

  it('saves and clears a note on one set', () => {
    useStore.setState(s => ({
      S: { ...s.S, active: activeWith({ id: 'bench', sets: [{ w: 60, r: 5, done: false }] }) },
    }))

    let host = renderSetNoteSheet()
    act(() => { type(host.querySelector('textarea'), 'Paused at the bottom') })
    act(() => { [...host.querySelectorAll('button')].find(b => b.textContent === 'Save').click() })
    expect(useStore.getState().S.active.entries[0].sets[0].note).toBe('Paused at the bottom')

    host = renderSetNoteSheet()
    act(() => { type(host.querySelector('textarea'), '') })
    act(() => { [...host.querySelectorAll('button')].find(b => b.textContent === 'Save').click() })
    expect(useStore.getState().S.active.entries[0].sets[0].note).toBeUndefined()
  })
})
