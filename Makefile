.PHONY: up down psql guardrails python-governance ci-smoke
up:
	docker compose up -d

down:
	docker compose down

psql:
	docker compose exec postgres psql -U $${POSTGRES_USER:-furniture} -d $${POSTGRES_DB:-furniture_ops_poc}

guardrails:
	docker compose exec postgres psql -U $${POSTGRES_USER:-furniture} -d $${POSTGRES_DB:-furniture_ops_poc} -c "select * from furniture_db_guardrail_summary;"

python-governance:
	./scripts/validate_python_governance.py

ci-smoke: python-governance
	./scripts/ci_smoke.sh
