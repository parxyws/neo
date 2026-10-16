# Managed by neo — reverse proxy to an app on this server
# (Node, Bun, Go, Python, FrankenPHP, Docker container ... listening on {{UPSTREAM}})
server {
    listen 80;
    listen [::]:80;
    server_name {{SERVER_NAMES}};

    access_log /var/log/nginx/{{DOMAIN}}.access.log;
    error_log  /var/log/nginx/{{DOMAIN}}.error.log;

    include snippets/neo/security-headers.conf;

    location / {
        proxy_pass http://{{UPSTREAM}};
        include snippets/neo/proxy-params.conf;
    }
}
