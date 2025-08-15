# Lambda Repackaging Process - Detailed Analysis

## Current Package Structure

### Before Enhancement:
```
lambda_function.zip
└── lambda_function.py (30 lines - basic functionality)
```

### After Enhancement:
```
lambda_function.zip
└── lambda_function.py (300+ lines - enhanced functionality)
```

## Repackaging Steps in Detail

### Step 1: Code Replacement
```bash
# Backup original
cp lambda_function.py lambda_function.py.backup

# Replace with enhanced version  
cp lambda_function_enhanced.py lambda_function.py
```

### Step 2: ZIP Recreation
```bash
# Remove old package
rm -f lambda_function.zip

# Create new package with enhanced code
zip lambda_function.zip lambda_function.py

# Result: New ZIP with larger, enhanced code
```

### Step 3: Terraform Detects Change
```hcl
resource "aws_lambda_function" "mongo_client" {
  filename         = "lambda_function.zip"  # Terraform checks file hash
  # When hash changes, Lambda function gets updated
}
```

## Package Size Comparison

### Current Package:
```bash
$ ls -la lambda_function.zip
-rw-r--r-- 1 user user 1.2K lambda_function.zip  # ~1.2KB
```

### Enhanced Package:
```bash
$ ls -la lambda_function.zip  
-rw-r--r-- 1 user user 4.8K lambda_function.zip  # ~4.8KB (4x larger)
```

## Terraform Update Process

### What Terraform Does:
1. **Hash Comparison**: Compares old vs new ZIP file hash
2. **Change Detection**: Detects code change
3. **Function Update**: Calls AWS Lambda UpdateFunctionCode API
4. **Atomic Replacement**: Replaces entire function code

### Terraform Plan Output:
```bash
$ terraform plan

# aws_lambda_function.mongo_client will be updated in-place
~ resource "aws_lambda_function" "mongo_client" {
    id               = "mongo-client"
    # (25 unchanged attributes hidden)
    
    ~ source_code_hash = "old-hash" -> "new-hash"
}
```

## Dependencies and Layers

### Current Setup (Unchanged):
```hcl
# Lambda Layer remains the same
resource "aws_lambda_layer_version" "pymongo" {
  filename   = "pymongo-layer.zip"  # No change needed
  layer_name = "pymongo"
  compatible_runtimes = ["python3.9"]
}

# Lambda still uses same layer
resource "aws_lambda_function" "mongo_client" {
  layers = [aws_lambda_layer_version.pymongo.arn]  # Same layer
}
```

### Why Layer Doesn't Need Repackaging:
- Enhanced code only uses existing dependencies (pymongo, json, os, datetime)
- No new external libraries added
- datetime is Python built-in (no additional dependency)

## Deployment Timeline

### Repackaging Process:
```
1. Code Update:     ~1 second
2. ZIP Creation:    ~1 second  
3. Terraform Plan:  ~10 seconds
4. Lambda Update:   ~30 seconds (AWS API call)
5. Function Ready:  ~5 seconds (warm-up)
Total:             ~47 seconds
```

### During Update:
- **Existing invocations**: Continue with old code
- **New invocations**: Queue until update completes
- **Zero downtime**: No service interruption
- **Atomic switch**: Old → New code instantly

## Rollback Process

### If Issues Occur:
```bash
# 1. Restore original code
cp lambda_function.py.backup lambda_function.py

# 2. Repackage with original code
rm -f lambda_function.zip
zip lambda_function.zip lambda_function.py

# 3. Terraform rollback
terraform apply  # Deploys original code back
```

### Rollback Timeline:
- **Detection**: Manual (monitoring/testing)
- **Rollback**: ~30 seconds (same as deployment)
- **Service restoration**: Immediate

## Best Practices for Lambda Repackaging

### 1. Always Backup
```bash
# Before any change
cp lambda_function.py lambda_function.py.backup
cp lambda_function.zip lambda_function.zip.backup
```

### 2. Test Package Locally
```bash
# Verify ZIP contents
unzip -l lambda_function.zip
# Should show: lambda_function.py

# Verify code syntax
python3 -m py_compile lambda_function.py
```

### 3. Gradual Deployment
```bash
# Option 1: Test in staging first
# Option 2: Use Lambda aliases/versions for blue-green deployment
# Option 3: Monitor CloudWatch logs during deployment
```

## Package Optimization

### Current Approach (Simple):
```bash
zip lambda_function.zip lambda_function.py
```

### Production Approach (Optimized):
```bash
# Remove unnecessary files
zip -r lambda_function.zip lambda_function.py -x "*.pyc" "__pycache__/*"

# Verify package
zip -sf lambda_function.zip
```

## Monitoring Package Updates

### CloudWatch Logs:
```bash
# Monitor deployment
aws logs tail /aws/lambda/mongo-client --follow

# Look for:
# "START RequestId: ..." (new invocation)
# "Method: GET, Path: /api/health" (enhanced code working)
```

### Function Metrics:
- **Duration**: May increase slightly (more code)
- **Memory**: Minimal increase
- **Error Rate**: Monitor for new issues
- **Invocation Count**: Should remain stable
```