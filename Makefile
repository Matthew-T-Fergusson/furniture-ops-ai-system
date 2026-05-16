.PHONY: up down psql guardrails
up:
	docker compose up -d

down:
	docker compose down

psql:
	docker compose exec postgres psql -U $${POSTGRES_USER:-furniture} -d $${POSTGRES_DB:-furniture_ops_poc}

guardrails:
	docker compose exec postgres psql -U $${POSTGRES_USER:-furniture} -d $${POSTGRES_DB:-furniture_ops_poc} -c "select * from furniture_db_guardrail_summary;"
