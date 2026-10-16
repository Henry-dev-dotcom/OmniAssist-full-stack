.PHONY: check web-check lint typecheck test-pwa build api-check

check: web-check api-check

web-check: lint typecheck test-pwa build

lint:
	pnpm lint

typecheck:
	pnpm typecheck

test-pwa:
	pnpm test:pwa

build:
	pnpm build

api-check:
	cd apps/api && uv sync --frozen && uv run ruff check src tests && uv run ruff format --check src tests && uv run mypy && uv run pytest -q
