FROM ghcr.io/chriswritescode-dev/opencode-manager:latest

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    psmisc unzip ca-certificates tini lsof curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=7860 \
    OPENCODE_SERVER_PORT=5551 \
    HOME=/root \
    AUTH_SECRET="super-secret-key-change-me" \
    AUTH_TRUSTED_ORIGINS="http://localhost:7860" \
    AUTH_SECURE_COOKIES=true \
    DATABASE_PATH=/root/data/opencode.db \
    WORKSPACE_PATH=/root \
    XDG_CACHE_HOME=/root/.cache

ENV PATH="/opt/bun/bin:/root/.opencode/bin:/usr/local/bin:$PATH"

RUN mkdir -p /root/data /root/.cache /root/.opencode && chmod -R 777 /root /app

RUN cat <<'EOF' > /usr/local/bin/custom-entrypoint.sh && chmod +x /usr/local/bin/custom-entrypoint.sh
#!/bin/bash
set +e

export HOME=/root
if ! command -v opencode >/dev/null 2>&1; then
    curl -fsSL "https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/').tar.gz" -o /tmp/opencode.tar.gz
    tar -xzf /tmp/opencode.tar.gz -C /tmp
    mkdir -p "/root/.opencode/bin"
    mv /tmp/opencode "/root/.opencode/bin/opencode"
    chmod 755 "/root/.opencode/bin/opencode"
    rm -f /tmp/opencode.tar.gz
fi

exec bun backend/src/index.ts
EOF

RUN chmod +x /usr/local/bin/custom-entrypoint.sh

EXPOSE 7860

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/custom-entrypoint.sh"]
