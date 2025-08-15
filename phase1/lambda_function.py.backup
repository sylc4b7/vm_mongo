import pymongo
import json
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Enhanced Lambda function for API Gateway proxy integration
    Handles multiple HTTP methods and endpoints
    """
    
    # CORS headers for all responses
    cors_headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
        'Content-Type': 'application/json'
    }
    
    try:
        # Extract HTTP method and path
        http_method = event.get('httpMethod', '')
        path = event.get('path', '')
        
        print(f"Method: {http_method}, Path: {path}")
        
        # Handle health check endpoint
        if path == '/api/health':
            return handle_health_check(cors_headers)
        
        # Handle documents endpoint
        if path == '/api/documents':
            return handle_documents(event, cors_headers)
        
        # Fallback for unknown endpoints
        return {
            'statusCode': 404,
            'headers': cors_headers,
            'body': json.dumps({
                'error': 'Endpoint not found',
                'available_endpoints': [
                    'GET /api/health',
                    'GET /api/documents',
                    'POST /api/documents',
                    'PUT /api/documents',
                    'DELETE /api/documents'
                ]
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': cors_headers,
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e)
            })
        }

def handle_health_check(cors_headers):
    """Health check endpoint"""
    try:
        # Test MongoDB connection
        client = pymongo.MongoClient(f"mongodb://{os.environ['MONGO_HOST']}:27017/", serverSelectionTimeoutMS=5000)
        client.server_info()  # Test connection
        client.close()
        
        return {
            'statusCode': 200,
            'headers': cors_headers,
            'body': json.dumps({
                'status': 'healthy',
                'timestamp': datetime.utcnow().isoformat(),
                'mongodb': 'connected',
                'version': '1.0.0'
            })
        }
    except Exception as e:
        return {
            'statusCode': 503,
            'headers': cors_headers,
            'body': json.dumps({
                'status': 'unhealthy',
                'timestamp': datetime.utcnow().isoformat(),
                'mongodb': 'disconnected',
                'error': str(e)
            })
        }

def handle_documents(event, cors_headers):
    """Handle documents CRUD operations"""
    http_method = event.get('httpMethod', '')
    
    # Parse request body for POST/PUT
    body = {}
    if event.get('body'):
        try:
            body = json.loads(event['body'])
        except json.JSONDecodeError:
            return {
                'statusCode': 400,
                'headers': cors_headers,
                'body': json.dumps({'error': 'Invalid JSON in request body'})
            }
    
    # Parse query parameters
    query_params = event.get('queryStringParameters') or {}
    
    # MongoDB connection
    client = pymongo.MongoClient(f"mongodb://{os.environ['MONGO_HOST']}:27017/")
    db = client['testdb']
    collection = db['testcol']
    
    try:
        if http_method == 'GET':
            return handle_get_documents(collection, query_params, cors_headers)
        elif http_method == 'POST':
            return handle_create_document(collection, body, cors_headers)
        elif http_method == 'PUT':
            return handle_update_documents(collection, body, cors_headers)
        elif http_method == 'DELETE':
            return handle_delete_documents(collection, query_params, body, cors_headers)
        else:
            return {
                'statusCode': 405,
                'headers': cors_headers,
                'body': json.dumps({'error': f'Method {http_method} not allowed'})
            }
    finally:
        client.close()

def handle_get_documents(collection, query_params, cors_headers):
    """GET /api/documents - Find documents"""
    try:
        # Build query from query parameters
        query = {}
        if 'filter' in query_params:
            query = json.loads(query_params['filter'])
        
        # Pagination
        limit = int(query_params.get('limit', 100))
        skip = int(query_params.get('skip', 0))
        
        # Execute query
        cursor = collection.find(query).skip(skip).limit(limit)
        docs = list(cursor)
        
        # Convert ObjectId to string
        for doc in docs:
            doc['_id'] = str(doc['_id'])
        
        # Count total documents
        total = collection.count_documents(query)
        
        return {
            'statusCode': 200,
            'headers': cors_headers,
            'body': json.dumps({
                'documents': docs,
                'total': total,
                'limit': limit,
                'skip': skip,
                'count': len(docs)
            })
        }
    except Exception as e:
        return {
            'statusCode': 400,
            'headers': cors_headers,
            'body': json.dumps({'error': f'Query error: {str(e)}'})
        }

def handle_create_document(collection, body, cors_headers):
    """POST /api/documents - Create document"""
    if not body:
        return {
            'statusCode': 400,
            'headers': cors_headers,
            'body': json.dumps({'error': 'Request body is required'})
        }
    
    try:
        # Add timestamp
        body['created_at'] = datetime.utcnow().isoformat()
        
        # Insert document
        result = collection.insert_one(body)
        
        return {
            'statusCode': 201,
            'headers': cors_headers,
            'body': json.dumps({
                'message': 'Document created successfully',
                'inserted_id': str(result.inserted_id),
                'document': {**body, '_id': str(result.inserted_id)}
            })
        }
    except Exception as e:
        return {
            'statusCode': 400,
            'headers': cors_headers,
            'body': json.dumps({'error': f'Insert error: {str(e)}'})
        }

def handle_update_documents(collection, body, cors_headers):
    """PUT /api/documents - Update documents"""
    if not body or 'query' not in body or 'update' not in body:
        return {
            'statusCode': 400,
            'headers': cors_headers,
            'body': json.dumps({
                'error': 'Request body must contain "query" and "update" fields',
                'example': {
                    'query': {'status': 'pending'},
                    'update': {'$set': {'status': 'completed'}}
                }
            })
        }
    
    try:
        # Add update timestamp
        if '$set' in body['update']:
            body['update']['$set']['updated_at'] = datetime.utcnow().isoformat()
        else:
            body['update']['$set'] = {'updated_at': datetime.utcnow().isoformat()}
        
        # Update documents
        result = collection.update_many(body['query'], body['update'])
        
        return {
            'statusCode': 200,
            'headers': cors_headers,
            'body': json.dumps({
                'message': 'Documents updated successfully',
                'matched_count': result.matched_count,
                'modified_count': result.modified_count
            })
        }
    except Exception as e:
        return {
            'statusCode': 400,
            'headers': cors_headers,
            'body': json.dumps({'error': f'Update error: {str(e)}'})
        }

def handle_delete_documents(collection, query_params, body, cors_headers):
    """DELETE /api/documents - Delete documents"""
    try:
        # Get query from body or query parameters
        query = {}
        if body and 'query' in body:
            query = body['query']
        elif 'filter' in query_params:
            query = json.loads(query_params['filter'])
        
        if not query:
            return {
                'statusCode': 400,
                'headers': cors_headers,
                'body': json.dumps({
                    'error': 'Query is required for delete operation',
                    'examples': [
                        'DELETE /api/documents?filter={"status":"completed"}',
                        'DELETE /api/documents with body: {"query": {"status": "completed"}}'
                    ]
                })
            }
        
        # Delete documents
        result = collection.delete_many(query)
        
        return {
            'statusCode': 200,
            'headers': cors_headers,
            'body': json.dumps({
                'message': 'Documents deleted successfully',
                'deleted_count': result.deleted_count
            })
        }
    except Exception as e:
        return {
            'statusCode': 400,
            'headers': cors_headers,
            'body': json.dumps({'error': f'Delete error: {str(e)}'})
        }