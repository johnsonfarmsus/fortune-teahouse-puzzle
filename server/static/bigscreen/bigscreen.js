// SPDX-License-Identifier: AGPL-3.0-or-later
// Big-screen scoreboard: polls /api/v1/summary every 5 seconds. No build step.
//
// States (docs/FINALE-DESIGN.md section 8):
//   S0 finale not open      S1 open      S2 line_ready
//   S3 the reveal (on the `started` transition, ?replay=1, or key R; any key skips)
//   S4 started: full README and contributors
(function () {
  "use strict";

  var POLL_MS = 5000;
  var FETCH_TIMEOUT_MS = 4000;
  var PART_LABELS = {
    logic: "Logic", wiring: "Wiring", sequence: "Sequence",
    word: "Word", rhythm: "Rhythm", helper: "Helper"
  };
  var MACHINE_LABELS = {
    fortune_machine: "Fortune Machine", cookie_machine: "Cookie Machine", oven: "Oven"
  };

  // Exact strings from the finale design, section 5 (reveal) and section 8 (states).
  var TXT = {
    s1: "The finale is open: make the line run!",
    s2: "The line is ready! Find a Pack A cookie and a Pack B cookie: the start code is on their backs.",
    s4: "The line is running! The machines belong to everyone who fixed them.",
    starting: "Starting the line…",
    code: "3.141592653",
    firstCookie: "The first cookie is out.",
    anglerfish: "The Anglerfish snaps his briefcase shut and swims off. Nobody took the free trial."
  };
  var REVEAL_LINES = [
    "Fortune Machine: printing", "Cookie Machine: pressing", "Oven: baking", "Gopher: packing"
  ];
  var T_START = 3000, T_LINE = 2000, T_COOKIE = 3000, T_FORTUNE = 8000, T_ANGLER = 4000;
  var SCROLL_PX_PER_S = 110, SCROLL_MIN_S = 12, SCROLL_MAX_S = 45;

  // The API lives next to this page: /bigscreen/ -> /api/v1/summary.
  var SUMMARY_URL = new URL("../api/v1/summary", window.location.href).toString();
  var CONTRIBUTORS_URL = new URL("../api/v1/contributors", window.location.href).toString();
  var README_URL = new URL("readme.json", window.location.href).toString();

  var params = new URLSearchParams(window.location.search);
  var replayRequested = params.get("replay") === "1";

  var readme = null;          // readme.json, once loaded
  var last = null;            // the last summary received
  var allContributors = null; // full list from /contributors (S4 and reveal); falls back to summary.recent
  var revealing = false;
  var forceS4 = false;        // after a ?replay=1 reveal on a line that has not really started
  var reveal = null;          // active reveal: { timers: [], done: fn }

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;   // never innerHTML: names are user input
    return e;
  }

  function clear(node) {
    while (node.firstChild) node.removeChild(node.firstChild);
  }

  function byId(id) { return document.getElementById(id); }

  // "6:00 pm" in the screen's local time.
  function formatTime(iso) {
    var d = new Date(iso);
    if (isNaN(d.getTime())) return "";
    var s = d.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
    return s.replace(/[\s ]*(AM|PM)$/i, function (m, ap) { return " " + ap.toLowerCase(); });
  }

  function stateOf(fin) {
    if (fin.started || forceS4) return "S4";
    if (!fin.open) return "S0";
    return fin.line_ready ? "S2" : "S1";
  }

  // ------------------------------------------------------------- machines

  function renderMachines(crews, compact) {
    var root = byId("machines");
    clear(root);
    root.className = "machines" + (compact ? " compact" : "");
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

  // ------------------------------------------------------------- state text

  var BANNERS = {
    S0: ["Finale locked", ""], S1: ["Finale open", "open"],
    S2: ["Line ready", "open"], S4: ["The line is running!", "started"]
  };

  function renderBanner(state) {
    var b = byId("banner");
    b.textContent = BANNERS[state][0];
    b.className = BANNERS[state][1];
  }

  function messageFor(state, fin) {
    if (state === "S0") {
      var base = "Finale locked: it opens when all three machines run";
      if (fin.open_reason !== "admin_closed" && fin.safety_net_at) {
        var t = formatTime(fin.safety_net_at);
        if (t) return base + ", or at " + t + ".";
      }
      return base + ".";
    }
    return { S1: TXT.s1, S2: TXT.s2, S4: TXT.s4 }[state];
  }

  // ------------------------------------------------------------- handoffs

  // "waiting for the Cookie Machine and the Oven": the crew machines this handoff touches
  // that are not running yet (packaging is not a crew machine).
  function waitingFor(h, crews) {
    var names = [];
    [h.from_machine, h.to_machine].forEach(function (m) {
      for (var i = 0; i < crews.length; i++) {
        if (crews[i].machine === m && !crews[i].runs) names.push("the " + crews[i].name);
      }
    });
    return names.join(" and ");
  }

  function handoffText(h, crews) {
    switch (h.status) {
      case "connected": return h.name + ": connected";
      case "locked": return h.name + ": locked";
      case "not_started": return h.name + ": not started";
      case "waiting":
        var w = waitingFor(h, crews);
        return h.name + ": waiting" + (w ? " for " + w : "");
      default: return h.name + ": " + h.settings_solved + " of " + h.settings_total + " settings";
    }
  }

  function renderHandoffs(list, crews) {
    var root = byId("handoffs");
    clear(root);
    list.forEach(function (h) {
      var box = el("div", "handoff " + h.status);
      var row = el("div", "row");
      row.appendChild(el("span", "name", handoffText(h, crews)));
      box.appendChild(row);
      var bar = el("div", "bar");
      var fill = el("div");
      var done = h.status === "connected" ? 100 :
        Math.round(100 * h.settings_solved / Math.max(1, h.settings_total));
      fill.style.width = done + "%";
      bar.appendChild(fill);
      box.appendChild(bar);
      root.appendChild(box);
    });
  }

  function renderNotes(n) {
    byId("notes").textContent =
      "Gnu's notes: " + n.found + " of " + n.total + " found (" + n.needed + " needed)";
    var pips = byId("pips");
    clear(pips);
    for (var i = 0; i < n.total; i++) pips.appendChild(el("span", "pip" + (i < n.found ? " on" : "")));
  }

  // ------------------------------------------------------------- README

  function triggerHolds(trig, s) {
    var id;
    if (trig.machine_runs) {
      id = trig.machine_runs;
      return s.crews.some(function (c) { return c.machine === id && c.runs; });
    }
    if (trig.handoff_connected) {
      id = trig.handoff_connected;
      return s.finale.handoffs.some(function (h) {
        return h.id === id && h.settings_total > 0 && h.settings_solved >= h.settings_total;
      });
    }
    return false;
  }

  function contributorNames() {
    var list = allContributors || (last ? last.contributors.recent : []);
    var seen = {}, out = [];
    list.forEach(function (c) {
      if (!seen[c.name]) { seen[c.name] = true; out.push(c.name); }
    });
    return out;
  }

  // Build the README into `root`. `all` shows every section and the Maintainers closing.
  function buildReadme(root, s, all) {
    clear(root);
    if (!readme) {
      root.appendChild(el("p", "readme-empty", "Loading the README…"));
      return;
    }
    if (all) {
      root.appendChild(el("h2", "readme-head", readme.title));
      root.appendChild(el("p", "readme-sub", readme.subtitle));
    }
    var secs = readme.sections.filter(function (sec) { return all || triggerHolds(sec.trigger, s); });
    if (!secs.length) {
      root.appendChild(el("p", "readme-empty",
        "Nothing written yet. Sections appear as machines run and handoffs connect."));
    } else {
      var grid = el("div", "readme");
      secs.forEach(function (sec) {
        var d = el("div", "sec");
        d.appendChild(el("h3", null, sec.heading));
        d.appendChild(el("p", null, sec.body));
        grid.appendChild(d);
      });
      root.appendChild(grid);
    }
    if (all) {
      var m = el("div", "maint");
      m.appendChild(el("h3", null, readme.closing.heading));
      m.appendChild(el("p", null, readme.closing.line));
      m.appendChild(el("p", "names", contributorNames().join(" · ")));
      root.appendChild(m);
    }
  }

  // ------------------------------------------------------------- ticker

  var lastTicker = "";
  function renderTicker(contrib) {
    var key = JSON.stringify(contrib.recent.map(function (c) { return [c.name, c.machine]; })) + contrib.total;
    if (key === lastTicker) return;   // keep the scroll going when nothing changed
    lastTicker = key;
    var t = byId("ticker");
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

  // ------------------------------------------------------------- render

  function render(s) {
    var fin = s.finale;
    var state = stateOf(fin);
    document.body.setAttribute("data-state", state);
    renderBanner(state);
    byId("message").textContent = messageFor(state, fin);

    var showMachines = state !== "S4";
    byId("machines").hidden = !showMachines;
    if (showMachines) renderMachines(s.crews, state !== "S0");

    var showFinale = state === "S1" || state === "S2";
    byId("finale").hidden = !showFinale;
    if (showFinale) {
      renderHandoffs(fin.handoffs, s.crews);
      renderNotes(fin.notes);
    }

    var showReadme = state !== "S0";
    byId("readme-card").hidden = !showReadme;
    if (showReadme) {
      byId("readme-title").textContent = state === "S4" ? "" : "README so far";
      byId("readme-title").hidden = state === "S4";
      buildReadme(byId("readme"), s, state === "S4");
    }

    document.querySelector(".ticker").hidden = state === "S4";
    if (state !== "S4") renderTicker(s.contributors);
    if (s.repo_url) byId("repo").href = s.repo_url;
    byId("conn").textContent = "";
    byId("updated").textContent = "Updated " + new Date(s.server_time).toLocaleTimeString();
  }

  // ------------------------------------------------------------- S3: the reveal

  function endReveal() {
    if (!reveal) return;
    reveal.timers.forEach(clearTimeout);
    reveal = null;
    revealing = false;
    byId("reveal").hidden = true;
    clear(byId("reveal"));
    if (last) render(last);
    pollSoon(0);
  }

  function startReveal() {
    if (revealing || !last) return;
    revealing = true;
    reveal = { timers: [] };
    var root = byId("reveal");
    clear(root);
    root.hidden = false;
    refreshContributors();

    var at = 0;
    function step(ms, fn) {
      var when = at;
      reveal.timers.push(setTimeout(fn, when));
      at += ms;
    }

    function show() {
      clear(root);
      for (var i = 0; i < arguments.length; i++) root.appendChild(arguments[i]);
      root.appendChild(el("div", "r-skip", "Press any key to skip"));
    }

    step(T_START, function () {
      show(el("div", "r-big", TXT.starting), el("div", "r-code", TXT.code));
    });

    var list = el("ul", "r-lines");
    var items = REVEAL_LINES.map(function (t) {
      var li = el("li", null, t);
      list.appendChild(li);
      return li;
    });
    REVEAL_LINES.forEach(function (_, i) {
      step(T_LINE, function () {
        if (i === 0) show(list);
        items[i].className = "lit";
      });
    });

    step(T_COOKIE, function () { show(el("div", "r-big", TXT.firstCookie)); });
    step(T_FORTUNE, function () {
      show(el("div", "r-fortune", readme ? readme.closing.fortune : ""));
    });
    step(T_ANGLER, function () { show(el("div", "r-big", TXT.anglerfish)); });

    // The full README scrolls past, then S4.
    reveal.timers.push(setTimeout(function () {
      var wrap = el("div", "r-scroll");
      buildReadme(wrap, last, true);
      show(wrap);
      var vh = window.innerHeight;
      var secs = Math.min(SCROLL_MAX_S, Math.max(SCROLL_MIN_S, (wrap.offsetHeight + vh) / SCROLL_PX_PER_S));
      var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      if (reduce) {
        wrap.style.top = "2vw";
        reveal.timers.push(setTimeout(endReveal, 15000));
        return;
      }
      wrap.style.transform = "translateY(" + vh + "px)";
      void wrap.offsetHeight;   // commit the start position before animating
      wrap.style.transition = "transform " + secs + "s linear";
      wrap.style.transform = "translateY(" + (-wrap.offsetHeight) + "px)";
      reveal.timers.push(setTimeout(endReveal, secs * 1000 + 500));
    }, at));
  }

  function refreshContributors() {
    var ctl = new AbortController();
    var timer = setTimeout(function () { ctl.abort(); }, FETCH_TIMEOUT_MS);
    fetch(CONTRIBUTORS_URL, { cache: "no-store", signal: ctl.signal })
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
      .then(function (j) { allContributors = j.contributors; })
      .catch(function () { /* keep summary.recent as the fallback */ })
      .then(function () { clearTimeout(timer); });
  }

  document.addEventListener("keydown", function (e) {
    if (revealing) { e.preventDefault(); endReveal(); return; }
    if ((e.key === "r" || e.key === "R") && !e.ctrlKey && !e.metaKey && !e.altKey) startReveal();
  });

  // ------------------------------------------------------------- polling

  var pollTimer = null;
  function pollSoon(ms) {
    clearTimeout(pollTimer);
    pollTimer = setTimeout(poll, ms);
  }

  function loadReadme() {
    if (readme) return Promise.resolve();
    var ctl = new AbortController();
    var timer = setTimeout(function () { ctl.abort(); }, FETCH_TIMEOUT_MS);
    return fetch(README_URL, { cache: "no-store", signal: ctl.signal })
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
      .then(function (j) { readme = j; })
      .catch(function () { /* retried on the next poll */ })
      .then(function () { clearTimeout(timer); });
  }

  var firstSummary = true;
  function onSummary(s) {
    var prev = last;
    last = s;
    var started = !!s.finale.started;
    if (firstSummary) {
      firstSummary = false;
      if (replayRequested) {
        forceS4 = !started;
        render(s);
        startReveal();
        return;
      }
      if (started) refreshContributors();
    } else if (prev && !prev.finale.started && started) {
      render(s);
      startReveal();
      return;
    }
    if (started && !allContributors) refreshContributors();
    render(s);
  }

  function poll() {
    if (revealing) { pollSoon(POLL_MS); return; }   // no polling during the reveal
    // Abort after FETCH_TIMEOUT_MS so a stalled request cannot pause polling.
    var ctl = new AbortController();
    var timer = setTimeout(function () { ctl.abort(); }, FETCH_TIMEOUT_MS);
    loadReadme()
      .then(function () { return fetch(SUMMARY_URL, { cache: "no-store", signal: ctl.signal }); })
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
      .then(function (s) {
        if (revealing) { last = s; return; }   // a reveal began while this was in flight
        onSummary(s);
      })
      .catch(function () {
        byId("conn").textContent = "Connection lost, retrying…";
      })
      .then(function () { clearTimeout(timer); pollSoon(POLL_MS); });
  }

  poll();
})();
