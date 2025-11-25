# HuLa 後端 Docker Compose 部署指南

## 概述

此配置用於在 Docker 環境中部署 HuLa Rust 後端服務，與現有的 MySQL 5.7、Redis 和 Nginx 集成。

## 前置條件

- Docker & Docker Compose
- MySQL 5.7 已運行（或通過 docker-compose 啟動）
- Redis 已運行（或通過 docker-compose 啟動）
- Nginx 已配置（或通過 docker-compose 啟動）

## 快速開始

### 1. 準備環境

複製 `.env.example` 為 `.env`，並修改配置：

```bash
cp .env.example .env
```

編輯 `.env` 文件中的環境變量：

```
DATABASE_URL=mysql://hula_user:hula_password@mysql:3306/hula_db
REDIS_URL=redis://:@redis:6379/0
SERVICE_URL=http://localhost:8080
JWT_SECRET=your-secret-key-here
```

### 2. 啟動服務

```bash
# 啟動所有服務
docker-compose -f docker-compose.backend.yml up -d

# 查看服務日誌
docker-compose -f docker-compose.backend.yml logs -f hula-backend

# 查看所有服務狀態
docker-compose -f docker-compose.backend.yml ps
```

### 3. 驗證部署

```bash
# 檢查後端健康狀態
curl http://localhost:8080/health

# 檢查 MySQL 連接
curl http://localhost:8080/api/health/db

# 檢查 Redis 連接
curl http://localhost:8080/api/health/cache
```

### 4. 停止服務

```bash
# 停止所有服務
docker-compose -f docker-compose.backend.yml down

# 停止並刪除卷（謹慎！會刪除數據）
docker-compose -f docker-compose.backend.yml down -v
```

## 配置說明

### docker-compose.backend.yml

#### hula-backend 服務

主要後端服務配置：

- **構建**：基於 `src-tauri/Dockerfile` 構建
- **端口**：
  - `8080`：REST API & WebSocket
  - `9090`：管理/健康檢查端口
- **環境變量**：
  - `DATABASE_URL`：MySQL 連接字符串
  - `REDIS_URL`：Redis 連接字符串
  - `SERVICE_URL`：外部訪問地址
  - `WS_URL`：WebSocket 地址

#### MySQL 服務

- **版本**：MySQL 5.7
- **默認憑證**：
  - 用戶：`hula_user`
  - 密碼：`hula_password`
  - 數據庫：`hula_db`
  - 根密碼：`root_password`
- **數據持久化**：`mysql-data` 卷

#### Redis 服務

- **版本**：Redis 7 Alpine
- **命令**：開啟 AOF 持久化
- **數據持久化**：`redis-data` 卷

#### Nginx 服務

- **用途**：反向代理與負載均衡
- **配置**：`nginx.conf`
- **日誌**：`nginx-logs` 目錄

## 環境變量

### .env 範本

```env
# 數據庫配置
DATABASE_URL=mysql://hula_user:hula_password@mysql:3306/hula_db

# Redis 配置
REDIS_URL=redis://:@redis:6379/0

# 服務配置
SERVICE_HOST=0.0.0.0
SERVICE_PORT=8080
SERVICE_URL=http://localhost:8080

# WebSocket 配置
WS_URL=ws://localhost:8080/ws

# 日誌配置
LOG_LEVEL=INFO
RUST_LOG=info

# 安全配置
JWT_SECRET=change-me-to-strong-secret
CORS_ORIGINS=http://localhost:5173,http://localhost:3000

# 性能配置
WORKERS=4
TIMEOUT=30
```

## 常見問題

### 問題 1：MySQL 連接失敗

**症狀**：
```
Error connecting to database: Connection refused
```

**解決**：

1. 檢查 MySQL 容器是否運行：
```bash
docker-compose -f docker-compose.backend.yml ps mysql
```

2. 檢查 MySQL 日誌：
```bash
docker-compose -f docker-compose.backend.yml logs mysql
```

