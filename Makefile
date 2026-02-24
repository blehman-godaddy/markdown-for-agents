VERSION := $(shell cat VERSION)
DIST_NAME := markdown-for-agents-$(VERSION)
DIST_DIR  := dist
TARBALL   := $(DIST_DIR)/$(DIST_NAME).tar.gz
CPANEL_TARBALL := $(DIST_DIR)/$(DIST_NAME)-cpanel-plugin.tar.gz

.PHONY: dist cpanel-plugin clean

dist: $(TARBALL)

$(TARBALL): VERSION composer.json composer.lock
	@echo "==> Installing production dependencies ..."
	composer install --no-dev --optimize-autoloader --no-interaction
	@echo "==> Building $(TARBALL) ..."
	mkdir -p $(DIST_DIR)
	@# Stage files into a temp directory for portable tarball creation
	@STAGE=$$(mktemp -d) && \
		mkdir -p "$$STAGE/$(DIST_NAME)" && \
		cp -R bin conf lib install vendor VERSION README.md "$$STAGE/$(DIST_NAME)/" && \
		chmod 755 "$$STAGE/$(DIST_NAME)/bin/html2markdown-wrapper.sh" \
		          "$$STAGE/$(DIST_NAME)/install/install.sh" \
		          "$$STAGE/$(DIST_NAME)/install/uninstall.sh" \
		          "$$STAGE/$(DIST_NAME)/lib/mfa-common.sh" && \
		tar czf $(TARBALL) -C "$$STAGE" $(DIST_NAME) && \
		rm -rf "$$STAGE"
	@echo "==> Created $(TARBALL)"
	@echo "    $$(du -h $(TARBALL) | cut -f1)  $(TARBALL)"

cpanel-plugin: $(CPANEL_TARBALL)

$(CPANEL_TARBALL): VERSION composer.json composer.lock
	@echo "==> Installing production dependencies ..."
	composer install --no-dev --optimize-autoloader --no-interaction
	@echo "==> Building $(CPANEL_TARBALL) ..."
	mkdir -p $(DIST_DIR)
	@STAGE=$$(mktemp -d) && \
		mkdir -p "$$STAGE/$(DIST_NAME)" && \
		cp -R bin conf lib cpanel vendor VERSION README.md "$$STAGE/$(DIST_NAME)/" && \
		chmod 755 "$$STAGE/$(DIST_NAME)/bin/html2markdown-wrapper.sh" \
		          "$$STAGE/$(DIST_NAME)/lib/mfa-common.sh" \
		          "$$STAGE/$(DIST_NAME)/cpanel/install-plugin.sh" \
		          "$$STAGE/$(DIST_NAME)/cpanel/uninstall-plugin.sh" \
		          "$$STAGE/$(DIST_NAME)/cpanel/scripts/"*.sh && \
		chmod 755 "$$STAGE/$(DIST_NAME)/cpanel/whm/cgi/addon_markdown_for_agents.cgi" && \
		tar czf $(CPANEL_TARBALL) -C "$$STAGE" $(DIST_NAME) && \
		rm -rf "$$STAGE"
	@echo "==> Created $(CPANEL_TARBALL)"
	@echo "    $$(du -h $(CPANEL_TARBALL) | cut -f1)  $(CPANEL_TARBALL)"

clean:
	rm -rf $(DIST_DIR)
