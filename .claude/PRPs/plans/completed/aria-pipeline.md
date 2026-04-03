# Plan: arIA Import Ordini — Full Pipeline Implementation

## Summary
Build a full-stack AI-powered document extraction system for Italian order documents.
- **Backend**: FastAPI + SQLAlchemy (SQLite) + OpenAI GPT-4o
- **Frontend**: Vue 3 + Vite + TailwindCSS

## Deviations from INSTRUCTIONS.md
- PostgreSQL → SQLite (docker-compose uses sqlite)
- ColPali/pgvector → skipped (no GPU deps); provider ID via GPT-4o VLM
- Agno framework → OpenAI SDK directly
- import_ui/ → frontend/ (path fix in Dockerfile)

## Files to Change
### Backend
- main.py (CREATE)
- app/__init__.py (CREATE)
- app/config.py (CREATE)
- app/database.py (CREATE)
- app/models/__init__.py, provider.py, few_shot_example.py (CREATE)
- app/schemas/__init__.py, provider.py, extraction.py (CREATE)
- app/services/__init__.py, pdf_service.py, llm_service.py, extraction_service.py (CREATE)
- app/routers/__init__.py, upload.py, pipeline.py, providers.py (CREATE)
- app/migrations/ env.py, script.py.mako, versions/001_initial.py (CREATE)

### Frontend
- frontend/package.json (UPDATE - add tailwindcss)
- frontend/vite.config.ts (UPDATE - tailwind plugin + dev proxy)
- frontend/src/style.css (CREATE)
- frontend/src/main.ts (UPDATE)
- frontend/src/App.vue (UPDATE)
- frontend/src/router/index.ts (UPDATE)
- frontend/src/types/index.ts (CREATE)
- frontend/src/api/index.ts (CREATE)
- frontend/src/views/DashboardView.vue (CREATE)
- frontend/src/views/ProcessView.vue (CREATE)
- frontend/src/views/ProvidersView.vue (CREATE)
- frontend/src/views/ProviderDetailView.vue (CREATE)
- frontend/src/components/BBoxCanvas.vue (CREATE)
- frontend/src/components/ExtractionForm.vue (CREATE)

### Infrastructure
- Dockerfile (UPDATE - fix import_ui → frontend)
- .env.example (UPDATE)
