#!/bin/bash

echo "🚀 MongoDB Lambda AWS - Complete Quick Start"
echo "============================================"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Check prerequisites
echo -e "${BLUE}🔍 Checking Prerequisites...${NC}"

PREREQ_FAILED=0

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI not found${NC}"
    echo "   Install: https://aws.amazon.com/cli/"
    PREREQ_FAILED=1
else
    echo -e "${GREEN}✅ AWS CLI found${NC}"
fi

# Check Terraform
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}❌ Terraform not found${NC}"
    echo "   Install: https://terraform.io/downloads"
    PREREQ_FAILED=1
else
    echo -e "${GREEN}✅ Terraform found${NC}"
fi

# Check AWS credentials
aws sts get-caller-identity &> /dev/null
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ AWS credentials not configured${NC}"
    echo "   Run: aws configure"
    PREREQ_FAILED=1
else
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region)
    echo -e "${GREEN}✅ AWS credentials configured${NC}"
    echo "   Account: $ACCOUNT_ID"
    echo "   Region: $REGION"
fi

# Check jq (optional but helpful)
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠️  jq not found (optional)${NC}"
    echo "   Install for better JSON handling"
else
    echo -e "${GREEN}✅ jq found${NC}"
fi

if [ $PREREQ_FAILED -eq 1 ]; then
    echo ""
    echo -e "${RED}❌ Prerequisites not met. Please install missing tools.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ All prerequisites met!${NC}"
echo ""

# Detect current state
echo -e "${BLUE}📊 Detecting Current State...${NC}"

# Check if terraform state exists
if [ -f "terraform.tfstate" ]; then
    PRIVATE_IP=$(terraform output -raw ec2_private_ip 2>/dev/null)
    PUBLIC_IP=$(terraform output -raw ec2_public_ip 2>/dev/null)
    API_URL=$(terraform output -raw api_gateway_invoke_url 2>/dev/null)
    SPA_URL=$(terraform output -raw spa_url 2>/dev/null)
    
    if [ ! -z "$SPA_URL" ]; then
        CURRENT_STATE="Phase 4 (SPA + CDN) - Complete System"
    elif [ ! -z "$API_URL" ]; then
        CURRENT_STATE="Phase 3 (API Gateway) - Internet API"
    elif [ -z "$PUBLIC_IP" ] && [ ! -z "$PRIVATE_IP" ]; then
        CURRENT_STATE="Phase 2 (Private) - Secure Backend"
    elif [ ! -z "$PUBLIC_IP" ]; then
        CURRENT_STATE="Phase 1 (Public) - Development Setup"
    else
        CURRENT_STATE="Deployed but unknown state"
    fi
    
    echo "Current State: $CURRENT_STATE"
    echo ""
else
    CURRENT_STATE="Not Deployed"
    echo "Current State: Not Deployed"
    echo ""
fi

# Menu
echo -e "${YELLOW}📋 Deployment Options:${NC}"
echo ""
echo "1) 🏗️  Deploy Phase 1: Public Setup (Development)"
echo "   • EC2 with SSH access + MongoDB"
echo "   • Lambda function for database operations"
echo "   • Perfect for initial setup and testing"
echo ""
echo "2) 🔒 Deploy Phase 2: Private Setup (Production Security)"
echo "   • Remove public access and SSH"
echo "   • Lambda-only database access"
echo "   • Enhanced security posture"
echo ""
echo "3) 🌐 Deploy Phase 3: API Gateway (Internet API)"
echo "   • Add REST API endpoint"
echo "   • CORS-enabled for web applications"
echo "   • curl and browser accessible"
echo ""
echo "4) 📱 Deploy Phase 4: Single Page Application (Complete System)"
echo "   • Add web interface with S3 + CloudFront"
echo "   • Global CDN distribution"
echo "   • Full-stack web application"
echo ""
echo "5) 🚀 Deploy All Phases Sequentially (Recommended)"
echo "   • Complete end-to-end deployment"
echo "   • Test each phase before proceeding"
echo "   • Full system validation"
echo ""
echo "6) 🧪 Test Current Deployment"
echo "   • Comprehensive system testing"
echo "   • Performance and security checks"
echo "   • Data consistency validation"
echo ""
echo "7) 📊 Show Current Status"
echo "   • Display all outputs and URLs"
echo "   • Show resource information"
echo "   • Connection details"
echo ""
echo "8) 💥 Destroy All Resources"
echo "   • Complete cleanup"
echo "   • Remove all AWS resources"
echo "   • Reset to clean state"
echo ""
echo "9) 📖 Open Documentation"
echo "   • View complete deployment guide"
echo "   • Troubleshooting information"
echo "   • Architecture details"
echo ""

read -p "Enter choice (1-9): " choice

