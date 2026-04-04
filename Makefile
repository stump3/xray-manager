# ─────────────────────────────────────────────────────────────────────────────
#  Xray Manager — Makefile
#  Сборка: make          → собрать xray-manager.sh из modules/
#  Проверка: make check  → shellcheck по всем модулям
#  Релиз: make release   → сборка + chmod + sha256
# ─────────────────────────────────────────────────────────────────────────────

MODULES := $(sort $(wildcard modules/*.sh))
OUT     := xray-manager.sh
VERSION := $(shell grep '^MANAGER_VERSION=' modules/01-constants.sh | cut -d'"' -f2)

.PHONY: build check release clean fmt

## Основная цель: собрать монолит из модулей
build: $(MODULES)
	@echo "  BUILD  $(OUT)  (v$(VERSION))"
	@cat $(MODULES) > $(OUT)
	@bash -n $(OUT) \
		&& printf "  SYNTAX ✓  %d lines\n" "$$(wc -l < $(OUT))" \
		|| { echo "  SYNTAX ✗  abort"; rm -f $(OUT); exit 1; }

## Запустить shellcheck по всем модулям
check:
	@command -v shellcheck >/dev/null || { echo "Install shellcheck first"; exit 1; }
	@echo "  LINT   modules/*.sh"
	@shellcheck -S warning --shell=bash -e SC2034,SC2086,SC2148 $(MODULES) \
		&& echo "  LINT   ✓ no warnings" \
		|| true

## Сборка + исполняемый файл + sha256
release: build
	@chmod +x $(OUT)
	@sha256sum $(OUT) > $(OUT).sha256
	@echo "  SHA256 $(shell cat $(OUT).sha256 | cut -c1-16)..."
	@echo "  RELEASE v$(VERSION) ready → $(OUT)"

## Показать состав и размеры модулей
ls:
	@echo "  MODULES ($(words $(MODULES)) files):"
	@wc -l $(MODULES) | sort -n | grep -v total | \
		awk '{printf "    %-32s %d lines\n", $$2, $$1}'
	@echo "  TOTAL: $$(wc -l $(MODULES) | tail -1 | awk '{print $$1}') lines"

## Удалить артефакты сборки
clean:
	@rm -f $(OUT) $(OUT).sha256
	@echo "  CLEAN  done"

## Собрать и сразу запустить (dev)
run: build
	@sudo bash $(OUT)

# По умолчанию — сборка
.DEFAULT_GOAL := build
