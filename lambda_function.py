import pymongo
import json
import os

def lambda_handler(event, context):
    client = pymongo.MongoClient(f"mongodb://{os.environ['MONGO_HOST']}:27017/")
    db = client['testdb']
    collection = db['testcol']
    
    try:
        if event.get('action') == 'insert':
            result = collection.insert_one(event['data'])
            return {
                'statusCode': 200,
                'body': json.dumps({'inserted_id': str(result.inserted_id)})
            }
        
        elif event.get('action') == 'find':
            docs = list(collection.find(event.get('query', {})))
            for doc in docs:
                doc['_id'] = str(doc['_id'])
            return {
                'statusCode': 200,
                'body': json.dumps(docs)
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
    
    finally:
        client.close()