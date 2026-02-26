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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_STEPS=8
AUTO_MODE=false

# Helper: prompt user or use default in auto mode
# Usage: ask VAR_NAME "prompt text" "default_value"
ask() {
    local var_name="$1" prompt="$2" default="${3:-}"
    if [ "$AUTO_MODE" = true ]; then
        eval "$var_name=\"\$default\""
    else
        read -p "$prompt" _input
        eval "$var_name=\"\${_input:-\$default}\""
    fi
}

DEPLOY_DIR=""

# Parse flags
for arg in "$@"; do
    case "$arg" in
        --auto)   AUTO_MODE=true ;;
        --destroy) ;; # handled below
        --config=*) DEPLOY_DIR="${arg#--config=}" ;;
        --config)   ;; # next arg handled below
        --help|-h)
            echo "Usage: ./setup.sh [--auto] [--config <dir>] [--destroy]"
            echo ""
            echo "  (no flags)  Interactive wizard — prompts for every setting"
            echo "  --auto      Non-interactive — reads all values from .env, fails if incomplete"
            echo "  --config    Path to deployment directory (contains .env, state files)"
            echo "  --destroy   Tear down all infrastructure created by this deployment"
            echo ""
            echo "The .env file pre-fills wizard defaults and is required for --auto."
            echo "Copy .env.example to .env and fill in your values."
            echo ""
            echo "For multi-deployment setups, use a private repo:"
            echo "  ./setup.sh --config ~/openclaw-deployments/myorg/my-agent --auto"
            exit 0
            ;;
    esac
done

# Handle --config <dir> (two-arg form)
PREV_ARG=""
for arg in "$@"; do
    if [ "$PREV_ARG" = "--config" ]; then
        DEPLOY_DIR="$arg"
    fi
    PREV_ARG="$arg"
done

# OPENCLAW_DEPLOY_DIR env var as fallback
DEPLOY_DIR="${DEPLOY_DIR:-${OPENCLAW_DEPLOY_DIR:-}}"

# Resolve deploy directory — determines where .env, tfstate, and tfvars live
if [ -n "$DEPLOY_DIR" ]; then
    DEPLOY_DIR="$(cd "$DEPLOY_DIR" 2>/dev/null && pwd)" || {
        echo -e "${RED}Error: --config directory does not exist: $DEPLOY_DIR${NC}"
        exit 1
    }
    ENV_FILE="$DEPLOY_DIR/.env"
    STATE_DIR="$DEPLOY_DIR"
else
    ENV_FILE="$SCRIPT_DIR/.env"
    STATE_DIR="$SCRIPT_DIR/terraform"
fi

# Source .env if it exists (pre-fills wizard prompts)
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
    echo -e "${CYAN}Loaded .env file: $ENV_FILE${NC}"
    echo ""
elif [ "$AUTO_MODE" = true ]; then
    echo -e "${RED}Error: --auto requires a .env file but none found at: $ENV_FILE${NC}"
    echo "Copy .env.example to .env and fill in your values."
    exit 1
fi

