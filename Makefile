VERSION := $(shell cat VERSION)
DIST_NAME := markdown-for-agents-$(VERSION)
DIST_DIR  := dist
TARBALL   := $(DIST_DIR)/$(DIST_NAME).tar.gz

.PHONY: dist clean

dist: $(TARBALL)

$(TARBALL): VERSION composer.json composer.lock
	@echo "==> Installing production dependencies ..."
	composer install --no-dev --optimize-autoloader --no-interaction
	@echo "==> Building $(TARBALL) ..."
	mkdir -p $(DIST_DIR)
	@# Stage files into a temp directory for portable tarball creation
	@STAGE=$$(mktemp -d) && \
		mkdir -p "$$STAGE/$(DIST_NAME)" && \
		cp -R bin conf install vendor VERSION README.md "$$STAGE/$(DIST_NAME)/" && \
		chmod 755 "$$STAGE/$(DIST_NAME)/bin/html2markdown-wrapper.sh" \
		          "$$STAGE/$(DIST_NAME)/install/install.sh" \
		          "$$STAGE/$(DIST_NAME)/install/uninstall.sh" && \
		tar czf $(TARBALL) -C "$$STAGE" $(DIST_NAME) && \
		rm -rf "$$STAGE"
	@echo "==> Created $(TARBALL)"
	@echo "    $$(du -h $(TARBALL) | cut -f1)  $(TARBALL)"

clean:
	rm -rf $(DIST_DIR)
