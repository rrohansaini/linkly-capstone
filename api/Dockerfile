FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# fixed non-root user (UID/GID 10001), no home, no login shell
RUN groupadd --gid 10001 app \
 && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app

# dependencies first so this layer is cached until requirements.txt changes
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app.py healthcheck.py ./

USER 10001:10001
EXPOSE 5000

HEALTHCHECK --interval=10s --timeout=4s --start-period=15s --retries=3 \
  CMD ["python", "/app/healthcheck.py"]

# --preload: init_schema() runs once in the master, not racing in every worker
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--preload", "--access-logfile", "-", "app:app"]
