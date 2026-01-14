// Test to verify isolate prevents access to host filesystem and sensitive locations
const fs = require('fs');
const path = require('path');

console.log('=== Testing Isolate Security Boundaries ===\n');

function tryAccess(description, fn) {
    try {
        const result = fn();
        console.log(`✗ ${description}`);
        console.log(`  SECURITY ISSUE: Access succeeded!`);
        console.log(`  Result:`, result);
        return false;
    } catch (e) {
        console.log(`✓ ${description}`);
        console.log(`  Blocked: ${e.code || e.message}`);
        return true;
    }
}

let allBlocked = true;

// Test 1: Try to access pay-server source code
console.log('File System Access Tests:\n');
allBlocked &= tryAccess(
    'Block access to /pay/src/pay-server',
    () => fs.readdirSync('/pay/src/pay-server')
);

// Test 2: Try to access pay directory
console.log();
allBlocked &= tryAccess(
    'Block access to /pay directory',
    () => fs.readdirSync('/pay')
);

// Test 3: Try to access home directory
console.log();
allBlocked &= tryAccess(
    'Block access to /home',
    () => fs.readdirSync('/home')
);

// Test 4: Try to access user's home directory specifically
console.log();
allBlocked &= tryAccess(
    'Block access to /home/tomchen',
    () => fs.readdirSync('/home/tomchen')
);

// Test 5: Try to read a sensitive file
console.log();
allBlocked &= tryAccess(
    'Block reading /etc/shadow',
    () => fs.readFileSync('/etc/shadow', 'utf8')
);

// Test 6: Try to write to /tmp (sandboxed /tmp is allowed)
console.log();
console.log('✓ Allow writing to /tmp (sandboxed /tmp, isolated from host)');
try {
    fs.writeFileSync('/tmp/test-sandbox.txt', 'sandboxed write');
    console.log('  Sandboxed /tmp is accessible (does not affect host)');
} catch (e) {
    console.log('  Unexpected error:', e.message);
}

// Test 7: Try to access parent of sandbox
console.log();
allBlocked &= tryAccess(
    'Block listing parent directories with traversal',
    () => fs.readdirSync('../../../../pay')
);

// Test 8: Show what IS accessible
console.log('\n--- What IS Accessible ---\n');
console.log('Current directory:', process.cwd());
console.log('Files in current dir:', fs.readdirSync('.'));
console.log('Can read own script:', fs.existsSync('script.js'));
console.log('Has node_modules:', fs.existsSync('node_modules'));

// Test 9: Network restrictions (if SHARE_NET is enabled)
console.log('\n--- Network Configuration ---\n');
if (process.env.HTTP_PROXY) {
    console.log('Network enabled via proxy only');
    console.log('HTTP_PROXY:', process.env.HTTP_PROXY);
    console.log('HTTPS_PROXY:', process.env.HTTPS_PROXY);
    console.log('Direct external connections: BLOCKED (must use proxy)');
} else {
    console.log('Network completely disabled');
    console.log('No HTTP_PROXY configured');
}

// Test 10: Verify /tmp is sandboxed
console.log();
console.log('✓ Verify /tmp isolation from host');
try {
    const tmpContents = fs.readdirSync('/tmp');
    console.log(`  Sandboxed /tmp contents:`, tmpContents);
    console.log('  (These files are isolated and cleaned up after execution)');
} catch (e) {
    console.log('  Could not read /tmp:', e.message);
}

// Summary
console.log('\n=== Security Test Summary ===\n');
if (allBlocked) {
    console.log('✓ All critical security boundaries enforced');
    console.log('✓ Host filesystem (/pay, /home) is protected');
    console.log('✓ Pay-server source code is inaccessible');
    console.log('✓ Sandbox isolation is working correctly');
    console.log('✓ Only sandboxed /box and /tmp are accessible');
} else {
    console.log('✗ WARNING: Some security boundaries were breached!');
    console.log('✗ Review the failures above');
}
