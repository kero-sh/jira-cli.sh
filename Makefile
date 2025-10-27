# Makefile for jira-cli
# Standard GNU structure

PREFIX ?= $(HOME)/.local
BINDIR = $(PREFIX)/bin
LIBDIR = $(PREFIX)/lib/jira-cli
SRCDIR = src
LOCALBINDIR = bin
LOCALLIBDIR = lib

# Get list of executable scripts
SCRIPTS = $(wildcard $(LOCALBINDIR)/*)
LIBS = $(wildcard $(LOCALLIBDIR)/*)

.PHONY: all install uninstall clean help test

all: help

help:
	@echo "Makefile for jira-cli"
	@echo ""
	@echo "Usage:"
	@echo "  make install         Install to $(PREFIX)"
	@echo "  make install PREFIX=/usr/local"
	@echo "                       Install to custom location"
	@echo "  make uninstall       Uninstall from $(PREFIX)"
	@echo "  make test            Verify dependencies"
	@echo "  make clean           Clean temporary files"
	@echo ""
	@echo "Structure:"
	@echo "  bin/    Executables (symbolic links)"
	@echo "  src/    Source scripts (.sh)"
	@echo "  lib/    Shared libraries"
	@echo ""

install: test-deps
	@echo "Installing jira-cli to $(PREFIX)..."
	@mkdir -p $(BINDIR)
	@mkdir -p $(LIBDIR)/src
	@mkdir -p $(LIBDIR)/lib
	@echo "Copying source files..."
	@cp -r $(SRCDIR)/* $(LIBDIR)/src/
	@cp -r $(LOCALLIBDIR)/* $(LIBDIR)/lib/
	@echo "Creating symbolic links in $(BINDIR)..."
	@for script in $(LOCALBINDIR)/*; do \
		name=$$(basename $$script); \
		echo "  Installing: $$name"; \
		ln -sf $(LIBDIR)/src/$${name}.sh $(BINDIR)/$$name; \
		chmod +x $(LIBDIR)/src/$${name}.sh; \
	done
	@echo "Installation completed!"
	@echo ""
	@echo "Add $(BINDIR) to your PATH if not already included:"
	@echo "  export PATH=\"$(BINDIR):\$$PATH\""

uninstall:
	@echo "Uninstalling jira-cli from $(PREFIX)..."
	@for script in $(LOCALBINDIR)/*; do \
		name=$$(basename $$script); \
		rm -f $(BINDIR)/$$name; \
		echo "  Removed: $$name"; \
	done
	@rm -rf $(LIBDIR)
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
