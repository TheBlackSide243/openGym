import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

// The rail's rules in index.css: at the top level, so every screen gets them (a merge once lost the
// brace closing the media query before them, and the rail applied only at 360px or less), with the
// names under the icons hidden for the eye only, and Back to top kept off the rail.
describe('the stylesheet of the rail', () => {
  const css = readFileSync(resolve(process.cwd(), 'src/index.css'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '')
  const depthAt = i => [...css.slice(0, i)].reduce((d, c) => d + (c === '{') - (c === '}'), 0)

  it('stands outside every @media, and the file closes every brace it opens', () => {
    expect(depthAt(css.length)).toBe(0)
    expect(depthAt(css.indexOf('body.tabbar-side{'))).toBe(0)
  })

  it('hides the names under the icons from the eye only', () => {
    const short = css.slice(css.indexOf('@media (max-height:480px){\n  body.tabbar-side'))
    const rule = /span:not\(\.tab-ic\):not\(\.cir\)\{([^}]*)\}/.exec(short)[1]
    expect(rule).not.toMatch(/display:\s*none/)
    expect(rule).toMatch(/position:absolute/)
    expect(rule).toMatch(/clip-path:inset\(50%\)/)
  })

  it('keeps Back to top off the rail', () => {
    expect(css).toMatch(/body\.tabbar-side #totop,body\.tabbar-side\.resting #totop\{left:auto;right:max\(calc\(var\(--rail\) \+ 16px\)/)
  })
})
