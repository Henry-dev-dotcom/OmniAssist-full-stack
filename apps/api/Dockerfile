FROM python:3.13-slim
COPY --from=ghcr.io/astral-sh/uv:0.13.1 /uv /usr/local/bin/uv
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY alembic.ini ./
COPY migrations ./migrations
COPY src ./src
RUN useradd --system --uid 10001 omni && chown -R omni /app
USER omni
EXPOSE 8000
# Single API instance in the MVP: migrate, then serve. Run several instances only after
# moving migrations to a separate release step.
CMD ["sh", "-c", "uv run --no-sync alembic upgrade head && exec uv run --no-sync uvicorn src.main:app --host 0.0.0.0 --port 8000 --proxy-headers"]
