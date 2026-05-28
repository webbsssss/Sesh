.PHONY: help build test lint deploy teardown validate kind-up kind-down

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

build: ## Build Go binary
	cd apps/payments-api && go build -o payments-api ./cmd/payments-api

test: ## Run Go tests
	cd apps/payments-api && go test ./... -v

docker-build: ## Build container image locally
	cd apps/payments-api && docker build -t payments-api:latest .

lint: ## Lint Helm chart
	helm lint helm-charts/microservice

template: ## Render Helm templates to stdout
	helm template helm-charts/microservice

validate: ## Validate Kubernetes / Istio manifests (requires kubeval or equivalent)
	helm template helm-charts/microservice > /tmp/rendered.yaml
	# kubeval /tmp/rendered.yaml
	@echo "Rendered to /tmp/rendered.yaml — run kubeval manually if installed"

infra: ## Provision EKS via Terraform
	cd terraform/environments/dev && terraform init && terraform apply

destroy: ## Destroy EKS via Terraform
	cd terraform/environments/dev && terraform destroy

setup-local: ## Install ArgoCD CLI and istioctl locally
	@echo "Install istioctl: curl -L https://istio.io/downloadIstio | sh -"
	@echo "Install argocd CLI: https://argo-cd.readthedocs.io/en/stable/cli_installation/"


kind-up: ## Create local kind cluster and deploy everything
	bash scripts/setup-kind.sh

kind-down: ## Destroy local kind cluster and registry
	bash scripts/teardown-kind.sh

port-forward-argocd: ## Port-forward ArgoCD UI
	kubectl port-forward svc/argocd-server -n argocd 8080:443

argocd-password: ## Get initial ArgoCD admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

demo-self-healing: ## Run self-healing demo
	bash scripts/demo-self-healing.sh

demo-canary: ## Run canary deployment demo
	bash scripts/demo-canary.sh
