# MongoDB Lambda API Gateway - Testing Guide

## Overview

This guide provides comprehensive information for testing the MongoDB Lambda API through AWS API Gateway. The API provides RESTful endpoints for CRUD operations on MongoDB collections.

## Architecture

```
Internet → API Gateway → Lambda Function → MongoDB (EC2)
```

- **API Gateway**: Provides public HTTP endpoints with CORS support
- **Lambda Function**: Handles business logic and MongoDB operations
- **MongoDB**: Running on EC2 instance in private subnet
- **VPC**: Secure network isolation

## API Endpoints

### Base URL
```
https://{api-gateway-id}.execute-api.{region}.amazonaws.com/prod
```

### Available Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/health` | Health check and system status |
| GET | `/api/documents` | Retrieve documents (with filtering and pagination) |
| POST | `/api/documents` | Create a new document |
| PUT | `/api/documents` | Update existing documents |
| DELETE | `/api/documents` | Delete documents |

## Endpoint Details

### 1. Health Check
**GET** `/api/health`

Returns system health status and MongoDB connectivity.

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "mongodb": "connected",
  "version": "1.0.0"
}
```

**Example:**
```bash
curl -X GET https://your-api-id.execute-api.us-east-1.amazonaws.com/prod/api/health
```

### 2. Get Documents
**GET** `/api/documents`

Retrieve documents with optional filtering and pagination.

**Query Parameters:**
- `filter`: JSON string for MongoDB query (optional)
- `limit`: Maximum number of documents to return (default: 100)
- `skip`: Number of documents to skip for pagination (default: 0)

**Response:**
```json
{
  "documents": [
    {
      "_id": "507f1f77bcf86cd799439011",
      "name": "Sample Document",
      "status": "active",
      "created_at": "2024-01-15T10:30:00.000Z"
    }
  ],
  "total": 1,
  "limit": 100,
  "skip": 0,
  "count": 1
}
```

**Examples:**
```bash
# Get all documents
curl -X GET https://your-api-id.execute-api.us-east-1.amazonaws.com/prod/api/documents

# Get documents with filter
curl -X GET 'https://your-api-id.execute-api.us-east-1.amazonaws.com/prod/api/documents?filter={"status":"active"}'

# Get with pagination
curl -X GET 'https://your-api-id.execute-api.us-east-1.amazonaws.com/prod/api/documents?limit=10&skip=20'
```

### 3. Create Document
**POST** `/api/documents`

Create a new document in the MongoDB collection.

**Request Body:**
```json
{
  "name": "New Document",
  "status": "active",
  "category": "test",
  "priority": 1
}
```

**Response:**
```json
{
  "message": "Document created successfully",
  "inserted_id": "507f1f77bcf86cd799439011",
  "document": {
    "_id": "507f1f77bcf86cd799439011",
    "name": "New Document",
    "status": "active",
    "category": "test",
    "priority": 1,
    "created_at": "2024-01-15T10:30:00.000Z"
  }
}
```

**Example:**
```bash
curl -X POST https://your-api-id.execute-api.us-east-1.amazonaws.com/prod/api/documents \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "Test Document",
    "status": "active",
    "description": "This is a test document"
  }'
```

### 4. Update Documents
**PUT** `/api/documents`

Update existing documents that match the query criteria.

**Request Body:**
```json
{
  "query": {
    "status": "pending"
  },
  "update": {
    "$set": {
      "status": "completed",
      "completed_by": "user123"
    }
  }
}
```

**Response:**
```json
{
  "message": "Documents updated successfully",
  "matched_count": 5,
  "modified_count": 5
}
```

**Example:**
```bash
curl -X PUT https://your-api-id.execute-api.us-east-1.amazonaws.com/prod/api/documents \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {"status": "pending"},
    "update": {"$set": {"status": "in-progress"}}
  }'
```

### 5. Delete Documents
**DELETE** `/api/documents`

Delete documents that match the query criteria.

**Query Parameters:**
- `filter`: JSON string for MongoDB query (required)

**Alternative: Request Body:**
```json
{
  "query": {
    "status": "completed"
  }
}
```

**Response:**
```json
{
  "message": "Documents deleted successfully",
  "deleted_count": 3
}
```

**Examples:**
```bash
# Delete using query parameter
curl -X DELETE 'https://your-api-id.execute-api.us-east-1.amazonaws.com/prod/api/documents?filter={"status":"completed"}'

# Delete using request body
curl -X DELETE https://your-api-id.execute-api.us-east-1.amazonaws.com/prod/api/documents \
  -H 'Content-Type: application/json' \
  -d '{"query": {"status": "completed"}}'
