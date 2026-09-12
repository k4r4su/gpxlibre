"""GPXlibre — base partagée des points bloqués (Bloc 5).

Serveur minimal auto-hébergeable (NAS, Raspberry Pi...). Stockage SQLite fichier,
aucune dépendance externe au réseau. Trust model v1 : les signalements sont acceptés
tels quels, sans vote ni compte — voir README.md pour le modèle de confiance complet.

Aucune donnée nominative : le `reporter_id` est un identifiant anonyme rotatif généré
et stocké côté client (jamais un compte), et il n'est jamais renvoyé dans les réponses.
"""
from __future__ import annotations

import math
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

DB_PATH = Path(__file__).parent / "data" / "blockages.db"
DB_PATH.parent.mkdir(parents=True, exist_ok=True)

# Un nouveau signalement à moins de ce rayon d'un point existant le "reconfirme" au lieu
# d'en créer un doublon — c'est notre seul mécanisme de confiance en v1 (pas de vote).
DEDUP_RADIUS_METERS = 100.0
# Un point non reconfirmé depuis plus de EXPIRE_AFTER_DAYS est purgé côté serveur ; le
# fondu (>90 j) est une décision d'affichage purement côté client (voir SharedBlockage.swift).
EXPIRE_AFTER_DAYS = 180


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlambda / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


@contextmanager
def db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db() -> None:
    with db() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS blockages (
                id TEXT PRIMARY KEY,
                lat REAL NOT NULL,
                lon REAL NOT NULL,
                note TEXT,
                reporter_id TEXT NOT NULL,
                created_at TEXT NOT NULL,
                last_confirmed_at TEXT NOT NULL
            )
            """
        )


class BlockageReport(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    note: Optional[str] = Field(default=None, max_length=280)
    reporter_id: str = Field(min_length=1, max_length=64)


class Blockage(BaseModel):
    id: str
    lat: float
    lon: float
    note: Optional[str] = None
    created_at: str
    last_confirmed_at: str


app = FastAPI(title="GPXlibre — points bloqués partagés", version="1")


@app.on_event("startup")
def on_startup() -> None:
    init_db()


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/blockages", response_model=Blockage)
def report_blockage(report: BlockageReport) -> dict:
    now = now_iso()
    with db() as conn:
        # Purge passive au fil des écritures : volume attendu trop faible pour justifier
        # une tâche cron séparée dans ce serveur ~100 lignes.
        cutoff = (datetime.now(timezone.utc) - timedelta(days=EXPIRE_AFTER_DAYS)).isoformat()
        conn.execute("DELETE FROM blockages WHERE last_confirmed_at < ?", (cutoff,))

        for row in conn.execute("SELECT * FROM blockages").fetchall():
            if haversine_meters(report.lat, report.lon, row["lat"], row["lon"]) <= DEDUP_RADIUS_METERS:
                conn.execute(
                    "UPDATE blockages SET last_confirmed_at = ?, note = COALESCE(?, note) WHERE id = ?",
                    (now, report.note, row["id"]),
                )
                return dict(conn.execute("SELECT * FROM blockages WHERE id = ?", (row["id"],)).fetchone())

        new_id = str(uuid.uuid4())
        conn.execute(
            "INSERT INTO blockages (id, lat, lon, note, reporter_id, created_at, last_confirmed_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (new_id, report.lat, report.lon, report.note, report.reporter_id, now, now),
        )
        return dict(conn.execute("SELECT * FROM blockages WHERE id = ?", (new_id,)).fetchone())


@app.get("/blockages", response_model=list[Blockage])
def list_blockages(
    min_lat: float = Query(..., ge=-90, le=90),
    min_lon: float = Query(..., ge=-180, le=180),
    max_lat: float = Query(..., ge=-90, le=90),
    max_lon: float = Query(..., ge=-180, le=180),
) -> list[dict]:
    if min_lat > max_lat or min_lon > max_lon:
        raise HTTPException(status_code=400, detail="bbox invalide")
    with db() as conn:
        rows = conn.execute(
            "SELECT * FROM blockages WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?",
            (min_lat, max_lat, min_lon, max_lon),
        ).fetchall()
        return [dict(row) for row in rows]
