# Base image with pinned version
FROM alpine:3.18.12 AS builder

# Set Nginx version
ENV NGINX_VERSION=1.28.0

# Install build dependencies
RUN apk add --no-cache --update \
    gcc \
    libc-dev \
    make \
    openssl-dev \
    pcre-dev \
    zlib-dev \
    linux-headers \
    curl \
    gnupg \
    libxslt-dev \
    gd-dev \
    geoip-dev

# Download and verify Nginx source
WORKDIR /tmp
RUN curl -fSL https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz -o nginx.tar.gz && \
    mkdir -p /usr/src && \
    tar -zxC /usr/src -f nginx.tar.gz && \
    rm nginx.tar.gz

# Configure and build Nginx with necessary modules
WORKDIR /usr/src/nginx-${NGINX_VERSION}
RUN ./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/tmp/nginx.pid \
    --lock-path=/tmp/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --user=nginx \
    --group=nginx \
    --with-compat \
    --with-file-aio \
    --with-threads \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_realip_module \
    --with-http_sub_module \
    --with-http_stub_status_module \
    --with-http_gzip_static_module \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && make install

# Create a minimal runtime image
FROM alpine:3.18.12

# Install minimal runtime dependencies and create Nginx user
RUN apk add --no-cache --update \
    ca-certificates \
    pcre \
    openssl \
    tzdata \
    curl \
    && addgroup -S nginx \
    && adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \
    && mkdir -p /var/cache/nginx \
    && mkdir -p /var/log/nginx

# Copy Nginx from builder stage
COPY --from=builder /etc/nginx /etc/nginx
COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx

# Copy the nginx.conf file (created outside the Dockerfile)
COPY nginx.conf /etc/nginx/nginx.conf

# Create necessary directories with proper permissions
RUN mkdir -p /var/cache/nginx/client_temp \
    /var/cache/nginx/proxy_temp \
    /var/cache/nginx/fastcgi_temp \
    /var/cache/nginx/uwsgi_temp \
    /var/cache/nginx/scgi_temp \
    /tmp/nginx \
    && chown -R nginx:nginx /var/cache/nginx \
    && chown -R nginx:nginx /var/log/nginx \
    && chown -R nginx:nginx /tmp/nginx \
    && chmod -R 755 /var/cache/nginx \
    && chmod -R 755 /var/log/nginx \
    && chmod -R 755 /tmp/nginx \
    && chmod 644 /etc/nginx/nginx.conf \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

# Create empty conf.d directory
RUN mkdir -p /etc/nginx/conf.d && \
    chown -R nginx:nginx /etc/nginx && \
    chmod 755 /etc/nginx/conf.d

# Create default health check endpoint and test page
RUN mkdir -p /usr/share/nginx/html && \
    echo '<html><body><h1>Test Page</h1><p>This is a _PLACEHOLDER_ for testing sub_filter.</p></body></html>' > /usr/share/nginx/html/index.html && \
    echo "OK" > /usr/share/nginx/html/health && \
    chown -R nginx:nginx /usr/share/nginx

# Use non-root user
USER nginx

STOPSIGNAL SIGQUIT

# Start Nginx with explicit PID path
CMD ["nginx", "-g", "daemon off; pid /tmp/nginx.pid;"]
