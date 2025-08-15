# Security Comparison: Current Setup vs AWS Security Reference

## Overview
This document compares our current MongoDB API infrastructure against AWS security best practices and reference architecture.

## Security Comparison Table

| **Security Component** | **Your Current Setup** | **AWS Security Reference** | **Gap/Risk** |
|------------------------|------------------------|----------------------------|--------------|
| **Network Security** | | | |
| VPC Configuration | ✅ Custom VPC with private subnets | ✅ Multi-AZ VPC with public/private subnets | ⚠️ Single AZ, no redundancy |
| Security Groups | ✅ Restrictive rules, Lambda-to-EC2 only | ✅ Principle of least privilege | ✅ Good |
| **Network ACLs** | **❌ Using default NACLs** | **✅ Custom NACLs for defense in depth** | **⚠️ Missing layer - Details Below** |
| **NAT Gateway** | **❌ No NAT Gateway** | **✅ NAT Gateway for private subnet internet** | **⚠️ Lambda direct internet - Details Below** |
| **Identity & Access** | | | |
| IAM Roles | ✅ Lambda execution role | ✅ Granular roles per service | ✅ Good |
| IAM Policies | ✅ VPC execution policy | ✅ Least privilege policies | ⚠️ Could be more granular |
| API Authentication | ✅ API Keys | ✅ IAM/Cognito + API Keys | ⚠️ No user authentication |
| **Data Protection** | | | |
| **Encryption at Rest** | **❌ MongoDB unencrypted** | **✅ All data encrypted** | **❌ High Risk - Details Below** |
| **Encryption in Transit** | **✅ HTTPS API Gateway** | **✅ TLS everywhere** | **⚠️ MongoDB connection unencrypted - Details Below** |
| **Secrets Management** | **❌ Environment variables in Lambda** | **✅ AWS Secrets Manager with rotation** | **❌ High Risk - Details Below** |
| **Monitoring & Logging** | | | |
| **CloudTrail** | **❌ Not configured** | **✅ Enabled for all regions** | **❌ Compliance Risk - Details Below** |
| **VPC Flow Logs** | **❌ Not enabled** | **✅ Enabled for network monitoring** | **❌ Blind spot - Details Below** |
| Lambda Logs | ✅ CloudWatch Logs | ✅ Structured logging | ✅ Good |
| **Backup & Recovery** | | | |
| **Database Backups** | **❌ No automated backups** | **✅ Automated backups + snapshots** | **❌ Data Loss Risk - Details Below** |
| Infrastructure as Code | ✅ Terraform | ✅ IaC with version control | ✅ Good |
| **DDoS Protection** | | | |
| **DDoS Mitigation** | **❌ No DDoS protection** | **✅ AWS Shield Standard + Advanced** | **❌ High Risk - Details Below** |
| **Rate Limiting** | **✅ API Gateway throttling (1000 req/s)** | **✅ Multiple layers of rate limiting** | **⚠️ Single layer only** |
| **Vulnerability Management** | | | |
| **Software Inventory** | **❌ Unknown software versions** | **✅ AWS Systems Manager Inventory** | **❌ Blind spot - Details Below** |
| **Vulnerability Scanning** | **❌ No vulnerability assessment** | **✅ Amazon Inspector + third-party tools** | **❌ High Risk - Details Below** |
| **Software Bill of Materials** | **❌ No SBOM tracking** | **✅ Dependency tracking + CVE monitoring** | **❌ Supply chain risk - Details Below** |
| **Compliance** | | | |
| Security Groups Audit | ❌ Manual | ✅ AWS Config rules | ⚠️ No automation |
| **Patch Management** | **❌ Manual EC2 patching** | **✅ Systems Manager Patch Manager** | **❌ Security Risk - Details Below** |
| **Cost vs Security** | **~$15/month** | **~$150-300/month** | **10-20x more expensive** |

## Detailed Breakdown of Major Deficiencies

