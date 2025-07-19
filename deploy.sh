#!/bin/bash

# Energrid Hybrid Architecture Deployment Script
# Usage: ./deploy.sh [environment] [action]
# Example: ./deploy.sh production apply

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"
DOCKER_DIR="$SCRIPT_DIR/docker"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Parse arguments
ENVIRONMENT=${1:-development}
ACTION=${2:-plan}

if [[ ! "$ENVIRONMENT" =~ ^(development|staging|production)$ ]]; then
    error "Invalid environment. Use: development, staging, or production"
fi

if [[ ! "$ACTION" =~ ^(plan|apply|destroy|init)$ ]]; then
    error "Invalid action. Use: init, plan, apply, or destroy"
fi

log "Starting Energrid deployment for $ENVIRONMENT environment"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        error "Terraform is not installed. Please install terraform first."
    fi
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI first."
    fi
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure'."
    fi
    
    success "Prerequisites check passed"
}

# Create terraform.tfvars if it doesn't exist
create_tfvars() {
    local tfvars_file="$TERRAFORM_DIR/terraform.tfvars"
    
    if [[ ! -f "$tfvars_file" ]]; then
        log "Creating terraform.tfvars file..."
        
        cat > "$tfvars_file" << EOF
# Energrid Terraform Configuration
project_name = "energrid"
environment  = "$ENVIRONMENT"

# Networking
vpc_cidr = "10.0.0.0/16"
admin_cidr_blocks = ["0.0.0.0/0"]  # Update with your IP range

# Database
database_password = "ChangeMePlease123!"  # Change this!

# Cache
cache_auth_token = "ChangeMePlease456!"   # Change this!

# ECR Repository (update with your account ID)
ecr_repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/energrid"

# Monitoring
alarm_email = "admin@energrid.com"        # Change this!
EOF
        
        warning "Created terraform.tfvars with default values."
        warning "Please update the following before deployment:"
        warning "  - database_password"
        warning "  - cache_auth_token"
        warning "  - ecr_repository_url"
        warning "  - alarm_email"
        warning "  - admin_cidr_blocks"
    fi
}

# Initialize Terraform
init_terraform() {
    log "Initializing Terraform..."
    cd "$TERRAFORM_DIR"
    
    terraform init
    
    # Create or select workspace
    if terraform workspace list | grep -q "$ENVIRONMENT"; then
        terraform workspace select "$ENVIRONMENT"
    else
        terraform workspace new "$ENVIRONMENT"
    fi
    
    success "Terraform initialized for $ENVIRONMENT environment"
}

# Build and push container images
build_and_push_images() {
    if [[ "$ACTION" != "apply" ]]; then
        return 0
    fi
    
    log "Building and pushing container images..."
    
    # Get ECR repository URL from terraform.tfvars
    ECR_URL=$(grep ecr_repository_url "$TERRAFORM_DIR/terraform.tfvars" | cut -d'"' -f2)
    
    if [[ -z "$ECR_URL" || "$ECR_URL" == "123456789012.dkr.ecr.us-east-1.amazonaws.com/energrid" ]]; then
        warning "ECR repository URL not configured properly in terraform.tfvars"
        warning "Skipping container image build and push"
        return 0
    fi
    
    # Extract region from ECR URL
    REGION=$(echo "$ECR_URL" | cut -d'.' -f4)
    
    # Login to ECR
    aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_URL"
    
    # Check if docker directory exists
    if [[ ! -d "$DOCKER_DIR" ]]; then
        error "Docker directory not found at $DOCKER_DIR"
        error "Please ensure docker/ directory exists with Dockerfile for each service"
        return 1
    fi
    
    # Build and push images
    local images=("trading-engine" "blockchain-node" "iot-processor")
    
    for image in "${images[@]}"; do
        if [[ -d "$DOCKER_DIR/$image" && -f "$DOCKER_DIR/$image/Dockerfile" ]]; then
            log "Building $image..."
            docker build -t "energrid/$image" -f "$DOCKER_DIR/$image/Dockerfile" .
            docker tag "energrid/$image:latest" "$ECR_URL/$image:latest"
            docker push "$ECR_URL/$image:latest"
            success "$image image pushed successfully"
        else
            error "$image Dockerfile not found at $DOCKER_DIR/$image/Dockerfile"
            return 1
        fi
    done
}

# Remove placeholder image creation function since we have proper Dockerfiles
# create_placeholder_images() { ... }

# Build Lambda packages
build_lambda_packages() {
    if [[ "$ACTION" != "apply" ]]; then
        return 0
    fi
    
    log "Building Lambda packages..."
    
    local lambda_dir="$TERRAFORM_DIR/modules/lambda/lambda-packages"
    
    # Lambda packages are already created as placeholders
    # In a real deployment, you would build actual Lambda functions here
    
    success "Lambda packages ready"
}

# Run Terraform
run_terraform() {
    log "Running Terraform $ACTION..."
    cd "$TERRAFORM_DIR"
    
    case "$ACTION" in
        init)
            # Already done in init_terraform
            ;;
        plan)
            terraform plan -var-file="terraform.tfvars" -out="$ENVIRONMENT.tfplan"
            ;;
        apply)
            if [[ -f "$ENVIRONMENT.tfplan" ]]; then
                terraform apply "$ENVIRONMENT.tfplan"
            else
                terraform apply -var-file="terraform.tfvars" -auto-approve
            fi
            ;;
        destroy)
            terraform destroy -var-file="terraform.tfvars" -auto-approve
            ;;
    esac
    
    success "Terraform $ACTION completed successfully"
}

# Show outputs
show_outputs() {
    if [[ "$ACTION" == "apply" ]]; then
        log "Deployment outputs:"
        cd "$TERRAFORM_DIR"
        terraform output
    fi
}

# Main execution
main() {
    log "=== Energrid Hybrid Architecture Deployment ==="
    log "Environment: $ENVIRONMENT"
    log "Action: $ACTION"
    echo
    
    check_prerequisites
    create_tfvars
    init_terraform
    
    if [[ "$ACTION" == "apply" ]]; then
        build_lambda_packages
        build_and_push_images
    fi
    
    run_terraform
    show_outputs
    
    success "Deployment $ACTION completed successfully!"
    
    if [[ "$ACTION" == "apply" ]]; then
        echo
        log "Next steps:"
        log "1. Update DNS records to point to the ALB"
        log "2. Configure SSL certificates in ACM"
        log "3. Deploy actual application code to src/ directory"
        log "4. Configure monitoring alerts"
        log "5. For more robust deployment, consider using Ansible:"
        log "   cd ansible && ansible-playbook site.yml -e environment=$ENVIRONMENT"
        echo
        log "Dashboard URL: https://console.aws.amazon.com/cloudwatch/home#dashboards"
        log "API Gateway URL: Check terraform outputs above"
    fi
}

# Execute main function
main
