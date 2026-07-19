# 云服务器部署指南（16核 64G 高配版）

本仓库部署在 **16核 / 64GiB 内存 / 系统盘50GB + 数据盘200GB** 的云服务器上。
相比早期 2核4G 版本，本文按高配重新调优了各容器的内存与并发，并把 **Docker 数据迁到 200GB 数据盘**，避免撑爆 50GB 系统盘。

> 说明：语义类模型（对话/embedding/rerank）走云端 API，本地不做大模型推理。
> DeepDOC 的 OCR/版面 ONNX 模型**未随仓库提交**，首次上传文档解析时会自动从 `hf-mirror.com` 下载（约 450MB，走服务器带宽）。

---

## 〇、模型服务架构（本地 ONNX + 云端 API）

系统的 AI 能力分两层，理解这个有助于你配置 Key 和排错：

### 本地 ONNX 模型 —— “眼睛”，免费/离线
负责**把文档读成文字**：OCR 文字检测识别、版面分析、表格结构识别。
- 位置：`backend/app/service/core/rag/res/deepdoc/`（首次解析自动下载）
- 特点：跑在 CPU、免费、不联网；只在**上传文档建库时**工作。16核可并行解析多个文档。

### 云端 API —— “大脑”，收费/联网
| 能力 | 模型 | 服务 | 说明 |
|------|------|------|------|
| 对话生成 | `LLM_MODEL` | 任意 OpenAI 兼容服务 | 可自由替换（见下） |
| 向量 Embedding | `text-embedding-v3` | 阿里云 DashScope | 建库+提问都用，维度 1024 |
| 重排 Rerank | `gte-rerank` | 阿里云 DashScope（专有） | **只能用阿里云**，换别家需改代码 |

### 推荐配置：对话用第三方，检索用阿里云
代码已支持三类服务**独立配置**（`.env` 里）：

```bash
# 阿里云 DashScope：embedding + rerank 用（必填）
DASHSCOPE_API_KEY=你的阿里云key
DASHSCOPE_BASE_URL="https://dashscope.aliyuncs.com/compatible-mode/v1"

# 对话 LLM：任意 OpenAI 兼容服务，不填则回退用 DASHSCOPE_*
LLM_API_KEY=你的对话服务key
LLM_BASE_URL=https://api.deepseek.com/v1
LLM_MODEL=deepseek-v4-pro

# 向量 Embedding：默认回退用 DASHSCOPE_*；如需换服务再取消注释
# EMBEDDING_API_KEY=
# EMBEDDING_BASE_URL=
# EMBEDDING_MODEL=text-embedding-v3
```

**换服务商注意：**
- **对话 LLM**：改 `LLM_*` 三行即可，无需动代码。
- **Embedding**：⚠️ 换了会改变向量维度，**必须删掉 ES 索引重建知识库**，否则检索失效。
- **Rerank**：`gte-rerank` 是阿里专有接口；彻底弃用阿里云需改写 `rag/nlp/model.py` 的 `rerank_similarity()`。

---

## 一、本机资源规划（16C64G）

各容器资源上限已在 `docker-compose.yml` / `.env` 中按高配配好：

| 容器 | 内存上限 | JVM/并发 | 说明 |
|------|---------|----------|------|
| Elasticsearch | 8G（`MEM_LIMIT`） | JVM 堆 4g（`ES_JAVA_OPTS`） | 堆 4g，余量留给 Lucene 文件缓存 |
| 后端 swxy_api | 16G | uvicorn **4 workers** | 多核并行处理 OCR 解析/对话 |
| PostgreSQL | 2G | — | 会话/消息记录 |
| Redis | 1.5G | maxmemory 1g，LRU | 缓存 |
| **合计** | **~27.5G** | | 64G 内存留足余量，无需依赖 swap |

> 相比 2C4G 版：ES 堆 512m→4g、后端 2g→16g（4 workers）、PG 512m→2g、Redis 256m→1.5g。
> 64GB 内存下 **swap 不再是必需**（本地不跑大模型推理），系统自带的 ~2G swap 保留即可，无需再挂 4G。

---

## 二、前置准备（首次，务必先做）

### 1. 安装 Docker 和 docker compose
```bash
curl -fsSL https://get.docker.com | sudo sh
sudo systemctl enable --now docker
```

### 2. ⭐ 把 Docker 数据迁到 200GB 数据盘（关键，避免撑爆 50GB 系统盘）

Docker 默认把镜像、容器、数据卷（含 ES 索引）都放在 `/var/lib/docker`，位于 **50GB 系统盘**。
知识库文档多了 ES 索引会持续增长，必须迁到 **200GB 数据盘 `/data`**：

