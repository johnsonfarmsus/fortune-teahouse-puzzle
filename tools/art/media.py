# SPDX-License-Identifier: AGPL-3.0-or-later
"""Client for the steam-machine's media API, and provenance for what it renders.

Only a machine on Trevor's network can reach the API, so the address and key
come from the environment and never from the repo (the private handoff file
says where to find them):

    MEDIA_API_URL   base URL of the media API
    MEDIA_API_KEY   the edge key, read into the environment at use time
    MEDIA_API_USER  whose library the renders land in

Rules from the handoff: media API only (never ComfyUI directly), one render at
a time, change nothing on the box, stop on a 502.

A job only moves from "finishing" to done when someone polls it. If a run is
interrupted, poll ``/api/media/job?id=<id>`` once (the id is in
``/api/media/queue``) or the next ``create`` refuses to start.
"""

from __future__ import annotations

import ast
import io
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

# The only image models DESIGN.md allows (Apache 2.0). A render whose graph
# loads anything else is refused before it can ship.
PINNED_MODELS = {
    "z_image_turbo_bf16.safetensors": "Z-Image-Turbo",
    "qwen_image_2512_fp8_e4m3fn.safetensors": "Qwen-Image-2512",
    "qwen_image_edit_2511_fp8mixed.safetensors": "Qwen-Image-Edit-2511",
}
PINNED_LORAS = {
    "Qwen-Image-2512-Lightning-8steps-V1.0-bf16.safetensors": "Qwen-Image-2512-Lightning 8-step",
    "Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors": "Qwen-Image-Edit-2511-Lightning 4-step",
}


class MediaError(RuntimeError):
    pass


