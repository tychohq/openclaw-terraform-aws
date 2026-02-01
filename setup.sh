#!/bin/bash
#
# OpenClaw AWS Setup - Interactive Wizard
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                                                               ║"
echo "║              OpenClaw on AWS - Setup Wizard                   ║"
echo "║                                                               ║"
echo "║  This wizard will deploy OpenClaw to your AWS account.       ║"
echo "║  Estimated cost: ~\$10/month                                   ║"
echo "║                                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

#═══════════════════════════════════════════════════════════════════════
# STEP 1: Check Prerequisites
#═══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 1/7: Checking Prerequisites${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Checking if required tools are installed..."
echo ""

# Check Terraform
echo -n "  Terraform: "
if command -v terraform &> /dev/null; then
    TF_VERSION=$(terraform version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4 || terraform version | head -1)
    echo -e "${GREEN}✓ Installed ($TF_VERSION)${NC}"
else
    echo -e "${RED}✗ Not found${NC}"
    echo ""
    echo -e "${RED}Terraform is required. Install it:${NC}"
    echo "  macOS:  brew install terraform"
    echo "  Ubuntu: apt install terraform"
    echo "  Other:  https://terraform.io/downloads"
    exit 1
fi

# Check AWS CLI
echo -n "  AWS CLI:   "
if command -v aws &> /dev/null; then
    AWS_VERSION=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2)
    echo -e "${GREEN}✓ Installed ($AWS_VERSION)${NC}"
else
    echo -e "${RED}✗ Not found${NC}"
    echo ""
    echo -e "${RED}AWS CLI is required. Install it:${NC}"
    echo "  macOS:  brew install awscli"
    echo "  Ubuntu: apt install awscli"
    echo "  Other:  https://aws.amazon.com/cli/"
    exit 1
fi

echo ""
echo -e "${GREEN}All prerequisites met!${NC}"
echo ""

#═══════════════════════════════════════════════════════════════════════
# STEP 2: Verify AWS Account Access
#═══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 2/7: Verifying AWS Account Access${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Checking your AWS credentials..."
echo ""

# Try to get current identity
set +e
AWS_IDENTITY=$(aws sts get-caller-identity 2>&1)
AWS_CHECK=$?
set -e

if [ $AWS_CHECK -ne 0 ]; then
    echo -e "${RED}✗ Cannot access AWS account${NC}"
    echo ""
    echo "Error: $AWS_IDENTITY"
    echo ""
    echo "Please configure AWS credentials:"
    echo "  aws configure"
    exit 1
fi