```bash
# 1) 停止 docker
sudo systemctl stop docker docker.socket

# 2) 迁移已有数据到数据盘（保留权限）
sudo mkdir -p /data/docker
sudo rsync -aP /var/lib/docker/ /data/docker/

# 3) 配置 data-root（合并进已有的 daemon.json，保留 registry-mirrors）
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "data-root": "/data/docker",
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://docker.m.daocloud.io"
  ]
}
EOF

# 4) 重启并确认 Docker Root Dir 指向 /data/docker
sudo systemctl start docker
docker info | grep "Docker Root Dir"     # 应显示 /data/docker

# 5) 确认无误后，删除旧数据释放系统盘空间
sudo rm -rf /var/lib/docker.bak 2>/dev/null; sudo mv /var/lib/docker /var/lib/docker.bak
#   验证容器/镜像都在后再：sudo rm -rf /var/lib/docker.bak
```

> 项目代码本身也建议放在数据盘（本仓库已在 `/data/projects/swxy`）。

---

## 三、启动后端
```bash
cd backend

# 1) 生成 .env（从示例复制），填入 Key
cp .env.example .env
vim .env        # DASHSCOPE_API_KEY=阿里云key(embedding/rerank用)
                # LLM_API_KEY=对话服务key
                # 详见「〇、模型服务架构」章节
                # MEM_LIMIT=8589934592 已按 16C64G 配好，一般无需改

# 2) 构建并启动（首次 build 会装 opencv/onnxruntime，16核较快）
docker compose up -d --build

# 3) 查看日志，看到 uvicorn 启动即成功
docker logs -f swxy_api
```

---

## 四、启动前端
```bash
cd ../frontend

# 1) 生成 .env，把后端地址改成服务器公网IP
cp .env.example .env
vim .env        # VITE_API_BASE=http://1.13.176.5:8000（本机公网IP）
                # ⚠️ 该地址会在 build 时编译进静态文件，用户浏览器直连后端，
                #    必须填公网IP/域名，不能是 localhost；改IP/域名后需重新 build。

# 2) 用 Docker + Nginx 生产部署（80 端口）
docker compose --profile prod up -d --build
```

> 开发调试也可用 `npm install && npm run dev`（端口 5181）；服务器上对外服务用上面的 prod（Nginx，端口 80）。

### 验证部署
```bash
docker ps                                 # swxy_frontend_prod 应 Up，端口 0.0.0.0:80->80
curl -s -o /dev/null -w "%{http_code}\n" http://localhost/   # 应 200
curl http://localhost/health              # 应 healthy
```
外网访问 `http://1.13.176.5/`（前端）、`http://1.13.176.5:8000/docs`（后端 API）。
若外网打不开但本机 curl 正常，多半是**云安全组**未放行 80/8000（主机 ufw/iptables 本项目默认全放行）。

---

## 五、使用与运维

- **文档可并行上传**：16核 64G 下 DeepDOC OCR 可同时解析多个文档（后端 4 workers）。
  单个几十页 PDF 解析仍需几十秒，属正常；超大 PDF（数百页）建议仍逐个上传观察。
- 观察资源：`docker stats`（各容器占用）、`free -h`、`df -h`（尤其 `/data` 数据盘）。
- `backend/` 下自带示例文件可测试：`国电电力.pdf`、`润本股份.pdf`、`test_txt.txt`、`test_docx.docx`。
- **端口放行**：云安全组放行后端 `8000`、前端 `80`。

---

## 六、离线服务器部署（无法联网的机器）

如目标服务器**不能联网**，DeepDOC 模型无法从 hf-mirror 自动下载，需要先在一台
**有模型的联网机器**上打包，再拷到离线机还原。

### 需要打包的本地资源（都在 backend/ 下）
| 资源 | 路径 | 作用 |
|------|------|------|
| DeepDOC 模型 | `app/service/core/rag/res/deepdoc/` | OCR/版面/表格识别 |
| 中文分词词典 | `app/service/core/rag/res/huqie.txt.trie`、`huqie.txt` | 中文分词 |
| nltk 资源 | `nltk_data/` | 英文词形还原/分词 |

> 这些默认被 .gitignore 排除，离线机只 `git clone` 拿不到，必须用下面的包补上。

### 步骤
```bash
# 1) 联网机打包
bash scripts/pack-offline-assets.sh          # Linux → offline-assets.tar.gz
# 或 Windows：powershell -File scripts/pack-offline-assets.ps1 → offline-assets.zip

# 2) 拷到离线服务器项目根目录

# 3) 离线机还原
cd swxy && bash scripts/restore-offline-assets.sh
```

- **Docker 镜像**：联网机 `docker save -o images.tar <镜像...>`，离线机 `docker load -i images.tar`。
  推荐直接把整个后端镜像 build 好后 `docker save` 打包，一步到位。
- **云端 API**：对话/embedding/rerank 仍需访问阿里云/第三方；完全内网需换可内网访问的模型服务。

---

## 七、常见问题

- **首次解析很慢**：在等 hf-mirror 下载 ONNX 模型，缓存后续正常。
- **系统盘 `/` 变满**：确认第二章第 2 步 Docker data-root 已迁到 `/data/docker`（`docker info | grep Root`）。
- **ES 起不来/退出**：`docker logs gsk-es-01` 看报错；确认 `MEM_LIMIT=8589934592` 且 `ES_JAVA_OPTS=-Xms4g -Xmx4g`。
- **端口**：后端 8000，前端 80（Nginx）。记得在云服务器安全组放行。