#═══════════════════════════════════════════════════════════════════════
# --auto mode: validate .env has everything we need
#═══════════════════════════════════════════════════════════════════════
if [ "$AUTO_MODE" = true ]; then
    MISSING=()

    # Required fields
    [ -z "${DEPLOYMENT_NAME:-}" ] && MISSING+=("DEPLOYMENT_NAME  (e.g. my-openclaw)")
    [ -z "${AWS_REGION:-}" ]      && MISSING+=("AWS_REGION       (e.g. us-east-1)")

    # Need at least one LLM provider
    if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -z "${OPENAI_API_KEY:-}" ]; then
        MISSING+=("ANTHROPIC_API_KEY or OPENAI_API_KEY  (at least one required)")
    fi

    # Need at least one channel
    HAS_SLACK=false
    HAS_DISCORD=false
    HAS_TELEGRAM=false

    if [ -n "${SLACK_BOT_TOKEN:-}" ]; then
        HAS_SLACK=true
        [ -z "${SLACK_APP_TOKEN:-}" ] && MISSING+=("SLACK_APP_TOKEN   (required when SLACK_BOT_TOKEN is set — Socket Mode app token)")
    fi

    if [ -n "${DISCORD_BOT_TOKEN:-}" ]; then
        HAS_DISCORD=true
        [ -z "${DISCORD_GUILD_ID:-}" ] && MISSING+=("DISCORD_GUILD_ID  (required when DISCORD_BOT_TOKEN is set)")
        [ -z "${DISCORD_OWNER_ID:-}" ] && MISSING+=("DISCORD_OWNER_ID  (required when DISCORD_BOT_TOKEN is set)")
    fi

    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
        HAS_TELEGRAM=true
        [ -z "${TELEGRAM_OWNER_ID:-}" ] && MISSING+=("TELEGRAM_OWNER_ID (required when TELEGRAM_BOT_TOKEN is set)")
    fi

    if [ "$HAS_SLACK" = false ] && [ "$HAS_DISCORD" = false ] && [ "$HAS_TELEGRAM" = false ]; then
        MISSING+=("SLACK_BOT_TOKEN, DISCORD_BOT_TOKEN, or TELEGRAM_BOT_TOKEN  (at least one channel required)")
    fi

    # Validate deployment name format
    if [ -n "${DEPLOYMENT_NAME:-}" ]; then
        if ! echo "$DEPLOYMENT_NAME" | grep -qE '^[a-z][a-z0-9-]{0,23}$'; then
            MISSING+=("DEPLOYMENT_NAME  (must be lowercase alphanumeric/hyphens, start with letter, max 24 chars — got: '$DEPLOYMENT_NAME')")
        fi
    fi

    if [ ${#MISSING[@]} -gt 0 ]; then
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}  Missing required .env values for --auto mode${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        for field in "${MISSING[@]}"; do
            echo -e "  ${RED}✗${NC} $field"
        done
        echo ""
        echo "Edit your .env file and re-run:  ./setup.sh --auto"
        echo "Or run without --auto for the interactive wizard."
        exit 1
    fi

    echo -e "${GREEN}✓ .env validated — all required values present${NC}"
    echo ""
fi

#═══════════════════════════════════════════════════════════════════════
# --destroy flag
#═══════════════════════════════════════════════════════════════════════
if [[ " $* " == *" --destroy "* ]] || [ "${1:-}" = "--destroy" ]; then
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  DESTROY OpenClaw Infrastructure${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if [ ! -f "$SCRIPT_DIR/terraform/terraform.tfstate" ]; then
        echo "No Terraform state found in terraform/. Nothing to destroy."
        exit 0
    fi

    cd "$SCRIPT_DIR/terraform"

    echo "Checking what will be destroyed..."
    echo ""

    set +e
    PLAN_OUTPUT=$(terraform plan -destroy -input=false 2>&1)
    set -e

    DESTROY_COUNT=$(echo "$PLAN_OUTPUT" | grep -oE '[0-9]+ to destroy' | grep -oE '[0-9]+' || echo "0")
    DESTROY_COUNT=${DESTROY_COUNT:-0}

    if [ "$DESTROY_COUNT" = "0" ]; then
        echo "No resources to destroy."
        exit 0
    fi

    echo -e "${RED}$DESTROY_COUNT resource(s) will be PERMANENTLY DESTROYED.${NC}"
    echo ""
    echo "$PLAN_OUTPUT" | grep -E '^\s+#.*will be destroyed' | while read -r line; do
        echo -e "  ${RED}$line${NC}"
    done
    echo ""
    echo -e "${RED}THIS ACTION CANNOT BE UNDONE!${NC}"
    echo ""

    if [ "$AUTO_MODE" = true ]; then
        echo -e "${YELLOW}--auto mode: skipping confirmation${NC}"
        DESTROY_CONFIRM="DESTROY"
    else
        read -p "Type 'DESTROY' to confirm: " DESTROY_CONFIRM
    fi

    if [ "$DESTROY_CONFIRM" != "DESTROY" ]; then
        echo ""
        echo "Aborted. No changes were made."
        exit 0
    fi

    echo ""
    echo "Destroying infrastructure..."
    terraform destroy -auto-approve

    echo ""
    echo -e "${GREEN}Infrastructure destroyed.${NC}"
    echo ""
    echo "To re-deploy:"
    echo "  ./setup.sh"
    exit 0
fi

#═══════════════════════════════════════════════════════════════════════
# Banner
#═══════════════════════════════════════════════════════════════════════
[ "$AUTO_MODE" != true ] && clear
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                                                               ║"
echo "║              OpenClaw on AWS - Setup Wizard                   ║"
echo "║                                                               ║"
echo "║  This wizard will deploy OpenClaw to your AWS account.       ║"
echo "║  Estimated cost: ~\$17/month (eu-central-1)                    ║"
echo "║                                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

#═══════════════════════════════════════════════════════════════════════
# STEP 1: Check Prerequisites
#═══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 1/$TOTAL_STEPS: Checking Prerequisites${NC}"
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
    echo "  https://terraform.io/downloads"
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
    echo "  https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

# Check jq
echo -n "  jq:        "
if command -v jq &> /dev/null; then
    JQ_VERSION=$(jq --version 2>&1)
    echo -e "${GREEN}✓ Installed ($JQ_VERSION)${NC}"
else
    echo -e "${RED}✗ Not found${NC}"
    echo ""
    echo -e "${RED}jq is required for config generation. Install it:${NC}"
    echo "  brew install jq  (macOS)"
    echo "  sudo apt install jq  (Ubuntu/Debian)"
    exit 1
fi

echo ""
echo -e "${GREEN}All prerequisites met!${NC}"
echo ""

#═══════════════════════════════════════════════════════════════════════
# STEP 2: Verify AWS Account Access
#═══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 2/$TOTAL_STEPS: Verifying AWS Account Access${NC}"
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

if [ "$AUTO_MODE" = true ]; then
    ACCOUNT_CHOICE="1"
else
    echo "Where do you want to deploy OpenClaw?"
    echo ""
    echo "  1) Use current account ($AWS_ACCOUNT_ID)"
    echo "  2) Use a different AWS profile"
    echo "  3) Assume role in a different account"
    echo ""
    read -p "Choose [1-3, default 1]: " ACCOUNT_CHOICE
fi

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
echo -e "${YELLOW}STEP 3/$TOTAL_STEPS: Select AWS Region${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
if [ "$AUTO_MODE" = true ]; then
    # AWS_REGION already set from .env (validated above)
    true
elif [ -n "${AWS_REGION:-}" ]; then
    echo -e "Region from .env: ${GREEN}$AWS_REGION${NC}"
    echo ""
    read -p "Use $AWS_REGION? [Y/n]: " REGION_CONFIRM
    if [[ $REGION_CONFIRM =~ ^[Nn]$ ]]; then
        unset AWS_REGION
    fi
fi

if [ "$AUTO_MODE" != true ] && [ -z "${AWS_REGION:-}" ]; then
    echo "Choose where to deploy OpenClaw:"
    echo ""
    echo "  1) us-east-1     (N. Virginia, US East)"
    echo "  2) us-west-2     (Oregon, US West)"
    echo "  3) eu-central-1  (Frankfurt, Europe)"
    echo ""
    read -p "Select region [1-3, default 1]: " REGION_CHOICE

    case $REGION_CHOICE in
        2) AWS_REGION="us-west-2" ;;
        3) AWS_REGION="eu-central-1" ;;
        *) AWS_REGION="us-east-1" ;;
    esac
fi

echo ""
echo -e "Selected region: ${GREEN}$AWS_REGION${NC}"
echo ""

#═══════════════════════════════════════════════════════════════════════
# STEP 4: Name Your Deployment
#═══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 4/$TOTAL_STEPS: Name Your Deployment${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
if [ "$AUTO_MODE" = true ]; then
    DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-openclaw}"
else
    echo "Give this deployment a name. Used for AWS resource tags"
    echo "and to distinguish multiple deployments."
    echo ""
    echo "Examples: my-openclaw, work-agent, home-assistant"
    echo ""
    ENV_DEFAULT="${DEPLOYMENT_NAME:-openclaw}"
    read -p "Name [$ENV_DEFAULT]: " DEPLOYMENT_NAME_INPUT
    DEPLOYMENT_NAME="${DEPLOYMENT_NAME_INPUT:-$ENV_DEFAULT}"
fi

