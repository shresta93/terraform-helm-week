FROM python:3.13-slim

# Prevents Python from writing .pyc files and buffers stdout - both matter
# for clean, immediate container logs (no output stuck in a buffer).
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN useradd --create-home --uid 1000 appuser

# Copy just the dependency list first so Docker caches this layer - a
# rebuild only reinstalls dependencies when requirements.txt actually
# changes, not on every code edit.
COPY --chown=appuser:appuser requirements.txt . 
RUN pip install --no-cache-dir -r requirements.txt

COPY --chown=appuser:appuser app.py . 
# Run as a non-root user - this image doesn't need root for anything it does.
USER appuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/healthz')" || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