case $choice in
    1)
        echo -e "${BLUE}🏗️  Deploying Phase 1: Public Setup...${NC}"
        echo ""
        echo "This will create:"
        echo "• EC2 t2.micro instance with public IP"
        echo "• MongoDB 6.0 installation"
        echo "• Lambda function with VPC access"
        echo "• SSH key pair for access"
        echo ""
        read -p "Continue? (y/n): " confirm
        if [ "$confirm" = "y" ]; then
            bash deploy.sh
            echo ""
            echo -e "${GREEN}✅ Phase 1 deployed!${NC}"
            echo ""
            echo "Next steps:"
            echo "• Test with: bash test-all-phases-complete.sh"
            echo "• SSH access: ssh -i ~/.ssh/id_rsa ubuntu@$(terraform output -raw ec2_public_ip 2>/dev/null)"
            echo "• Proceed to Phase 2 when ready"
        fi
        ;;
    2)
        echo -e "${BLUE}🔒 Deploying Phase 2: Private Setup...${NC}"
        echo ""
        echo "This will:"
        echo "• Remove public IP and SSH access"
        echo "• Keep all data intact"
        echo "• Enhance security posture"
        echo "• Maintain Lambda connectivity"
        echo ""
        read -p "Continue? (y/n): " confirm
        if [ "$confirm" = "y" ]; then
            cp main-private.tf main.tf
            cp outputs-private.tf outputs.tf
            terraform plan
            echo ""
            read -p "Apply changes? (y/n): " apply_confirm
            if [ "$apply_confirm" = "y" ]; then
                terraform apply -auto-approve
                echo ""
                echo -e "${GREEN}✅ Phase 2 deployed!${NC}"
                echo ""
                echo "Security improvements:"
                echo "• No public IP access"
                echo "• SSH completely blocked"
                echo "• Lambda-only database access"
                echo "• Test with: bash test-all-phases-complete.sh"
            fi
        fi
        ;;
    3)
        echo -e "${BLUE}🌐 Deploying Phase 3: API Gateway...${NC}"
        echo ""
        echo "This will add:"
        echo "• REST API endpoint"
        echo "• CORS support for browsers"
        echo "• Public HTTPS access"
        echo "• curl and web app compatibility"
        echo ""
        read -p "Continue? (y/n): " confirm
        if [ "$confirm" = "y" ]; then
            bash deploy-api.sh
            echo ""
            echo -e "${GREEN}✅ Phase 3 deployed!${NC}"
            echo ""
            API_URL=$(terraform output -raw api_gateway_invoke_url 2>/dev/null)
            echo "Your API URL: $API_URL"
            echo ""
            echo "Test with curl:"
            echo "curl -X POST $API_URL -H 'Content-Type: application/json' -d '{\"action\":\"find\",\"query\":{}}'"
        fi
        ;;
    4)
        echo -e "${BLUE}📱 Deploying Phase 4: Single Page Application...${NC}"
        echo ""
        echo "This will add:"
        echo "• S3 static website hosting"
        echo "• CloudFront global CDN"
        echo "• Complete web interface"
        echo "• MongoDB management dashboard"
        echo ""
        echo "Note: CloudFront deployment takes 10-15 minutes"
        echo ""
        read -p "Continue? (y/n): " confirm
        if [ "$confirm" = "y" ]; then
            bash deploy-spa.sh
            echo ""
            echo -e "${GREEN}✅ Phase 4 deployed!${NC}"
            echo ""
            SPA_URL=$(terraform output -raw spa_url 2>/dev/null)
            echo "Your SPA URL: $SPA_URL"
            echo ""
            echo "Note: CloudFront may take 10-15 minutes to fully propagate"
            echo "If the site doesn't load immediately, please wait and try again"
        fi
        ;;
    5)
        echo -e "${BLUE}🚀 Deploying All Phases Sequentially...${NC}"
        echo ""
        echo "This will deploy all phases with testing between each:"
        echo "Phase 1 → Test → Phase 2 → Test → Phase 3 → Test → Phase 4"
        echo ""
        echo "Total time: ~20-30 minutes (including CloudFront)"
        echo ""
        read -p "Continue with full deployment? (y/n): " confirm
        if [ "$confirm" = "y" ]; then
            echo ""
            echo -e "${YELLOW}Starting Phase 1: Public Setup...${NC}"
            bash deploy.sh
            
            echo ""
            echo -e "${YELLOW}Testing Phase 1...${NC}"
            bash test-all-phases-complete.sh
            
            echo ""
            read -p "Phase 1 complete. Continue to Phase 2? (y/n): " confirm2
            if [ "$confirm2" = "y" ]; then
                echo -e "${YELLOW}Starting Phase 2: Private Setup...${NC}"
                cp main-private.tf main.tf
                cp outputs-private.tf outputs.tf
                terraform apply -auto-approve
                
                echo ""
                echo -e "${YELLOW}Testing Phase 2...${NC}"
                bash test-all-phases-complete.sh
                
                echo ""
                read -p "Phase 2 complete. Continue to Phase 3? (y/n): " confirm3
                if [ "$confirm3" = "y" ]; then
                    echo -e "${YELLOW}Starting Phase 3: API Gateway...${NC}"
                    bash deploy-api.sh
                    
                    echo ""
                    echo -e "${YELLOW}Testing Phase 3...${NC}"
                    bash test-all-phases-complete.sh
                    
                    echo ""
                    read -p "Phase 3 complete. Continue to Phase 4? (y/n): " confirm4
                    if [ "$confirm4" = "y" ]; then
                        echo -e "${YELLOW}Starting Phase 4: SPA + CDN...${NC}"
                        bash deploy-spa.sh
                        
                        echo ""
                        echo -e "${YELLOW}Final Testing...${NC}"
                        bash test-all-phases-complete.sh
                        
                        echo ""
                        echo -e "${GREEN}🎉 ALL PHASES COMPLETE!${NC}"
                        echo ""
                        SPA_URL=$(terraform output -raw spa_url 2>/dev/null)
                        API_URL=$(terraform output -raw api_gateway_invoke_url 2>/dev/null)
                        echo "🌐 Your Web App: $SPA_URL"
                        echo "🔗 Your API: $API_URL"
                        echo ""
                        echo "The complete MongoDB management system is now live!"
                    fi
                fi
            fi
        fi
        ;;
    6)
        echo -e "${BLUE}🧪 Testing Current Deployment...${NC}"
        bash test-all-phases-complete.sh
        ;;
    7)
        echo -e "${BLUE}📊 Current Status:${NC}"
        echo ""
        echo "State: $CURRENT_STATE"
        echo ""
        if [ -f "terraform.tfstate" ]; then
            echo "Terraform Outputs:"
            terraform output 2>/dev/null || echo "No outputs available"
            echo ""
            echo "AWS Resources:"
            echo "• EC2 Instances: $(aws ec2 describe-instances --query 'Reservations[].Instances[?State.Name!=`terminated`] | length(@)' --output text 2>/dev/null || echo 'Unknown')"
            echo "• Lambda Functions: $(aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `mongo`)] | length(@)' --output text 2>/dev/null || echo 'Unknown')"
            echo "• S3 Buckets: $(aws s3 ls | grep mongo-spa | wc -l 2>/dev/null || echo 'Unknown')"
        else
            echo "No deployment found."
        fi
        ;;
    8)
        echo -e "${RED}💥 Destroying All Resources...${NC}"
        echo ""
        echo "This will permanently delete:"
        echo "• All EC2 instances"
        echo "• Lambda functions"
        echo "• API Gateway"
        echo "• S3 buckets and content"
        echo "• CloudFront distributions"
        echo "• All MongoDB data"
        echo ""
        echo -e "${RED}⚠️  THIS CANNOT BE UNDONE!${NC}"
        echo ""
        read -p "Are you absolutely sure? Type 'DELETE' to confirm: " confirm
        if [ "$confirm" = "DELETE" ]; then
            echo ""
            echo "Destroying resources..."
            terraform destroy -auto-approve
            
            echo ""
            echo "Cleaning up local files..."
            rm -f *.zip response.json terraform.tfstate* index_updated.html
            
            echo ""
            echo -e "${GREEN}✅ All resources destroyed!${NC}"
            echo ""
            echo "Verification:"
            aws ec2 describe-instances --query 'Reservations[].Instances[?State.Name!=`terminated`]' --output table 2>/dev/null || echo "EC2 check failed"
            aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `mongo`)]' --output table 2>/dev/null || echo "Lambda check failed"
        else
            echo "Destruction cancelled."
        fi
        ;;
    9)
        echo -e "${BLUE}📖 Opening Documentation...${NC}"
        echo ""
        echo "Available documentation files:"
        echo "• COMPLETE_DEPLOYMENT_GUIDE.md - Full deployment guide"
        echo "• DEPLOYMENT_GUIDE.md - Original guide"
        echo "• README files for each phase"
        echo ""
        if command -v code &> /dev/null; then
            echo "Opening in VS Code..."
            code COMPLETE_DEPLOYMENT_GUIDE.md
        elif command -v notepad &> /dev/null; then
            echo "Opening in Notepad..."
            notepad COMPLETE_DEPLOYMENT_GUIDE.md
        else
            echo "Please open COMPLETE_DEPLOYMENT_GUIDE.md in your preferred editor"
        fi
        ;;
    *)
        echo -e "${RED}Invalid choice. Please run again.${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${BLUE}📚 Additional Resources:${NC}"
echo "• Complete Guide: COMPLETE_DEPLOYMENT_GUIDE.md"
echo "• Test Script: bash test-all-phases-complete.sh"
echo "• Quick Start: bash quick-start-complete.sh"
echo ""
echo -e "${GREEN}Thank you for using MongoDB Lambda AWS! 🚀${NC}"