# Validate deployment name
if ! echo "$DEPLOYMENT_NAME" | grep -qE '^[a-z][a-z0-9-]{0,23}$'; then
    echo -e "${RED}Error: Name must start with a letter, be lowercase alphanumeric/hyphens, max 24 chars.${NC}"
    exit 1
fi

echo ""
echo -e "Deployment name: ${GREEN}$DEPLOYMENT_NAME${NC}"
echo ""

#═══════════════════════════════════════════════════════════════════════
# STEP 5: Configure OpenClaw
#═══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 5/$TOTAL_STEPS: Configure OpenClaw${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
if [ "$AUTO_MODE" = true ]; then
    CONFIG_CHOICE="1"
else
    echo "How do you want to configure OpenClaw?"
    echo ""
    echo "  1) Quick setup — enter API key + channel token (recommended for first time)"
    echo "  2) Config files — point to existing openclaw config files"
    echo "  3) Skip — configure manually after deploy via SSM"
    echo ""
    read -p "Choose [1-3, default 1]: " CONFIG_CHOICE
    CONFIG_CHOICE="${CONFIG_CHOICE:-1}"
fi

CONFIG_JSON=""
ENV_CONTENT=""
OWNER_NAME=""
TIMEZONE="UTC"
TF_VAR_ARGS=""

