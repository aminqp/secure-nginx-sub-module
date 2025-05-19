# my-app.Dockerfile
FROM custom-nginx:1.28.0
USER nginx
COPY --chown=nginx:nginx /path/to/build/directory/ /usr/share/nginx/html
COPY --chown=nginx:nginx my-app.nginx.conf /etc/nginx/conf.d/my-app.nginx.conf

EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
