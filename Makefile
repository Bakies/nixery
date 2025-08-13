# Makefile for Nixery multi-arch Docker builds

# Image configuration
IMAGE_NAME = bakies/nixery
IMAGE_TAG ?= latest
PLATFORMS = linux/amd64,linux/arm64

# Docker buildx builder name
BUILDER_NAME = nixery-builder

.PHONY: help build push setup-builder clean

help: ## Show this help message
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*?##/ { printf "  %-15s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

setup-builder: ## Create and configure docker buildx builder
	@echo "Setting up multi-arch builder..."
	@docker buildx create --name $(BUILDER_NAME) --driver docker-container --bootstrap --use 2>/dev/null || \
		docker buildx use $(BUILDER_NAME) 2>/dev/null || \
		(echo "Using existing builder" && docker buildx use $(BUILDER_NAME))
	@docker buildx inspect --bootstrap

build: setup-builder ## Build multi-arch Docker image
	@echo "Building $(IMAGE_NAME):$(IMAGE_TAG) for $(PLATFORMS)..."
	@docker buildx build \
		--platform $(PLATFORMS) \
		--tag $(IMAGE_NAME):$(IMAGE_TAG) \
		.

push: setup-builder ## Build and push multi-arch Docker image
	@echo "Building and pushing $(IMAGE_NAME):$(IMAGE_TAG) for $(PLATFORMS)..."
	@docker buildx build \
		--platform $(PLATFORMS) \
		--tag $(IMAGE_NAME):$(IMAGE_TAG) \
		--push \
		.

clean: ## Remove buildx builder
	@echo "Removing builder $(BUILDER_NAME)..."
	@docker buildx rm $(BUILDER_NAME) 2>/dev/null || true

# Development targets
build-local: ## Build image for local architecture only
	@echo "Building $(IMAGE_NAME):$(IMAGE_TAG) for local architecture..."
	@docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .

run: ## Run the container locally
	@echo "Running $(IMAGE_NAME):$(IMAGE_TAG) on port 8080..."
	@docker run -p 8080:8080 --rm $(IMAGE_NAME):$(IMAGE_TAG)

# Version management
tag: ## Tag image with git commit hash
	$(eval GIT_HASH := $(shell git rev-parse --short HEAD))
	@echo "Tagging image with git hash: $(GIT_HASH)"
	@docker tag $(IMAGE_NAME):$(IMAGE_TAG) $(IMAGE_NAME):$(GIT_HASH)

push-tagged: tag ## Push both latest and git hash tagged images
	@echo "Pushing tagged images..."
	@docker buildx build \
		--platform $(PLATFORMS) \
		--tag $(IMAGE_NAME):$(IMAGE_TAG) \
		--tag $(IMAGE_NAME):$(shell git rev-parse --short HEAD) \
		--push \
		.