#-----------------------------------------------------------------------
# Option 1: Quick Setup
#-----------------------------------------------------------------------
if [ "$CONFIG_CHOICE" = "1" ]; then

    if [ "$AUTO_MODE" = true ]; then
        # Auto mode: use .env vars directly, no prompts
        ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
        OPENAI_API_KEY="${OPENAI_API_KEY:-}"
        SLACK_APP_TOKEN_VAL="${SLACK_APP_TOKEN:-}"
        SLACK_BOT_TOKEN_VAL="${SLACK_BOT_TOKEN:-}"
        SLACK_CHANNEL_ID="${SLACK_CHANNEL_ID:-}"
        DISCORD_TOKEN="${DISCORD_BOT_TOKEN:-}"
        DISCORD_GUILD_ID="${DISCORD_GUILD_ID:-}"
        DISCORD_CHANNEL_ID="${DISCORD_CHANNEL_ID:-}"
        DISCORD_OWNER_ID="${DISCORD_OWNER_ID:-}"
        TELEGRAM_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
        TELEGRAM_OWNER_ID="${TELEGRAM_OWNER_ID:-}"
        OWNER_NAME="${OWNER_NAME:-}"
        TIMEZONE="${TIMEZONE:-America/New_York}"
    else
    echo ""
    echo -e "${BLUE}── LLM Provider ──────────────────────────────${NC}"
    echo ""
    echo "Which LLM provider? (you need at least one)"
    echo ""
    echo "  1) Anthropic (Claude) — recommended"
    echo "  2) OpenAI (GPT)"
    echo "  3) Both"
    echo ""
    read -p "Choose [1-3, default 1]: " LLM_CHOICE
    LLM_CHOICE="${LLM_CHOICE:-1}"

    # Save .env defaults before clearing
    _ENV_ANTHROPIC="${ANTHROPIC_API_KEY:-}"
    _ENV_OPENAI="${OPENAI_API_KEY:-}"

    ANTHROPIC_API_KEY=""
    OPENAI_API_KEY=""

    if [ "$LLM_CHOICE" = "1" ] || [ "$LLM_CHOICE" = "3" ]; then
        echo ""
        if [ -n "$_ENV_ANTHROPIC" ]; then
            _MASKED="${_ENV_ANTHROPIC:0:10}...${_ENV_ANTHROPIC: -4}"
            read -p "Anthropic API key [$_MASKED]: " _INPUT
            ANTHROPIC_API_KEY="${_INPUT:-$_ENV_ANTHROPIC}"
        else
            read -p "Anthropic API key: " ANTHROPIC_API_KEY
        fi
        if [ -z "$ANTHROPIC_API_KEY" ]; then
            echo -e "${RED}Error: Anthropic API key is required${NC}"
            exit 1
        fi
    fi

    if [ "$LLM_CHOICE" = "2" ] || [ "$LLM_CHOICE" = "3" ]; then
        echo ""
        if [ -n "$_ENV_OPENAI" ]; then
            _MASKED="${_ENV_OPENAI:0:7}...${_ENV_OPENAI: -4}"
            read -p "OpenAI API key [$_MASKED]: " _INPUT
            OPENAI_API_KEY="${_INPUT:-$_ENV_OPENAI}"
        else
            read -p "OpenAI API key: " OPENAI_API_KEY
        fi
        if [ -z "$OPENAI_API_KEY" ]; then
            echo -e "${RED}Error: OpenAI API key is required${NC}"
            exit 1
        fi
    fi

    echo ""
    echo -e "${BLUE}── Chat Channel ──────────────────────────────${NC}"
    echo ""
    echo "How will you talk to your OpenClaw?"
    echo ""
    echo "  1) Slack bot (recommended for teams)"
    echo "  2) Discord bot"
    echo "  3) Telegram bot"
    echo "  4) Multiple (configure each)"
    echo ""
    read -p "Choose [1-4, default 1]: " CHANNEL_CHOICE
    CHANNEL_CHOICE="${CHANNEL_CHOICE:-1}"

    # Save .env defaults before clearing
    _ENV_SLACK_APP_TOKEN="${SLACK_APP_TOKEN:-}"
    _ENV_SLACK_BOT_TOKEN="${SLACK_BOT_TOKEN:-}"
    _ENV_SLACK_CHANNEL="${SLACK_CHANNEL_ID:-}"
    _ENV_DISCORD_TOKEN="${DISCORD_BOT_TOKEN:-}"
    _ENV_DISCORD_GUILD="${DISCORD_GUILD_ID:-}"
    _ENV_DISCORD_CHANNEL="${DISCORD_CHANNEL_ID:-}"
    _ENV_DISCORD_OWNER="${DISCORD_OWNER_ID:-}"
    _ENV_TELEGRAM_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
    _ENV_TELEGRAM_OWNER="${TELEGRAM_OWNER_ID:-}"
    _ENV_OWNER_NAME="${OWNER_NAME:-}"
    _ENV_TIMEZONE="${TIMEZONE:-America/New_York}"

    SLACK_APP_TOKEN_VAL=""
    SLACK_BOT_TOKEN_VAL=""
    SLACK_CHANNEL_ID=""
    DISCORD_TOKEN=""
    DISCORD_GUILD_ID=""
    DISCORD_CHANNEL_ID=""
    DISCORD_OWNER_ID=""
    TELEGRAM_TOKEN=""
    TELEGRAM_OWNER_ID=""

    SETUP_SLACK=false
    SETUP_DISCORD=false
    SETUP_TELEGRAM=false

    case $CHANNEL_CHOICE in
        1) SETUP_SLACK=true ;;
        2) SETUP_DISCORD=true ;;
        3) SETUP_TELEGRAM=true ;;
        4)
            echo ""
            echo "Select channels to configure (enter numbers separated by spaces):"
            echo "  1) Slack  2) Discord  3) Telegram"
            read -p "Channels [e.g. 1 2]: " MULTI_CHANNELS
            for ch in $MULTI_CHANNELS; do
                case $ch in
                    1) SETUP_SLACK=true ;;
                    2) SETUP_DISCORD=true ;;
                    3) SETUP_TELEGRAM=true ;;
                esac
            done
            ;;
    esac

    if [ "$SETUP_SLACK" = true ]; then
        echo ""
        echo -e "${BLUE}── Slack Setup ───────────────────────────────${NC}"
        echo ""
        echo "You need a Slack app with Socket Mode enabled."
        echo "Create one at: https://api.slack.com/apps"
        echo ""

        if [ -n "$_ENV_SLACK_APP_TOKEN" ]; then
            _MASKED="${_ENV_SLACK_APP_TOKEN:0:10}...${_ENV_SLACK_APP_TOKEN: -4}"
            read -p "Slack App Token (xapp-...) [$_MASKED]: " _INPUT
            SLACK_APP_TOKEN_VAL="${_INPUT:-$_ENV_SLACK_APP_TOKEN}"
        else
            read -p "Slack App Token (xapp-... from Socket Mode settings): " SLACK_APP_TOKEN_VAL
        fi
        if [ -z "$SLACK_APP_TOKEN_VAL" ]; then
            echo -e "${RED}Error: Slack App Token is required${NC}"
            exit 1
        fi

        if [ -n "$_ENV_SLACK_BOT_TOKEN" ]; then
            _MASKED="${_ENV_SLACK_BOT_TOKEN:0:10}...${_ENV_SLACK_BOT_TOKEN: -4}"
            read -p "Slack Bot Token (xoxb-...) [$_MASKED]: " _INPUT
            SLACK_BOT_TOKEN_VAL="${_INPUT:-$_ENV_SLACK_BOT_TOKEN}"
        else
            read -p "Slack Bot Token (xoxb-... from OAuth & Permissions): " SLACK_BOT_TOKEN_VAL
        fi
        if [ -z "$SLACK_BOT_TOKEN_VAL" ]; then
            echo -e "${RED}Error: Slack Bot Token is required${NC}"
            exit 1
        fi

        if [ -n "$_ENV_SLACK_CHANNEL" ]; then
            read -p "Restrict to channel ID [$_ENV_SLACK_CHANNEL] (blank=all channels): " _INPUT
            SLACK_CHANNEL_ID="${_INPUT:-$_ENV_SLACK_CHANNEL}"
        else
            read -p "Restrict to channel ID (blank=all channels): " SLACK_CHANNEL_ID
        fi
    fi

    if [ "$SETUP_DISCORD" = true ]; then
        echo ""
        echo -e "${BLUE}── Discord Setup ─────────────────────────────${NC}"
        echo ""
        if [ -n "$_ENV_DISCORD_TOKEN" ]; then
            _MASKED="${_ENV_DISCORD_TOKEN:0:10}...${_ENV_DISCORD_TOKEN: -4}"
            read -p "Discord bot token [$_MASKED]: " _INPUT
            DISCORD_TOKEN="${_INPUT:-$_ENV_DISCORD_TOKEN}"
        else
            read -p "Discord bot token: " DISCORD_TOKEN
        fi
        if [ -z "$DISCORD_TOKEN" ]; then
            echo -e "${RED}Error: Discord bot token is required${NC}"
            exit 1
        fi

        if [ -n "$_ENV_DISCORD_GUILD" ]; then
            read -p "Discord guild (server) ID [$_ENV_DISCORD_GUILD]: " _INPUT
            DISCORD_GUILD_ID="${_INPUT:-$_ENV_DISCORD_GUILD}"
        else
            read -p "Discord guild (server) ID (right-click server → Copy Server ID): " DISCORD_GUILD_ID
        fi
        if [ -z "$DISCORD_GUILD_ID" ]; then
            echo -e "${RED}Error: Discord guild ID is required${NC}"
            exit 1
        fi

        if [ -n "$_ENV_DISCORD_CHANNEL" ]; then
            read -p "Restrict to channel ID [$_ENV_DISCORD_CHANNEL] (blank=all channels): " _INPUT
            DISCORD_CHANNEL_ID="${_INPUT:-$_ENV_DISCORD_CHANNEL}"
        else
            read -p "Restrict to channel ID (blank=all channels, right-click channel → Copy Channel ID): " DISCORD_CHANNEL_ID
        fi

        if [ -n "$_ENV_DISCORD_OWNER" ]; then
            read -p "Your Discord user ID [$_ENV_DISCORD_OWNER]: " _INPUT
            DISCORD_OWNER_ID="${_INPUT:-$_ENV_DISCORD_OWNER}"
        else
            read -p "Your Discord user ID (right-click yourself → Copy User ID): " DISCORD_OWNER_ID
        fi
        if [ -z "$DISCORD_OWNER_ID" ]; then
            echo -e "${RED}Error: Discord user ID is required${NC}"
            exit 1
        fi
    fi

    if [ "$SETUP_TELEGRAM" = true ]; then
        echo ""
        echo -e "${BLUE}── Telegram Setup ────────────────────────────${NC}"
        echo ""
        if [ -n "$_ENV_TELEGRAM_TOKEN" ]; then
            _MASKED="${_ENV_TELEGRAM_TOKEN:0:10}...${_ENV_TELEGRAM_TOKEN: -4}"
            read -p "Telegram bot token [$_MASKED]: " _INPUT
            TELEGRAM_TOKEN="${_INPUT:-$_ENV_TELEGRAM_TOKEN}"
        else
            read -p "Telegram bot token (from @BotFather): " TELEGRAM_TOKEN
        fi
        if [ -z "$TELEGRAM_TOKEN" ]; then
            echo -e "${RED}Error: Telegram bot token is required${NC}"
            exit 1
        fi

        if [ -n "$_ENV_TELEGRAM_OWNER" ]; then
            read -p "Telegram owner chat ID [$_ENV_TELEGRAM_OWNER]: " _INPUT
            TELEGRAM_OWNER_ID="${_INPUT:-$_ENV_TELEGRAM_OWNER}"
        else
            read -p "Telegram owner chat ID (your numeric user ID): " TELEGRAM_OWNER_ID
        fi
        if [ -z "$TELEGRAM_OWNER_ID" ]; then
            echo -e "${RED}Error: Telegram owner chat ID is required${NC}"
            exit 1
        fi
    fi

    echo ""
    echo -e "${BLUE}── Owner Info ────────────────────────────────${NC}"
    echo ""
    if [ -n "$_ENV_OWNER_NAME" ]; then
        read -p "Your name [$_ENV_OWNER_NAME]: " _INPUT
        OWNER_NAME="${_INPUT:-$_ENV_OWNER_NAME}"
    else
        read -p "Your name (for the agent to know who you are): " OWNER_NAME
    fi
    read -p "Timezone [$_ENV_TIMEZONE]: " _INPUT
    TIMEZONE="${_INPUT:-$_ENV_TIMEZONE}"

    fi # end interactive Quick Setup

    # Generate config JSON with jq
    GATEWAY_TOKEN=$(openssl rand -hex 24)

    CONFIG_JSON=$(jq -n \
      --arg gw_token "$GATEWAY_TOKEN" \
      '{
        gateway: {
          mode: "local",
          auth: { token: $gw_token },
          port: 18789
        }
      }')

    # Add Slack channel if configured
    if [ -n "$SLACK_BOT_TOKEN_VAL" ]; then
      CONFIG_JSON=$(echo "$CONFIG_JSON" | jq \
        --arg app_token "$SLACK_APP_TOKEN_VAL" \
        --arg bot_token "$SLACK_BOT_TOKEN_VAL" \
        '.channels.slack = {
          enabled: true,
          mode: "socket",
          appToken: $app_token,
          botToken: $bot_token
        }')

      # If a specific channel ID was provided, restrict to that channel
      if [ -n "$SLACK_CHANNEL_ID" ]; then
        CONFIG_JSON=$(echo "$CONFIG_JSON" | jq \
          --arg channel_id "$SLACK_CHANNEL_ID" \
          '.channels.slack.channels[$channel_id] = { allow: true }')
      fi
    fi

    # Add Discord channel if configured
    if [ -n "$DISCORD_TOKEN" ]; then
      CONFIG_JSON=$(echo "$CONFIG_JSON" | jq \
        --arg token "$DISCORD_TOKEN" \
        --arg guild_id "$DISCORD_GUILD_ID" \
        --arg owner_id "$DISCORD_OWNER_ID" \
        '.channels.discord = {
          enabled: true,
          token: $token,
          groupPolicy: "allowlist",
          dmPolicy: "pairing",
          allowFrom: [$owner_id],
          guilds: {
            ($guild_id): {
              requireMention: false
            }
          }
        }')

      # If a specific channel ID was provided, restrict to that channel
      if [ -n "$DISCORD_CHANNEL_ID" ]; then
        CONFIG_JSON=$(echo "$CONFIG_JSON" | jq \
          --arg guild_id "$DISCORD_GUILD_ID" \
          --arg channel_id "$DISCORD_CHANNEL_ID" \
          '.channels.discord.guilds[$guild_id].channels[$channel_id] = { allow: true }')
      fi
    fi

    # Add Telegram channel if configured
    if [ -n "$TELEGRAM_TOKEN" ]; then
      CONFIG_JSON=$(echo "$CONFIG_JSON" | jq \
        --arg token "$TELEGRAM_TOKEN" \
        --arg owner_id "$TELEGRAM_OWNER_ID" \
        '.channels.telegram = {
          enabled: true,
          botToken: $token,
          dmPolicy: "pairing",
          groupPolicy: "allowlist",
          allowFrom: [$owner_id]
        }')
    fi

    # Add model config — use agents.defaults.model.primary (not agents.main)
    if [ -n "$ANTHROPIC_API_KEY" ]; then
      CONFIG_JSON=$(echo "$CONFIG_JSON" | jq \
        '.agents.defaults.model.primary = "anthropic/claude-sonnet-4-20250514"')
    elif [ -n "$OPENAI_API_KEY" ]; then
      CONFIG_JSON=$(echo "$CONFIG_JSON" | jq \
        '.agents.defaults.model.primary = "openai/gpt-4o"')
    fi

    # Generate .env content
    ENV_CONTENT=""
    [ -n "$ANTHROPIC_API_KEY" ] && ENV_CONTENT+="ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY"$'\n'
    [ -n "$OPENAI_API_KEY" ] && ENV_CONTENT+="OPENAI_API_KEY=$OPENAI_API_KEY"$'\n'
    [ -n "$SLACK_APP_TOKEN_VAL" ] && ENV_CONTENT+="SLACK_APP_TOKEN=$SLACK_APP_TOKEN_VAL"$'\n'
    [ -n "$SLACK_BOT_TOKEN_VAL" ] && ENV_CONTENT+="SLACK_BOT_TOKEN=$SLACK_BOT_TOKEN_VAL"$'\n'
    ENV_CONTENT+="GATEWAY_AUTH_TOKEN=$GATEWAY_TOKEN"$'\n'

    # Write secrets to temp files
    echo "$CONFIG_JSON" > /tmp/openclaw-config.json
    printf '%s' "$ENV_CONTENT" > /tmp/openclaw-env

    echo ""
    echo -e "${GREEN}✓ Configuration generated${NC}"
    echo ""

