.PHONY: build push test clean help

PROJECT_ID ?= $(shell gcloud config get-value project)
IMAGE_TAG ?= latest
IMAGE_NAME = gcr.io/$(PROJECT_ID)/a2a-deployer
FULL_IMAGE = $(IMAGE_NAME):$(IMAGE_TAG)

help:
	@echo "Available targets:"
	@echo "  build       - Build the deployer Docker image"
	@echo "  push        - Push the deployer image to GCR"
	@echo "  test        - Test the deployer locally"
	@echo "  clean       - Remove local Docker images"
	@echo "  all         - Build and push"
	@echo ""
	@echo "Environment variables:"
	@echo "  PROJECT_ID  - GCP project ID (current: $(PROJECT_ID))"
	@echo "  IMAGE_TAG   - Docker image tag (current: $(IMAGE_TAG))"

build:
	@echo "Building $(FULL_IMAGE)..."
	docker build -t $(FULL_IMAGE) -f Dockerfile .
	@echo "Build completed!"

push: build
	@echo "Pushing $(FULL_IMAGE) to GCR..."
	docker push $(FULL_IMAGE)
	@echo "Push completed!"

test:
	@if [ -z "$(CLUSTER_NAME)" ]; then \
		echo "Error: CLUSTER_NAME is required for testing"; \
		exit 1; \
	fi
	@echo "Testing deployer on cluster $(CLUSTER_NAME)..."
	./test_deployer.sh

clean:
	@echo "Removing local Docker images..."
	docker rmi $(FULL_IMAGE) 2>/dev/null || true
	@echo "Cleanup completed!"

all: build push

validate:
	@echo "Validating Dockerfile..."
	docker run --rm -i hadolint/hadolint < Dockerfile || true
	@echo "Validating shell scripts..."
	shellcheck *.sh || true
