# AGENTS.md

本文件为在本仓库工作的 AI 会话（agent）提供协作约定。

## Git 提交 / 推送：强制委派

**任何 `git commit`、`git push` 及相关的暂存操作，一律委派给 `git-committer` 子代理执行，
主会话不得自行运行 git 提交类命令。**

- 定义位置：`.opencode/agent/git-committer.md`（随仓库分发）。
- 目的：① 统一提交规范（Conventional Commits，英文 type + 中文描述、分类提交、敏感文件校验）；
  ② 把冗长的 `git status/diff/log` 与核对过程隔离在子代理的独立上下文，**不污染主会话上下文**。
- 主会话允许的 git 操作仅限**只读查看**（如 `git status`、`git diff` 供自己了解改动），
  一旦要落库，改为委派。

### 如何委派（省上游上下文的推荐做法）

为避免交接摘要占用主会话上下文，采用**文件交接**协议：

1. 产出改动的会话把「提交总结 / 交接说明」写入 `.opencode/commit-handoff.md`
   （该路径已被 gitignore，属一次性交接件，不入库）。
2. 派发子代理时只需一句：
   > 用 git-committer 子代理提交并推送，交接见 `.opencode/commit-handoff.md`。
3. 子代理读取该文件、核对 diff、分类提交并推送，**成功后删除该文件**，
   最终只向主会话回一条精简汇报（提交哈希 + 推送引用更新）。

若改动很小、不介意摘要进上下文，也可直接在派发消息里给出提交总结；
甚至不给总结，让子代理直接依据 `git diff` 自行归纳分类。

## 运维须知：改凭证 / agent 配置后需重启 serve

**opencode serve 是常驻进程，仅在启动时加载一次凭证与 agent 配置，之后不重读。**
因此下列改动**不会对正在运行的会话立即生效**，必须让 serve 重新加载：

- provider 凭证：`~/.local/share/opencode/auth.json`（如 `opencode auth login` 或手动写入）
- provider 配置：项目根 `opencode.json`（baseURL、模型列表等）
- 子代理定义：`.opencode/agent/*.md`（尤其 frontmatter 的 `model:`）

典型症状：改了以上内容后，子代理调用**返回空**或报 `AI_APICallError: Authorization Required`，
且 opencode 日志里 `llm.model` 显示的仍是**旧模型**——即证明 serve 用的是启动时的缓存。

让 serve 重新加载的方式（任选其一）：

1. **IDE / GUI 扩展**：彻底关闭并重连窗口（VS Code Remote 下扩展宿主会重拉 serve）；
   或找到 serve 进程 `kill` 掉，扩展会自动拉起新进程：
   ```bash
   ps -C opencode -o pid,lstart,cmd        # 找到 `opencode serve ...` 的 pid
   kill <pid>                              # 扩展会自动重启 serve, 新进程加载最新配置
   ```
2. **终端 TUI**：退出 opencode 后重开。

> 验证凭证/模型本身是否正确（绕开常驻 serve 的缓存），可用一次性新进程：
> `opencode run --model deepseek/deepseek-v4-pro "只回复两个字：正常"`。
> 若这条能正常返回、而 IDE 会话里仍失败，即可确认问题出在 serve 未重启，而非配置本身。

## 其他约定

- `.opencode/` 为会话工作区，仅 `agent/` 目录随仓库分发，其余（node_modules、快照、
  attachments、交接件等）均被 gitignore，不要提交。
- `.env` 等含密钥文件已被 gitignore，禁止入库，改用 `.env.example`。