#-----------------------------------------------------------------------
# Option 2: Config Files
#-----------------------------------------------------------------------
elif [ "$CONFIG_CHOICE" = "2" ]; then
    echo ""
    echo "Point to your config files. Leave blank to skip any."
    echo ""

    read -p "OpenClaw config JSON path [../../mac-mini-setup/openclaw-secrets.json]: " CONFIG_PATH
    CONFIG_PATH="${CONFIG_PATH:-../../mac-mini-setup/openclaw-secrets.json}"

    read -p "OpenClaw .env path [../../mac-mini-setup/openclaw-secrets.env]: " ENV_PATH
    ENV_PATH="${ENV_PATH:-../../mac-mini-setup/openclaw-secrets.env}"

    read -p "Auth profiles JSON path [../../mac-mini-setup/openclaw-auth-profiles.json]: " AUTH_PATH
    AUTH_PATH="${AUTH_PATH:-../../mac-mini-setup/openclaw-auth-profiles.json}"

    # Validate and read config files
    if [ -n "$CONFIG_PATH" ] && [ -f "$CONFIG_PATH" ]; then
        CONFIG_JSON=$(cat "$CONFIG_PATH")
        echo -e "  Config JSON: ${GREEN}✓ loaded${NC}"
    elif [ -n "$CONFIG_PATH" ]; then
        echo -e "  Config JSON: ${YELLOW}file not found, skipping${NC}"
    fi

    if [ -n "$ENV_PATH" ] && [ -f "$ENV_PATH" ]; then
        ENV_CONTENT=$(cat "$ENV_PATH")
        echo -e "  .env file:   ${GREEN}✓ loaded${NC}"
    elif [ -n "$ENV_PATH" ]; then
        echo -e "  .env file:   ${YELLOW}file not found, skipping${NC}"
    fi

    AUTH_PROFILES_JSON=""
    if [ -n "$AUTH_PATH" ] && [ -f "$AUTH_PATH" ]; then
        AUTH_PROFILES_JSON=$(cat "$AUTH_PATH")
        echo -e "  Auth profiles: ${GREEN}✓ loaded${NC}"
    elif [ -n "$AUTH_PATH" ]; then
        echo -e "  Auth profiles: ${YELLOW}file not found, skipping${NC}"
    fi

    # Write to temp files if loaded
    if [ -n "$CONFIG_JSON" ]; then
        echo "$CONFIG_JSON" > /tmp/openclaw-config.json
    fi
    if [ -n "$ENV_CONTENT" ]; then
        printf '%s' "$ENV_CONTENT" > /tmp/openclaw-env
    fi

    echo ""
    read -p "Owner name: " OWNER_NAME
    read -p "Timezone [America/New_York]: " TIMEZONE
    TIMEZONE="${TIMEZONE:-America/New_York}"
    echo ""

