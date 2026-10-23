// A short screen — a foldable closed (about 466×678 points), a small phone — keeps an exercise's
// picture to a third of the height, so its sets show with it; the full-screen viewer and the
// compact and mini pictures keep their own sizes.
import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

const css = readFileSync(resolve(process.cwd(), 'src/index.css'), 'utf8')
const block = css.match(/@media \(max-height:760px\)\{([\s\S]*?)\n\}/)?.[1] || ''

describe('a short screen', () => {
  it('caps the exercise picture at a third of the height', () => {
    expect(block).toMatch(/height:min\(320px,32vh\)/)
    for (const el of ['img', 'video', '.exmedia-x']) {
      expect(block).toContain(`.exmedia:not(.viewer):not(.compact):not(.mini) ${el}`)
    }
  })
  it('leaves the viewer and the small pictures alone', () => {
    expect(block).not.toMatch(/\.exmedia\.viewer|\.exmedia\.compact|\.exmedia\.mini/)
  })
})
