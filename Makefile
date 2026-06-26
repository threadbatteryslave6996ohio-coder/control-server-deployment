COMPOSE ?= docker compose
STACK_NAME ?= control-server
ENV_FILE ?= .env
TARGETS_DIR ?= prometheus/targets
TARGETS_FILE ?= $(TARGETS_DIR)/managed-hosts.yml

.PHONY: help init bootstrap up up-grafana down restart ps logs status config validate targets

help:
	@printf '%s\n' \
		'Available targets:' \
		'  init          Prepare .env and the default Prometheus target file' \
		'  bootstrap     Prepare local env and target files' \
		'  up            Start Prometheus and Loki' \
		'  up-grafana    Start Prometheus, Loki, and Grafana' \
		'  down          Stop the stack and remove containers' \
		'  restart       Restart the stack' \
		'  ps            Show running services' \
		'  logs          Follow service logs' \
		'  status        Show service status' \
		'  config        Render the effective compose config' \
		'  validate      Check compose config and file layout' \
		'  targets       Show discovered Prometheus target files'

init:
	@test -f "$(ENV_FILE)" || cp .env.example "$(ENV_FILE)"
	@mkdir -p "$(TARGETS_DIR)"
	@test -f "$(TARGETS_FILE)" || cp "$(TARGETS_DIR)/managed-hosts.yml.example" "$(TARGETS_FILE)"
	@printf '%s\n' "Init complete. Edit $(ENV_FILE) and $(TARGETS_FILE)."

bootstrap:
	@$(MAKE) init
	@printf '%s\n' "Bootstrap complete. Add more Prometheus target files under $(TARGETS_DIR)/ as needed."

up:
	$(COMPOSE) --project-name "$(STACK_NAME)" up -d

up-grafana:
	$(COMPOSE) --project-name "$(STACK_NAME)" --profile grafana up -d

down:
	$(COMPOSE) --project-name "$(STACK_NAME)" down

restart:
	$(COMPOSE) --project-name "$(STACK_NAME)" restart

ps:
	$(COMPOSE) --project-name "$(STACK_NAME)" ps

logs:
	$(COMPOSE) --project-name "$(STACK_NAME)" logs -f

status:
	$(COMPOSE) --project-name "$(STACK_NAME)" ps

config:
	$(COMPOSE) --project-name "$(STACK_NAME)" config

validate:
	@test -f docker-compose.yml
	@test -f prometheus/prometheus.yml
	@test -f loki/loki-config.yaml
	@$(COMPOSE) --project-name "$(STACK_NAME)" config >/dev/null

targets:
	@test -d "$(TARGETS_DIR)" && find "$(TARGETS_DIR)" -maxdepth 1 -type f | sort || true
