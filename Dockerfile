# Sử dụng node slim làm base để nhẹ và bảo mật
FROM node:24.13.0-slim AS base

# Cài đặt công cụ hệ thống (Dùng lệnh chung cho cả 2 kiến trúc)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl lsof ripgrep ca-certificates grep gawk sed findutils \
    coreutils procps jq less tree file python3 python3-pip python3-venv \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Cài đặt pnpm và Bun
RUN corepack enable && corepack prepare pnpm@latest --activate \
    && curl -fsSL https://bun.sh/install | bash \
    && ln -s /root/.bun/bin/bun /usr/local/bin/bun

WORKDIR /app

# Stage cài đặt phụ thuộc
FROM base AS deps
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY shared/package.json ./shared/
COPY backend/package.json ./backend/
COPY frontend/package.json ./frontend/
RUN pnpm install --frozen-lockfile

# Stage build code
FROM base AS builder
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN pnpm --filter frontend build

# Stage chạy cuối cùng
FROM base AS runner
ARG OPENCODE_VERSION=latest

RUN curl -LsSf https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh \
    && mv /root/.local/bin/uv /usr/local/bin/uv \
    && mv /root/.local/bin/uvx /usr/local/bin/uvx \
    && chmod +x /usr/local/bin/uv /usr/local/bin/uvx \
    && curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path $( [ "${OPENCODE_VERSION}" != "latest" ] && echo "--version ${OPENCODE_VERSION}" ) \
    && mv /root/.opencode /opt/opencode \
    && chmod -R 755 /opt/opencode \
    && ln -s /opt/opencode/bin/opencode /usr/local/bin/opencode

ENV NODE_ENV=production HOST=0.0.0.0 PORT=5003
COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/shared ./shared
COPY --from=builder /app/backend ./backend
COPY --from=builder /app/frontend/dist ./frontend/dist
COPY package.json pnpm-workspace.yaml ./
COPY scripts/docker-entrypoint.sh /docker-entrypoint.sh

# Cập nhật: Tạo thư mục workspace và data trong /root, bỏ phân quyền user node
RUN chmod +x /docker-entrypoint.sh \
    && mkdir -p /app/backend/node_modules/@opencode-manager \
    && ln -s /app/shared /app/backend/node_modules/@opencode-manager/shared \
    && mkdir -p /root/workspace /root/data

# Mặc định container chạy dưới quyền root (Không cần khai báo USER)
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["bun", "backend/src/index.ts"]
