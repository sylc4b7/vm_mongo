// MongoDB CRUD Application JavaScript

let apiUrl = '';
let apiKey = '';

// Initialize the application
document.addEventListener('DOMContentLoaded', function() {
    // Load saved configuration
    apiUrl = localStorage.getItem('apiUrl') || document.getElementById('apiUrl').value;
    apiKey = localStorage.getItem('apiKey') || '';
    
    document.getElementById('apiUrl').value = apiUrl;
    document.getElementById('apiKey').value = apiKey;
    
    // Auto-load documents if configuration exists
    if (apiUrl && apiKey) {
        loadDocuments();
    }
});

// Toggle API key visibility
function toggleApiKey() {
    const apiKeyInput = document.getElementById('apiKey');
    apiKeyInput.type = apiKeyInput.type === 'password' ? 'text' : 'password';
}

// Test API connection
async function testConnection() {
    updateConfig();
    const statusDiv = document.getElementById('connectionStatus');
    
    try {
        const response = await fetch(`${apiUrl}/api/health`);
        const data = await response.json();
        
        if (response.ok && data.status === 'healthy') {
            statusDiv.innerHTML = '<span class="success">✅ Connection successful! MongoDB is connected.</span>';
        } else {
            statusDiv.innerHTML = '<span class="error">❌ API responded but MongoDB may be disconnected.</span>';
        }
    } catch (error) {
        statusDiv.innerHTML = `<span class="error">❌ Connection failed: ${error.message}</span>`;
    }
}

// Update configuration from form
function updateConfig() {
    apiUrl = document.getElementById('apiUrl').value.trim();
    apiKey = document.getElementById('apiKey').value.trim();
    
    // Save to localStorage
    localStorage.setItem('apiUrl', apiUrl);
    localStorage.setItem('apiKey', apiKey);
}

// Make API request with error handling
async function makeApiRequest(endpoint, options = {}) {
    updateConfig();
    
    if (!apiUrl || !apiKey) {
        throw new Error('Please configure API URL and API Key first');
    }
    
    const defaultOptions = {
        headers: {
            'Content-Type': 'application/json',
            'X-API-Key': apiKey
        }
    };
    
    const mergedOptions = {
        ...defaultOptions,
        ...options,
        headers: {
            ...defaultOptions.headers,
            ...options.headers
        }
    };
    
    const response = await fetch(`${apiUrl}${endpoint}`, mergedOptions);
    const data = await response.json();
    
    if (!response.ok) {
        throw new Error(data.error || `HTTP ${response.status}`);
    }
    
    return data;
}

// Create a new document
async function createDocument() {
    const resultDiv = document.getElementById('createResult');
    
    try {
        const document = {
            name: document.getElementById('createName').value.trim(),
            status: document.getElementById('createStatus').value,
            category: document.getElementById('createCategory').value.trim(),
            priority: parseInt(document.getElementById('createPriority').value)
        };
        
        if (!document.name) {
            throw new Error('Name is required');
        }
        
        const result = await makeApiRequest('/api/documents', {
            method: 'POST',
            body: JSON.stringify(document)
        });
        
        resultDiv.innerHTML = `<span class="success">✅ Document created with ID: ${result.inserted_id}</span>`;
        
        // Clear form
        document.getElementById('createName').value = '';
        document.getElementById('createCategory').value = '';
        document.getElementById('createPriority').value = '1';
        
        // Refresh documents list
        loadDocuments();
        
    } catch (error) {
        resultDiv.innerHTML = `<span class="error">❌ Error: ${error.message}</span>`;
    }
}

// Load and display documents
async function loadDocuments(force = false) {
    const container = document.getElementById('documentsContainer');
    
    if (!force) {
        container.innerHTML = '<p>Loading documents...</p>';
    }
    
    try {
        let endpoint = '/api/documents';
        const params = new URLSearchParams();
        
        // Add filters
        const filterStatus = document.getElementById('filterStatus').value;
        if (filterStatus) {
            params.append('filter', JSON.stringify({status: filterStatus}));
        }
        
        // Add limit
        const limit = document.getElementById('limitDocs').value;
        if (limit) {
            params.append('limit', limit);
        }
        
        if (params.toString()) {
            endpoint += '?' + params.toString();
        }
        
        const result = await makeApiRequest(endpoint);
        
        displayDocuments(result.documents, result.total);
        
    } catch (error) {
        container.innerHTML = `<span class="error">❌ Error loading documents: ${error.message}</span>`;
    }
}

