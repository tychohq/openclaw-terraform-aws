#!/bin/bash
#
# OpenClaw AWS Setup Wizard
# One script to deploy everything
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}"
cat << 'EOF'
   ___                    ____ _                
  / _ \ _ __   ___ _ __  / ___| | __ ___      __
 | | | | '_ \ / _ \ '_ \| |   | |/ _` \ \ /\ / /
 | |_| | |_) |  __/ | | | |___| | (_| |\ V  V / 
  \___/| .__/ \___|_| |_|\____|_|\__,_| \_/\_/  
       |_|                            on AWS
EOF
echo -e "${NC}"
echo "=============================================="
echo "         OpenClaw AWS Setup Wizard"
echo "=============================================="
echo ""

# Check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    local missing=()
    
    if ! command -v terraform &> /dev/null; then
        missing+=("terraform")
    fi
    
    if ! command -v aws &> /dev/null; then
        missing+=("aws-cli")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}Missing required tools: ${missing[*]}${NC}"
        echo ""
        echo "Install them first:"
        echo "  - Terraform: https://terraform.io/downloads"
        echo "  - AWS CLI:   https://aws.amazon.com/cli/"
        echo "  - jq:        brew install jq / apt install jq"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}AWS credentials not configured!${NC}"
        echo "Run: aws configure"
        exit 1
    fi
    
    echo -e "${GREEN}✓ All prerequisites met${NC}"
    echo ""
}

# Get user input
get_user_input() {
    # Deployment type
    echo -e "${BLUE}Which deployment do you want?${NC}"
    echo ""
    echo "  1) Minimal - Single user, ~\$12/month ⭐ RECOMMENDED"
    echo "              No domain needed, polling mode"
    echo ""
    echo "  2) Simple  - Single user, ~\$18/month"
    echo "              Requires domain, webhook mode"
    echo ""
    echo "  3) Full    - Production, ~\$120/month"
    echo "              ALB + WAF + Private subnet"
    echo ""
    read -p "Choose [1/2/3]: " DEPLOY_TYPE
    
    case $DEPLOY_TYPE in
        1) DEPLOY_DIR="minimal"; NEEDS_DOMAIN=false ;;
        2) DEPLOY_DIR="simple"; NEEDS_DOMAIN=true ;;
        3) DEPLOY_DIR="full"; NEEDS_DOMAIN=true ;;
        *) echo "Invalid choice"; exit 1 ;;
    esac
    
    echo ""
    
    # Domain (only for simple/full)
    if [ "$NEEDS_DOMAIN" = true ]; then
        read -p "Enter your domain name (e.g., openclaw.example.com): " DOMAIN_NAME
        if [ -z "$DOMAIN_NAME" ]; then
            echo -e "${RED}Domain name is required for this deployment type${NC}"
            exit 1
        fi
    else
        DOMAIN_NAME=""
    fi
    
    # Region
    echo ""
    echo "AWS Region options:"
    echo "  1) eu-central-1 (Frankfurt)"
    echo "  2) us-east-1 (N. Virginia)"
    echo "  3) us-west-2 (Oregon)"
    echo "  4) Other"
    read -p "Choose [1-4, default 1]: " REGION_CHOICE
    
    case $REGION_CHOICE in
        2) AWS_REGION="us-east-1" ;;
        3) AWS_REGION="us-west-2" ;;
        4) read -p "Enter region: " AWS_REGION ;;
        *) AWS_REGION="eu-central-1" ;;
    esac
    
    # Secrets
    echo ""
    echo -e "${YELLOW}API Keys (will be stored in AWS Secrets Manager)${NC}"
    echo ""
    read -p "Anthropic API Key (sk-ant-...): " ANTHROPIC_KEY
    read -p "Telegram Bot Token (123456:ABC...): " TELEGRAM_TOKEN
    
    # Generate gateway token
    GATEWAY_TOKEN=$(openssl rand -base64 32)
    
    echo ""
    echo -e "${GREEN}Configuration summary:${NC}"
    echo "  Deployment:  $DEPLOY_DIR"
    if [ -n "$DOMAIN_NAME" ]; then
        echo "  Domain:      $DOMAIN_NAME"
    else
        echo "  Domain:      (not needed - polling mode)"
    fi
    echo "  Region:      $AWS_REGION"
    echo "  Anthropic:   ${ANTHROPIC_KEY:0:10}..."
    echo "  Telegram:    ${TELEGRAM_TOKEN:0:10}..."
    echo ""
    read -p "Proceed with deployment? [y/N]: " CONFIRM
    
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
}

# Create tfvars
create_tfvars() {
    echo ""
    echo -e "${YELLOW}Creating Terraform configuration...${NC}"
    
    cd "terraform/$DEPLOY_DIR"
    
    if [ -n "$DOMAIN_NAME" ]; then
        cat > terraform.tfvars << EOF
aws_region  = "$AWS_REGION"
domain_name = "$DOMAIN_NAME"
environment = "prod"
EOF
    else
        cat > terraform.tfvars << EOF
aws_region  = "$AWS_REGION"
environment = "prod"
EOF
    fi
    
    echo -e "${GREEN}✓ Created terraform.tfvars${NC}"
}

# Deploy infrastructure
deploy_infrastructure() {
    echo ""
    echo -e "${YELLOW}Deploying infrastructure (this takes 5-10 minutes)...${NC}"
    echo ""
    
    terraform init
    terraform apply -auto-approve
    
    # Capture outputs
    INSTANCE_ID=$(terraform output -raw instance_id 2>/dev/null || echo "")
    PUBLIC_IP=$(terraform output -raw public_ip 2>/dev/null || echo "")
    ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "")
    
    echo ""
    echo -e "${GREEN}✓ Infrastructure deployed${NC}"
}

# Store secrets
store_secrets() {
    echo ""
    echo -e "${YELLOW}Storing secrets in AWS Secrets Manager...${NC}"
    
    local project_name="openclaw"
    
    aws secretsmanager put-secret-value \
        --secret-id "$project_name/anthropic-api-key" \
        --secret-string "$ANTHROPIC_KEY" \
        --region "$AWS_REGION" || true
    
    aws secretsmanager put-secret-value \
        --secret-id "$project_name/telegram-bot-token" \
        --secret-string "$TELEGRAM_TOKEN" \
        --region "$AWS_REGION" || true
    
    # Gateway token only for simple/full (webhook mode)
    if [ "$DEPLOY_DIR" != "minimal" ]; then
        aws secretsmanager put-secret-value \
            --secret-id "$project_name/gateway-auth-token" \
            --secret-string "$GATEWAY_TOKEN" \
            --region "$AWS_REGION" || true
    fi
    
    echo -e "${GREEN}✓ Secrets stored${NC}"
}

# Wait for instance
wait_for_instance() {
    echo ""
    echo -e "${YELLOW}Waiting for EC2 instance to be ready...${NC}"
    
    aws ec2 wait instance-status-ok \
        --instance-ids "$INSTANCE_ID" \
        --region "$AWS_REGION"
    
    # Additional wait for user data to complete
    echo "Waiting for OpenClaw installation (2 minutes)..."
    sleep 120
    
    echo -e "${GREEN}✓ Instance ready${NC}"
}

# Start services
start_services() {
    echo ""
    echo -e "${YELLOW}Starting OpenClaw services...${NC}"
    
    aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["sudo systemctl start caddy || true","sudo systemctl start openclaw"]' \
        --region "$AWS_REGION" \
        --output text > /dev/null
    
    sleep 10
    echo -e "${GREEN}✓ Services started${NC}"
}

# Set webhook
set_telegram_webhook() {
    echo ""
    echo -e "${YELLOW}Setting Telegram webhook...${NC}"
    
    local webhook_url="https://$DOMAIN_NAME/telegram-webhook"
    
    curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/setWebhook?url=$webhook_url" | jq .
    
    echo -e "${GREEN}✓ Webhook configured${NC}"
}

# Print summary
print_summary() {
    echo ""
    echo -e "${GREEN}=============================================="
    echo "         DEPLOYMENT COMPLETE! 🎉"
    echo "==============================================${NC}"
    echo ""
    
    if [ -n "$PUBLIC_IP" ]; then
        echo -e "${YELLOW}⚠️  ACTION REQUIRED: Point your domain to this IP${NC}"
        echo ""
        echo "   $DOMAIN_NAME → $PUBLIC_IP"
        echo ""
    fi
    
    if [ -n "$ALB_DNS" ]; then
        echo -e "${YELLOW}⚠️  ACTION REQUIRED: Create a CNAME record${NC}"
        echo ""
        echo "   $DOMAIN_NAME → $ALB_DNS"
        echo ""
    fi
    
    echo "Connect to your instance:"
    echo "   aws ssm start-session --target $INSTANCE_ID"
    echo ""
    echo "Check OpenClaw status:"
    echo "   sudo systemctl status openclaw"
    echo ""
    echo "View logs:"
    echo "   sudo journalctl -u openclaw -f"
    echo ""
    echo "Your gateway token (save this!):"
    echo "   $GATEWAY_TOKEN"
    echo ""
    echo -e "${BLUE}Once DNS propagates, message your Telegram bot!${NC}"
}

# Main
main() {
    check_prerequisites
    get_user_input
    create_tfvars
    deploy_infrastructure
    store_secrets
    
    if [ -n "$INSTANCE_ID" ]; then
        wait_for_instance
        start_services
    fi
    
    if [ -n "$TELEGRAM_TOKEN" ]; then
        set_telegram_webhook
    fi
    
    print_summary
}

main "$@"