### 1. Secrets Management (High Risk)

#### Your Current Setup (Risky):
```hcl
# In Terraform - visible in state files
environment {
  variables = {
    MONGO_HOST = aws_instance.mongo.private_ip  # IP exposed
  }
}
```

```python
# In Lambda code - hardcoded connection
client = pymongo.MongoClient(f"mongodb://{os.environ['MONGO_HOST']}:27017/")
# No authentication, credentials visible in logs
```

#### AWS Security Reference (Secure):
```hcl
# Secrets Manager
resource "aws_secretsmanager_secret" "mongo_credentials" {
  name = "mongo-db-credentials"
}

resource "aws_secretsmanager_secret_version" "mongo_credentials" {
  secret_id = aws_secretsmanager_secret.mongo_credentials.id
  secret_string = jsonencode({
    username = "admin"
    password = "secure_password"
    host     = aws_instance.mongo.private_ip
    port     = 27017
  })
}
```

#### Security Risks:
- **Terraform state files** contain connection strings
- **CloudWatch logs** may expose connection details
- **No database authentication** (anyone with IP can connect)
- **No credential rotation**
- **Version control** may contain sensitive data

### 2. Network ACLs (Missing Defense Layer)

#### Your Setup:
```hcl
# Using default NACLs - allows all traffic
# No explicit network-level controls
```

#### Security Reference:
```hcl
resource "aws_network_acl" "private" {
  vpc_id = aws_vpc.main.id
  
  # Only allow specific ports/protocols
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    from_port  = 27017
    to_port    = 27017
    cidr_block = "10.0.0.0/16"
    action     = "allow"
  }
}
```

**Risk:** No network-level filtering beyond security groups

### 3. NAT Gateway (Lambda Internet Exposure)

#### Your Setup:
```hcl
# Lambda in public subnet with direct internet
vpc_config {
  subnet_ids = [aws_subnet.main.id]  # Public subnet
}
```

#### Security Reference:
```hcl
# Lambda in private subnet, internet via NAT
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
}
```

**Risk:** Lambda can be attacked directly from internet

### 4. Encryption at Rest (MongoDB Unprotected)

#### Your Setup:
```bash
# install_mongo.sh - no encryption
sudo systemctl start mongod  # Default config, no encryption
```

#### Security Reference:
```bash
# MongoDB with encryption
mongod --enableEncryption --encryptionKeyFile /path/to/keyfile
```

**Risk:** Database files readable if EC2 compromised

### 5. Encryption in Transit (MongoDB Connection)

#### Your Setup:
```python
# Unencrypted MongoDB connection
client = pymongo.MongoClient(f"mongodb://{host}:27017/")
```

#### Security Reference:
```python
# TLS encrypted connection
client = pymongo.MongoClient(f"mongodb://{host}:27017/", tls=True)
```

**Risk:** Network traffic can be intercepted

### 6. CloudTrail (No Audit Trail)

#### Your Setup:
```hcl
# No CloudTrail configuration
```

#### Security Reference:
```hcl
resource "aws_cloudtrail" "main" {
  name           = "main-trail"
  s3_bucket_name = aws_s3_bucket.trail.bucket
  
  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }
}
```

**Risk:** No record of who did what, when (compliance failure)

### 7. VPC Flow Logs (Network Blind Spot)

#### Your Setup:
```hcl
# No flow logs
```

#### Security Reference:
```hcl
resource "aws_flow_log" "vpc" {
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}
```

**Risk:** Cannot detect network attacks or unusual traffic

### 8. Database Backups (Data Loss Risk)

#### Your Setup:
```bash
# No backup strategy in install_mongo.sh
```

#### Security Reference:
```bash
# Automated backups
mongodump --host localhost --out /backups/$(date +%Y%m%d)
# + S3 sync + retention policy
```

**Risk:** Permanent data loss if EC2 fails

### 9. Patch Management (Vulnerable System)

