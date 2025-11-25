# HuLa 後端 Dockerfile - 構建於 Rust
# 此 Dockerfile 構建 Tauri Rust 後端服務
# 
# 構建指令：
#   docker build -t hula-backend:latest -f src-tauri/Dockerfile .
#
# 運行指令：
#   docker run -d --name hula-backend -p 8080:8080 hula-backend:latest

# 多階段構建：第一階段用於編譯，第二階段用於運行時
ARG RUST_VERSION=1.75
ARG RUST_PROFILE=release

# ========== 第一階段：構建 ==========
FROM rust:${RUST_VERSION}-bullseye as builder

WORKDIR /build

# 安裝系統依賴
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    libgdk-3-0 \
    libgtk-3-dev \
    libwebkit2gtk-4.1-dev \
    librsvg2-dev \
    libayatana-appindicator3-dev \
    libasound2-dev \
    && rm -rf /var/lib/apt/lists/*

# 複製 Rust 項目
COPY src-tauri ./

# 構建後端
# 根據 RUST_PROFILE 選擇構建配置（release 或 debug）
RUN if [ "${RUST_PROFILE}" = "release" ]; then \
        cargo build --release; \
    else \
        cargo build; \
    fi

# ========== 第二階段：運行時 ==========
FROM debian:bullseye-slim

WORKDIR /app

# 安裝運行時依賴
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl1.1 \
    libgdk-3-0 \
    libgtk-3-0 \
    libwebkit2gtk-4.1-0 \
    librsvg2-2 \
    libayatana-appindicator3-1 \
    libasound2 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 從構建階段複製編譯好的二進制文件
# 根據 RUST_PROFILE 複製對應的二進制文件
ARG RUST_PROFILE=release
COPY --from=builder /build/target/${RUST_PROFILE}/hula-backend /app/hula-backend

# 複製配置文件（如果有）
COPY src-tauri/config/ /app/config/ || true

# 複製資源文件（如果有）
COPY src-tauri/resources/ /app/resources/ || true

# 創建日誌目錄
RUN mkdir -p /app/logs /app/data

# 設置環境變量
ENV RUST_LOG=info
ENV SERVICE_HOST=0.0.0.0
ENV SERVICE_PORT=8080

# 暴露端口
EXPOSE 8080 9090

# 健康檢查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# 運行應用
ENTRYPOINT ["/app/hula-backend"]
CMD ["--host", "0.0.0.0", "--port", "8080"]
