# OpenAPI

FastAPI generates the schema. Export it with:

```
cd apps/api && uv run python -c "import json; from src.main import app; print(json.dumps(app.openapi(), indent=2))" > ../../packages/contracts/openapi/openapi.json
```

Commit `openapi.json` when routes change. Client DTOs must match it.