#### Your Setup:
```bash
# Manual patching only
sudo apt update && sudo apt upgrade  # When you remember
```

#### Security Reference:
```hcl
resource "aws_ssm_patch_baseline" "ubuntu" {
  name             = "ubuntu-baseline"
  operating_system = "UBUNTU"
  
  approval_rule {
    approve_after_days = 7
    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Bugfix"]
    }
  }
}
```

**Risk:** Running vulnerable software with known exploits

### 10. DDoS Protection (High Risk)

#### Your Setup:
```hcl
# Only API Gateway throttling
throttle_settings {
  rate_limit  = 1000   # 1000 requests/second
  burst_limit = 2000   # 2000 burst capacity
}
# No additional DDoS protection
```

#### Security Reference:
```hcl
# AWS Shield Advanced
resource "aws_shield_protection" "api_gateway" {
  name         = "api-gateway-protection"
  resource_arn = aws_api_gateway_rest_api.mongo_api.arn
}

# CloudFront for additional protection
resource "aws_cloudfront_distribution" "api" {
  origin {
    domain_name = "${aws_api_gateway_rest_api.mongo_api.id}.execute-api.${var.region}.amazonaws.com"
    origin_id   = "api-gateway"
  }
  
  # Built-in DDoS protection
  web_acl_id = aws_wafv2_web_acl.api_protection.arn
}

# WAF for application-layer protection
resource "aws_wafv2_web_acl" "api_protection" {
  name  = "api-ddos-protection"
  scope = "CLOUDFRONT"
  
  rule {
    name     = "RateLimitRule"
    priority = 1
    
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    
    action {
      block {}
    }
  }
}
```

#### DDoS Attack Vectors You're Vulnerable To:
- **Volumetric attacks** - High traffic floods
- **Protocol attacks** - SYN floods, UDP floods
- **Application layer attacks** - HTTP floods, slowloris
- **API-specific attacks** - Expensive query floods

#### Current Protection Gaps:
- **No AWS Shield** - Basic DDoS protection missing
- **No WAF** - Application-layer attacks unfiltered
- **No CloudFront** - No edge-level protection
- **Single rate limit** - Only API Gateway throttling
- **No geographic blocking** - Worldwide access

#### Attack Impact:
- **API unavailability** - Service goes down
- **Lambda cost explosion** - Attackers trigger expensive functions
- **Database overload** - MongoDB crashes under load
- **Legitimate users blocked** - Service degradation

**Risk:** Your API can be easily taken offline by DDoS attacks

### 11. Software Inventory (Blind Spot)

#### Your Setup:
```bash
# Unknown software versions running
# EC2 instance with:
# - Ubuntu 20.04 (unknown patch level)
# - MongoDB (unknown version)
# - Python 3.9 (Lambda runtime)
# - pymongo (unknown version in layer)
# - No inventory tracking
```

#### Security Reference:
```hcl
# Systems Manager Inventory
resource "aws_ssm_association" "inventory" {
  name = "AWS-GatherSoftwareInventory"
  
  targets {
    key    = "InstanceIds"
    values = [aws_instance.mongo.id]
  }
  
  parameters = {
    applications         = "Enabled"
    awsComponents       = "Enabled"
    customInventory     = "Enabled"
    instanceDetailedInformation = "Enabled"
    services            = "Enabled"
  }
}

# Inventory dashboard
resource "aws_ssm_resource_data_sync" "inventory" {
  name = "inventory-sync"
  
  s3_destination {
    bucket_name = aws_s3_bucket.inventory.bucket
    region      = var.aws_region
  }
}
```

**What You Don't Know:**
- **Exact MongoDB version** - Could have known CVEs
- **Ubuntu package versions** - Security patches missing
- **Python dependencies** - Vulnerable libraries
- **System services** - Unnecessary services running
- **Installed packages** - Attack surface unknown

### 12. Vulnerability Scanning (High Risk)