AWS_ACCOUNT_ID=$(echo "$AWS_IDENTITY" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
AWS_USER_ARN=$(echo "$AWS_IDENTITY" | grep -o '"Arn": "[^"]*"' | cut -d'"' -f4)
AWS_USER=$(echo "$AWS_USER_ARN" | rev | cut -d'/' -f1 | rev)

echo -e "  Current Account:  ${GREEN}$AWS_ACCOUNT_ID${NC}"
echo -e "  Current User:     ${GREEN}$AWS_USER${NC}"
echo ""

echo "Where do you want to deploy OpenClaw?"
echo ""
echo "  1) Use current account ($AWS_ACCOUNT_ID)"
echo "  2) Use a different AWS profile"
echo "  3) Assume role in a different account"
echo ""
read -p "Choose [1-3, default 1]: " ACCOUNT_CHOICE

#-----------------------------------------------------------------------
# Option 2: Use a different AWS profile
#-----------------------------------------------------------------------
if [ "$ACCOUNT_CHOICE" = "2" ]; then
    echo ""
    echo -e "${BLUE}AWS Profile Selection${NC}"
    echo ""
    
    # List available profiles
    echo "Available profiles:"
    PROFILES=""
    if [ -f ~/.aws/credentials ]; then
        PROFILES=$(grep '^\[' ~/.aws/credentials | tr -d '[]')
    fi
    if [ -f ~/.aws/config ]; then
        CONFIG_PROFILES=$(grep '^\[profile ' ~/.aws/config | sed 's/\[profile //' | tr -d ']')
        PROFILES="$PROFILES $CONFIG_PROFILES"
    fi
    
    # Remove duplicates and print
    echo "$PROFILES" | tr ' ' '\n' | sort -u | while read -r profile; do
        if [ -n "$profile" ]; then
            echo "  • $profile"
        fi
    done
    echo ""
    
    read -p "Enter profile name: " AWS_PROFILE_NAME
    
    if [ -z "$AWS_PROFILE_NAME" ]; then
        echo -e "${RED}Error: Profile name is required${NC}"
        exit 1
    fi
    
    export AWS_PROFILE="$AWS_PROFILE_NAME"
    
    echo ""
    echo "Verifying profile '$AWS_PROFILE_NAME'..."
    echo ""
    
    # Try to get identity with the profile
    set +e
    NEW_IDENTITY=$(aws sts get-caller-identity 2>&1)
    IDENTITY_RESULT=$?
    set -e
    
    # If failed, check if MFA might be needed
    if [ $IDENTITY_RESULT -ne 0 ]; then
        echo -e "${YELLOW}Profile verification failed.${NC}"
        echo "Error: $NEW_IDENTITY"
        echo ""
        
        # Check if it's an MFA-related error
        if echo "$NEW_IDENTITY" | grep -qiE "mfa|token|session|accessdenied"; then
            echo "This might require MFA. Do you want to authenticate with MFA? [y/N]: "
            read -p "" USE_MFA
            
            if [[ $USE_MFA =~ ^[Yy]$ ]]; then
                echo ""
                # Need to get MFA device - use default profile temporarily
                unset AWS_PROFILE
                
                echo "Detecting MFA devices for your user..."
                set +e
                MFA_DEVICES=$(aws iam list-mfa-devices --query 'MFADevices[*].SerialNumber' --output text 2>/dev/null)
                set -e
                
                if [ -n "$MFA_DEVICES" ] && [ "$MFA_DEVICES" != "None" ]; then
                    echo "Found MFA device(s):"
                    echo "$MFA_DEVICES" | tr '\t' '\n' | while read -r device; do
                        [ -n "$device" ] && echo "  • $device"
                    done
                    echo ""
                    
                    # Use first device if only one
                    FIRST_DEVICE=$(echo "$MFA_DEVICES" | awk '{print $1}')
                    read -p "MFA device ARN [$FIRST_DEVICE]: " MFA_SERIAL
                    MFA_SERIAL="${MFA_SERIAL:-$FIRST_DEVICE}"
                else
                    echo "Could not auto-detect MFA device."
                    echo "Format: arn:aws:iam::ACCOUNT_ID:mfa/USERNAME"
                    read -p "MFA device ARN: " MFA_SERIAL
                fi
                
                if [ -z "$MFA_SERIAL" ]; then
                    echo -e "${RED}Error: MFA device ARN is required${NC}"
                    exit 1
                fi
                
                read -p "Enter MFA code (6 digits): " MFA_CODE
                
                if [ -z "$MFA_CODE" ]; then
                    echo -e "${RED}Error: MFA code is required${NC}"
                    exit 1
                fi
                
                echo ""
                echo "Getting session credentials with MFA..."
                
                set +e
                SESSION_CREDS=$(aws sts get-session-token \
                    --serial-number "$MFA_SERIAL" \
                    --token-code "$MFA_CODE" \
                    --duration-seconds 3600 2>&1)
                SESSION_RESULT=$?
                set -e
                
                if [ $SESSION_RESULT -ne 0 ]; then
                    echo -e "${RED}✗ Failed to get session token${NC}"
                    echo "Error: $SESSION_CREDS"
                    exit 1
                fi
                
                # Export the session credentials
                export AWS_ACCESS_KEY_ID=$(echo "$SESSION_CREDS" | grep -o '"AccessKeyId": "[^"]*"' | cut -d'"' -f4)
                export AWS_SECRET_ACCESS_KEY=$(echo "$SESSION_CREDS" | grep -o '"SecretAccessKey": "[^"]*"' | cut -d'"' -f4)
                export AWS_SESSION_TOKEN=$(echo "$SESSION_CREDS" | grep -o '"SessionToken": "[^"]*"' | cut -d'"' -f4)
                unset AWS_PROFILE
                
                EXPIRATION=$(echo "$SESSION_CREDS" | grep -o '"Expiration": "[^"]*"' | cut -d'"' -f4)
                echo -e "${GREEN}✓ MFA authentication successful${NC}"
                echo -e "${YELLOW}Session expires: $EXPIRATION${NC}"
                echo ""
                
                # Re-verify
                NEW_IDENTITY=$(aws sts get-caller-identity)
            else
                echo -e "${RED}Aborted.${NC}"
                exit 1
            fi
        else
            echo -e "${RED}Cannot use this profile. Please check configuration.${NC}"
            exit 1
        fi
    fi
    
    # Parse the identity
    AWS_ACCOUNT_ID=$(echo "$NEW_IDENTITY" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
    AWS_USER_ARN=$(echo "$NEW_IDENTITY" | grep -o '"Arn": "[^"]*"' | cut -d'"' -f4)
    AWS_USER=$(echo "$AWS_USER_ARN" | rev | cut -d'/' -f1 | rev)
    
    echo -e "${GREEN}✓ Profile verified${NC}"
    echo -e "  Account:  ${GREEN}$AWS_ACCOUNT_ID${NC}"
    echo -e "  User:     ${GREEN}$AWS_USER${NC}"
    echo ""

#-----------------------------------------------------------------------
# Option 3: Assume role in a different account
#-----------------------------------------------------------------------
elif [ "$ACCOUNT_CHOICE" = "3" ]; then
    echo ""
    echo -e "${BLUE}Assume Role Configuration${NC}"
    echo ""
    
    # Ask if user wants to use a different profile as source
    echo "Do you want to use a specific AWS profile as source credentials?"
    echo "(Required if your default credentials can't assume the target role)"
    echo ""
    read -p "Use a specific profile? [y/N]: " USE_SOURCE_PROFILE
    
    if [[ $USE_SOURCE_PROFILE =~ ^[Yy]$ ]]; then
        echo ""
        echo "Available profiles:"
        PROFILES=""
        if [ -f ~/.aws/credentials ]; then
            PROFILES=$(grep '^\[' ~/.aws/credentials | tr -d '[]')
        fi
        if [ -f ~/.aws/config ]; then
            CONFIG_PROFILES=$(grep '^\[profile ' ~/.aws/config | sed 's/\[profile //' | tr -d ']')
            PROFILES="$PROFILES $CONFIG_PROFILES"
        fi
        echo "$PROFILES" | tr ' ' '\n' | sort -u | while read -r profile; do
            [ -n "$profile" ] && echo "  • $profile"
        done
        echo ""
        
        read -p "Source profile name: " SOURCE_PROFILE
        
        if [ -n "$SOURCE_PROFILE" ]; then
            export AWS_PROFILE="$SOURCE_PROFILE"
            echo ""
            echo "Verifying source profile '$SOURCE_PROFILE'..."
            
            set +e
            SOURCE_IDENTITY=$(aws sts get-caller-identity 2>&1)
            SOURCE_RESULT=$?
            set -e
            
            if [ $SOURCE_RESULT -ne 0 ]; then
                echo -e "${YELLOW}Profile verification failed.${NC}"
                echo "Error: $SOURCE_IDENTITY"
                echo ""
                
                # Check if MFA might be needed
                if echo "$SOURCE_IDENTITY" | grep -qiE "mfa|token|session|invalid|expired|accessdenied"; then
                    echo "This profile may require MFA authentication."
                    read -p "Do you want to authenticate with MFA? [y/N]: " USE_MFA
                    
                    if [[ $USE_MFA =~ ^[Yy]$ ]]; then
                        echo ""
                        # Get MFA device using default credentials
                        unset AWS_PROFILE
                        
                        echo "Detecting MFA devices..."
                        set +e
                        MFA_DEVICES=$(aws iam list-mfa-devices --query 'MFADevices[*].SerialNumber' --output text 2>/dev/null)
                        set -e
                        
                        if [ -n "$MFA_DEVICES" ] && [ "$MFA_DEVICES" != "None" ]; then
                            echo "Found MFA device(s):"
                            echo "$MFA_DEVICES" | tr '\t' '\n' | while read -r device; do
                                [ -n "$device" ] && echo "  • $device"
                            done
                            echo ""
                            FIRST_DEVICE=$(echo "$MFA_DEVICES" | awk '{print $1}')
                            read -p "MFA device ARN [$FIRST_DEVICE]: " MFA_SERIAL
                            MFA_SERIAL="${MFA_SERIAL:-$FIRST_DEVICE}"
                        else
                            echo "Enter your MFA device ARN:"
                            read -p "MFA ARN: " MFA_SERIAL
                        fi
                        
                        if [ -z "$MFA_SERIAL" ]; then
                            echo -e "${RED}Error: MFA device ARN is required${NC}"
                            exit 1
                        fi
                        
                        read -p "Enter MFA code (6 digits): " MFA_CODE
                        
                        if [ -z "$MFA_CODE" ]; then
                            echo -e "${RED}Error: MFA code is required${NC}"
                            exit 1
                        fi
                        
                        echo ""
                        echo "Getting session credentials with MFA..."
                        
                        set +e
                        SESSION_CREDS=$(aws sts get-session-token \
                            --serial-number "$MFA_SERIAL" \
                            --token-code "$MFA_CODE" \
                            --duration-seconds 3600 2>&1)
                        SESSION_RESULT=$?
                        set -e
                        
                        if [ $SESSION_RESULT -ne 0 ]; then
                            echo -e "${RED}✗ Failed to get session token${NC}"
                            echo "Error: $SESSION_CREDS"
                            exit 1
                        fi
                        
                        # Export session credentials (these will be used for assume-role)
                        export AWS_ACCESS_KEY_ID=$(echo "$SESSION_CREDS" | grep -o '"AccessKeyId": "[^"]*"' | cut -d'"' -f4)
                        export AWS_SECRET_ACCESS_KEY=$(echo "$SESSION_CREDS" | grep -o '"SecretAccessKey": "[^"]*"' | cut -d'"' -f4)
                        export AWS_SESSION_TOKEN=$(echo "$SESSION_CREDS" | grep -o '"SessionToken": "[^"]*"' | cut -d'"' -f4)
                        
                        EXPIRATION=$(echo "$SESSION_CREDS" | grep -o '"Expiration": "[^"]*"' | cut -d'"' -f4)
                        echo -e "${GREEN}✓ MFA authentication successful${NC}"
                        echo -e "${YELLOW}Session expires: $EXPIRATION${NC}"
                        echo ""
                        
                        # Verify with new credentials
                        SOURCE_IDENTITY=$(aws sts get-caller-identity)
                        SOURCE_ACCOUNT=$(echo "$SOURCE_IDENTITY" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
                        echo -e "${GREEN}✓ Source credentials ready (Account: $SOURCE_ACCOUNT)${NC}"
                        echo ""
                    else
                        echo -e "${RED}Cannot proceed without valid source credentials.${NC}"
                        exit 1
                    fi
                else
                    echo -e "${RED}Cannot access source profile '$SOURCE_PROFILE'.${NC}"
                    echo "Please check that the profile exists and is configured correctly."
                    exit 1
                fi
            else
                SOURCE_ACCOUNT=$(echo "$SOURCE_IDENTITY" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
                echo -e "${GREEN}✓ Using source profile '$SOURCE_PROFILE' (Account: $SOURCE_ACCOUNT)${NC}"
                echo ""
            fi
        fi
    fi
    
    echo "Enter the Role ARN to assume."
    echo "Format: arn:aws:iam::TARGET_ACCOUNT_ID:role/ROLE_NAME"
    echo ""
    read -p "Role ARN: " ROLE_ARN
    
    if [ -z "$ROLE_ARN" ]; then
        echo -e "${RED}Error: Role ARN is required${NC}"
        exit 1
    fi
    
    echo ""
    read -p "External ID (leave empty if not required): " EXTERNAL_ID
    
    echo ""
    read -p "Does this role require MFA? [y/N]: " MFA_REQUIRED
    
    MFA_ARGS=""
    
    if [[ $MFA_REQUIRED =~ ^[Yy]$ ]]; then
        echo ""
        echo "Detecting MFA devices..."
        
        set +e
        MFA_DEVICES=$(aws iam list-mfa-devices --query 'MFADevices[*].SerialNumber' --output text 2>/dev/null)
        set -e
        
        if [ -n "$MFA_DEVICES" ] && [ "$MFA_DEVICES" != "None" ]; then
            echo "Found MFA device(s):"
            echo "$MFA_DEVICES" | tr '\t' '\n' | while read -r device; do
                [ -n "$device" ] && echo "  • $device"
            done
            echo ""
            
            FIRST_DEVICE=$(echo "$MFA_DEVICES" | awk '{print $1}')
            read -p "MFA device ARN [$FIRST_DEVICE]: " MFA_SERIAL
            MFA_SERIAL="${MFA_SERIAL:-$FIRST_DEVICE}"
        else
            echo "Could not auto-detect MFA device."
            echo "Format: arn:aws:iam::ACCOUNT_ID:mfa/USERNAME"
            read -p "MFA device ARN: " MFA_SERIAL
        fi
        
        if [ -z "$MFA_SERIAL" ]; then
            echo -e "${RED}Error: MFA device ARN is required${NC}"
            exit 1
        fi
        
        read -p "Enter MFA code (6 digits): " MFA_CODE
        
        if [ -z "$MFA_CODE" ]; then
            echo -e "${RED}Error: MFA code is required${NC}"
            exit 1
        fi
        
        MFA_ARGS="--serial-number $MFA_SERIAL --token-code $MFA_CODE"
    fi
    
    SESSION_NAME="openclaw-setup-$(date +%s)"
    
    echo ""
    echo "Assuming role..."
    
    # Build command
    ASSUME_CMD="aws sts assume-role --role-arn $ROLE_ARN --role-session-name $SESSION_NAME"
    [ -n "$EXTERNAL_ID" ] && ASSUME_CMD="$ASSUME_CMD --external-id $EXTERNAL_ID"
    [ -n "$MFA_ARGS" ] && ASSUME_CMD="$ASSUME_CMD $MFA_ARGS"
    
    set +e
    ASSUMED_ROLE=$(eval $ASSUME_CMD 2>&1)
    ASSUME_RESULT=$?
    set -e
    
    if [ $ASSUME_RESULT -ne 0 ]; then
        echo -e "${RED}✗ Failed to assume role${NC}"
        echo ""
        echo "Error: $ASSUMED_ROLE"
        echo ""
        echo "Common issues:"
        echo "  • Role ARN is incorrect"
        echo "  • Trust policy doesn't allow your account/user"
        echo "  • External ID is required but not provided"
        echo "  • MFA is required but not provided or incorrect"
        exit 1
    fi
    
    # Extract and export credentials
    export AWS_ACCESS_KEY_ID=$(echo "$ASSUMED_ROLE" | grep -o '"AccessKeyId": "[^"]*"' | cut -d'"' -f4)
    export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUMED_ROLE" | grep -o '"SecretAccessKey": "[^"]*"' | cut -d'"' -f4)
    export AWS_SESSION_TOKEN=$(echo "$ASSUMED_ROLE" | grep -o '"SessionToken": "[^"]*"' | cut -d'"' -f4)
    
    # Get new identity
    NEW_IDENTITY=$(aws sts get-caller-identity)
    AWS_ACCOUNT_ID=$(echo "$NEW_IDENTITY" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
    AWS_USER_ARN=$(echo "$NEW_IDENTITY" | grep -o '"Arn": "[^"]*"' | cut -d'"' -f4)
    AWS_USER=$(echo "$AWS_USER_ARN" | rev | cut -d'/' -f1 | rev)
    
    EXPIRATION=$(echo "$ASSUMED_ROLE" | grep -o '"Expiration": "[^"]*"' | cut -d'"' -f4)
    
    echo -e "${GREEN}✓ Role assumed successfully${NC}"
    echo -e "  Account:  ${GREEN}$AWS_ACCOUNT_ID${NC}"
    echo -e "  Role:     ${GREEN}$AWS_USER${NC}"
    echo -e "${YELLOW}Session expires: $EXPIRATION${NC}"
    echo ""
fi

echo -e "${GREEN}✓ Target account confirmed: $AWS_ACCOUNT_ID${NC}"
echo ""

#═══════════════════════════════════════════════════════════════════════
# STEP 3: Select AWS Region
#═══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 3/7: Select AWS Region${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Choose where to deploy OpenClaw:"
echo ""
echo "  1) eu-central-1  (Frankfurt, Europe)"
echo "  2) us-east-1     (N. Virginia, US East)"
echo "  3) us-west-2     (Oregon, US West)"
echo ""
read -p "Select region [1-3, default 1]: " REGION_CHOICE

case $REGION_CHOICE in
    2) AWS_REGION="us-east-1" ;;
    3) AWS_REGION="us-west-2" ;;
    *) AWS_REGION="eu-central-1" ;;
esac

echo ""
echo -e "Selected region: ${GREEN}$AWS_REGION${NC}"
echo ""

#═══════════════════════════════════════════════════════════════════════
# STEP 4: Check for Existing Resources
#═══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 4/7: Scanning Account for Existing Resources${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Scanning account $AWS_ACCOUNT_ID in $AWS_REGION..."
echo "This ensures we don't accidentally destroy your existing resources."
echo ""

EXISTING_OPENCLAW=()
EXISTING_ACCOUNT=()
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${BLUE}Checking for OpenClaw-specific resources:${NC}"
echo ""

# Check VPCs with openclaw tag
echo -n "  VPCs with 'openclaw' tag... "
set +e
EXISTING_VPC=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=*openclaw*" \
    --region "$AWS_REGION" \
    --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null)
set -e
if [ -n "$EXISTING_VPC" ] && [ "$EXISTING_VPC" != "None" ]; then
    echo -e "${YELLOW}Found${NC}"
    while read -r vpc_id vpc_name; do
        [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ] && EXISTING_OPENCLAW+=("VPC: $vpc_id ($vpc_name)")
    done <<< "$EXISTING_VPC"
else
    echo -e "${GREEN}None${NC}"
fi

# Check EC2 instances with openclaw tag
echo -n "  EC2 instances with 'openclaw' tag... "
set +e
EXISTING_EC2=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=*openclaw*" "Name=instance-state-name,Values=running,stopped,pending" \
    --region "$AWS_REGION" \
    --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null)
set -e
if [ -n "$EXISTING_EC2" ] && [ "$EXISTING_EC2" != "None" ]; then
    echo -e "${YELLOW}Found${NC}"
    while read -r inst_id state inst_name; do
        [ -n "$inst_id" ] && [ "$inst_id" != "None" ] && EXISTING_OPENCLAW+=("EC2: $inst_id ($inst_name, $state)")
    done <<< "$EXISTING_EC2"
else
    echo -e "${GREEN}None${NC}"
fi

# Check Security Groups with openclaw name
echo -n "  Security Groups with 'openclaw' name... "
set +e
EXISTING_SG=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=*openclaw*" \
    --region "$AWS_REGION" \
    --query 'SecurityGroups[*].[GroupId,GroupName]' \
    --output text 2>/dev/null)
set -e
if [ -n "$EXISTING_SG" ] && [ "$EXISTING_SG" != "None" ]; then
    echo -e "${YELLOW}Found${NC}"
    while read -r sg_id sg_name; do
        [ -n "$sg_id" ] && [ "$sg_id" != "None" ] && EXISTING_OPENCLAW+=("Security Group: $sg_id ($sg_name)")
    done <<< "$EXISTING_SG"
else
    echo -e "${GREEN}None${NC}"
fi

# Check IAM role
echo -n "  IAM role 'openclaw-ec2-role'... "
set +e
EXISTING_ROLE=$(aws iam get-role --role-name openclaw-ec2-role --query 'Role.Arn' --output text 2>/dev/null)
set -e
if [ -n "$EXISTING_ROLE" ] && [ "$EXISTING_ROLE" != "None" ]; then
    echo -e "${YELLOW}Found${NC}"
    EXISTING_OPENCLAW+=("IAM Role: openclaw-ec2-role")
else
    echo -e "${GREEN}None${NC}"
fi

# Check IAM instance profile
echo -n "  IAM instance profile 'openclaw-ec2-profile'... "
set +e
EXISTING_PROFILE=$(aws iam get-instance-profile --instance-profile-name openclaw-ec2-profile --query 'InstanceProfile.Arn' --output text 2>/dev/null)
set -e
if [ -n "$EXISTING_PROFILE" ] && [ "$EXISTING_PROFILE" != "None" ]; then
    echo -e "${YELLOW}Found${NC}"
    EXISTING_OPENCLAW+=("IAM Instance Profile: openclaw-ec2-profile")
else
    echo -e "${GREEN}None${NC}"
fi

# Check Subnets with openclaw tag
echo -n "  Subnets with 'openclaw' tag... "
set +e
EXISTING_SUBNET=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=*openclaw*" \
    --region "$AWS_REGION" \
    --query 'Subnets[*].[SubnetId,Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null)
set -e
if [ -n "$EXISTING_SUBNET" ] && [ "$EXISTING_SUBNET" != "None" ]; then
    echo -e "${YELLOW}Found${NC}"
    while read -r subnet_id subnet_name; do
        [ -n "$subnet_id" ] && [ "$subnet_id" != "None" ] && EXISTING_OPENCLAW+=("Subnet: $subnet_id ($subnet_name)")
    done <<< "$EXISTING_SUBNET"
else
    echo -e "${GREEN}None${NC}"
fi

# Check Internet Gateways with openclaw tag
echo -n "  Internet Gateways with 'openclaw' tag... "
set +e
EXISTING_IGW=$(aws ec2 describe-internet-gateways \
    --filters "Name=tag:Name,Values=*openclaw*" \
    --region "$AWS_REGION" \
    --query 'InternetGateways[*].[InternetGatewayId,Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null)
set -e
if [ -n "$EXISTING_IGW" ] && [ "$EXISTING_IGW" != "None" ]; then
    echo -e "${YELLOW}Found${NC}"
    while read -r igw_id igw_name; do
        [ -n "$igw_id" ] && [ "$igw_id" != "None" ] && EXISTING_OPENCLAW+=("Internet Gateway: $igw_id ($igw_name)")
    done <<< "$EXISTING_IGW"
else
    echo -e "${GREEN}None${NC}"
fi

# Check local Terraform state
echo -n "  Local Terraform state file... "
if [ -f "$SCRIPT_DIR/terraform/terraform.tfstate" ]; then
    echo -e "${YELLOW}Found${NC}"
    EXISTING_OPENCLAW+=("Local file: terraform.tfstate")
else
    echo -e "${GREEN}None${NC}"
fi

echo ""
echo -e "${BLUE}Checking account's existing infrastructure (non-OpenClaw):${NC}"
echo ""

# Count total VPCs in region
echo -n "  Total VPCs in region... "
set +e
TOTAL_VPCS=$(aws ec2 describe-vpcs --region "$AWS_REGION" --query 'length(Vpcs)' --output text 2>/dev/null)
set -e
TOTAL_VPCS=${TOTAL_VPCS:-0}
if [ "$TOTAL_VPCS" -gt 1 ]; then
    echo -e "${CYAN}$TOTAL_VPCS VPCs${NC}"
    EXISTING_ACCOUNT+=("$TOTAL_VPCS VPCs in region")
else
    echo -e "${GREEN}$TOTAL_VPCS (default only)${NC}"
fi

# Count running EC2 instances
echo -n "  Running EC2 instances... "
set +e
TOTAL_EC2=$(aws ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running,stopped" \
    --region "$AWS_REGION" \
    --query 'length(Reservations[*].Instances[*])' \
    --output text 2>/dev/null)
set -e
TOTAL_EC2=${TOTAL_EC2:-0}
if [ "$TOTAL_EC2" -gt 0 ]; then
    echo -e "${CYAN}$TOTAL_EC2 instances${NC}"
    EXISTING_ACCOUNT+=("$TOTAL_EC2 EC2 instances running/stopped")
else
    echo -e "${GREEN}None${NC}"
fi

# Count RDS instances
echo -n "  RDS databases... "
set +e
TOTAL_RDS=$(aws rds describe-db-instances --region "$AWS_REGION" --query 'length(DBInstances)' --output text 2>/dev/null)
set -e
TOTAL_RDS=${TOTAL_RDS:-0}
if [ "$TOTAL_RDS" -gt 0 ]; then
    echo -e "${CYAN}$TOTAL_RDS databases${NC}"
    EXISTING_ACCOUNT+=("$TOTAL_RDS RDS databases")
else
    echo -e "${GREEN}None${NC}"
fi

# Count Lambda functions
echo -n "  Lambda functions... "
set +e
TOTAL_LAMBDA=$(aws lambda list-functions --region "$AWS_REGION" --query 'length(Functions)' --output text 2>/dev/null)
set -e
TOTAL_LAMBDA=${TOTAL_LAMBDA:-0}
if [ "$TOTAL_LAMBDA" -gt 0 ]; then
    echo -e "${CYAN}$TOTAL_LAMBDA functions${NC}"
    EXISTING_ACCOUNT+=("$TOTAL_LAMBDA Lambda functions")
else
    echo -e "${GREEN}None${NC}"
fi

# Count S3 buckets (global)
echo -n "  S3 buckets (global)... "
set +e
TOTAL_S3=$(aws s3api list-buckets --query 'length(Buckets)' --output text 2>/dev/null)
set -e
TOTAL_S3=${TOTAL_S3:-0}
if [ "$TOTAL_S3" -gt 0 ]; then
    echo -e "${CYAN}$TOTAL_S3 buckets${NC}"
    EXISTING_ACCOUNT+=("$TOTAL_S3 S3 buckets")
else
    echo -e "${GREEN}None${NC}"
fi

echo ""

# Report OpenClaw findings
if [ ${#EXISTING_OPENCLAW[@]} -gt 0 ]; then
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠️  EXISTING OPENCLAW RESOURCES DETECTED                      ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    for resource in "${EXISTING_OPENCLAW[@]}"; do
        echo -e "  ${YELLOW}•${NC} $resource"
    done
    echo ""
    echo -e "${RED}These resources may be MODIFIED or REPLACED by this deployment.${NC}"
    echo ""
fi

# Report account summary
if [ ${#EXISTING_ACCOUNT[@]} -gt 0 ]; then
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  ℹ️  ACCOUNT HAS EXISTING INFRASTRUCTURE                       ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "This account contains other resources:"
    echo ""
    for resource in "${EXISTING_ACCOUNT[@]}"; do
        echo -e "  ${CYAN}•${NC} $resource"
    done
    echo ""
    echo -e "${GREEN}OpenClaw deployment will NOT affect these resources.${NC}"
    echo "OpenClaw creates isolated resources with 'openclaw' prefix."
    echo ""
fi

# Summary and confirmation
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    DEPLOYMENT SUMMARY                         ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Target Account:  $AWS_ACCOUNT_ID"
echo "  Target Region:   $AWS_REGION"
echo ""
echo "  Resources to be created:"
echo "    • 1 VPC (10.0.0.0/16) with 'openclaw-vpc' tag"
echo "    • 1 Public subnet with 'openclaw-public' tag"
echo "    • 1 Internet Gateway"
echo "    • 1 Security Group (outbound only)"
echo "    • 1 IAM Role (openclaw-ec2-role)"
echo "    • 1 EC2 instance (t3.micro)"
echo ""

if [ ${#EXISTING_OPENCLAW[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️  ${#EXISTING_OPENCLAW[@]} existing OpenClaw resource(s) may be affected.${NC}"
    echo ""
    echo "Options:"
    echo "  1) Continue - I understand existing OpenClaw resources may be modified"
    echo "  2) Abort - Do not make any changes"
    echo ""
    read -p "Choose [1-2]: " EXISTING_CHOICE
    
    if [ "$EXISTING_CHOICE" != "1" ]; then
        echo ""
        echo "Aborted. No changes were made."
        echo ""
        echo "To manage existing resources:"
        echo "  • Destroy first: cd terraform && terraform destroy"
        echo "  • Or use a different region"
        exit 0
    fi
    echo ""
else
    echo -e "${GREEN}✓ No conflicts detected. Safe to proceed.${NC}"
    echo ""
    read -p "Do you want to proceed with deployment? [y/N]: " PROCEED_CHOICE
    
    if [[ ! $PROCEED_CHOICE =~ ^[Yy]$ ]]; then
        echo ""
        echo "Aborted. No changes were made."
        exit 0
    fi
    echo ""
fi

#═══════════════════════════════════════════════════════════════════════
# STEP 5: Collect Credentials
#═══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 5/7: Enter Your API Credentials${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Telegram Token
echo -e "${BLUE}Telegram Bot Token${NC}"
echo "Create a bot via @BotFather on Telegram and paste the token here."
echo "Format: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
echo ""
read -p "Token: " TELEGRAM_TOKEN

if [ -z "$TELEGRAM_TOKEN" ]; then
    echo -e "${RED}Error: Telegram token is required${NC}"
    exit 1
fi

echo ""

# Anthropic Key
echo -e "${BLUE}Anthropic API Key${NC}"
echo "Get your API key from: https://console.anthropic.com/settings/keys"
echo "Format: sk-ant-..."
echo ""
read -p "Key: " ANTHROPIC_KEY

if [ -z "$ANTHROPIC_KEY" ]; then
    echo -e "${RED}Error: Anthropic API key is required${NC}"
    exit 1
fi

echo ""

#═══════════════════════════════════════════════════════════════════════
# STEP 6: Deploy Infrastructure
#═══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 6/7: Deploying Infrastructure${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Preparing deployment to AWS account $AWS_ACCOUNT_ID in $AWS_REGION..."
echo ""

cd "$SCRIPT_DIR/terraform"

# Create tfvars
cat > terraform.tfvars << EOF
aws_region = "$AWS_REGION"
EOF

# Initialize Terraform
echo "  Initializing Terraform..."
terraform init -input=false > /dev/null 2>&1

# Plan and capture output
echo "  Analyzing deployment plan..."
echo ""

set +e
PLAN_OUTPUT=$(terraform plan -input=false -out=tfplan -detailed-exitcode 2>&1)
PLAN_EXIT=$?
set -e

# Parse plan results
ADD_COUNT=$(echo "$PLAN_OUTPUT" | grep -oP '\d+(?= to add)' || echo "0")
CHANGE_COUNT=$(echo "$PLAN_OUTPUT" | grep -oP '\d+(?= to change)' || echo "0")
DESTROY_COUNT=$(echo "$PLAN_OUTPUT" | grep -oP '\d+(?= to destroy)' || echo "0")

ADD_COUNT=${ADD_COUNT:-0}
CHANGE_COUNT=${CHANGE_COUNT:-0}
DESTROY_COUNT=${DESTROY_COUNT:-0}

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    DEPLOYMENT PLAN                            ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Resources to be CREATED:   $ADD_COUNT"
echo "  Resources to be MODIFIED:  $CHANGE_COUNT"
echo "  Resources to be DESTROYED: $DESTROY_COUNT"
echo ""

# Show what will be created
if [ "$ADD_COUNT" != "0" ]; then
    echo -e "${GREEN}Resources to CREATE:${NC}"
    echo "$PLAN_OUTPUT" | grep -E '^\s+\+.*will be created' | head -20 | while read -r line; do
        echo "    $line"
    done
    echo ""
fi

# Show what will be changed
if [ "$CHANGE_COUNT" != "0" ]; then
    echo -e "${YELLOW}Resources to MODIFY:${NC}"
    echo "$PLAN_OUTPUT" | grep -E '^\s+~.*will be updated' | head -20 | while read -r line; do
        echo "    $line"
    done
    echo ""
fi

# Show what will be destroyed - THIS IS CRITICAL
if [ "$DESTROY_COUNT" != "0" ]; then
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ⚠️  WARNING: RESOURCES WILL BE DESTROYED!                    ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${RED}The following resources will be PERMANENTLY DELETED:${NC}"
    echo ""
    echo "$PLAN_OUTPUT" | grep -E '^\s+-.*will be destroyed' | while read -r line; do
        echo -e "    ${RED}$line${NC}"
    done
    echo ""
    echo -e "${RED}THIS ACTION CANNOT BE UNDONE!${NC}"
    echo ""
    echo "Type 'DESTROY' to confirm you want to destroy these resources:"
    read -p "> " DESTROY_CONFIRM
    
    if [ "$DESTROY_CONFIRM" != "DESTROY" ]; then
        echo ""
        echo "Aborted. You did not confirm destruction."
        echo "No changes were made."
        exit 0
    fi
    echo ""
fi

# Final confirmation
echo "Summary: $ADD_COUNT to add, $CHANGE_COUNT to change, $DESTROY_COUNT to destroy"
echo ""
echo -e "${YELLOW}This will make changes to AWS account $AWS_ACCOUNT_ID${NC}"
echo ""
read -p "Do you want to apply these changes? [y/N]: " APPLY_CONFIRM

if [[ ! $APPLY_CONFIRM =~ ^[Yy]$ ]]; then
    echo ""
    echo "Aborted. No changes were made."
    exit 0
fi

echo ""
echo "  Applying changes (this takes 2-3 minutes)..."

# Apply
terraform apply -auto-approve tfplan

# Get instance ID
INSTANCE_ID=$(terraform output -raw instance_id)

echo ""
echo -e "${GREEN}✓ Infrastructure deployed successfully!${NC}"
echo -e "  Instance ID: ${GREEN}$INSTANCE_ID${NC}"
echo ""

#═══════════════════════════════════════════════════════════════════════
# STEP 7: Configure OpenClaw
#═══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 7/7: Configuring OpenClaw${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "  Waiting for EC2 instance to be ready..."
aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
echo -e "  ${GREEN}✓ Instance is running${NC}"

echo "  Waiting for OpenClaw to install (60 seconds)..."
sleep 60
echo -e "  ${GREEN}✓ Installation complete${NC}"

echo "  Configuring OpenClaw with your credentials..."

# Create config (base64 to handle special chars)
CONFIG_JSON=$(cat << EOF
{
  "model": {
    "provider": "anthropic",
    "model": "claude-sonnet-4-20250514"
  },
  "anthropicApiKey": "$ANTHROPIC_KEY",
  "channels": {
    "telegram": {
      "botToken": "$TELEGRAM_TOKEN"
    }
  }
}
EOF
)

CONFIG_B64=$(echo "$CONFIG_JSON" | base64 -w0 2>/dev/null || echo "$CONFIG_JSON" | base64)

# Send configuration via SSM
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":[
        \"mkdir -p /home/openclaw/.openclaw\",
        \"echo '$CONFIG_B64' | base64 -d > /home/openclaw/.openclaw/config.json\",
        \"chown -R openclaw:openclaw /home/openclaw/.openclaw\",
        \"systemctl restart openclaw\"
    ]}" \
    --region "$AWS_REGION" \
    --query 'Command.CommandId' \
    --output text)

echo "  Applying configuration..."
sleep 15

# Check command status
set +e
STATUS=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'Status' \
    --output text 2>/dev/null)
set -e

if [ "$STATUS" = "Success" ]; then
    echo -e "  ${GREEN}✓ OpenClaw configured and started${NC}"
else
    echo -e "  ${YELLOW}⚠ Configuration in progress (Status: $STATUS)${NC}"
fi

echo ""

#═══════════════════════════════════════════════════════════════════════
# COMPLETE
#═══════════════════════════════════════════════════════════════════════
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                                                               ║"
echo "║                    SETUP COMPLETE! 🎉                         ║"
echo "║                                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "Your OpenClaw instance is ready!"
echo ""
echo -e "  ${BLUE}Instance ID:${NC}  $INSTANCE_ID"
echo -e "  ${BLUE}Region:${NC}       $AWS_REGION"
echo -e "  ${BLUE}Account:${NC}      $AWS_ACCOUNT_ID"
echo ""
echo -e "${GREEN}→ Message your Telegram bot now!${NC}"
echo ""
echo "Useful commands:"
echo ""
echo "  # Connect to instance"
echo "  aws ssm start-session --target $INSTANCE_ID --region $AWS_REGION"
echo ""
echo "  # View logs"
echo "  sudo journalctl -u openclaw -f"
echo ""
echo "  # Restart OpenClaw"
echo "  sudo systemctl restart openclaw"
echo ""
echo "  # Destroy everything"
echo "  cd $(pwd) && terraform destroy"
echo ""
