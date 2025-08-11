#!/bin/bash

echo "🚀 MongoDB Lambda AWS - Quick Start"
echo "=================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Please install: https://aws.amazon.com/cli/"
    exit 1
fi

# Check Terraform
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform not found. Please install: https://terraform.io/downloads"
    exit 1
fi

# Check AWS credentials
aws sts get-caller-identity &> /dev/null
if [ $? -ne 0 ]; then
    echo "❌ AWS credentials not configured. Run: aws configure"
    exit 1
fi

echo "✅ All prerequisites met!"
echo ""

# Phase selection
echo "Select deployment phase:"
echo "1) Phase 1: Public Setup (Development)"
echo "2) Phase 2: Private Setup (Production)"  
echo "3) Phase 3: API Gateway (Internet Access)"
echo "4) Run All Phases Sequentially"
echo "5) Test Current Deployment"
echo "6) Destroy All Resources"
echo ""
read -p "Enter choice (1-6): " choice

case $choice in
    1)
        echo "🔧 Deploying Phase 1: Public Setup..."
        bash deploy.sh
        echo ""
        echo "✅ Phase 1 deployed! Test with:"
        echo "bash test-all-phases.sh"
        ;;
    2)
        echo "🔒 Deploying Phase 2: Private Setup..."
        cp main-private.tf main.tf
        cp outputs-private.tf outputs.tf
        terraform plan
        read -p "Apply changes? (y/n): " confirm
        if [ "$confirm" = "y" ]; then
            terraform apply
            echo ""
            echo "✅ Phase 2 deployed! Test with:"
            echo "bash test-all-phases.sh"
        fi
        ;;
    3)
        echo "🌐 Deploying Phase 3: API Gateway..."
        bash deploy-api.sh
        echo ""
        echo "✅ Phase 3 deployed! Your API URL:"
        terraform output api_gateway_invoke_url
        echo ""
        echo "Test with:"
        echo "bash test-all-phases.sh"
        ;;
    4)
        echo "🚀 Running All Phases Sequentially..."
        echo ""
        echo "Phase 1: Public Setup..."
        bash deploy.sh
        echo ""
        read -p "Phase 1 complete. Continue to Phase 2? (y/n): " confirm
        if [ "$confirm" = "y" ]; then
            echo "Phase 2: Private Setup..."
            cp main-private.tf main.tf
            cp outputs-private.tf outputs.tf
            terraform apply -auto-approve
            echo ""
            read -p "Phase 2 complete. Continue to Phase 3? (y/n): " confirm
            if [ "$confirm" = "y" ]; then
                echo "Phase 3: API Gateway..."
                bash deploy-api.sh
                echo ""
                echo "🎉 All phases complete!"
                echo "Your API URL:"
                terraform output api_gateway_invoke_url
            fi
        fi
        ;;
    5)
        echo "🧪 Testing current deployment..."
        bash test-all-phases.sh
        ;;
    6)
        echo "💥 Destroying all resources..."
        read -p "Are you sure? This will delete everything! (y/n): " confirm
        if [ "$confirm" = "y" ]; then
            terraform destroy -auto-approve
            rm -f *.zip response.json terraform.tfstate*
            echo "✅ All resources destroyed!"
        fi
        ;;
    *)
        echo "Invalid choice. Please run again."
        exit 1
        ;;
esac

echo ""
echo "📖 For detailed instructions, see: DEPLOYMENT_GUIDE.md"