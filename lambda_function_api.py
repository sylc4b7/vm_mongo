import pymongo
import json
import os

def lambda_handler(event, context):
    # Parse API Gateway event
    try:
        if event.get('body'):
            body = json.loads(event['body'])
        else:
            body = event
    except:
        return {
            'statusCode': 400,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'error': 'Invalid JSON in request body'})
        }
    
    # MongoDB connection
    client = pymongo.MongoClient(f"mongodb://{os.environ['MONGO_HOST']}:27017/")
    db = client['testdb']
    collection = db['testcol']
    
    try:
        if body.get('action') == 'insert':
            result = collection.insert_one(body['data'])
            response_body = {'inserted_id': str(result.inserted_id)}
            
        elif body.get('action') == 'find':
            docs = list(collection.find(body.get('query', {})))
            for doc in docs:
                doc['_id'] = str(doc['_id'])
            response_body = {'documents': docs}
            
        elif body.get('action') == 'update':
            result = collection.update_many(body['query'], body['update'])
            response_body = {'modified_count': result.modified_count}
            
        elif body.get('action') == 'delete':
            result = collection.delete_many(body.get('query', {}))
            response_body = {'deleted_count': result.deleted_count}
            
        else:
            response_body = {'error': 'Invalid action. Use: insert, find, update, delete'}
            
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps(response_body)
        }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'error': str(e)})
        }
    
    finally:
        client.close()