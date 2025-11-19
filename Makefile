# Makefile for jira-cli
# Self-contained installation

PREFIX ?= $(HOME)/.local
SRCDIR = src
LOCALBINDIR = bin
LOCALLIBDIR = lib

# Get list of executable scripts and libs
SCRIPTS = $(wildcard $(LOCALBINDIR)/*)
LIBS = $(wildcard $(LOCALLIBDIR)/*.sh)
SRC_SCRIPTS = $(wildcard $(SRCDIR)/*.sh)

.PHONY: all install uninstall clean help test

all: help

help:
	@echo "Makefile for jira-cli"
	@echo ""
	@echo "Usage:"
	@echo "  make install         Install to $(PREFIX)"
	@echo "  make install PREFIX=/usr/local"
	@echo "                       Install to custom location (self-contained)"
	@echo "  make uninstall       Uninstall from $(PREFIX)"
	@echo "  make test            Verify dependencies"
	@echo "  make clean           Clean temporary files"
	@echo ""

install: test-deps
	@echo "Installing jira-cli to $(PREFIX) (self-contained)..."
	@mkdir -p $(PREFIX)/bin
	@mkdir -p $(PREFIX)/src
	@mkdir -p $(PREFIX)/lib
	@echo "Copying executables..."
	@cp -r $(LOCALBINDIR)/* $(PREFIX)/bin/
	@chmod +x $(PREFIX)/bin/*
	@echo "Copying source scripts..."
	@cp $(SRCDIR)/*.sh $(PREFIX)/src/
	@chmod +x $(PREFIX)/src/*.sh
	@echo "Copying libraries..."
	@cp $(LOCALLIBDIR)/*.sh $(PREFIX)/lib/
	@echo ""
	@echo "==> jira-cli has been installed successfully!"
	@echo ""
	@echo "To use jira-cli, add the following to your shell profile:"
	@echo ""
	@echo "  # For bash (~/.bashrc or ~/.bash_profile):"
	@echo "  export PATH=\"$(PREFIX)/bin:\$$PATH\""
	@echo ""
	@echo "  # For zsh (~/.zshrc):"
	@echo "  export PATH=\"$(PREFIX)/bin:\$$PATH\""
	@echo ""
	@echo "Then restart your shell or run:"
	@echo "  source ~/.bashrc  # or source ~/.zshrc"
	@echo ""
	@echo "Verify installation with:"
	@echo "  jira --help"
	@echo ""

uninstall:
	@echo "Uninstalling jira-cli from $(PREFIX)..."
	@rm -rf $(PREFIX)/bin/jira*
	@rm -rf $(PREFIX)/bin/md2jira
	@rm -rf $(PREFIX)/src
	@rm -rf $(PREFIX)/lib
	@echo "Uninstallation completed!"

test-deps:
	@echo "Verifying dependencies..."
	@command -v bash >/dev/null 2>&1 || { echo "ERROR: bash not found"; exit 1; }
	@command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found"; exit 1; }
	@command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not found. Install with: brew install jq (macOS) or apt-get install jq (Linux)"; exit 1; }
	@command -v git >/dev/null 2>&1 || { echo "ERROR: git not found"; exit 1; }
	@echo "✓ Basic dependencies OK"
	@command -v yq >/dev/null 2>&1 && echo "✓ yq found (optional)" || echo "⚠ yq not found (optional, for --output yaml)"
	@command -v column >/dev/null 2>&1 && echo "✓ column found (optional)" || echo "⚠ column not found (optional, for --output table)"

test: test-deps
	@echo ""
	@echo "Testing configuration..."
	@if [ -z "$$JIRA_HOST" ]; then \
		echo "⚠ JIRA_HOST not configured"; \
	else \
		echo "✓ JIRA_HOST: $$JIRA_HOST"; \
	fi
	@if [ -z "$$JIRA_TOKEN" ] && [ -z "$$JIRA_EMAIL" ]; then \
		echo "⚠ Authentication not configured (JIRA_TOKEN or JIRA_EMAIL+JIRA_API_TOKEN)"; \
	else \
		echo "✓ Authentication configured"; \
	fi

clean:
	@echo "Cleaning temporary files..."
	@find . -name "*.tmp" -delete
	@find . -name "*~" -delete
	@echo "Cleanup completed!"

.PHONY: check-scripts
check-scripts:
	@echo "Verifying scripts..."
	@for script in $(SRCDIR)/*.sh; do \
		echo "Checking: $$script"; \
		bash -n $$script || exit 1; \
	done
	@echo "✓ All scripts have valid syntax"
