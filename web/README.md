# MongoDB CRUD Web Application

A single-page web application for performing CRUD operations on your MongoDB API.

## Features

- **Create** documents with name, status, category, and priority
- **Read** documents with filtering and pagination
- **Update** documents using MongoDB query syntax
- **Delete** documents individually or in bulk
- **API Configuration** with connection testing
- **Local Storage** for API settings persistence

## Setup

1. **Get your API details:**
   ```bash
   # Get API URL
   terraform output api_gateway_base_url
   
   # Get API Key
   terraform output api_key_value
   ```

2. **Open the web application:**
   ```bash
   # Open in browser
   open web/index.html
   # or
   firefox web/index.html
   # or
   chrome web/index.html
   ```

3. **Configure API settings:**
   - Enter your API Gateway URL
   - Enter your API Key
   - Click "Test Connection" to verify

## Usage

### Create Documents
- Fill in the form fields (name, status, category, priority)
- Click "Create Document"
- Document will be added and list will refresh

### Read Documents
- Use filters to find specific documents
- Set limit for pagination
- Click "Load Documents" or "Refresh"

### Update Documents
- Enter MongoDB query in JSON format: `{"status": "pending"}`
- Enter update operation: `{"$set": {"status": "completed"}}`
- Click "Update Documents"

### Delete Documents
- **Single delete:** Click "Delete This Document" on any document
- **Bulk delete:** Enter query and click "Delete Documents"

## Example Queries

### Filter Examples:
```json
{"status": "active"}
{"category": "test"}
{"priority": {"$gte": 5}}
```

### Update Examples:
```json
{"$set": {"status": "completed"}}
{"$inc": {"priority": 1}}
{"$set": {"status": "archived", "updated_by": "admin"}}
```

### Delete Examples:
```json
{"status": "completed"}
{"category": "test"}
{"created_at": {"$lt": "2025-01-01"}}
```

## Security Notes

- API Key is stored in browser localStorage
- Use "Show/Hide" button to toggle API key visibility
- All requests require valid API key authentication
- CORS is enabled for browser access

## Troubleshooting

### Connection Issues:
- Verify API Gateway URL is correct
- Check API Key is valid
- Ensure CORS is properly configured
- Check browser console for errors

### API Errors:
- 403 Forbidden: Invalid or missing API key
- 400 Bad Request: Invalid JSON in query/update
- 500 Internal Error: Check Lambda logs

### Browser Compatibility:
- Modern browsers with ES6+ support
- Chrome, Firefox, Safari, Edge
- JavaScript must be enabled