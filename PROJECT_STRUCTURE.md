# Energrid Project Structure

## 📁 Directory Structure

```
energrid-contract-ethereum/
├── ansible/                           # Ansible deployment automation
│   ├── tasks/                        # Deployment tasks
│   ├── templates/                    # Configuration templates
│   ├── vars/                         # Environment variables
│   ├── reports/                      # Deployment reports
│   ├── site.yml                      # Main playbook
│   ├── ansible.cfg                   # Ansible configuration
│   ├── requirements.yml              # Ansible collections
│   ├── requirements.txt              # Python dependencies
│   └── README.md                     # Ansible documentation
├── docker/                           # Container definitions
│   ├── trading-engine/Dockerfile     # Trading engine service
│   ├── blockchain-node/Dockerfile    # Blockchain node service
│   ├── iot-processor/Dockerfile      # IoT processor service
│   ├── nginx/nginx.conf              # Load balancer config
│   ├── database/init.sql             # Database schema
│   └── docker-compose.yml            # Local development
├── terraform/                        # Infrastructure as Code
│   ├── modules/                      # Terraform modules
│   │   ├── networking/               # VPC, subnets, routing
│   │   ├── security/                 # Security groups, IAM
│   │   ├── ecs/                      # ECS Fargate services
│   │   ├── lambda/                   # Lambda functions
│   │   ├── api-gateway/              # API Gateway config
│   │   ├── database/                 # RDS MySQL
│   │   ├── cache/                    # ElastiCache Redis
│   │   └── monitoring/               # CloudWatch dashboards
│   ├── main.tf                       # Main configuration
│   ├── variables.tf                  # Input variables
│   ├── outputs.tf                    # Output values
│   └── terraform.tfvars              # Environment variables
├── docs/                             # Project documentation
│   ├── architecture/                 # Architecture decisions
│   ├── deployment/                   # Deployment guides
│   ├── operations/                   # Operations manual
│   ├── security/                     # Security guidelines
│   └── monitoring/                   # Monitoring setup
├── src/                              # Application source code
├── contracts/                        # Smart contracts
├── test/                             # Test suites
├── scripts/                          # Utility scripts
├── deploy.sh                         # Simple deployment script
└── README.md                         # This file
```

## 🚀 Deployment Options

### Option 1: Ansible (Recommended)
Professional-grade deployment with full automation:

```bash
# Install dependencies
pip install -r ansible/requirements.txt
ansible-galaxy collection install -r ansible/requirements.yml

# Deploy to development
cd ansible
ansible-playbook site.yml -e environment=development

# Deploy to production
ansible-playbook site.yml -e environment=production -e auto_approve=true
```

### Option 2: Shell Script
Simple deployment for quick testing:

```bash
# Make executable
chmod +x deploy.sh

# Deploy to development
./deploy.sh development apply

# Deploy to production
./deploy.sh production apply
```

### Option 3: Manual Terraform
Direct infrastructure management:

```bash
cd terraform
terraform init
terraform workspace new production
terraform plan -var-file="terraform.tfvars"
terraform apply
```

## 🏗️ Architecture

### Hybrid ECS + Lambda Architecture
- **ECS Fargate** for critical, high-performance components
- **Lambda** for auxiliary, event-driven operations  
- **API Gateway** for unified routing and management
- **RDS MySQL** for persistent data storage
- **ElastiCache Redis** for caching and session management

### Container Services (ECS)
1. **Trading Engine** - Core energy trading logic
2. **Blockchain Node** - Ethereum/Polygon interaction
3. **IoT Processor** - Real-time energy meter data processing

### Serverless Functions (Lambda)
1. **Authentication** - User login/logout/tokens
2. **Notifications** - Email/SMS alerts
3. **Analytics** - Data processing and reporting
4. **Certificates** - CEL token certificate generation
5. **CRUD API** - Simple database operations
6. **Webhooks** - External system integrations

## 🔧 Development

### Local Development with Docker
```bash
cd docker
docker-compose up -d
```

This starts all services locally:
- Trading Engine: http://localhost:8080
- Blockchain Node: http://localhost:8081  
- IoT Processor: http://localhost:8082
- Database: localhost:3306
- Redis: localhost:6379
- Nginx: http://localhost

### Environment Configuration
Each environment has its own configuration:
- **Development**: `ansible/vars/development.yml`
- **Staging**: `ansible/vars/staging.yml`
- **Production**: `ansible/vars/production.yml`

## 📊 Monitoring

### CloudWatch Dashboards
- ECS service metrics (CPU, memory, tasks)
- Lambda function metrics (invocations, errors, duration)
- API Gateway metrics (requests, latency, errors)
- Database and cache performance
- Custom business metrics

### Alerting
- High CPU/memory utilization
- Service health check failures
- Lambda error rates
- API Gateway 4xx/5xx errors
- Database connection issues

## 🔒 Security

### Infrastructure Security
- VPC with private subnets
- Security groups with minimal access
- IAM roles with least privilege
- Secrets Manager for sensitive data
- WAF protection for public endpoints

### Application Security  
- Container images run as non-root user
- Network segmentation between services
- Encrypted data at rest and in transit
- Regular security updates and scanning

## 💰 Cost Optimization

### Estimated Monthly Costs
- **ECS Services**: ~$277/month (critical components)
- **Lambda Functions**: ~$18/month (auxiliary operations)
- **Infrastructure**: ~$161/month (database, cache, networking)
- **Total**: ~$456/month

### Cost Controls
- Auto-scaling based on demand
- Spot instances for non-critical workloads
- Reserved instances for predictable workloads
- Lifecycle policies for logs and backups

## 🛠️ Troubleshooting

### Common Issues

1. **Docker build failures**
   - Check Dockerfile syntax
   - Verify base image availability
   - Ensure sufficient disk space

2. **Terraform state issues**
   - Check AWS credentials
   - Verify Terraform version compatibility
   - Use `terraform force-unlock` if needed

3. **ECS service not starting**
   - Check CloudWatch logs
   - Verify security group configurations
   - Ensure ECR image exists

4. **Lambda cold starts**
   - Consider provisioned concurrency
   - Optimize function initialization
   - Use smaller deployment packages

### Debug Commands
```bash
# Check AWS credentials
aws sts get-caller-identity

# View Terraform state
terraform show

# Check ECS service status  
aws ecs describe-services --cluster energrid-production-cluster

# View container logs
aws logs tail /aws/ecs/energrid-production-trading-engine --follow

# Test API endpoints
curl -f http://your-alb-dns/health
```

## 📝 Contributing

1. **Create feature branch**: `git checkout -b feature/your-feature`
2. **Update documentation**: Keep docs in sync with changes
3. **Test deployment**: Verify changes in development environment
4. **Security review**: Ensure no sensitive data in commits
5. **Create pull request**: Include deployment impact assessment

## 📞 Support

For deployment issues or questions:
- Check the documentation in `docs/`
- Review CloudWatch logs and metrics
- Create GitHub issue with deployment details
- Contact DevOps team for production issues

---

*This project uses a hybrid architecture optimized for performance, cost, and operational simplicity.*
