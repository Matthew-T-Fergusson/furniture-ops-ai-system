.PHONY: up down psql guardrails migrate-status migrate-validate migrate-apply python-governance ci-smoke
up:
	docker compose up -d

down:
	docker compose down

psql:
	docker compose exec postgres psql -U $${POSTGRES_USER:-furniture} -d $${POSTGRES_DB:-furniture_ops_poc}

guardrails:
	docker compose exec postgres psql -U $${POSTGRES_USER:-furniture} -d $${POSTGRES_DB:-furniture_ops_poc} -c "select * from furniture_db_guardrail_summary;"

migrate-status:
	./scripts/db_cli.py migrate status

migrate-validate:
	./scripts/db_cli.py migrate validate

migrate-apply:
	./scripts/db_cli.py migrate apply

python-governance:
	./scripts/validate_python_governance.py

ci-smoke: python-governance
	./scripts/ci_smoke.sh