#-----------------------------------------------------------------------
# Option 3: Skip
#-----------------------------------------------------------------------
else
    echo ""
    echo -e "${CYAN}Skipping OpenClaw config. You can configure manually after deploy via SSM.${NC}"
    echo ""
fi

#═══════════════════════════════════════════════════════════════════════
# STEP 6: Check for Existing Resources
#═══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 6/$TOTAL_STEPS: Scanning Account for Existing Resources${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Scanning account $AWS_ACCOUNT_ID in $AWS_REGION..."
echo "This ensures we don't accidentally destroy your existing resources."
echo ""

EXISTING_OPENCLAW=()
EXISTING_ACCOUNT=()

echo -e "${BLUE}Checking for resources tagged with '$DEPLOYMENT_NAME':${NC}"
echo ""

# Check VPCs with deployment_name tag
echo -n "  VPCs with '$DEPLOYMENT_NAME' tag... "
set +e
EXISTING_VPC=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=*${DEPLOYMENT_NAME}*" \
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

# Check EC2 instances with deployment_name tag
echo -n "  EC2 instances with '$DEPLOYMENT_NAME' tag... "
set +e
EXISTING_EC2=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=*${DEPLOYMENT_NAME}*" "Name=instance-state-name,Values=running,stopped,pending" \
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

# Check Security Groups with deployment_name name
echo -n "  Security Groups with '$DEPLOYMENT_NAME' name... "
set +e
EXISTING_SG=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=*${DEPLOYMENT_NAME}*" \
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
echo -n "  IAM role '${DEPLOYMENT_NAME}-ec2-role'... "
set +e
EXISTING_ROLE=$(aws iam get-role --role-name "${DEPLOYMENT_NAME}-ec2-role" --query 'Role.Arn' --output text 2>/dev/null)
set -e
if [ -n "$EXISTING_ROLE" ] && [ "$EXISTING_ROLE" != "None" ]; then
    echo -e "${YELLOW}Found${NC}"
    EXISTING_OPENCLAW+=("IAM Role: ${DEPLOYMENT_NAME}-ec2-role")
else
    echo -e "${GREEN}None${NC}"
fi

# Check IAM instance profile
echo -n "  IAM instance profile '${DEPLOYMENT_NAME}-ec2-profile'... "
set +e
EXISTING_PROFILE=$(aws iam get-instance-profile --instance-profile-name "${DEPLOYMENT_NAME}-ec2-profile" --query 'InstanceProfile.Arn' --output text 2>/dev/null)
set -e
if [ -n "$EXISTING_PROFILE" ] && [ "$EXISTING_PROFILE" != "None" ]; then
    echo -e "${YELLOW}Found${NC}"
    EXISTING_OPENCLAW+=("IAM Instance Profile: ${DEPLOYMENT_NAME}-ec2-profile")
else
    echo -e "${GREEN}None${NC}"
fi

# Check Subnets with deployment_name tag
echo -n "  Subnets with '$DEPLOYMENT_NAME' tag... "
set +e
EXISTING_SUBNET=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=*${DEPLOYMENT_NAME}*" \
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

