# SPDX-License-Identifier: AGPL-3.0-or-later
"""FastAPI application: JSON API under /api/v1 plus the static big-screen page."""
from __future__ import annotations

import hmac
import html
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterator

from fastapi import APIRouter, Depends, FastAPI, Header, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from starlette.exceptions import HTTPException as StarletteHTTPException
from pydantic import BaseModel, Field, field_validator

from . import service
from .config import NUDGES, Settings, fmt_time, parse_time
from .db import connect, init_db
from .ratelimit import TokenBuckets
from .service import ApiError

STATIC_DIR = Path(__file__).resolve().parent.parent / "static"
GUESS_PATHS = ("/api/v1/finale/notes", "/api/v1/finale/start")


# ------------------------------------------------------------------- schemas

class DeviceRef(BaseModel):
    device_id: str

    @field_validator("device_id")
    @classmethod
    def _uuid(cls, v: str) -> str:
        return service.check_device_id(v)


class DeviceIn(DeviceRef):
    display_name: str | None = Field(default=None, max_length=200)
    crew: str | None = None

    @field_validator("display_name")
    @classmethod
    def _name(cls, v: str | None) -> str | None:
        return service.clean_display_name(v)


class SolveIn(DeviceRef):
    credited: bool = True


class SettingIn(DeviceRef):
    setting_index: int


class CodeIn(DeviceRef):
    code: str = Field(max_length=100)


class HintIn(DeviceRef):
    to_crew: str
    nudge_id: str


class SafetyNetIn(BaseModel):
    at: str | None = None  # ISO 8601 with offset, or null to clear

    @field_validator("at")
    @classmethod
    def _at(cls, v: str | None) -> str | None:
        if v is not None:
            parse_time(v)
        return v


class LineIn(BaseModel):
    started: bool


class ResetIn(BaseModel):
    confirm: str
    scope: str = "progress"


# -------------------------------------------------------------- dependencies

class Ctx:
    def __init__(self, conn, settings: Settings, clock: Callable[[], datetime]):
        self.conn = conn
        self.settings = settings
        self.clock = clock

    @property
    def now(self) -> datetime:
        return self.clock()

    @property
    def now_str(self) -> str:
        return fmt_time(self.now)


def get_ctx(request: Request) -> Iterator[Ctx]:
    st = request.app.state
    conn = connect(st.settings.database_path)
    try:
        yield Ctx(conn, st.settings, st.clock)
    finally:
        conn.close()


def require_admin(request: Request, x_admin_secret: str | None = Header(default=None)) -> None:
    secret = request.app.state.settings.admin_secret
    if not secret:
        raise ApiError(503, "admin_disabled", "ADMIN_SECRET is not set on the server.")
    if x_admin_secret is None or not hmac.compare_digest(x_admin_secret.encode(), secret.encode()):
        raise ApiError(401, "bad_admin_secret", "Missing or wrong X-Admin-Secret header.")


# -------------------------------------------------------------------- routes

api = APIRouter(prefix="/api/v1")
admin = APIRouter(prefix="/api/v1/admin", dependencies=[Depends(require_admin)])


@api.get("/health")
def health() -> dict:
    return {"ok": True}


@api.post("/devices")
def register_device(body: DeviceIn, ctx: Ctx = Depends(get_ctx)) -> dict:
    sent = body.model_fields_set - {"device_id"}
    fields = {k: getattr(body, k) for k in sent}
    return service.upsert_device(ctx.conn, body.device_id, fields, ctx.now_str)


@api.get("/crews/{machine}")
def get_crew(machine: str, ctx: Ctx = Depends(get_ctx)) -> dict:
    return service.crew_view(ctx.conn, service.check_machine(machine))


@api.post("/crews/{machine}/parts/{part}/solve")
def solve_part(machine: str, part: str, body: SolveIn, ctx: Ctx = Depends(get_ctx)) -> dict:
    service.check_machine(machine)
    service.check_part(part)
    return service.solve_part(ctx.conn, body.device_id, machine, part, ctx.now_str, body.credited)