3. 驗證連接字符串格式（如果使用外部 MySQL）：
```
DATABASE_URL=mysql://user:password@host:port/database
```

### 問題 2：WebSocket 連接超時

**症狀**：
```
WebSocket connection timeout
```

**解決**：

1. 檢查 Nginx 配置中的 WebSocket 超時設置
2. 確保防火牆允許 WebSocket 連接
3. 查看代理超時配置：
```bash
docker-compose -f docker-compose.backend.yml exec nginx cat /etc/nginx/nginx.conf | grep proxy_read_timeout
```

### 問題 3：磁盤空間不足

**症狀**：
```
Error writing to container: no space left on device
```

**解決**：

1. 清理 Docker 資源：
```bash
docker system prune -a
```

2. 檢查磁盤使用情況：
```bash
df -h
```

3. 考慮移動卷到其他磁盤

### 問題 4：容器無法訪問外部服務

**症狀**：
```
Connection refused to external service
```

**解決**：

使用 `host.docker.internal` 而不是 `localhost`：

```env
# 對於本地外部服務
DATABASE_URL=mysql://hula_user:hula_password@host.docker.internal:3306/hula_db
REDIS_URL=redis://:@host.docker.internal:6379/0
```

## 生產環境建議

### 1. SSL/TLS 證書

使用 Let's Encrypt 的 certbot 自動化 SSL：

```bash
docker run --rm -it \
  -v /etc/letsencrypt:/etc/letsencrypt \
  -v /var/lib/letsencrypt:/var/lib/letsencrypt \
  -p 80:80 \
  certbot/certbot certify -d your-domain.com
```

### 2. 資源限制

在 docker-compose 中設置 CPU 和內存限制：

```yaml
deploy:
  resources:
    limits:
      cpus: '2'
      memory: 2G
```

### 3. 日誌管理

配置日誌輪轉：

```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```

### 4. 備份策略

定期備份數據：

```bash
# 備份 MySQL
docker-compose -f docker-compose.backend.yml exec mysql \
  mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" --all-databases > backup.sql

# 備份 Redis
docker-compose -f docker-compose.backend.yml exec redis \
  redis-cli BGSAVE
```

### 5. 監控與告警

考慮集成：
- Prometheus for 指標收集
- Grafana for 可視化
- ELK Stack for 日誌分析

## 高級配置

### 負載均衡

在 `docker-compose.backend.yml` 中添加多個後端實例：

```yaml
upstream hula_backend {
    server hula-backend-1:8080;
    server hula-backend-2:8080;
    server hula-backend-3:8080;
}
```

### 數據庫複製

配置 MySQL 主從複製以實現高可用性。

### Redis 集群

使用 Redis Sentinel 或 Redis Cluster 以實現高可用性。

## 故障排查

### 查看完整日誌

```bash
docker-compose -f docker-compose.backend.yml logs --tail=100 -f hula-backend
```

### 進入容器進行調試

```bash
docker-compose -f docker-compose.backend.yml exec hula-backend /bin/bash
```

### 檢查網絡連接

```bash
docker-compose -f docker-compose.backend.yml exec hula-backend \
  curl http://mysql:3306 --verbose
```

## 相關文件

- `docker-compose.backend.yml` - Docker Compose 配置
- `src-tauri/Dockerfile` - 後端容器鏡像構建配置
- `nginx.conf` - Nginx 反向代理配置
- `.env` - 環境變量配置

## 更新與維護

### 更新後端代碼

```bash
# 重新構建鏡像
docker-compose -f docker-compose.backend.yml build --no-cache hula-backend

# 重新啟動服務
docker-compose -f docker-compose.backend.yml up -d
```

### 數據庫遷移

```bash
# 進入容器並執行遷移
docker-compose -f docker-compose.backend.yml exec hula-backend \
  ./hula-backend migrate
```

## 支持

如有問題，請查看：
- 項目文檔：`/workspaces/nf_chat/docs/`
- 部署指南：`/workspaces/nf_chat/scripts/deploy_prod.sh`
