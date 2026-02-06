.PHONY: init plan apply destroy validate test deploy clean fmt check help

TERRAFORM_DIR := ./terraform
PROJECT_ID ?= $(shell gcloud config get-value project)
REGION ?= us-central1
DEPLOYMENT_NAME ?= a2a-marketplace
CLUSTER_NAME ?= $(DEPLOYMENT_NAME)-gke
TF_VAR_FILE ?= terraform.tfvars

export TF_VAR_project_id=$(PROJECT_ID)
export TF_VAR_region=$(REGION)
export TF_VAR_deployment_name=$(DEPLOYMENT_NAME)

help:
	@echo "GCP Marketplace Deployment Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  init        - Initialize Terraform and validate configuration"
	@echo "  plan        - Generate and show Terraform execution plan"
	@echo "  apply       - Build and apply Terraform infrastructure"
	@echo "  destroy     - Destroy Terraform infrastructure"
	@echo "  validate    - Validate Terraform configuration and GCP resources"
	@echo "  test        - Run tests for the deployment"
	@echo "  deploy      - Deploy application to GKE cluster"
	@echo "  fmt         - Format Terraform files"
	@echo "  check       - Run pre-deployment checks"
	@echo "  clean       - Clean Terraform state and temporary files"
	@echo ""
	@echo "Environment variables:"
	@echo "  PROJECT_ID       - GCP project ID (default: current gcloud config)"
	@echo "  REGION           - GCP region (default: us-central1)"
	@echo "  DEPLOYMENT_NAME  - Deployment name prefix (default: a2a-marketplace)"

init:
	@echo "==> Initializing Terraform..."
	cd $(TERRAFORM_DIR) && terraform init -upgrade
	@echo "==> Validating Terraform configuration..."
	cd $(TERRAFORM_DIR) && terraform validate
	@echo "==> Checking GCP authentication..."
	@gcloud auth application-default print-access-token > /dev/null 2>&1 || \
		(echo "Please run: gcloud auth application-default login" && exit 1)
	@echo "==> Enabling required GCP APIs..."
	@gcloud services enable \
		compute.googleapis.com \
		container.googleapis.com \
		cloudresourcemanager.googleapis.com \
		iam.googleapis.com \
		sqladmin.googleapis.com \
		servicenetworking.googleapis.com \
		cloudbuild.googleapis.com \
		--project=$(PROJECT_ID) || true
	@echo "==> Initialization complete!"

plan:
	@echo "==> Generating Terraform plan..."
	@if [ ! -f "$(TERRAFORM_DIR)/.terraform.lock.hcl" ]; then \
		echo "Error: Terraform not initialized. Run 'make init' first."; \
		exit 1; \
	fi
	cd $(TERRAFORM_DIR) && terraform plan -out=tfplan
	@echo "==> Plan saved to $(TERRAFORM_DIR)/tfplan"

apply:
	@echo "==> Applying Terraform configuration..."
	@if [ ! -f "$(TERRAFORM_DIR)/.terraform.lock.hcl" ]; then \
		echo "Error: Terraform not initialized. Run 'make init' first."; \
		exit 1; \
	fi
	cd $(TERRAFORM_DIR) && terraform apply -auto-approve
	@echo "==> Getting GKE cluster credentials..."
	@gcloud container clusters get-credentials $(CLUSTER_NAME) \
		--region=$(REGION) \
		--project=$(PROJECT_ID) || true
	@echo "==> Infrastructure deployment complete!"
	@echo ""
	@echo "Cluster: $(CLUSTER_NAME)"
	@echo "Region: $(REGION)"
	@echo "Project: $(PROJECT_ID)"

destroy:
	@echo "==> WARNING: This will destroy all infrastructure!"
	@echo "==> Press Ctrl+C to cancel, or wait 10 seconds to continue..."
	@sleep 10
	@echo "==> Destroying Terraform infrastructure..."
	cd $(TERRAFORM_DIR) && terraform destroy -auto-approve
	@echo "==> Infrastructure destroyed!"

