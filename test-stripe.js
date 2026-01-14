// Test script using Stripe API through egress proxy
const http = require('http');
const url = require('url');

// Initialize with API key from environment variable
const apiKey = process.env.STRIPE_API_KEY;
if (!apiKey) {
    console.error('Error: STRIPE_API_KEY environment variable is not set');
    console.error('Please create a .env file with your Stripe API key');
    process.exit(1);
}

console.log('Testing Stripe API through egress proxy...');

const proxyUrl = url.parse(process.env.HTTPS_PROXY || process.env.HTTP_PROXY);
console.log('Proxy:', `${proxyUrl.hostname}:${proxyUrl.port}`);

function makeStripeRequest(endpoint, callback) {
    const options = {
        hostname: proxyUrl.hostname,
        port: proxyUrl.port,
        path: `https://api.stripe.com${endpoint}`,
        method: 'GET',
        headers: {
            'Authorization': `Bearer ${apiKey}`,
            'Host': 'api.stripe.com'
        }
    };

    const req = http.request(options, (res) => {
        let data = '';
        res.on('data', (chunk) => { data += chunk; });
        res.on('end', () => callback(null, res, data));
    });

    req.on('error', (err) => callback(err));
    req.setTimeout(10000, () => {
        req.destroy();
        callback(new Error('Request timeout'));
    });
    req.end();
}

async function main() {
    console.log('Fetching customers from Stripe API...\n');

    makeStripeRequest('/v1/customers?limit=3', (err, res, data) => {
        if (err) {
            console.error('Error:', err.message);
            process.exit(1);
        }

        console.log('Status:', res.statusCode);

        try {
            const customers = JSON.parse(data);
            console.log('Success! Retrieved', customers.data.length, 'customers\n');

            customers.data.forEach((customer, idx) => {
                console.log(`Customer ${idx + 1}:`, {
                    id: customer.id,
                    email: customer.email || 'no email',
                    created: new Date(customer.created * 1000).toISOString()
                });
            });

            console.log('\nSandbox test complete! Stripe API is accessible through egress proxy.');
        } catch (e) {
            console.error('Failed to parse response:', e.message);
            console.log('Response:', data.substring(0, 200));
        }
    });
}

main();