@api.get("/contributors")
def get_contributors(machine: str | None = None, ctx: Ctx = Depends(get_ctx)) -> dict:
    if machine is not None:
        service.check_machine(machine)
    items = service.contributors(ctx.conn, machine)
    return {"total": len(items), "contributors": items}


@api.get("/finale")
def get_finale(ctx: Ctx = Depends(get_ctx)) -> dict:
    return service.finale_view(ctx.conn, ctx.settings, ctx.now)


@api.post("/finale/handoffs/{handoff_id}/settings")
def post_setting(handoff_id: str, body: SettingIn, ctx: Ctx = Depends(get_ctx)) -> dict:
    return service.solve_setting(ctx.conn, ctx.settings, ctx.now, handoff_id,
                                 body.device_id, body.setting_index)


@api.post("/finale/notes")
def post_note(body: CodeIn, ctx: Ctx = Depends(get_ctx)) -> dict:
    return service.submit_note(ctx.conn, ctx.settings, ctx.now, body.device_id, body.code)


@api.post("/finale/start")
def post_start(body: CodeIn, ctx: Ctx = Depends(get_ctx)) -> dict:
    return service.start_line(ctx.conn, ctx.settings, ctx.now, body.device_id, body.code)


@api.get("/hints/nudges")
def get_nudges() -> dict:
    return {"nudges": list(NUDGES)}


@api.post("/hints", status_code=200)
def post_hint(body: HintIn, ctx: Ctx = Depends(get_ctx)) -> dict:
    return service.push_hint(ctx.conn, body.device_id, body.to_crew, body.nudge_id, ctx.now_str)


@api.get("/hints")
def get_hints(crew: str, after_id: int | None = Query(default=None, ge=0), ctx: Ctx = Depends(get_ctx)) -> dict:
    service.check_machine(crew)
    return {"crew": crew, "hints": service.list_hints(ctx.conn, crew, after_id)}


@api.get("/summary")
def get_summary(ctx: Ctx = Depends(get_ctx)) -> dict:
    return service.summary(ctx.conn, ctx.settings, ctx.now)


@admin.get("/state")
def admin_state(ctx: Ctx = Depends(get_ctx)) -> dict:
    s = ctx.settings
    return {
        "finale": service.finale_view(ctx.conn, s, ctx.now),
        "config": {
            "notes_total": s.notes_total,
            "notes_k": s.gnu_notes_k,
            "handoff_settings_total": s.handoff_settings_total,
            "env_safety_net_at": fmt_time(s.finale_safety_net_at) if s.finale_safety_net_at else None,
        },
    }


@admin.put("/finale/safety-net")
def admin_safety_net(body: SafetyNetIn, ctx: Ctx = Depends(get_ctx)) -> dict:
    with service.tx(ctx.conn):
        # "none" records an explicit clear that also hides the env default.
        service.set_setting(ctx.conn, "safety_net_at",
                            fmt_time(parse_time(body.at)) if body.at else "none")
    return service.finale_view(ctx.conn, ctx.settings, ctx.now)


def _override(value: str | None):
    def handler(ctx: Ctx = Depends(get_ctx)) -> dict:
        with service.tx(ctx.conn):
            service.set_setting(ctx.conn, "finale_override", value)
        return service.finale_view(ctx.conn, ctx.settings, ctx.now)
    return handler


admin.post("/finale/open")(_override("open"))
admin.post("/finale/close")(_override("closed"))
admin.post("/finale/auto")(_override(None))


@admin.post("/finale/line")
def admin_line(body: LineIn, ctx: Ctx = Depends(get_ctx)) -> dict:
    with service.tx(ctx.conn):
        service.set_setting(ctx.conn, "line_started_at", ctx.now_str if body.started else None)
    return service.finale_view(ctx.conn, ctx.settings, ctx.now)