```

## Error Handling

The API returns appropriate HTTP status codes and error messages:

### Common Status Codes
- `200`: Success
- `201`: Created (for POST requests)
- `400`: Bad Request (invalid JSON, missing required fields)
- `404`: Not Found (invalid endpoint)
- `405`: Method Not Allowed
- `500`: Internal Server Error
- `503`: Service Unavailable (MongoDB connection issues)

### Error Response Format
```json
{
  "error": "Error description",
  "message": "Additional details (optional)"
}
```

## CORS Support

The API includes full CORS support for web applications:

**Allowed Origins:** `*` (all origins)
**Allowed Methods:** `GET, POST, PUT, DELETE, OPTIONS`
**Allowed Headers:** `Content-Type, X-Amz-Date, Authorization, X-Api-Key, X-Amz-Security-Token`

## Testing Tools

### 1. Automated Testing Script
Run the comprehensive test suite:
```bash
./test-api-enhanced.sh
```

This script tests all endpoints, error handling, CORS, and pagination.

### 2. Manual Testing with curl

#### Quick Test Sequence
```bash
# 1. Check health
curl -X GET $API_BASE_URL/api/health

# 2. Create a document
curl -X POST $API_BASE_URL/api/documents \
  -H 'Content-Type: application/json' \
  -d '{"name":"Test Doc","status":"active"}'

# 3. Get all documents
curl -X GET $API_BASE_URL/api/documents

# 4. Update documents
curl -X PUT $API_BASE_URL/api/documents \
  -H 'Content-Type: application/json' \
  -d '{"query":{"status":"active"},"update":{"$set":{"status":"completed"}}}'

# 5. Delete documents
curl -X DELETE "$API_BASE_URL/api/documents?filter={\"status\":\"completed\"}"
```

### 3. Testing with Postman

Import the following collection for Postman testing:

1. Create a new collection
2. Set base URL variable: `{{baseUrl}}`
3. Add requests for each endpoint
4. Set appropriate headers: `Content-Type: application/json`

### 4. Web Browser Testing

For GET requests, you can test directly in a web browser:
```
https://your-api-id.execute-api.us-east-1.amazonaws.com/prod/api/health
https://your-api-id.execute-api.us-east-1.amazonaws.com/prod/api/documents
```

## Sample Data for Testing

### Create Sample Documents
```bash
# User document
curl -X POST $API_BASE_URL/api/documents \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "user",
    "name": "John Doe",
    "email": "john@example.com",
    "status": "active",
    "created_at": "2024-01-15T10:00:00Z"
  }'

# Product document
curl -X POST $API_BASE_URL/api/documents \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "product",
    "name": "Laptop",
    "price": 999.99,
    "category": "electronics",
    "in_stock": true
  }'

# Order document
curl -X POST $API_BASE_URL/api/documents \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "order",
    "order_id": "ORD-001",
    "customer": "John Doe",
    "total": 999.99,
    "status": "pending"
  }'
```

## Performance Considerations

- **Lambda Cold Start**: First request may take 2-3 seconds
- **Concurrent Requests**: Lambda can handle multiple concurrent requests
- **Timeout**: Lambda function timeout is set to 30 seconds
- **Payload Limit**: Maximum request/response size is 6MB

## Security Notes

- API Gateway is publicly accessible
- No authentication is currently implemented
- CORS allows all origins (`*`)
- MongoDB is in private subnet, only accessible via Lambda
- All traffic is encrypted in transit (HTTPS)

## Troubleshooting

### Common Issues

1. **502 Bad Gateway**: Lambda function error or timeout
2. **503 Service Unavailable**: MongoDB connection issues
3. **CORS Errors**: Missing preflight OPTIONS request handling

### Debug Steps

1. Check API Gateway logs in CloudWatch
2. Check Lambda function logs in CloudWatch
3. Verify MongoDB is running on EC2
4. Test Lambda function directly (bypass API Gateway)
5. Check security group rules

### Getting Help

1. Check CloudWatch logs for detailed error messages
2. Use the health endpoint to verify system status
3. Run the automated test script to identify issues
4. Verify all infrastructure is deployed correctly

## Deployment

To deploy the enhanced API Gateway:

```bash
./deploy-enhanced-api.sh
```

This script will:
1. Create enhanced Terraform configuration
2. Update Lambda function with new code
3. Deploy infrastructure
4. Provide testing endpoints

## Cleanup

To remove all resources:
```bash
terraform destroy -auto-approve
```

This will delete all AWS resources and stop billing.