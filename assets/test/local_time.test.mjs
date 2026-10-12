import assert from "node:assert/strict"
import test from "node:test"
import LocalTime from "../js/hooks/local_time.mjs"

function hookFor(timestamp) {
  const hook = Object.create(LocalTime)
  hook.el = {
    dateTime: timestamp,
    textContent: "—",
    title: "",
    removeAttribute(name) { delete this[name] },
  }
  return hook
}

test("uses the local timezone, including daylight saving and date boundaries", () => {
  const previousTimezone = process.env.TZ

  try {
    for (const timezone of ["Europe/Berlin", "America/New_York"]) {
      process.env.TZ = timezone

      for (const timestamp of ["2026-10-12T14:05:30Z", "2026-01-12T00:30:00Z"]) {
        const hook = hookFor(timestamp)
        hook.mounted()

        const expected = new Intl.DateTimeFormat(undefined, {
          dateStyle: "medium",
          timeStyle: "short",
          hourCycle: "h23",
          timeZone: timezone,
        }).format(new Date(timestamp))

        assert.equal(hook.el.textContent, expected)
        assert.doesNotMatch(hook.el.textContent, /UTC/)
        assert.ok(hook.el.title.length > hook.el.textContent.length)
      }
    }
  } finally {
    if (previousTimezone === undefined) delete process.env.TZ
    else process.env.TZ = previousTimezone
  }
})

test("uses 24-hour time for evenings and midnight without AM or PM", () => {
  const previousTimezone = process.env.TZ

  try {
    process.env.TZ = "UTC"

    for (const [timestamp, expectedTime] of [
      ["2026-10-12T20:39:00Z", "20:39"],
      ["2026-10-12T00:30:00Z", "00:30"],
    ]) {
      const hook = hookFor(timestamp)
      hook.mounted()

      assert.ok(hook.el.textContent.includes(expectedTime))
      assert.doesNotMatch(hook.el.textContent, /\b(?:AM|PM)\b/)
      assert.doesNotMatch(hook.el.title, /\b(?:AM|PM)\b/)
    }
  } finally {
    if (previousTimezone === undefined) delete process.env.TZ
    else process.env.TZ = previousTimezone
  }
})

test("refreshes the formatted value when the timestamp changes", () => {
  const hook = hookFor("2026-10-12T14:05:30Z")
  hook.mounted()
  const previousText = hook.el.textContent

  hook.el.dateTime = "2026-10-13T15:10:00Z"
  hook.updated()

  assert.notEqual(hook.el.textContent, previousText)
})

test("handles an invalid timestamp without crashing or leaving an old tooltip", () => {
  const hook = hookFor("2026-10-12T14:05:30Z")
  hook.mounted()
  hook.el.dateTime = "invalid"
  hook.updated()

  assert.equal(hook.el.textContent, "—")
  assert.equal(hook.el.title, undefined)
})
