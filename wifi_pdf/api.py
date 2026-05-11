from __future__ import annotations

import os
import threading
from contextlib import asynccontextmanager

from fastapi import FastAPI, Header, HTTPException, Request

from .config import load_settings
from .exceptions import ConfigurationError, PayloadValidationError, RenderingError, WorkDriveError
from .jobs import JobStore
from .logging_utils import configure_logging, resolve_log_dir
from .payload_parser import get_qr_code_only_value
from .pipeline import WifiPdfPipeline
from .utils import batch_timestamp, relative_to_root, sanitize_filename
from .models import parse_payload


settings = load_settings()
logger = configure_logging(resolve_log_dir(settings.output.root_dir / "logs"))
job_store = JobStore(settings.output.root_dir / "jobs", logger)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("WiFi PDF API starting with config %s", relative_to_root(settings.config_path))
    yield
    logger.info("WiFi PDF API shutting down")


app = FastAPI(title="WiFi PDF Generator", version="1.0.0", lifespan=lifespan)


def _validate_api_key(provided_api_key: str | None) -> None:
    expected_api_key = os.getenv(settings.api.api_key_env)
    if expected_api_key and provided_api_key != expected_api_key:
        raise HTTPException(status_code=401, detail="Invalid X-API-Key")


def _build_job_id(building_name: str) -> str:
    return f"{batch_timestamp()}-{sanitize_filename(building_name, default='wifi-batch')}"


def _run_job(job_id: str, payload) -> None:
    try:
        job_store.mark_running(job_id)
        pipeline = WifiPdfPipeline(settings, logger)
        result = pipeline.process_batch(payload)
    except PayloadValidationError as exc:
        logger.warning("Job %s failed payload validation: %s", job_id, exc)
        job_store.mark_failed(job_id, str(exc))
    except ConfigurationError as exc:
        logger.error("Job %s failed configuration: %s", job_id, exc)
        job_store.mark_failed(job_id, str(exc))
    except WorkDriveError as exc:
        logger.error("Job %s failed WorkDrive upload: %s", job_id, exc)
        job_store.mark_failed(job_id, str(exc))
    except RenderingError as exc:
        logger.error("Job %s failed rendering: %s", job_id, exc)
        job_store.mark_failed(job_id, str(exc))
    except Exception as exc:  # pragma: no cover - unexpected runtime failure
        logger.exception("Job %s failed unexpectedly", job_id)
        job_store.mark_failed(job_id, f"Unexpected error: {exc}")
    else:
        job_store.mark_succeeded(job_id, result.to_dict())
        logger.info("Job %s completed successfully", job_id)


@app.get("/health")
@app.get("/pdf/health")
async def health() -> dict[str, str]:
    return {
        "status": "ok",
        "config_path": relative_to_root(settings.config_path),
        "output_root": relative_to_root(settings.output.root_dir),
    }


@app.get("/jobs/{job_id}")
@app.get("/pdf/jobs/{job_id}")
async def get_job(job_id: str) -> dict:
    job = job_store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")
    return job


@app.post("/webhooks/zoho/wifi-pdfs")
@app.post("/pdf/webhooks/zoho/wifi-pdfs")
async def create_wifi_pdfs(
    request: Request,
    x_api_key: str | None = Header(default=None, alias="X-API-Key"),
) -> dict:
    _validate_api_key(x_api_key)

    try:
        payload = await request.json()
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Invalid JSON body: {exc}") from exc

    try:
        batch = parse_payload(payload)
    except PayloadValidationError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    qr_flag_raw = get_qr_code_only_value(payload) if isinstance(payload, dict) else None
    logger.info(
        "Accepted WiFi PDF request for building '%s': records=%s template=%s qr_code_only=%s qr_flag_raw=%r passwords_generated=%s crm_password_update=%s",
        batch.building_name,
        len(batch.records),
        batch.template_name,
        batch.qr_code_only,
        qr_flag_raw,
        batch.passwords_generated,
        batch.update_crm_password_fields,
    )

    job_id = _build_job_id(batch.building_name)
    job_store.create(
        job_id,
        {
            "building_name": batch.building_name,
            "record_count": len(batch.records),
            "template_name": batch.template_name,
            "workdrive_enabled": settings.workdrive.enabled,
        },
    )

    worker = threading.Thread(target=_run_job, args=(job_id, batch), daemon=True)
    worker.start()

    return {
        "status": "accepted",
        "job_id": job_id,
        "building_name": batch.building_name,
        "record_count": len(batch.records),
        "template_name": batch.template_name,
        "job_status_url": f"/jobs/{job_id}",
    }
