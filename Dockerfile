# Stage 1: Build virtual environment dependencies
FROM python:3.12-slim@sha256:69b18751db56e8feef922f32aa7b17fbef282594a2b9eb0201ae6b4b47000d8d AS builder

WORKDIR /build

COPY app/requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: Distroless-style hardened runtime container
FROM python:3.12-slim@sha256:69b18751db56e8feef922f32aa7b17fbef282594a2b9eb0201ae6b4b47000d8d AS runner

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application code
COPY app/ /app/

# Create and switch to an unprivileged non-root user (UID 10001)
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -s /usr/sbin/nologin -d /app appuser && \
    chown -R appuser:appgroup /app

USER 10001:10001

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
