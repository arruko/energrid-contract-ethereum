# Energrid Ansible Deployment

This directory contains Ansible playbooks for deploying the Energrid hybrid architecture to AWS.

## Prerequisites

1. **Install Python dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

2. **Install Ansible collections:**
   ```bash
   ansible-galaxy collection install -r requirements.yml
   ```

3. **Configure AWS credentials:**
   ```bash
   aws configure
   ```

4. **Install additional tools:**
   - Terraform >= 1.0
   - Docker >= 20.0
   - AWS CLI >= 2.0

## Usage

### Deploy to Development
```bash
ansible-playbook site.yml -e environment=development
```

### Deploy to Staging
```bash
ansible-playbook site.yml -e environment=staging
```

### Deploy to Production
```bash
ansible-playbook site.yml -e environment=production -e auto_approve=true
```

### Deploy with custom variables
```bash
ansible-playbook site.yml -e environment=production -e @custom-vars.yml
```

## Configuration

Environment-specific variables are stored in `vars/` directory:
- `vars/development.yml` - Development environment
- `vars/staging.yml` - Staging environment  
- `vars/production.yml` - Production environment

### Required Variables

All environments require these variables to be set:
- `database_password` - Database password
- `cache_auth_token` - Redis authentication token
- `alarm_email` - Email for CloudWatch alarms
- `admin_cidr_blocks` - IP ranges for admin access

### Sensitive Variables

For production, use ansible-vault to encrypt sensitive data:

```bash
# Create encrypted variables
ansible-vault create vars/production-secrets.yml

# Edit encrypted variables
ansible-vault edit vars/production-secrets.yml

# Deploy with vault password
ansible-playbook site.yml -e environment=production --ask-vault-pass
```

## Tasks

The deployment is broken down into these tasks:

### 1. Terraform (`tasks/terraform.yml`)
- Creates/updates AWS infrastructure
- Manages Terraform state and workspaces
- Outputs important resource information

### 2. Docker (`tasks/docker.yml`)
- Builds container images from `docker/` directory
- Pushes images to ECR
- Tags images appropriately

### 3. Lambda (`tasks/lambda.yml`)
- Packages Lambda functions
- Deploys/updates function code
- Configures runtime settings

### 4. Monitoring (`tasks/monitoring.yml`)
- Sets up CloudWatch alarms
- Creates dashboards
- Configures log retention

### 5. Validation (`tasks/validation.yml`)
- Tests deployed services
- Validates health endpoints
- Generates deployment report

## Templates

### `templates/terraform.tfvars.j2`
Generates Terraform variables file from Ansible variables.

### `templates/deployment-report.md.j2`
Creates deployment report with infrastructure details and health status.

## Reports

Deployment reports are saved in `reports/` directory with timestamp:
- `deployment-production-1642694400.md`
- `deployment-staging-1642694500.md`

## Examples

### Custom deployment with specific features
```bash
ansible-playbook site.yml \
  -e environment=production \
  -e deploy_containers=true \
  -e deploy_lambda=false \
  -e setup_monitoring=true \
  -e create_bastion=true
```

### Update only Lambda functions
```bash
ansible-playbook site.yml \
  -e environment=production \
  -e deploy_containers=false \
  -e deploy_lambda=true \
  -e update_lambda_code=true \
  --tags lambda
```

### Terraform plan only (no apply)
```bash
ansible-playbook site.yml \
  -e environment=production \
  -e auto_approve=false \
  --tags terraform
```

## Troubleshooting

### Common Issues

1. **AWS credentials not configured**
   ```bash
   aws configure
   export AWS_PROFILE=your-profile
   ```

2. **Terraform state locked**
   ```bash
   cd terraform
   terraform force-unlock LOCK_ID
   ```

3. **Docker build fails**
   - Check Docker daemon is running
   - Verify Dockerfile syntax
   - Ensure sufficient disk space

4. **ECR authentication fails**
   ```bash
   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin YOUR_ECR_URL
   ```

### Debug Mode

Run with verbose output:
```bash
ansible-playbook site.yml -e environment=development -vvv
```

### Check specific task results
```bash
ansible-playbook site.yml -e environment=development --check --diff
```
