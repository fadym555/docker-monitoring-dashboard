.PHONY: up down restart logs ps test clean

up:        ## Start the stack and wait until every service is healthy
	docker compose up -d --wait

down:      ## Stop the stack, keep the data
	docker compose down

restart:   ## Restart every service
	docker compose restart

logs:      ## Follow the logs
	docker compose logs -f --tail=100

ps:        ## Show service status
	docker compose ps

test:      ## Run the end-to-end checks against the running stack
	bash tests/smoke.sh

clean:     ## Remove the stack and all stored metrics and dashboards state
	docker compose down -v
