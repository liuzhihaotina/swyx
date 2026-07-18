# 云服务器部署指南（2核4G 个人学习版）

本仓库已针对 **2核4GiB** 云服务器做了内存优化，个人学习、仅跑 RAG 可直接 `git clone` 使用。

> 说明：语义类模型（对话/embedding/rerank）走云端 API，本地不做大模型推理。
> DeepDOC 的 OCR/版面 ONNX 模型**未随仓库提交**，首次上传文档解析时会自动从 `hf-mirror.com` 下载（约 450MB，走服务器带宽）。

---

## 〇、模型服务架构（本地 ONNX + 云端 API）

系统的 AI 能力分两层，理解这个有助于你配置 Key 和排错：

### 本地 ONNX 模型 —— “眼睛”，免费/离线
负责**把文档读成文字**：OCR 文字检测识别、版面分析、表格结构识别。
- 位置：`backend/app/service/core/rag/res/deepdoc/`（首次解析自动下载）
- 特点：跑在 CPU、免费、不联网；只在**上传文档建库时**工作（这也是解析 PDF 吃 CPU/内存的原因）

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

# 对话 LLM：任意 OpenAI 兼容服务（示例 apidock），不填则回退用 DASHSCOPE_*
LLM_API_KEY=你的对话服务key
LLM_BASE_URL=https://apidock.ai/v1
LLM_MODEL=deepseek-r1

# 向量 Embedding：默认回退用 DASHSCOPE_*；如需换服务再取消注释
# EMBEDDING_API_KEY=
# EMBEDDING_BASE_URL=
# EMBEDDING_MODEL=text-embedding-v3
```

**换服务商注意：**
- **对话 LLM**：改 `LLM_*` 三行即可，无需动代码。
- **Embedding**：⚠️ 换了会改变向量维度，**必须删掉 ES 索引重建知识库**，否则检索失效。
- **Rerank**：`gte-rerank` 是阿里专有接口，OpenAI 无对应标准；彻底弃用阿里云需改写 `rag/nlp/model.py` 的 `rerank_similarity()`（换 Jina/Cohere/BGE 或跳过）。

> 结论：个人学习最省心的组合是 **对话=第三方（如 apidock），embedding/rerank=阿里云**——改动最小、无需重建知识库。

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

# 1) 生成 .env（从示例复制），填入 Key
cp .env.example .env
vim .env        # DASHSCOPE_API_KEY=阿里云key(embedding/rerank用)
                # LLM_API_KEY=对话服务key(如 apidock)
                # 详见上面「〇、模型服务架构」章节


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

## 六、离线服务器部署（无法联网的机器）

如果目标服务器**不能联网**，DeepDOC 模型无法从 hf-mirror 自动下载，需要先在一台
**有模型的联网机器**上打包，再拷到离线机还原。

### 需要打包的本地资源（都在 backend/ 下）
| 资源 | 路径 | 作用 |
|------|------|------|
| DeepDOC 模型 | `app/service/core/rag/res/deepdoc/`（det/rec/layout*/tsr.onnx + updown_concat_xgb.model） | OCR/版面/表格识别 |
| 中文分词词典 | `app/service/core/rag/res/huqie.txt.trie`、`huqie.txt` | 中文分词 |
| nltk 资源 | `nltk_data/` | 英文词形还原/分词 |

> 这些默认被 .gitignore 排除，所以离线机只 `git clone` 是**拿不到**的，必须用下面的包补上。

### 步骤 1：在联网机器上打包
```bash
# Windows（你的开发机）
powershell -ExecutionPolicy Bypass -File scripts/pack-offline-assets.ps1
#   → 生成 offline-assets.zip

# 或 Linux 联网机
bash scripts/pack-offline-assets.sh
#   → 生成 offline-assets.tar.gz
```

### 步骤 2：拷贝到离线服务器
把 `offline-assets.zip`（或 `.tar.gz`）用 U 盘/内网 scp 拷到离线服务器的**项目根目录**。

### 步骤 3：在离线服务器还原
```bash
cd swxy
bash scripts/restore-offline-assets.sh   # 自动解压到正确位置并校验
```

### 关于其他离线依赖
- **Docker 镜像**：离线机也拉不到 `python:3.11.7-slim`、ES/PG/Redis 等基础镜像。
  需在联网机 `docker pull` 后用 `docker save -o images.tar <镜像...>`，拷到离线机 `docker load -i images.tar`。
- **Python 依赖**：Dockerfile 里 pip 装的包也需联网。离线可在联网机构建好整个后端镜像后
  `docker save` 打包，离线机 `docker load` 直接用（推荐，一步到位）。
- **云端 API**：对话/embedding/rerank 仍需访问 apidock / 阿里云。**完全离线的内网如果连这些也访问不了，
  RAG 的问答与向量化将无法工作**——此时需改用可内网访问的模型服务（超出本项目默认范围）。

---

## 七、常见问题

- **首次解析很慢**：在等 hf-mirror 下载 ONNX 模型，下载一次后缓存，后续正常。
- **ES 起不来/退出**：多为内存不足，确认已挂 Swap；`docker logs gsk-es-01` 看具体报错。
- **端口**：后端 8000，前端 80（Nginx）。记得在云服务器安全组放行。
