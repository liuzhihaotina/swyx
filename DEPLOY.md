# 云服务器部署指南（2核4G 个人学习版）

本仓库已针对 **2核4GiB** 云服务器做了内存优化，个人学习、仅跑 RAG 可直接 `git clone` 使用。

> 说明：大模型（对话/embedding/rerank）都走阿里云 DashScope 云端 API，本地不做大模型推理。
> DeepDOC 的 OCR/版面 ONNX 模型**未随仓库提交**，首次上传文档解析时会自动从 `hf-mirror.com` 下载（约 450MB，走服务器带宽）。

---

## 一、前置准备（首次，务必先做）

### 1. 安装 Docker 和 docker compose
```bash
# Ubuntu 示例
curl -fsSL https://get.docker.com | sudo sh
sudo systemctl enable --now docker
```

### 2. 挂载 4G Swap（关键：防止解析 PDF 时内存溢出被杀）
```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h   # 确认 Swap 一行有 4G
```

---

## 二、拉取代码
```bash
git clone <你的仓库地址> swxy
cd swxy
```

---

## 三、启动后端
```bash
cd backend

# 1) 生成 .env（从示例复制），填入你的 DashScope Key
cp .env.example .env
vim .env        # 修改 DASHSCOPE_API_KEY=你的key

# 2) 构建并启动（首次 build 会装 opencv/onnxruntime，较慢，耐心等）
docker compose up -d --build

# 3) 查看日志，看到 uvicorn 启动即成功
docker logs -f swxy_api
```

各容器内存上限（已在 docker-compose.yml 配好）：
| 容器 | 上限 |
|------|------|
| Elasticsearch | 1.5G（JVM 堆 512m） |
| 后端 swxy_api | 2G |
| PostgreSQL | 512M |
| Redis | 256M |

---

## 四、启动前端
```bash
cd ../frontend

# 1) 生成 .env，把后端地址改成服务器公网IP
cp .env.example .env
vim .env        # VITE_API_BASE=http://你的服务器IP:8000

# 2) 用 Docker + Nginx 部署（比 npm run dev 省内存，推荐）
docker compose up -d --build
```

> 开发调试也可用 `npm install && npm run dev`，但服务器上建议用上面的 Docker 方式。

---

## 五、使用注意（避免卡顿/崩溃）
- **文档一个一个上传，不要批量**：DeepDOC OCR 很吃 CPU/内存，单个几十页 PDF 解析要几十秒~1分钟，期间机器会卡，属正常。
- 观察资源：`docker stats`（各容器占用）、`free -h`（swap 使用情况）。
- 若解析大 PDF 时后端被杀（`docker logs swxy_api` 出现 `Killed`），说明该文档太大，换小文档或减少页数。
- `backend/` 下自带示例文件可用于测试：`国电电力.pdf`、`润本股份.pdf`、`test_txt.txt`、`test_docx.docx`。

---

## 六、常见问题
- **首次解析很慢**：在等 hf-mirror 下载 ONNX 模型，下载一次后缓存，后续正常。
- **ES 起不来/退出**：多为内存不足，确认已挂 Swap；`docker logs gsk-es-01` 看具体报错。
- **端口**：后端 8000，前端 80（Nginx）。记得在云服务器安全组放行。
