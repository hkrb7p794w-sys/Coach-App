"""FastAPI-Anwendung. Phase 1: nur der Health-Check, damit CI und Deployment testbar sind."""

from fastapi import FastAPI

from coach_backend import __version__


def create_app() -> FastAPI:
    app = FastAPI(title="Coach Backend", version=__version__)

    @app.get("/v1/health")
    def health() -> dict[str, str]:
        return {"status": "ok", "version": __version__}

    return app


app = create_app()
