# Onyx front door for Railway: routes /api, /openapi.json, /auth/saml and /scim to
# the API server and everything else to the Next.js web server (as upstream nginx).
FROM nginx:1.30.5

# Export the container's DNS resolver as $NGINX_LOCAL_RESOLVERS so upstream hosts
# (*.railway.internal) are resolved at request time; nginx then starts even when
# the API or web server is not up yet.
ENV NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1 \
    PORT=80 \
    NGINX_PROXY_CONNECT_TIMEOUT=300 \
    NGINX_PROXY_SEND_TIMEOUT=300 \
    NGINX_PROXY_READ_TIMEOUT=300

# The official image renders /etc/nginx/templates/*.template with envsubst at start.
COPY templates/default.conf.template /etc/nginx/templates/default.conf.template