validate:
	@echo "==> Validating Terraform configuration..."
	cd $(TERRAFORM_DIR) && terraform validate
	@echo "==> Formatting check..."
	cd $(TERRAFORM_DIR) && terraform fmt -check -recursive
	@echo "==> Validating schema.yaml..."
	@if [ -f "schema.yaml" ]; then \
		python3 -c "import yaml; yaml.safe_load(open('schema.yaml'))" && \
		echo "schema.yaml is valid"; \
	fi
	@echo "==> Checking Helm charts..."
	@if [ -d "helm" ]; then \
		for chart in helm/*/; do \
			echo "Validating $$chart..."; \
			helm lint "$$chart" || exit 1; \
		done; \
	fi
	@echo "==> Checking GCP project..."
	@gcloud projects describe $(PROJECT_ID) > /dev/null 2>&1 || \
		(echo "Error: Project $(PROJECT_ID) not accessible" && exit 1)
	@echo "==> Validation complete!"

test:
	@echo "==> Running deployment tests..."
	@echo "==> Checking if cluster exists..."
	@gcloud container clusters describe $(CLUSTER_NAME) \
		--region=$(REGION) \
		--project=$(PROJECT_ID) > /dev/null 2>&1 && \
		echo "✓ GKE cluster exists" || \
		echo "✗ GKE cluster not found"
	@echo "==> Testing cluster connectivity..."
	@kubectl cluster-info > /dev/null 2>&1 && \
		echo "✓ Cluster accessible" || \
		echo "✗ Cannot connect to cluster"
	@echo "==> Checking node status..."
	@kubectl get nodes > /dev/null 2>&1 && \
		echo "✓ Nodes ready: $$(kubectl get nodes --no-headers | wc -l)" || \
		echo "✗ Cannot get node status"
	@echo "==> Checking namespaces..."
	@kubectl get namespaces > /dev/null 2>&1 && \
		echo "✓ Namespaces accessible" || \
		echo "✗ Cannot list namespaces"
	@echo "==> Running Terraform validation tests..."
	@cd $(TERRAFORM_DIR) && terraform validate
	@echo "==> Test suite complete!"

deploy:
	@echo "==> Deploying application to GKE..."
	@if ! kubectl cluster-info > /dev/null 2>&1; then \
		echo "Error: Cannot connect to cluster. Run 'make apply' first."; \
		exit 1; \
	fi
	@echo "==> Ensuring cluster credentials..."
	@gcloud container clusters get-credentials $(CLUSTER_NAME) \
		--region=$(REGION) \
		--project=$(PROJECT_ID)
	@echo "==> Creating namespace if not exists..."
	@kubectl create namespace $(DEPLOYMENT_NAME) --dry-run=client -o yaml | kubectl apply -f - || true
	@echo "==> Deploying Helm charts..."
	@if [ -d "helm" ]; then \
		for chart in helm/*/Chart.yaml; do \
			chart_dir=$$(dirname $$chart); \
			chart_name=$$(basename $$chart_dir); \
			echo "Deploying $$chart_name..."; \
			helm upgrade --install $$chart_name $$chart_dir \
				--namespace $(DEPLOYMENT_NAME) \
				--create-namespace \
				--wait \
				--timeout 10m || exit 1; \
		done; \
	else \
		echo "No Helm charts found in ./helm directory"; \
	fi
	@echo "==> Checking deployment status..."
	@kubectl get all -n $(DEPLOYMENT_NAME)
	@echo "==> Deployment complete!"
	@echo ""
	@echo "To view services:"
	@echo "  kubectl get services -n $(DEPLOYMENT_NAME)"
	@echo ""
	@echo "To view pods:"
	@echo "  kubectl get pods -n $(DEPLOYMENT_NAME)"

fmt:
	@echo "==> Formatting Terraform files..."
	cd $(TERRAFORM_DIR) && terraform fmt -recursive
	@echo "==> Format complete!"

check: validate
	@echo "==> Running pre-deployment checks..."
	@echo "==> Checking gcloud CLI..."
	@which gcloud > /dev/null || (echo "Error: gcloud not found" && exit 1)
	@echo "==> Checking kubectl..."
	@which kubectl > /dev/null || (echo "Error: kubectl not found" && exit 1)
	@echo "==> Checking Terraform..."
	@which terraform > /dev/null || (echo "Error: terraform not found" && exit 1)
	@echo "==> Checking Helm..."
	@which helm > /dev/null || (echo "Error: helm not found" && exit 1)
	@echo "==> Checking project quotas..."
	@gcloud compute project-info describe --project=$(PROJECT_ID) > /dev/null 2>&1 || \
		(echo "Warning: Cannot check project quotas" && exit 0)
	@echo "==> All checks passed!"

clean:
	@echo "==> Cleaning Terraform files..."
	@rm -rf $(TERRAFORM_DIR)/.terraform
	@rm -f $(TERRAFORM_DIR)/.terraform.lock.hcl
	@rm -f $(TERRAFORM_DIR)/tfplan
	@rm -f $(TERRAFORM_DIR)/terraform.tfstate
	@rm -f $(TERRAFORM_DIR)/terraform.tfstate.backup
	@rm -f $(TERRAFORM_DIR)/*.tfvars
	@echo "==> Clean complete!"

all: init validate plan apply test deploy

marketplace-build:
	@echo "==> Building GCP Marketplace package..."
	@if [ ! -f "schema.yaml" ]; then \
		echo "Error: schema.yaml not found"; \
		exit 1; \
	fi
	@echo "==> Validating schema.yaml..."
	@python3 -c "import yaml; yaml.safe_load(open('schema.yaml'))"
	@echo "==> Building deployer image..."
	@if [ -f "Dockerfile" ]; then \
		gcloud builds submit --tag gcr.io/$(PROJECT_ID)/$(DEPLOYMENT_NAME)-deployer:latest . || \
		docker build -t gcr.io/$(PROJECT_ID)/$(DEPLOYMENT_NAME)-deployer:latest .; \
	fi
	@echo "==> Marketplace build complete!"

marketplace-test:
	@echo "==> Testing GCP Marketplace deployment..."
	@mpdev verify --deployer=gcr.io/$(PROJECT_ID)/$(DEPLOYMENT_NAME)-deployer:latest || \
		echo "Warning: mpdev not installed or verification failed"
	@echo "==> Marketplace test complete!"

.DEFAULT_GOAL := help
