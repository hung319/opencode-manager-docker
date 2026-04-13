# ==========================================
# 1. BASE STAGE: Cài đặt cơ bản & Pnpm
# ==========================================
FROM node:24.13.0-slim AS base
RUN corepack enable && corepack prepare pnpm@latest --activate
WORKDIR /app

# ==========================================
# 2. DEPENDENCIES STAGE: Cài đặt toàn bộ gói (gồm cả DevDeps để build)
# ==========================================
FROM base AS deps
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY shared/package.json ./shared/
COPY backend/package.json ./backend/
COPY frontend/package.json ./frontend/
RUN pnpm install --frozen-lockfile

# ==========================================
# 3. BUILDER STAGE: Build code (Frontend/Shared)
# ==========================================
FROM deps AS builder
COPY . .
RUN pnpm --filter frontend build

# ==========================================
# 4. PROD-DEPS STAGE: Cài đặt gói Production (Tối ưu dung lượng)
# ==========================================
FROM base AS prod-deps
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY shared/package.json ./shared/
COPY backend/package.json ./backend/
COPY frontend/package.json ./frontend/
# Lệnh --prod giúp loại bỏ hàng trăm MB của devDependencies
RUN pnpm install --frozen-lockfile --prod

# ==========================================
# 5. DOWNLOADER STAGE: Tải tools độc lập để tránh file rác
# ==========================================
FROM debian:bookworm-slim AS downloader
ARG OPENCODE_VERSION=latest
RUN apt-get update && apt-get install -y curl ca-certificates bash

# Tải UV & gom file
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh \
    && mkdir -p /out/usr/local/bin \
    && mv /root/.local/bin/uv /out/usr/local/bin/uv \
    && mv /root/.local/bin/uvx /out/usr/local/bin/uvx

# Tải Opencode & gom file
RUN curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path $( [ "${OPENCODE_VERSION}" != "latest" ] && echo "--version ${OPENCODE_VERSION}" ) \
    && mv /root/.opencode /out/opt-opencode

# ==========================================
# 6. RUNNER STAGE: Môi trường chạy cuối cùng
# ==========================================
FROM node:24.13.0-slim AS runner
WORKDIR /app
ENV NODE_ENV=production HOST=0.0.0.0 PORT=5003

# Gộp chung việc cài các công cụ hệ thống và dọn dẹp vào 1 layer duy nhất
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl lsof ripgrep ca-certificates grep gawk sed findutils bash \
    coreutils procps jq less tree file python3 python3-pip python3-venv \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && curl -fsSL https://bun.sh/install | bash \
    && ln -s /root/.bun/bin/bun /usr/local/bin/bun \
    && rm -rf /root/.bun/install

# Chỉ Copy những thứ thật sự cần thiết từ các Stage trước
COPY --from=downloader /out/usr/local/bin/ /usr/local/bin/
COPY --from=downloader /out/opt-opencode /opt/opencode
RUN chmod +x /usr/local/bin/uv /usr/local/bin/uvx \
    && chmod -R 755 /opt/opencode \
    && ln -s /opt/opencode/bin/opencode /usr/local/bin/opencode

# Copy bộ node_modules siêu nhẹ (chỉ có dependencies)
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=builder /app/shared ./shared
COPY --from=builder /app/backend ./backend
COPY --from=builder /app/frontend/dist ./frontend/dist
COPY package.json pnpm-workspace.yaml ./
COPY scripts/docker-entrypoint.sh /docker-entrypoint.sh

# Cấu hình workspace và quyền thực thi
RUN chmod +x /docker-entrypoint.sh \
    && mkdir -p /app/backend/node_modules/@opencode-manager \
    && ln -s /app/shared /app/backend/node_modules/@opencode-manager/shared \
    && mkdir -p /root/workspace /root/data

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["bun", "backend/src/index.ts"]