@admin.post("/reset")
def admin_reset(body: ResetIn, ctx: Ctx = Depends(get_ctx)) -> dict:
    if body.confirm != "reset":
        raise ApiError(400, "confirm_required", 'Send {"confirm": "reset"}.')
    if body.scope not in ("progress", "all"):
        raise ApiError(400, "bad_scope", 'scope must be "progress" or "all".')
    service.reset(ctx.conn, body.scope)
    return {"reset": body.scope}


# ----------------------------------------------------------------------- app

def _client_ip(request: Request, trust_proxy: bool) -> str:
    if trust_proxy:
        fwd = request.headers.get("x-forwarded-for")
        if fwd:
            # Rightmost entry: the hop our own reverse proxy appended. Earlier
            # entries are client-controlled and can be spoofed.
            return fwd.split(",")[-1].strip()
    return request.client.host if request.client else "unknown"


def _error(status: int, code: str, message: str, headers: dict | None = None) -> JSONResponse:
    return JSONResponse({"error": {"code": code, "message": message}}, status_code=status,
                        headers=headers)


def create_app(settings: Settings | None = None,
               clock: Callable[[], datetime] | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    app = FastAPI(title="Fortune Teahouse scoreboard", version="1.0.0",
                  docs_url="/api/docs", openapi_url="/api/openapi.json", redoc_url=None)
    app.state.settings = settings
    app.state.clock = clock or (lambda: datetime.now(timezone.utc))
    init_db(settings)

    default_bucket = TokenBuckets(settings.rate_limit_rps, settings.rate_limit_burst)
    guess_bucket = TokenBuckets(10.0 if settings.rate_limit_rps > 0 else 0, 30)

    @app.exception_handler(ApiError)
    async def _api_error(_: Request, exc: ApiError) -> JSONResponse:
        return _error(exc.status, exc.code, exc.message)

    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, exc: RequestValidationError) -> JSONResponse:
        details = [{"loc": [str(p) for p in e["loc"]], "msg": str(e["msg"])} for e in exc.errors()]
        body = {"error": {"code": "validation_error", "message": "Invalid request.", "details": details}}
        return JSONResponse(body, status_code=422)

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        codes = {404: "not_found", 405: "method_not_allowed"}
        messages = {404: "No such endpoint.", 405: "Method not allowed."}
        code = codes.get(exc.status_code, "http_error")
        message = messages.get(exc.status_code) or (exc.detail if isinstance(exc.detail, str) else "Error.")
        return _error(exc.status_code, code, message, dict(exc.headers or {}))

    @app.middleware("http")
    async def rate_limit(request: Request, call_next):
        ip = _client_ip(request, settings.trust_proxy)
        limited = not default_bucket.allow(ip)
        if not limited and request.method == "POST" and request.url.path in GUESS_PATHS:
            limited = not guess_bucket.allow(ip)
        if limited:
            return _error(429, "rate_limited", "Too many requests. Slow down.", {"Retry-After": "1"})
        return await call_next(request)

    # Added last so it is outermost: preflights and 429s still carry CORS headers.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_methods=["GET", "POST", "PUT", "OPTIONS"],
        allow_headers=["Content-Type", "X-Admin-Secret"],
        max_age=600,
    )

    app.include_router(api)
    app.include_router(admin)

    bigscreen_html = (STATIC_DIR / "bigscreen" / "index.html").read_text(encoding="utf-8")
    page = bigscreen_html.replace("{{REPO_URL}}", html.escape(settings.repo_url, quote=True))

    @app.get("/", include_in_schema=False)
    def root() -> RedirectResponse:
        return RedirectResponse("bigscreen/")

    @app.get("/bigscreen", include_in_schema=False)
    def bigscreen_redirect() -> RedirectResponse:
        return RedirectResponse("bigscreen/")

    @app.get("/bigscreen/", include_in_schema=False)
    @app.get("/bigscreen/index.html", include_in_schema=False)
    def bigscreen() -> HTMLResponse:
        return HTMLResponse(page)

    app.mount("/bigscreen", StaticFiles(directory=STATIC_DIR / "bigscreen"), name="bigscreen")
    return app