class Client:
    def __init__(self, url: str | None = None, key: str | None = None, user: str | None = None):
        self.url = (url or os.environ.get("MEDIA_API_URL", "")).rstrip("/")
        self.key = key or os.environ.get("MEDIA_API_KEY", "")
        self.user = user or os.environ.get("MEDIA_API_USER", "")
        if not (self.url and self.key and self.user):
            raise MediaError("set MEDIA_API_URL, MEDIA_API_KEY and MEDIA_API_USER (see docs/ART-BRIEF.md)")

    def _request(self, method: str, path: str, params: dict[str, str] | None = None,
                 body: Any = None, timeout: float = 60) -> bytes:
        url = self.url + path + ("?" + urllib.parse.urlencode(params) if params else "")
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("x-pairvis-edge-key", self.key)
        req.add_header("remote-user", self.user)
        if data is not None:
            req.add_header("content-type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.read()
        except urllib.error.HTTPError as e:
            if e.code == 502:
                raise MediaError("502: the render backend is down; stop and tell Trevor") from e
            raise MediaError(f"{method} {path}: HTTP {e.code}") from e

    def _json(self, method: str, path: str, **kw: Any) -> Any:
        return json.loads(self._request(method, path, **kw))

    def queue(self) -> dict[str, Any]:
        return self._json("GET", "/api/media/queue")

    def create(self, kind: str, prompt: str, **opts: Any) -> dict[str, Any]:
        """Start one render and wait for it. Returns the library item {name, kind}."""
        q = self.queue()
        if q.get("mine"):
            raise MediaError("a render of ours is already queued; one at a time")
        r = self._json("POST", "/api/media/create", body={"kind": kind, "prompt": prompt, **opts})
        if "done" in r:
            return r["done"]
        job = r["job"]
        while True:
            s = self._json("GET", "/api/media/job", params={"id": job}, timeout=30)
            if s["status"] == "done":
                return s["item"]
            if s["status"] == "error":
                raise MediaError(f"render failed: {s.get('error')}")
            time.sleep(3)

    def file(self, item: dict[str, Any]) -> bytes:
        return self._request("GET", "/api/media/file", params={"name": item["name"], "kind": item["kind"]}, timeout=120)

    def meta(self, item: dict[str, Any]) -> dict[str, Any]:
        """The stored metadata for one of our library items."""
        lib = self._json("GET", "/api/media/library", timeout=60)
        for it in lib.get(item["kind"], []):
            if it.get("name") == item["name"]:
                return parse_meta(it.get("meta"))
        raise MediaError(f"{item['name']} is not in the library")


def parse_meta(meta: Any) -> dict[str, Any]:
    """The library stores metadata as a Python literal string; read it safely."""
    if isinstance(meta, dict):
        return meta
    if not meta:
        return {}
    try:
        value = ast.literal_eval(meta)
    except (ValueError, SyntaxError):
        try:
            value = json.loads(meta)
        except ValueError:
            return {}
    return value if isinstance(value, dict) else {}


def graph_from_png(data: bytes) -> dict[str, Any]:
    """The ComfyUI graph that ComfyUI's SaveImage embeds in the PNG ('prompt' text chunk).

    The library's ``comfy_prompt`` field is only a job id, and the handoff rules
    out asking ComfyUI for it, so the file itself is the record."""
    from PIL import Image  # only needed here; keeps the rest importable without Pillow

    try:
        text = Image.open(io.BytesIO(data)).info.get("prompt")
    except OSError:
        return {}
    try:
        graph = json.loads(text) if text else {}
    except ValueError:
        return {}
    return graph if isinstance(graph, dict) else {}


def provenance(meta: dict[str, Any], graph: dict[str, Any] | None = None) -> dict[str, Any]:
    """Model, LoRAs, seed and sampler settings from a render's ComfyUI graph."""
    if graph is None:
        graph = meta.get("comfy_prompt") or {}
        if isinstance(graph, str):
            graph = parse_meta(graph)
    models: list[str] = []
    loras: list[str] = []
    seeds: list[int] = []
    steps = cfg = None
    for node in graph.values() if isinstance(graph, dict) else []:
        if not isinstance(node, dict):
            continue
        cls = str(node.get("class_type", ""))
        inputs = node.get("inputs", {}) or {}
        for key in ("unet_name", "ckpt_name"):
            if isinstance(inputs.get(key), str):
                models.append(inputs[key])
        if "lora" in cls.lower() and isinstance(inputs.get("lora_name"), str):
            loras.append(inputs["lora_name"])
        for key in ("seed", "noise_seed"):
            if isinstance(inputs.get(key), int):
                seeds.append(inputs[key])
        if cls.startswith("KSampler"):
            steps = inputs.get("steps", steps)
            cfg = inputs.get("cfg", cfg)
    return {
        "prompt": meta.get("prompt"),
        "mode": meta.get("mode"),
        "quality": meta.get("quality"),
        "shape": meta.get("shape"),
        "models": [PINNED_MODELS.get(m, m) for m in models],
        "model_files": models,
        "loras": [PINNED_LORAS.get(name, name) for name in loras],
        "seed": seeds[0] if len(set(seeds)) == 1 else seeds,
        "steps": steps,
        "cfg": cfg,
    }


def check_pinned(record: dict[str, Any]) -> list[str]:
    """Problems that stop a render from shipping (DESIGN.md: pinned models only)."""
    problems = []
    if not record.get("model_files"):
        problems.append("no model found in the render graph")
    for m in record.get("model_files", []):
        if m not in PINNED_MODELS:
            problems.append(f"model {m} is not pinned")
    for lora in record.get("loras", []):
        if lora not in PINNED_LORAS.values():
            problems.append(f"LoRA {lora} is not pinned")
    if not isinstance(record.get("seed"), int):
        problems.append("no single seed in the render graph")
    return problems


def render(client: Client, kind: str, prompt: str, out: Path, **opts: Any) -> dict[str, Any]:
    """Render, save the file, and return its provenance record (also saved as <out>.json)."""
    item = client.create(kind, prompt, **opts)
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    data = client.file(item)
    out.write_bytes(data)
    record = {"library_item": item["name"], **provenance(client.meta(item), graph_from_png(data))}
    record["problems"] = check_pinned(record)
    out.with_suffix(out.suffix + ".json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    return record
