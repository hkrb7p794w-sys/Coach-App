# Coach Backend

Eigenständiger Python-Dienst für die Coach-App: Garmin-Sync, regelbasierte Auswertung und KI-Aufrufe
(Gemini, Ausweichstufe Groq). API-Keys liegen nur hier, nie in der App.

Stand Phase 1: Grundgerüst mit Health-Check. Garmin, KI und Deployment-Anleitung folgen in Phase 2.

## Entwicklung

```sh
uv sync
uv run ruff check . && uv run ruff format --check .
uv run pytest
uv run uvicorn coach_backend.main:app --reload   # http://127.0.0.1:8000/v1/health
```