#### Your Setup:
```bash
# No vulnerability scanning
# No CVE monitoring
# No security assessments
# Manual security reviews only
```

#### Security Reference:
```hcl
# Amazon Inspector for EC2
resource "aws_inspector_assessment_target" "mongo" {
  name = "mongo-assessment"
  resource_group_arn = aws_inspector_resource_group.mongo.arn
}

resource "aws_inspector_assessment_template" "mongo" {
  name       = "mongo-security-assessment"
  target_arn = aws_inspector_assessment_target.mongo.arn
  duration   = 3600
  
  rules_package_arns = [
    "arn:aws:inspector:us-east-1:316112463485:rulespackage/0-gEjTy7T7", # Security Best Practices
    "arn:aws:inspector:us-east-1:316112463485:rulespackage/0-rExsr2X8", # Network Reachability
    "arn:aws:inspector:us-east-1:316112463485:rulespackage/0-R01qwB5Q", # Runtime Behavior
    "arn:aws:inspector:us-east-1:316112463485:rulespackage/0-gBONHN9h"  # Common Vulnerabilities
  ]
}

# Lambda vulnerability scanning
resource "aws_inspector2_enabler" "lambda" {
  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["Lambda"]
}
```

**Unknown Vulnerabilities:**
- **CVE database** - No automated CVE checking
- **Configuration issues** - Insecure settings undetected
- **Network vulnerabilities** - Open ports/services
- **Application vulnerabilities** - Code-level security flaws
- **Dependency vulnerabilities** - Third-party library risks

### 13. Software Bill of Materials (Supply Chain Risk)

#### Your Setup:
```python
# pymongo layer - unknown dependencies
# No dependency tracking
# No license compliance
# No supply chain security
```

#### Security Reference:
```yaml
# Example SBOM tracking
sbom:
  components:
    - name: "pymongo"
      version: "4.3.3"
      licenses: ["Apache-2.0"]
      vulnerabilities: []
      supplier: "MongoDB Inc."
    - name: "python"
      version: "3.9.16"
      vulnerabilities: ["CVE-2023-XXXX"]
      patch_available: true
```

```hcl
# Dependency scanning
resource "aws_codebuild_project" "dependency_scan" {
  name         = "dependency-vulnerability-scan"
  service_role = aws_iam_role.codebuild.arn
  
  artifacts {
    type = "NO_ARTIFACTS"
  }
  
  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:5.0"
    type         = "LINUX_CONTAINER"
  }
  
  source {
    type = "NO_SOURCE"
    buildspec = "buildspec-security.yml"
  }
}
```

**Supply Chain Risks:**
- **Malicious packages** - Compromised dependencies
- **License violations** - Legal compliance issues
- **Outdated dependencies** - Known security flaws
- **Transitive dependencies** - Hidden vulnerable components
- **No provenance tracking** - Unknown software origins

**Risk:** Running unknown software versions with potential zero-day exploits

## Critical Gaps to Address

### Immediate Priority (High Risk):
1. **Implement vulnerability scanning (Amazon Inspector)**
2. **Create software inventory (Systems Manager)**
3. **Add DDoS protection (AWS Shield + WAF)**
4. **Encrypt MongoDB data**
5. **Use AWS Secrets Manager**
6. **Enable CloudTrail**
7. **Set up automated backups**

### Medium Priority (Compliance/Monitoring):
8. **Implement patch management**
9. **Enable VPC Flow Logs**
10. **Add Network ACLs**
11. **Move Lambda to private subnet with NAT**
12. **Establish Software Bill of Materials (SBOM)**

## Cost Impact

- **Current Setup:** ~$15/month
- **Security Reference:** ~$150-300/month
- **Cost Multiplier:** 10-20x more expensive

## Conclusion

Your current setup is **functionally secure** for development/testing but has **8 major security gaps** that could lead to:
- Data breaches
- Compliance failures
- Data loss
- Undetected attacks

The setup prioritizes **cost over security** - appropriate for development, risky for production.