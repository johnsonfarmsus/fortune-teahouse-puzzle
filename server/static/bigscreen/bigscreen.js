// SPDX-License-Identifier: AGPL-3.0-or-later
// Big-screen scoreboard: polls /api/v1/summary every 5 seconds. No build step.
(function () {
  "use strict";

  var POLL_MS = 5000;
  var PART_LABELS = {
    logic: "Logic", wiring: "Wiring", sequence: "Sequence",
    word: "Word", rhythm: "Rhythm", helper: "Helper"
  };
  var STATUS_LABELS = {
    connected: "Connected", in_progress: "In progress", not_started: "Not started",
    waiting: "Waiting for a machine", locked: "Locked until the finale opens"
  };
  var MACHINE_LABELS = {
    fortune_machine: "Fortune Machine", cookie_machine: "Cookie Machine", oven: "Oven"
  };

  // The API lives next to this page: /bigscreen/ -> /api/v1/summary.
  var SUMMARY_URL = new URL("../api/v1/summary", window.location.href).toString();

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;   // never innerHTML: names are user input
    return e;
  }

  function clear(node) {
    while (node.firstChild) node.removeChild(node.firstChild);
  }

  function renderMachines(crews) {
    var root = document.getElementById("machines");
    clear(root);
    crews.forEach(function (c) {
      var card = el("div", "card" + (c.runs ? " runs" : ""));
      var h = el("h2");
      h.appendChild(el("span", null, c.name));
      h.appendChild(el("span", "status",
        c.runs ? "RUNNING" : c.parts_solved + " of " + c.parts_total + " fixed"));
      card.appendChild(h);
      var ul = el("ul", "parts");
      c.parts.forEach(function (p) {
        var li = el("li", "part" + (p.solved ? " on" : ""));
        li.appendChild(el("span", "light", p.solved ? "✓" : ""));
        li.appendChild(el("span", null, PART_LABELS[p.part] || p.part));
        li.appendChild(el("span", "n", p.solved_count ? String(p.solved_count) : ""));
        ul.appendChild(li);
      });
      card.appendChild(ul);
      root.appendChild(card);
    });
  }

  function renderBanner(fin) {
    var b = document.getElementById("banner");
    b.className = "";
    if (fin.started) {
      b.textContent = "The line is running!";
      b.className = "started";
    } else if (fin.open) {
      b.textContent = "Finale open";
      b.className = "open";
    } else {
      b.textContent = "Finale locked";
    }
  }

  function renderHandoffs(list) {
    var root = document.getElementById("handoffs");
    clear(root);
    list.forEach(function (h) {
      var box = el("div", "handoff " + h.status);
      var row = el("div", "row");
      row.appendChild(el("span", null, h.name));
      var label = h.status === "connected" ? "Connected" :
        (h.settings_solved + " of " + h.settings_total + " settings");
      row.appendChild(el("span", null, label));
      box.appendChild(row);
      var bar = el("div", "bar");
      var fill = el("div");
      fill.style.width = Math.round(100 * h.settings_solved / Math.max(1, h.settings_total)) + "%";
      bar.appendChild(fill);
      box.appendChild(bar);
      box.appendChild(el("div", "st", STATUS_LABELS[h.status] || h.status));
      root.appendChild(box);
    });
  }

  function renderNotes(n) {
    document.getElementById("notes").textContent = n.found + " of " + n.total;
    document.getElementById("notes-sub").textContent =
      n.total ? ("Need " + n.needed + " to start the line" + (n.complete ? " - enough found!" : "")) : "";
    var pips = document.getElementById("pips");
    clear(pips);
    for (var i = 0; i < n.total; i++) pips.appendChild(el("span", "pip" + (i < n.found ? " on" : "")));
  }

  var lastTicker = "";
  function renderTicker(contrib) {
    var key = JSON.stringify(contrib.recent.map(function (c) { return [c.name, c.machine]; })) + contrib.total;
    if (key === lastTicker) return;   // keep the scroll going when nothing changed
    lastTicker = key;
    var t = document.getElementById("ticker");
    clear(t);
    if (!contrib.recent.length) {
      t.appendChild(el("span", "who", "Contributors will appear here as fixes are merged."));
      return;
    }
    t.appendChild(el("span", "who", contrib.total + " contributors:"));
    contrib.recent.forEach(function (c) {
      var s = el("span", "who");
      s.appendChild(el("b", null, c.name));
      s.appendChild(document.createTextNode(" · " + (MACHINE_LABELS[c.machine] || c.machine)));
      t.appendChild(s);
    });
    t.style.setProperty("--dur", Math.max(30, contrib.recent.length * 4) + "s");
  }

  function render(s) {
    renderBanner(s.finale);
    renderMachines(s.crews);
    renderHandoffs(s.finale.handoffs);
    renderNotes(s.finale.notes);
    renderTicker(s.contributors);
    if (s.repo_url) document.getElementById("repo").href = s.repo_url;
    document.getElementById("conn").textContent = "";
    document.getElementById("updated").textContent =
      "Updated " + new Date(s.server_time).toLocaleTimeString();
  }

  function poll() {
    fetch(SUMMARY_URL, { cache: "no-store" })
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
      .then(render)
      .catch(function () {
        document.getElementById("conn").textContent = "Connection lost, retrying…";
      })
      .then(function () { setTimeout(poll, POLL_MS); });
  }

  poll();
})();