# Check Internet Gateways with deployment_name tag
echo -n "  Internet Gateways with '$DEPLOYMENT_NAME' tag... "
set +e
EXISTING_IGW=$(aws ec2 describe-internet-gateways \
    --filters "Name=tag:Name,Values=*${DEPLOYMENT_NAME}*" \
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
    echo -e "${YELLOW}║  EXISTING RESOURCES DETECTED                                  ║${NC}"
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
    echo -e "${CYAN}║  ACCOUNT HAS EXISTING INFRASTRUCTURE                          ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "This account contains other resources:"
    echo ""
    for resource in "${EXISTING_ACCOUNT[@]}"; do
        echo -e "  ${CYAN}•${NC} $resource"
    done
    echo ""
    echo -e "${GREEN}OpenClaw deployment will NOT affect these resources.${NC}"
    echo "OpenClaw creates isolated resources with '${DEPLOYMENT_NAME}' prefix."
    echo ""
fi

# Summary and confirmation
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    DEPLOYMENT SUMMARY                         ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Target Account:   $AWS_ACCOUNT_ID"
echo "  Target Region:    $AWS_REGION"
echo "  Deployment Name:  $DEPLOYMENT_NAME"
[ -n "$OWNER_NAME" ] && echo "  Owner:            $OWNER_NAME"
echo ""
echo "  Resources to be created:"
if [ -n "${EXISTING_VPC_ID:-}" ]; then
    echo "    • Using existing VPC: ${EXISTING_VPC_ID}"
    echo "    • Using existing subnet: ${EXISTING_SUBNET_ID}"
    if [ -n "${EXISTING_SECURITY_GROUP_ID:-}" ]; then
        echo "    • Using existing security group: ${EXISTING_SECURITY_GROUP_ID}"
    else
        echo "    • 1 Security Group (outbound only)"
    fi
else
    echo "    • 1 VPC (10.0.0.0/16) with '${DEPLOYMENT_NAME}-vpc' tag"
    echo "    • 1 Public subnet with '${DEPLOYMENT_NAME}-public' tag"
    echo "    • 1 Internet Gateway"
    echo "    • 1 Security Group (outbound only)"
fi
echo "    • 1 IAM Role (${DEPLOYMENT_NAME}-ec2-role)"
echo "    • 1 EC2 instance (t4g.medium)"
echo ""

if [ ${#EXISTING_OPENCLAW[@]} -gt 0 ]; then
    echo -e "${YELLOW}${#EXISTING_OPENCLAW[@]} existing resource(s) may be affected.${NC}"
    echo ""
    echo "Options:"
    echo "  1) Continue - I understand existing resources may be modified"
    echo "  2) Abort - Do not make any changes"
    echo ""
    if [ "$AUTO_MODE" = true ]; then
        echo -e "${YELLOW}--auto mode: continuing${NC}"
        EXISTING_CHOICE="1"
    else
        read -p "Choose [1-2]: " EXISTING_CHOICE
    fi

    if [ "$EXISTING_CHOICE" != "1" ]; then
        echo ""
        echo "Aborted. No changes were made."
        echo ""
        echo "To manage existing resources:"
        echo "  • Destroy first: ./setup.sh --destroy"
        echo "  • Or use a different region"
        exit 0
    fi
    echo ""
else
    echo -e "${GREEN}✓ No conflicts detected. Safe to proceed.${NC}"
    echo ""
    if [ "$AUTO_MODE" = true ]; then
        PROCEED_CHOICE="y"
    else
        read -p "Do you want to proceed with deployment? [y/N]: " PROCEED_CHOICE
    fi

    if [[ ! $PROCEED_CHOICE =~ ^[Yy]$ ]]; then
        echo ""
        echo "Aborted. No changes were made."
        exit 0
    fi
    echo ""
fi

#═══════════════════════════════════════════════════════════════════════
# STEP 7: Deploy Infrastructure
#═══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 7/$TOTAL_STEPS: Deploying Infrastructure${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Preparing deployment to AWS account $AWS_ACCOUNT_ID in $AWS_REGION..."
echo ""

cd "$SCRIPT_DIR/terraform"

# If using external deploy dir, link state files
if [ -n "$DEPLOY_DIR" ] && [ "$DEPLOY_DIR" != "$SCRIPT_DIR/terraform" ]; then
    # Remove any existing state files in terraform dir (they're stale/from another deploy)
    rm -f terraform.tfstate terraform.tfstate.backup
    # Symlink from deploy dir if state exists there
    [ -f "$DEPLOY_DIR/terraform.tfstate" ] && ln -sf "$DEPLOY_DIR/terraform.tfstate" terraform.tfstate
    [ -f "$DEPLOY_DIR/terraform.tfstate.backup" ] && ln -sf "$DEPLOY_DIR/terraform.tfstate.backup" terraform.tfstate.backup
    # Ensure state will be created in deploy dir
    TFSTATE_LINK=true
else
    TFSTATE_LINK=false
fi

# Create terraform.tfvars with non-secret values
cat > terraform.tfvars << EOF
aws_region      = "$AWS_REGION"
deployment_name = "$DEPLOYMENT_NAME"
EOF

[ -n "$OWNER_NAME" ] && echo "owner_name      = \"$OWNER_NAME\"" >> terraform.tfvars
[ -n "${INSTANCE_NAME:-}" ] && echo "instance_name   = \"$INSTANCE_NAME\"" >> terraform.tfvars
[ "$TIMEZONE" != "UTC" ] && echo "timezone        = \"$TIMEZONE\"" >> terraform.tfvars

# Existing infrastructure (deploy into existing VPC)
[ -n "${EXISTING_VPC_ID:-}" ] && echo "existing_vpc_id            = \"$EXISTING_VPC_ID\"" >> terraform.tfvars
[ -n "${EXISTING_SUBNET_ID:-}" ] && echo "existing_subnet_id         = \"$EXISTING_SUBNET_ID\"" >> terraform.tfvars
[ -n "${EXISTING_SECURITY_GROUP_ID:-}" ] && echo "existing_security_group_id = \"$EXISTING_SECURITY_GROUP_ID\"" >> terraform.tfvars

# Pass secrets via TF_VAR_ environment variables (safe for JSON with special chars)
if [ -f /tmp/openclaw-config.json ]; then
    export TF_VAR_openclaw_config_json="$(cat /tmp/openclaw-config.json)"
fi
if [ -f /tmp/openclaw-env ]; then
    export TF_VAR_openclaw_env="$(cat /tmp/openclaw-env)"
fi
if [ -n "${AUTH_PROFILES_JSON:-}" ]; then
    export TF_VAR_openclaw_auth_profiles_json="$AUTH_PROFILES_JSON"
fi

# Export credentials for Terraform compatibility
# Older Terraform versions can't read AWS CLI v2 SSO cache directly.
# If using an SSO profile, export temporary credentials as env vars.
if [ -n "${AWS_PROFILE:-}" ]; then
    set +e
    SSO_CREDS=$(aws configure export-credentials --profile "$AWS_PROFILE" --format env 2>/dev/null)
    SSO_RC=$?
    set -e
    if [ $SSO_RC -eq 0 ] && [ -n "$SSO_CREDS" ]; then
        eval "$SSO_CREDS"
        unset AWS_PROFILE  # env vars take priority, avoid conflicts
    fi
fi

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
ADD_COUNT=$(echo "$PLAN_OUTPUT" | grep -oE '[0-9]+ to add' | grep -oE '[0-9]+' || echo "0")
CHANGE_COUNT=$(echo "$PLAN_OUTPUT" | grep -oE '[0-9]+ to change' | grep -oE '[0-9]+' || echo "0")
DESTROY_COUNT=$(echo "$PLAN_OUTPUT" | grep -oE '[0-9]+ to destroy' | grep -oE '[0-9]+' || echo "0")

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
    echo -e "${RED}║  WARNING: RESOURCES WILL BE DESTROYED!                        ║${NC}"
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
    if [ "$AUTO_MODE" = true ]; then
        echo -e "${YELLOW}--auto mode: skipping confirmation${NC}"
        DESTROY_CONFIRM="DESTROY"
    else
        echo "Type 'DESTROY' to confirm you want to destroy these resources:"
        read -p "> " DESTROY_CONFIRM
    fi

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
if [ "$AUTO_MODE" = true ]; then
    APPLY_CONFIRM="y"
else
    read -p "Do you want to apply these changes? [y/N]: " APPLY_CONFIRM
fi

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

# Clean up temp files
rm -f /tmp/openclaw-config.json /tmp/openclaw-env /tmp/openclaw-auth-profiles.json

echo ""
echo -e "${GREEN}✓ Infrastructure deployed successfully!${NC}"
echo -e "  Instance ID: ${GREEN}$INSTANCE_ID${NC}"
echo ""

#═══════════════════════════════════════════════════════════════════════
# STEP 8: Wait for Instance
#═══════════════════════════════════════════════════════════════════════
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 8/$TOTAL_STEPS: Waiting for Instance${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "  Waiting for EC2 instance to be ready..."
aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
echo -e "  ${GREEN}✓ Instance is running${NC}"

echo -n "  Waiting for cloud-init to complete (this takes ~2 minutes)..."
for i in $(seq 1 12); do
    sleep 10
    echo -n "."
done
echo ""
echo -e "  ${GREEN}✓ Installation complete${NC}"

echo ""

#═══════════════════════════════════════════════════════════════════════
# COMPLETE
#═══════════════════════════════════════════════════════════════════════
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                                                               ║"
echo "║                    DEPLOYED! 🎉                               ║"
echo "║                                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "  ${BLUE}Instance ID:${NC}      $INSTANCE_ID"
echo -e "  ${BLUE}Region:${NC}           $AWS_REGION"
echo -e "  ${BLUE}Account:${NC}          $AWS_ACCOUNT_ID"
echo -e "  ${BLUE}Deployment Name:${NC}  $DEPLOYMENT_NAME"
echo ""

if [ -n "$CONFIG_JSON" ] || [ -n "$ENV_CONTENT" ]; then
    # Config was provided — show configured output
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  OpenClaw is pre-configured and starting up now.${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  1. Check install progress:"
    echo ""
    echo -e "     ${CYAN}aws ssm start-session --target $INSTANCE_ID --region $AWS_REGION${NC}"
    echo -e "     ${CYAN}tail -f /var/log/openclaw-install.log${NC}"
    echo ""
    echo "  2. View gateway logs:"
    echo ""
    echo -e "     ${CYAN}sudo -u openclaw journalctl --user -u openclaw-gateway -f${NC}"
    echo ""
    echo "  3. Open dashboard via SSM port forward:"
    echo ""
    echo -e "     ${CYAN}aws ssm start-session --target $INSTANCE_ID --region $AWS_REGION \\${NC}"
    echo -e "     ${CYAN}  --document-name AWS-StartPortForwardingSession \\${NC}"
    echo -e "     ${CYAN}  --parameters '{\"portNumber\":[\"18789\"],\"localPortNumber\":[\"18789\"]}'${NC}"
    echo ""
    echo -e "     ${CYAN}http://localhost:18789/${NC}"
    echo ""
    echo "  4. Message your bot!"
    echo ""
else
    # No config — show manual onboard instructions
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  NEXT STEP: Configure OpenClaw${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  1. Connect to your instance:"
    echo ""
    echo -e "     ${CYAN}aws ssm start-session --target $INSTANCE_ID --region $AWS_REGION${NC}"
    echo ""
    echo "  2. Initialize OpenClaw (enter your API keys when prompted):"
    echo ""
    echo -e "     ${CYAN}sudo -u openclaw openclaw onboard --install-daemon${NC}"
    echo ""
    echo "  3. Open dashboard locally (SSM port forward):"
    echo ""
    echo -e "     ${CYAN}aws ssm start-session --target $INSTANCE_ID --region $AWS_REGION \\${NC}"
    echo -e "     ${CYAN}  --document-name AWS-StartPortForwardingSession \\${NC}"
    echo -e "     ${CYAN}  --parameters '{\"portNumber\":[\"18789\"],\"localPortNumber\":[\"18789\"]}'${NC}"
    echo ""
    echo -e "     ${CYAN}http://localhost:18789/${NC}"
    echo -e "     ${CYAN}Token: sudo -u openclaw openclaw config get gateway.auth.token${NC}"
    echo ""
    echo "  4. Message your bot!"
    echo ""
fi

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  TEAR DOWN & REBUILD${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  # Destroy everything and start over:"
echo -e "  ${CYAN}./setup.sh --destroy${NC}"
echo ""
echo "  # Then re-deploy:"
echo -e "  ${CYAN}./setup.sh${NC}"
echo ""

echo "Other useful commands:"
echo ""
echo "  # View logs (user service)"
echo "  sudo -u openclaw journalctl --user -u openclaw-gateway -f"
echo ""
echo "  # Restart OpenClaw (user service)"
echo "  sudo -u openclaw systemctl --user restart openclaw-gateway"
echo ""
