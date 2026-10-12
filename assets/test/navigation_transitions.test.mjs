import assert from "node:assert/strict"
import test from "node:test"
import {navigationTransitions} from "../js/navigation_transitions.mjs"

function setup({supported = true, reducedMotion = false, visibility = "visible", throws = false} = {}) {
  const events = new Map()
  const transitions = []
  const browserWindow = {
    addEventListener(name, callback) { events.set(name, callback) },
    matchMedia() { return {matches: reducedMotion} },
  }
  const browserDocument = {visibilityState: visibility}

  if (supported) {
    browserDocument.startViewTransition = callback => {
      if (throws) throw new Error("Transitions unavailable")
      const transition = {
        ready: Promise.resolve(),
        finished: new Promise(() => {}),
        skipped: false,
        skipTransition() { this.skipped = true },
        update: callback,
      }
      transitions.push(transition)
      return transition
    }
  }

  return {
    patch: navigationTransitions(browserWindow, browserDocument),
    transitions,
    navigate(kind = "redirect") { events.get("phx:page-loading-start")({detail: {kind}}) },
    stop() { events.get("phx:page-loading-stop")() },
  }
}

test("navigation waits for the old snapshot and patches exactly once", () => {
  const state = setup()
  let patches = 0
  state.navigate()
  state.patch(() => patches++)
  assert.equal(patches, 0)
  assert.equal(state.transitions.length, 1)

  state.transitions[0].update()
  state.transitions[0].update()
  assert.equal(patches, 1)
})

test("ordinary form and upload patches are not animated", () => {
  const state = setup()
  let patches = 0
  state.navigate("element")
  state.patch(() => patches++)
  state.patch(() => patches++)
  assert.equal(patches, 2)
  assert.equal(state.transitions.length, 0)
})

test("unsupported browsers, reduced motion and hidden pages navigate normally", () => {
  for (const options of [{supported: false}, {reducedMotion: true}, {visibility: "hidden"}]) {
    const state = setup(options)
    let patches = 0
    state.navigate()
    state.patch(() => patches++)
    assert.equal(patches, 1)
    assert.equal(state.transitions.length, 0)
  }
})

test("a synchronous transition failure still applies the patch", () => {
  const state = setup({throws: true})
  let patches = 0
  state.navigate()
  state.patch(() => patches++)
  assert.equal(patches, 1)
})

test("rapid navigation skips the previous animation without dropping a patch", () => {
  const state = setup()
  let patches = 0
  state.navigate()
  state.patch(() => patches++)
  state.transitions[0].update()
  state.navigate()
  state.patch(() => patches++)
  assert.equal(state.transitions[0].skipped, true)
  state.transitions[1].update()
  assert.equal(patches, 2)
})

test("a finished navigation does not animate a later background update", () => {
  const state = setup()
  let patches = 0
  state.navigate()
  state.stop()
  state.patch(() => patches++)
  assert.equal(patches, 1)
  assert.equal(state.transitions.length, 0)
})
