// Pure helpers for the omaShare plugin. No Quickshell imports so the parsers
// can be exercised under plain node.

function parseLine(line) {
  try {
    var value = JSON.parse(String(line || ""))
    return value && typeof value === "object" ? value : null
  } catch (e) {
    return null
  }
}

// The plugin's own entry in shell.json, or null when it is not there yet.
//
// Settings live on the bar layout entry (like the built-in bar widgets) so the
// receiver's on/off state travels with the widget: take the widget out of the
// bar and the receiver stops with it. A top-level plugins[] entry is honoured
// as a fallback so a service-only install still has somewhere to persist.
function barEntry(config, pluginId) {
  var id = String(pluginId || "")
  if (!config || typeof config !== "object" || id === "") return null
  var layout = config.bar && typeof config.bar === "object" ? config.bar.layout : null
  var regions = ["left", "center", "right"]
  for (var r = 0; r < regions.length; r++) {
    var entries = layout && Array.isArray(layout[regions[r]]) ? layout[regions[r]] : []
    for (var e = 0; e < entries.length; e++) {
      var entry = entries[e]
      if (typeof entry === "string") {
        if (entry === id) return { id: id, settings: {} }
        continue
      }
      if (!entry || typeof entry !== "object") continue
      if (String(entry.id || "") !== id) continue
      var settings = {}
      for (var key in entry) if (key !== "id") settings[key] = entry[key]
      return { id: id, settings: settings }
    }
  }
  var plugins = Array.isArray(config.plugins) ? config.plugins : []
  for (var p = 0; p < plugins.length; p++) {
    var plugin = plugins[p]
    if (!plugin || typeof plugin !== "object" || String(plugin.id || "") !== id) continue
    var pluginSettings = {}
    for (var pluginKey in plugin) if (pluginKey !== "id") pluginSettings[pluginKey] = plugin[pluginKey]
    return { id: id, settings: pluginSettings }
  }
  return null
}

// Quattro accepts a bare id in bar.layout, but inline settings can only attach
// to object entries. Promote a matching string in place before writing the
// first setting.
function hasStringBarEntry(config, pluginId) {
  var id = String(pluginId || "")
  var layout = config && config.bar && typeof config.bar === "object" ? config.bar.layout : null
  if (!layout || id === "") return false
  var regions = ["left", "center", "right"]
  for (var r = 0; r < regions.length; r++) {
    var entries = Array.isArray(layout[regions[r]]) ? layout[regions[r]] : []
    for (var e = 0; e < entries.length; e++) if (entries[e] === id) return true
  }
  return false
}

function promoteStringBarEntry(config, pluginId, settings) {
  var id = String(pluginId || "")
  var layout = config && config.bar && typeof config.bar === "object" ? config.bar.layout : null
  if (!layout || id === "") return false
  var regions = ["left", "center", "right"]
  for (var r = 0; r < regions.length; r++) {
    var entries = Array.isArray(layout[regions[r]]) ? layout[regions[r]] : []
    for (var e = 0; e < entries.length; e++) {
      if (entries[e] !== id) continue
      var promoted = { id: id }
      for (var key in settings) if (key !== "id") promoted[key] = settings[key]
      entries[e] = promoted
      return true
    }
  }
  return false
}

// Receiving is on unless the entry says otherwise; an absent entry means the
// widget has not been placed in the bar at all, so nothing runs.
function receiverEnabledIn(entry) {
  return !!entry && entry.settings.receiverEnabled !== false
}

// `qs devices --json` prints one pretty-printed JSON array on stdout.
// Normalize it to rows the panel can render; tolerate a non-array payload.
function parseDevices(raw) {
  var text = String(raw || "").trim()
  if (text === "") return []
  try {
    var parsed = JSON.parse(text)
    if (!Array.isArray(parsed)) return []
    var next = []
    for (var i = 0; i < parsed.length; i++) {
      var row = parsed[i] || {}
      next.push({
        name: String(row.name || ""),
        id: String(row.id || ""),
        ip: String(row.ip || ""),
        port: Number(row.port || 0),
        type: String(row.type || "")
      })
    }
    next.sort(function(a, b) { return a.name.localeCompare(b.name) })
    return next
  } catch (e) {
    return []
  }
}

function basename(path) {
  var value = String(path || "")
  var at = value.lastIndexOf("/")
  return at >= 0 ? value.substring(at + 1) : value
}

function timeAgo(timestamp) {
  var ms = Date.now() - Number(timestamp || 0)
  if (ms < 0 || !isFinite(ms)) return ""
  var s = Math.floor(ms / 1000)
  if (s < 5) return "just now"
  if (s < 60) return s + "s ago"
  var m = Math.floor(s / 60)
  if (m < 60) return m + "m ago"
  var h = Math.floor(m / 60)
  if (h < 24) return h + "h ago"
  return Math.floor(h / 24) + "d ago"
}

if (typeof module !== "undefined") {
  module.exports = {
    parseLine: parseLine,
    barEntry: barEntry,
    hasStringBarEntry: hasStringBarEntry,
    promoteStringBarEntry: promoteStringBarEntry,
    receiverEnabledIn: receiverEnabledIn,
    parseDevices: parseDevices,
    basename: basename,
    timeAgo: timeAgo
  }
}
