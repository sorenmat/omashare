// Plain-node unit tests for Model.js. Run: node test/model.test.js
"use strict"
const assert = require("node:assert")
const Model = require("../Model.js")

let passed = 0
function t(name, fn) {
  fn()
  passed += 1
  console.log("ok " + passed + " - " + name)
}

// ---------------------------------------------------------------- parseLine

t("parseLine parses a JSON object", () => {
  const v = Model.parseLine('{"event":"ready","version":"0.1.0"}')
  assert.deepStrictEqual(v, { event: "ready", version: "0.1.0" })
})
t("parseLine returns null for garbage", () => {
  assert.strictEqual(Model.parseLine("not json"), null)
})
t("parseLine returns null for a JSON string", () => {
  assert.strictEqual(Model.parseLine('"hello"'), null)
})
t("parseLine returns null for empty input", () => {
  assert.strictEqual(Model.parseLine(""), null)
  assert.strictEqual(Model.parseLine(null), null)
})

// ----------------------------------------------------------------- barEntry

t("barEntry finds an object entry in bar.layout.right", () => {
  const config = { bar: { layout: { right: [{ id: "smo.omashare", receiverEnabled: false, deviceName: "Box" }] } } }
  const entry = Model.barEntry(config, "smo.omashare")
  assert.strictEqual(entry.id, "smo.omashare")
  assert.strictEqual(entry.settings.receiverEnabled, false)
  assert.strictEqual(entry.settings.deviceName, "Box")
})
t("barEntry finds a bare string entry in bar.layout.left", () => {
  const config = { bar: { layout: { left: ["omarchy.clock", "smo.omashare"] } } }
  assert.deepStrictEqual(Model.barEntry(config, "smo.omashare"), { id: "smo.omashare", settings: {} })
})
t("barEntry falls back to top-level plugins[]", () => {
  const config = { plugins: [{ id: "smo.omashare", receiverEnabled: true }] }
  assert.deepStrictEqual(Model.barEntry(config, "smo.omashare").settings, { receiverEnabled: true })
})
t("barEntry returns null when absent", () => {
  assert.strictEqual(Model.barEntry({ bar: { layout: {} } }, "smo.omashare"), null)
  assert.strictEqual(Model.barEntry(null, "smo.omashare"), null)
  assert.strictEqual(Model.barEntry({}, ""), null)
})

// --------------------------------------------- string-entry promotion flow

t("hasStringBarEntry / promoteStringBarEntry round-trip", () => {
  const config = { bar: { layout: { right: ["smo.omashare"] } } }
  assert.strictEqual(Model.hasStringBarEntry(config, "smo.omashare"), true)
  assert.strictEqual(Model.hasStringBarEntry(config, "other.id"), false)
  assert.strictEqual(Model.promoteStringBarEntry(config, "smo.omashare", { receiverEnabled: false }), true)
  assert.deepStrictEqual(config.bar.layout.right, [{ id: "smo.omashare", receiverEnabled: false }])
  assert.strictEqual(Model.hasStringBarEntry(config, "smo.omashare"), false)
  assert.strictEqual(Model.promoteStringBarEntry(config, "smo.omashare", {}), false)
})
t("promoteStringBarEntry is a no-op without a string entry", () => {
  const config = { bar: { layout: { right: [] } } }
  assert.strictEqual(Model.promoteStringBarEntry(config, "smo.omashare", { a: 1 }), false)
})

// ------------------------------------------------------------ receiverEnabledIn

t("receiverEnabledIn: missing entry is off", () => {
  assert.strictEqual(Model.receiverEnabledIn(null), false)
})
t("receiverEnabledIn: present entry with no key is on", () => {
  assert.strictEqual(Model.receiverEnabledIn({ id: "x", settings: {} }), true)
})
t("receiverEnabledIn: explicit false is off", () => {
  assert.strictEqual(Model.receiverEnabledIn({ id: "x", settings: { receiverEnabled: false } }), false)
})

// --------------------------------------------------------------- parseDevices

t("parseDevices normalizes a qs devices payload", () => {
  const raw = JSON.stringify([
    { name: "Pixel 9", id: "dev-abc", ip: "10.0.0.5", port: 53317, type: "android" },
    { name: "Desk", id: "dev-xyz", ip: "", port: 0, type: "desktop" }
  ])
  const rows = Model.parseDevices(raw)
  assert.strictEqual(rows.length, 2)
  assert.deepStrictEqual(rows[0], { name: "Desk", id: "dev-xyz", ip: "", port: 0, type: "desktop" })
  assert.deepStrictEqual(rows[1], { name: "Pixel 9", id: "dev-abc", ip: "10.0.0.5", port: 53317, type: "android" })
})
t("parseDevices tolerates an object payload and empty input", () => {
  assert.deepStrictEqual(Model.parseDevices(JSON.stringify({ name: "x" })), [])
  assert.deepStrictEqual(Model.parseDevices(""), [])
  assert.deepStrictEqual(Model.parseDevices("garbage"), [])
})

// -------------------------------------------------------------------- basename

t("basename strips the directory", () => {
  assert.strictEqual(Model.basename("/home/smo/Downloads/a.png"), "a.png")
})
t("basename tolerates a bare name", () => {
  assert.strictEqual(Model.basename("a.png"), "a.png")
})

// -------------------------------------------------------------------- timeAgo

t("timeAgo buckets", () => {
  const now = Date.now()
  assert.strictEqual(Model.timeAgo(now - 2000), "just now")
  assert.strictEqual(Model.timeAgo(now - 30 * 1000), "30s ago")
  assert.strictEqual(Model.timeAgo(now - 5 * 60 * 1000), "5m ago")
  assert.strictEqual(Model.timeAgo(now - 3 * 60 * 60 * 1000), "3h ago")
  assert.strictEqual(Model.timeAgo(now - 40 * 60 * 60 * 1000), "1d ago")
  assert.strictEqual(Model.timeAgo(now + 60 * 1000), "")
})

console.log("\n" + passed + " tests passed")
