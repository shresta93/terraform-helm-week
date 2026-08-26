import os
import logging
from contextlib import contextmanager

from flask import Flask, jsonify, request
import psycopg2
import psycopg2.extras
#adding a test comment
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

DATABASE_URL = os.environ.get("DATABASE_URL")

_schema_ready = False


@contextmanager
def get_db_connection():
    if not DATABASE_URL:
        raise RuntimeError("DATABASE_URL is not set")
    conn = psycopg2.connect(DATABASE_URL)
    try:
        yield conn
    finally:
        conn.close()


def ensure_schema():
    """Create the tasks table if it doesn't exist yet. Safe to call repeatedly."""
    global _schema_ready
    if _schema_ready:
        return
    with get_db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS tasks (
                    id SERIAL PRIMARY KEY,
                    title TEXT NOT NULL,
                    done BOOLEAN NOT NULL DEFAULT FALSE,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
                )
                """
            )
        conn.commit()
    _schema_ready = True


@app.get("/healthz")
def healthz():
    # Deliberately does NOT touch the database. This answers "is the
    # process alive", which is what Kubernetes' liveness/readiness probes
    # need. A database outage shouldn't make Kubernetes kill and restart
    # otherwise-healthy app pods - that would turn one outage into two.
    return jsonify(status="ok"), 200


@app.get("/tasks")
def list_tasks():
    try:
        ensure_schema()
        with get_db_connection() as conn:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute("SELECT id, title, done, created_at FROM tasks ORDER BY id")
                rows = cur.fetchall()
        return jsonify([dict(r) for r in rows]), 200
    except Exception as exc:
        logger.exception("failed to list tasks")
        return jsonify(error="database unavailable", detail=str(exc)), 503


@app.post("/tasks")
def create_task():
    body = request.get_json(silent=True) or {}
    title = body.get("title")
    if not title:
        return jsonify(error="title is required"), 400
    try:
        ensure_schema()
        with get_db_connection() as conn:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(
                    "INSERT INTO tasks (title) VALUES (%s) RETURNING id, title, done, created_at",
                    (title,),
                )
                row = cur.fetchone()
            conn.commit()
        return jsonify(dict(row)), 201
    except Exception as exc:
        logger.exception("failed to create task")
        return jsonify(error="database unavailable", detail=str(exc)), 503


@app.patch("/tasks/<int:task_id>")
def update_task(task_id):
    body = request.get_json(silent=True) or {}
    if "done" not in body:
        return jsonify(error="done (boolean) is required"), 400
    try:
        ensure_schema()
        with get_db_connection() as conn:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(
                    "UPDATE tasks SET done = %s WHERE id = %s RETURNING id, title, done, created_at",
                    (bool(body["done"]), task_id),
                )
                row = cur.fetchone()
            conn.commit()
        if row is None:
            return jsonify(error="not found"), 404
        return jsonify(dict(row)), 200
    except Exception as exc:
        logger.exception("failed to update task")
        return jsonify(error="database unavailable", detail=str(exc)), 503


@app.delete("/tasks/<int:task_id>")
def delete_task(task_id):
    try:
        ensure_schema()
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM tasks WHERE id = %s", (task_id,))
                deleted = cur.rowcount
            conn.commit()
        if deleted == 0:
            return jsonify(error="not found"), 404
        return "", 204
    except Exception as exc:
        logger.exception("failed to delete task")
        return jsonify(error="database unavailable", detail=str(exc)), 503


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
