# Coach Backend (Gerüst)

Stand Phase 1: Grundgerüst mit Health-Check. In Phase 2 wird daraus der Cloudflare Worker, der die KI-Aufrufe
(Gemini, Ausweichstufe Groq) weiterreicht und die KI-Keys hält. Garmin ruft die App direkt über die offizielle
Personal API ab (siehe `docs/decisions.md`).

## Entwicklung

```sh
uv sync
uv run ruff check . && uv run ruff format --check .
uv run pytest
uv run uvicorn coach_backend.main:app --reload   # http://127.0.0.1:8000/v1/health
```
