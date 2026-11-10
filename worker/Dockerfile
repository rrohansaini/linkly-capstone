FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN groupadd --gid 10001 app \
 && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY worker.py healthcheck.py ./

# Reports directory owned by 10001. A NEW named volume mounted here copies this
# ownership on first use, which fixes "Permission denied" (incident 06).
RUN mkdir /reports && chown 10001:10001 /reports

USER 10001:10001

HEALTHCHECK --interval=10s --timeout=4s --start-period=10s --retries=3 \
  CMD ["python", "/app/healthcheck.py"]

CMD ["python", "/app/worker.py"]
