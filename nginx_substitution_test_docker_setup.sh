#!/bin/bash
set -e

echo "Building image..."
docker build --no-cache -t test-secure-nginx:1.28.0 -f nginx.Dockerfile .
#docker build -t test-secure-nginx:1.28.0 -f nginx.Dockerfile .

echo "Setting up test environment..."
mkdir -p test/{html,conf}
echo '<html><body>Test page with __TEST_TOKEN__ placeholder</body></html>' > test/html/index.html
cat > test/conf/default.conf << EOF
server {
    listen 80;
    server_name localhost;

    # Add debugging for sub_filter
    error_log /var/log/nginx/error.log debug;

    location / {
        root /usr/share/nginx/html;
        index index.html;
        sub_filter '__TEST_TOKEN__' 'REPLACED_VALUE';
        sub_filter_once on;
        sub_filter_types text/html;
    }

    # Add health endpoint explicitly
    location /health {
        access_log off;
        add_header Content-Type text/plain;
        return 200 "OK";
    }
}
EOF

# Find a free port using a temporary socket
find_free_port() {
  local port=$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
  echo "$port"
}

# Get a free port
FREE_PORT=$(find_free_port)
echo "Using free port: $FREE_PORT"

echo "Starting container..."
docker stop nginx-test 2>/dev/null || true
docker rm nginx-test 2>/dev/null || true

# Run container with debug mode
docker run -d --name nginx-test \
  -v $(pwd)/test/html:/usr/share/nginx/html:ro \
  -v $(pwd)/test/conf:/etc/nginx/conf.d:ro \
  -p $FREE_PORT:80 \
  test-secure-nginx:1.28.0

echo "Waiting for container to start..."
sleep 5

echo "Checking container status..."
docker ps | grep nginx-test || { echo "Container not running!"; docker logs nginx-test; exit 1; }

echo "Verifying file permissions and contents inside container..."
docker exec nginx-test ls -la /usr/share/nginx/html
docker exec nginx-test cat /usr/share/nginx/html/index.html
docker exec nginx-test ls -la /etc/nginx/conf.d
docker exec nginx-test cat /etc/nginx/conf.d/default.conf

echo "Testing health endpoint..."
HEALTH=$(curl -s http://localhost:$FREE_PORT/health)
if [ "$HEALTH" = "OK" ]; then
  echo "✅ Health check passed"
else
  echo "❌ Health check failed"
  echo "Health response: '$HEALTH'"
  echo "Container logs:"
  docker logs nginx-test
  exit 1
fi

echo "Testing sub_filter functionality..."
echo "Raw HTML response:"
curl -v http://localhost:$FREE_PORT/

RESULT=$(curl -s http://localhost:$FREE_PORT/ | grep -o "REPLACED_VALUE" || echo "NOT_FOUND")
if [ "$RESULT" = "REPLACED_VALUE" ]; then
  echo "✅ Sub filter is working"
else
  echo "❌ Sub filter test failed"
  echo "Raw HTML response:"
  curl -s http://localhost:$FREE_PORT/
  echo "Docker logs:"
  docker logs nginx-test
  echo "NGINX error log:"
  docker exec nginx-test cat /var/log/nginx/error.log
  exit 1
fi


echo "Running security tests..."

# 1. Test for server information disclosure
echo "Testing for server information disclosure..."
SERVER_HEADER=$(curl -s -I http://localhost:$FREE_PORT/ | grep -i "Server:")
if [ -z "$SERVER_HEADER" ] || [[ "$SERVER_HEADER" != *"nginx/"* ]]; then
  echo "✅ Server header does not disclose detailed version information"
else
  echo "⚠️ Server header may be exposing version information: $SERVER_HEADER"
fi

# 2. Test for security headers
echo "Testing for security headers..."
SECURITY_HEADERS=$(curl -s -I http://localhost:$FREE_PORT/)
MISSING_HEADERS=()

if ! echo "$SECURITY_HEADERS" | grep -q "X-Content-Type-Options: nosniff"; then
  MISSING_HEADERS+=("X-Content-Type-Options")
fi

if ! echo "$SECURITY_HEADERS" | grep -q "X-Frame-Options"; then
  MISSING_HEADERS+=("X-Frame-Options")
fi

if ! echo "$SECURITY_HEADERS" | grep -q "X-XSS-Protection"; then
  MISSING_HEADERS+=("X-XSS-Protection")
fi

if [ ${#MISSING_HEADERS[@]} -eq 0 ]; then
  echo "✅ All recommended security headers are present"
else
  echo "⚠️ Some recommended security headers are missing: ${MISSING_HEADERS[*]}"
fi

# 3. Test for invalid HTTP methods
echo "Testing for invalid HTTP methods..."
OPTIONS_RESPONSE=$(curl -s -I -X OPTIONS http://localhost:$FREE_PORT/ | head -n 1)
if [[ "$OPTIONS_RESPONSE" == *"405"* ]] || [[ "$OPTIONS_RESPONSE" == *"403"* ]]; then
  echo "✅ Server properly handles OPTIONS method"
else
  echo "⚠️ Server allows OPTIONS method: $OPTIONS_RESPONSE"
fi

TRACE_RESPONSE=$(curl -s -I -X TRACE http://localhost:$FREE_PORT/ | head -n 1)
if [[ "$TRACE_RESPONSE" == *"405"* ]] || [[ "$TRACE_RESPONSE" == *"403"* ]]; then
  echo "✅ Server properly restricts TRACE method"
else
  echo "⚠️ Server allows TRACE method: $TRACE_RESPONSE"
fi

# 4. Test for directory listing
echo "Testing for directory listing prevention..."
mkdir -p test/html/testdir
curl -s http://localhost:$FREE_PORT/testdir/ > /tmp/dirlist_test
if grep -q "Index of" /tmp/dirlist_test; then
  echo "⚠️ Directory listing may be enabled"
else
  echo "✅ Directory listing appears to be disabled"
fi
rm /tmp/dirlist_test

# 5. Test for HTTP to HTTPS redirection (if applicable on port 80)
# This is commented out as your current setup is using only HTTP
# echo "Testing for HTTP to HTTPS redirection..."
# REDIRECT=$(curl -s -I http://localhost:$FREE_PORT/ | grep -i "Location:")
# if [[ "$REDIRECT" == *"https://"* ]]; then
#   echo "✅ HTTP requests are redirected to HTTPS"
# else
#   echo "⚠️ No HTTP to HTTPS redirection detected"
# fi

echo "Checking module is enabled..."
MODULES=$(docker exec nginx-test nginx -V 2>&1 | grep "with-http_sub_module")
if [ -n "$MODULES" ]; then
  echo "✅ Module is enabled"
else
  echo "❌ Module is not enabled"
  exit 1
fi

echo "All tests passed! 🎉"
docker stop nginx-test
docker rm nginx-test