// Display documents in the UI
function displayDocuments(documents, total) {
    const container = document.getElementById('documentsContainer');
    
    if (!documents || documents.length === 0) {
        container.innerHTML = '<p>No documents found.</p>';
        return;
    }
    
    let html = `<h3>Documents (${documents.length} of ${total} total)</h3>`;
    
    documents.forEach(doc => {
        html += `
            <div class="document">
                <strong>ID:</strong> ${doc._id}<br>
                <strong>Name:</strong> ${doc.name || 'N/A'}<br>
                <strong>Status:</strong> ${doc.status || 'N/A'}<br>
                <strong>Category:</strong> ${doc.category || 'N/A'}<br>
                <strong>Priority:</strong> ${doc.priority || 'N/A'}<br>
                <strong>Created:</strong> ${doc.created_at || 'N/A'}<br>
                ${doc.updated_at ? `<strong>Updated:</strong> ${doc.updated_at}<br>` : ''}
                <button onclick="deleteDocument('${doc._id}')" class="delete-btn">Delete This Document</button>
            </div>
        `;
    });
    
    container.innerHTML = html;
}

// Delete a single document
async function deleteDocument(documentId) {
    if (!confirm('Are you sure you want to delete this document?')) {
        return;
    }
    
    try {
        const query = JSON.stringify({_id: {$oid: documentId}});
        const endpoint = `/api/documents?filter=${encodeURIComponent(query)}`;
        
        const result = await makeApiRequest(endpoint, {
            method: 'DELETE'
        });
        
        alert(`✅ Document deleted successfully. Deleted count: ${result.deleted_count}`);
        loadDocuments();
        
    } catch (error) {
        alert(`❌ Error deleting document: ${error.message}`);
    }
}

// Update documents (bulk operation)
async function updateDocuments() {
    const resultDiv = document.getElementById('updateResult');
    
    try {
        const queryText = document.getElementById('updateQuery').value.trim();
        const updateText = document.getElementById('updateData').value.trim();
        
        if (!queryText || !updateText) {
            throw new Error('Both query and update data are required');
        }
        
        const query = JSON.parse(queryText);
        const update = JSON.parse(updateText);
        
        const result = await makeApiRequest('/api/documents', {
            method: 'PUT',
            body: JSON.stringify({
                query: query,
                update: update
            })
        });
        
        resultDiv.innerHTML = `<span class="success">✅ Updated ${result.modified_count} documents (${result.matched_count} matched)</span>`;
        
        // Refresh documents list
        loadDocuments();
        
    } catch (error) {
        resultDiv.innerHTML = `<span class="error">❌ Error: ${error.message}</span>`;
    }
}

// Delete documents (bulk operation)
async function deleteDocuments() {
    const resultDiv = document.getElementById('deleteResult');
    
    if (!confirm('Are you sure you want to delete documents matching this query?')) {
        return;
    }
    
    try {
        const queryText = document.getElementById('deleteQuery').value.trim();
        
        if (!queryText) {
            throw new Error('Query is required for delete operation');
        }
        
        const query = JSON.parse(queryText);
        const endpoint = `/api/documents?filter=${encodeURIComponent(JSON.stringify(query))}`;
        
        const result = await makeApiRequest(endpoint, {
            method: 'DELETE'
        });
        
        resultDiv.innerHTML = `<span class="success">✅ Deleted ${result.deleted_count} documents</span>`;
        
        // Refresh documents list
        loadDocuments();
        
    } catch (error) {
        resultDiv.innerHTML = `<span class="error">❌ Error: ${error.message}</span>`;
    }
}