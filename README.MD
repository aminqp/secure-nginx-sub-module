# Secure Nginx Substitution Module Guidelines

This document provides clear, practical guidelines for implementing Content Security Policy (CSP) with nonce support in Single Page Applications (SPAs) using Nginx's substitution module.

## Table of Contents
- [Key Concepts](#key-concepts)
  - [Content Security Policy (CSP)](#content-security-policy-csp)
  - [Nonce](#nonce)
- [Implementation Steps](#implementation-steps)
  - [1. Webpack Configuration](#1-webpack-configuration)
  - [2. Custom Nginx Docker Image](#2-custom-nginx-docker-image)
  - [3. Nginx Configuration](#3-nginx-configuration)
  - [4. Docker Setup](#4-docker-setup)
- [Advanced Configurations](#advanced-configurations)
  - [MUI Integration](#mui-integration)
  - [Webpack Module Federation](#webpack-module-federation)
- [Building and Testing](#building-and-testing)
- [Security Considerations](#security-considerations)

## Key Concepts

### Content Security Policy (CSP)

Content Security Policy is a security mechanism that helps prevent Cross-Site Scripting (XSS) and other code injection attacks. CSP works by specifying which content sources browsers should consider valid, effectively blocking unauthorized scripts and resources.

**Key benefits:**
- Blocks XSS attacks by preventing unauthorized script execution
- Controls which resources (images, styles, scripts) can be loaded
- Prevents data exfiltration through unauthorized connections
- Provides an additional security layer beyond input validation

[Learn more about CSP](https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP)

### Nonce

A nonce ("number used once") is a unique, random value generated for each page request. When used with CSP, nonces allow specific inline scripts to execute while maintaining strict security policies.

**Why use nonces:**
- Allows necessary inline scripts without the insecure `unsafe-inline` directive
- Provides per-request security tokens that can't be predicted by attackers
- Maintains strong CSP protection while supporting dynamic content
- Works well with modern JavaScript frameworks and SPAs

[Learn more about nonce attributes](https://developer.mozilla.org/en-US/docs/Web/HTML/Global_attributes/nonce)

## Implementation Steps

This section provides a step-by-step guide to implementing CSP with nonce support in a Single Page Application. The implementation involves four main components:

1. **Webpack Configuration**: Setting up your frontend build process to support nonce attributes
2. **Custom Nginx Docker Image**: Building a secure Nginx image with the substitution module
3. **Nginx Configuration**: Configuring Nginx to generate nonces and replace placeholders
4. **Docker Setup**: Deploying your application with the custom Nginx configuration

Follow these steps in order to create a complete, secure implementation.

### 1. Webpack Configuration

#### Setting `__webpack_nonce__`

To allow Webpack to dynamically manage the `nonce` attribute for script tags during runtime, integrate the following script block directly within the `<head>` section of your main HTML template file:

```html
<!DOCTYPE html>
<html lang="en">
    <head>
        <!-- Place this before any script tag -->
        <script nonce="__CSP_NONCE__">
            window.__webpack_nonce__ = "__CSP_NONCE__"
        </script>
        <!-- Other head content -->
    </head>
    <body>
        <!-- Body content -->
    </body>
</html>
```
This HTML document serves as a template for a web application that:
- Sets up Content Security Policy (CSP) nonce values
- Configures webpack security settings
- Creates a root element for mounting the application
- Uses server-side templating to dynamically insert:
    - A customizable root element ID
    - Custom script tags for federated modules

The template includes placeholders that will be populated during build/runtime, particularly for webpack bundling and module federation support.


#### Configure Style Loader for Nonce Support

Enable `style-loader` to add nonce attributes to dynamically created style tags:
this will
- Configures `style-loader` to add a `nonce` attribute to each created `<style>` tag 
- Sets the nonce value to `__CSP_NONCE__` (likely a placeholder that gets replaced during build) 

```javascript
// In webpack config
{
  test: /\.css$/i,
  use: [
    {
      loader: 'style-loader',
      options: {
        attributes: {
          nonce: '__CSP_NONCE__' // Adds nonce attribute to style tags
        }
      }
    },
    'css-loader'
  ]
}
```
## Processing Flow:
1. When Webpack encounters a CSS file, it applies this rule
2. The file is first processed by `css-loader` to handle imports and convert to JS 
3. Then `style-loader` takes that output and creates styles with the specified nonce attribute 
4. At runtime, these styles are injected into the document


#### Set Up HtmlWebpackPlugin

Configure HtmlWebpackPlugin to use your HTML template:

```javascript
new HtmlWebpackPlugin({
  template: path.resolve(__dirname, 'template.html'),
  // Other options...
})
```

#### Create NonceInjectorPlugin

Develop a custom Webpack plugin to insert nonce placeholders into generated files. The plugin injects a placeholder value (`__CSP_NONCE__`) as a nonce attribute for all script and style tags generated by Webpack.

##### Key Components
1. **Imports**:
   Import the HtmlWebpackPlugin which this plugin will hook into.

```javascript
   const HtmlWebpackPlugin = require('html-webpack-plugin')
```

2. **Plugin Class Definition**:
   Define a class that follows the Webpack plugin pattern with an `apply` method that receives the Webpack compiler instance.
```javascript
   class NonceInjectorPlugin {
     apply(compiler) {
       // Plugin logic here
     }
   }
```

3. **Webpack Compilation Hook**:
   Tap into Webpack's compilation hook. This hook is triggered for each compilation created by the compiler.
```javascript
   compiler.hooks.compilation.tap('NonceInjectorPlugin', (compilation) => {
     // More hooks inside
   });
```

                             
4. **HtmlWebpackPlugin Hook**:
   Use HtmlWebpackPlugin's `alterAssetTags` hook to modify the HTML tags before they are inserted into the HTML document.
```javascript
   HtmlWebpackPlugin.getHooks(compilation).alterAssetTags.tapAsync(
     'NonceInjectorPlugin',
     (data, callback) => {
       // Nonce injection logic
     }
   );
```

5. **Nonce Injection Logic**:
   Iterate through all script and style tags in the HTML and adds a nonce attribute with the value `__CSP_NONCE__` to each tag.
```javascript
   data.assetTags.scripts.forEach(tag => {
     tag.attributes.nonce = '__CSP_NONCE__';
   });
   data.assetTags.styles.forEach(tag => {
     tag.attributes.nonce = '__CSP_NONCE__';
   });
```

6. **Callback**:
   Call the callback function with the modified data to allow the HTML generation to continue.
```javascript
   callback(null, data);
```

7. **Module Export**:
   Export the plugin class for use in Webpack configuration.
```javascript
   module.exports = { NonceInjectorPlugin }
```

Here's the final NonceInjectorPlugin
```javascript
// plugins/nonce-injector-plugin.js
const HtmlWebpackPlugin = require('html-webpack-plugin')

class NonceInjectorPlugin {
  apply(compiler) {
    compiler.hooks.compilation.tap('NonceInjectorPlugin', (compilation) => {
      HtmlWebpackPlugin.getHooks(compilation).alterAssetTags.tapAsync(
        'NonceInjectorPlugin',
        (data, callback) => {
          // Add nonce to all scripts and styles
          data.assetTags.scripts.forEach(tag => {
            tag.attributes.nonce = '__CSP_NONCE__';
          });
          data.assetTags.styles.forEach(tag => {
            tag.attributes.nonce = '__CSP_NONCE__';
          });
          callback(null, data);
        }
      );
    });
  }
}

module.exports = { NonceInjectorPlugin }
```

#### Complete Webpack Configuration

Integrate all components in your webpack configuration:

```javascript
const HtmlWebpackPlugin = require('html-webpack-plugin');
const { NonceInjectorPlugin } = require('./plugins/nonce-injector-plugin');

module.exports = {
  // Other webpack config...
  module: {
    rules: [
      // CSS rule with nonce support
      {
        test: /\.css$/i,
        use: [
          {
            loader: 'style-loader',
            options: {
              attributes: {
                nonce: '__CSP_NONCE__'
              }
            }
          },
          'css-loader'
        ]
      },
      // Other rules...
    ]
  },
  plugins: [
    // Other plugins...
    new HtmlWebpackPlugin({
      template: path.resolve(__dirname, 'template.html')
    }),
    new NonceInjectorPlugin() // Must come after HtmlWebpackPlugin
  ]
}
```

### 2. Custom Nginx Docker Image
Nginx lacks native support for adding nonces to response bodies. To achieve this, the Nginx Substitution Module is necessary, allowing for on-the-fly content rewriting for each HTTP request.

To incorporate this functionality, you can customize the standard Nginx Docker image by integrating third-party modules, such as the **substitution module**. This particular module facilitates regular expression-based text replacement within response bodies. This capability proves valuable for dynamically injecting content or modifying links directly on the server.


```dockerfile
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

# Copy the nginx.conf file
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
```

This Dockerfile uses a multi-stage build approach to create a minimal, security-focused Nginx container:
1. **Builder Stage**:
- Uses Alpine 3.18.12 as a base
- Installs build dependencies
- Downloads Nginx 1.28.0 source code
- Compiles Nginx with specific modules and configuration paths

2. **Runtime Stage**:
- Creates a fresh Alpine 3.18.12 container
- Installs only essential runtime dependencies
- Copies compiled Nginx binaries from the builder stage
- Sets up a proper directory structure with secure permissions
- Creates a non-root nginx user and configures ownership
- Adds a basic test page and health check endpoint
- Configures logging to stdout/stderr
- Runs Nginx as a non-root user

The approach minimizes the final image size and attack surface by separating build and runtime environments.   

### 3. Nginx Configuration

#### 3.1 Base Nginx configuration
Create a base Nginx configuration file (`nginx.conf`):

```nginx
worker_processes auto;
error_log /var/log/nginx/error.log warn;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;

    sendfile on;
    keepalive_timeout 65;

    # Ensure sub_filter buffer settings
    output_buffers 1 256k;
    postpone_output 1460;

    # Server information hiding
    server_tokens off;

    # Common security headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "deny" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Content-Security-Policy "default-src 'self';" always;
    add_header X-Content-Security-Policy "default-src 'self';" always;
    add_header X-WebKit-CSP "default-src 'self';" always;
    add_header Access-control-Allow-Credentials false;

    # Prevent directory listing
    autoindex off;

    # GZIP Configuration
    gzip on;
    gzip_disable "msie6";
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_min_length 256;
    gzip_types
        application/atom+xml
        application/javascript
        application/json
        application/ld+json
        application/manifest+json
        application/rss+xml
        application/vnd.geo+json
        application/vnd.ms-fontobject
        application/x-font-ttf
        application/x-web-app-manifest+json
        application/xhtml+xml
        application/xml
        font/opentype
        image/bmp
        image/svg+xml
        image/x-icon
        text/cache-manifest
        text/css
        text/plain
        text/vcard
        text/vnd.rim.location.xloc
        text/vtt
        text/x-component
        text/x-cross-domain-policy;

    # Include other configuration files
    include /etc/nginx/conf.d/*.conf;
}
```
This is a production-ready NGINX web server configuration that focuses on performance, security, and proper logging. Here are the key components: `nginx.conf`
##### Core Components
- **Worker Setup**: Automatically adjusts worker processes based on available CPU cores
- **Logging**: Configures error and access logging with detailed formatting
- **Connection Handling**: Sets up to handle 1024 concurrent connections per worker

##### Security Features
- **Server Information Protection**: Hides NGINX version information
- **Security Headers**: Implements multiple protective HTTP headers:
  - Protection against content-type sniffing
  - Frame protection (anti-clickjacking)
  - XSS protection
  - Content Security Policy implementation

- **Directory Protection**: Prevents directory listing

##### Performance Optimizations
- **Efficient File Delivery**: Enables sendfile for improved performance
- **Connection Management**: Sets 65-second keepalive timeout
- **Buffer Configuration**: Optimizes output buffer settings
- **Compression**: Implements comprehensive gzip compression for 25+ content types

##### Structure
- Includes external MIME type definitions
- Modular design that can include additional configuration files

This configuration provides a strong foundation for serving web content securely and efficiently, with particular attention to performance optimization and security hardening.


#### 3.2 Application-specific Nginx configuration
Create an application-specific Nginx configuration (`my-app.nginx.conf`):

```nginx
server {
  listen 8080;
  server_name localhost;

  add_header Access-Control-Allow-Origin <ORIGIN>; # replace <ORIGIN> with the real domain
  add_header X-Frame-Options deny;
  add_header Access-Control-Allow-Credentials false;

  # Generate unique nonce for each request
  set $cspNonce $request_id;

  # Define all external dependencies
  set $globSrc "https://fonts.googleapis.com";
  set $styleSrc "style-src 'self' 'nonce-$cspNonce' https://fonts.googleapis.com;";
  set $fontSrc "font-src 'self' fonts.googleapis.com;";
  set $imgSrc "img-src 'self' data: image/svg+xml;";
  set $cspSrc "default-src 'self' 'nonce-$cspNonce' $globSrc $styleSrc $fontSrc $imgSrc";

  # Security headers
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-Frame-Options "deny" always;
  add_header X-XSS-Protection "1; mode=block" always;
  add_header Content-Security-Policy $cspSrc;
  add_header X-Content-Security-Policy $cspSrc;
  add_header X-WebKit-CSP $cspSrc;
  add_header Access-control-Allow-Credentials false;

  location / {
    root /usr/share/nginx/html;
    index index.html;

    # Replace nonce placeholders with actual nonce value
    sub_filter '__CSP_NONCE__' '$cspNonce';
    sub_filter_once off;
    sub_filter_types text/html application/javascript;

    # Handle SPA routing
    try_files $uri $uri/ /index.html;
  }

  # Health check endpoint
  location /health {
    access_log off;
    add_header Content-Type text/plain;
    return 200 "OK";
  }
}
```
This NGINX configuration sets up a secure web server for a Single Page Application with a strong focus on security through Content Security Policy (CSP) implementation. `my-app.nginx.conf`

##### Key Features
- **Basic Server Setup**: Configures server to listen on port 8080 with localhost as the server name
- **Security Headers**: Implements comprehensive security headers to protect against common web vulnerabilities:
  - Content Security Policy with dynamic nonce generation
  - Protection against clickjacking (X-Frame-Options)
  - XSS protection
  - Content type sniffing protection

- **Dynamic CSP Nonce**: Generates a unique nonce for each request to allow secure inline scripts
- **Content Sources Control**: Defines specific allowed sources for different resource types (styles, fonts, images)
- **SPA Support**: Handles Single Page Application routing by redirecting to index.html
- **Runtime Substitution**: Replaces placeholder nonce values in HTML/JS files with actual nonce values
- **Health Check Endpoint**: Provides a simple health check endpoint for monitoring

This configuration helps secure web applications against various attacks like XSS, clickjacking, and other injection attacks while maintaining the functionality needed for modern web applications.


### 4. Docker Setup

Create a Dockerfile for your application:

```dockerfile
# my-app.Dockerfile
FROM custom-nginx:1.28.0
USER nginx
COPY --chown=nginx:nginx /path/to/build/directory/ /usr/share/nginx/html
COPY --chown=nginx:nginx my-app.nginx.conf /etc/nginx/conf.d/my-app.nginx.conf

EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
```

## Advanced Configurations

### MUI Integration

If you're using Material-UI (MUI), additional configuration is required for proper nonce support:

```javascript
// Import required packages
import createCache from "@emotion/cache";
import { CacheProvider } from "@emotion/react";
import { ThemeProvider } from "@mui/material/styles";

// Create emotion cache with nonce support
const cache = createCache({
  key: 'mui-styles', // Must be kebab-case
  nonce: window.__webpack_nonce__,
  prepend: true
});

// Wrap your app with the cache provider
const AppProvider = () => {
  return (
    <CacheProvider value={cache}>
      <ThemeProvider theme={myTheme}>
        {/* Your app components */}
      </ThemeProvider>    
    </CacheProvider>
  );
};
```

### Webpack Module Federation

For applications using Webpack Module Federation, additional configuration is needed:

1. Update your HTML template:

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <!-- Set nonce for webpack -->
    <script nonce="__CSP_NONCE__">
        window.__webpack_nonce__ = "__CSP_NONCE__"
    </script>
    <!-- HtmlWebpackPlugin will add script tags here -->
</head>
<body>
    <!-- Root element for the app -->
    <div id="__<%= appRootElName %>_root__"></div>

    <!-- Custom script tags for federated modules -->
    <% customHeadTags.forEach(function(tag) { %>
    <<%= tag.tagName %> <% getAttributes(tag) %> ><%= tag.content %></<%= tag.tagName %>>
    <% }) %>
</body>
</html>
```

2. Configure HtmlWebpackPlugin to handle federated modules:

```javascript
const moduleFederationPluginConfig = require('./federation.json');

new HtmlWebpackPlugin({
  template: path.resolve(__dirname, 'template.html'),
  templateParameters: {
    getAttributes: (tagConfigs) => {
      return Object.entries(tagConfigs.attrs).
          reduce((acc, [attrName, attrValue]) => {
            return acc.concat(`${attrName}="${attrValue}" `);
          }, '');
    },
    appRootElName: moduleFederationPluginConfig.name,
    customTags: [
      ...(moduleFederationPluginConfig?.remotes ?
        Object.entries(moduleFederationPluginConfig.remotes).map(([appName, remoteAppSrc]) => ({
          tagName: 'script',
          attrs: {
            defer: 'defer',
            src: remoteAppSrc.replace(`${appName}@`,''),
            nonce: '__CSP_NONCE__'
          }
        })) : []
      ),
      // Uncomment if you're using Notistack      
      // {
      //   tagName: 'style',
      //   attrs: {
      //     id: '_goober',
      //     nonce: '__CSP_NONCE__'
      //   },
      //   content: '.go12354 { height: 0;}'
      // }
    ]
  }
})
```

## Building and Testing

### Building the Docker Image

```bash
# Build the custom Nginx image
docker build -t secure-nginx:1.28.0 -f nginx.Dockerfile .
```

### Running the Container

```bash
# Run the container with default configuration
docker run -d --name secure-nginx -p 8080:80 secure-nginx:1.28.0

# Run with custom configuration and HTML files
docker run -d --name secure-nginx \
  -v $(pwd)/test/html:/usr/share/nginx/html \
  -v $(pwd)/test/conf:/etc/nginx/conf.d \
  -p 8080:80 \
  secure-nginx:1.28.0
```

### Testing the Setup

The project includes comprehensive test scripts to verify both basic substitution functionality and CSP nonce implementation:

#### Basic Substitution Test

```bash
# Run the basic substitution test
bash nginx_substitution_test_docker_setup.sh
```

This script automatically:
1. Builds the Docker image with the substitution module
2. Creates a test HTML file with `__TEST_TOKEN__` placeholders
3. Configures Nginx to replace those placeholders with "REPLACED_VALUE"
4. Verifies the substitution works correctly
5. Performs security checks:
   - Validates security headers are present
   - Tests protection against invalid HTTP methods
   - Verifies directory listing is disabled
   - Confirms server information is properly hidden
