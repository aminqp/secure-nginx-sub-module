#!/bin/bash
set -e

echo "Building image..."
docker build --no-cache -t test-secure-nginx:1.24.0 -f nginx.Dockerfile .

echo "Setting up test environment..."
mkdir -p test/{html,conf}
echo '<html><body>Test page with __TEST_TOKEN__ placeholder</body></html>' > test/html/index.html
cat > test/conf/default.conf << EOF
server {
    listen 80;
    server_name localhost;
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
docker run -d --name nginx-test \
  -v $(pwd)/test/html:/usr/share/nginx/html \
  -v $(pwd)/test/conf:/etc/nginx/conf.d \
  -p $FREE_PORT:80 \
  test-secure-nginx:1.24.0

echo "Waiting for container to start..."
sleep 3

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
RESULT=$(curl -s http://localhost:$FREE_PORT/ | grep -o "REPLACED_VALUE")
if [ "$RESULT" = "REPLACED_VALUE" ]; then
  echo "✅ Sub filter is working"
else
  echo "❌ Sub filter test failed"
  echo "Raw HTML response:"
  curl -s http://localhost:$FREE_PORT/
  exit 1
fi

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
