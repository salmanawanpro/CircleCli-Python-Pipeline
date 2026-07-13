# --- builder stage ---
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --target=/install -r requirements.txt

# --- runtime stage ---
FROM python:3.12-slim
WORKDIR /app

RUN useradd --create-home --uid 10001 appuser

COPY --from=builder /install /usr/local/lib/python3.12/site-packages
COPY app/ ./app/

ENV PYTHONPATH=/usr/local/lib/python3.12/site-packages \
    PORT=5000 \
    PYTHONUNBUFFERED=1

EXPOSE 5000
USER appuser

HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import os,urllib.request; urllib.request.urlopen(f'http://127.0.0.1:{os.environ.get(\"PORT\",\"5000\")}/health')" || exit 1

CMD ["sh", "-c", "gunicorn -b 0.0.0.0:${PORT:-5000} app.app:app"]
