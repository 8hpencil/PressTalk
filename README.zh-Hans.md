# PressTalk

**macOS 按住即说的语音听写工具，用你自己的 API 密钥驱动。**

[English README](README.md)

PressTalk 常驻菜单栏。按住快捷键说话，松开即把转写文字直接输入到当前光标处，任何 App 都行。它通过**你自己的** Google AI Studio API 密钥（BYOK）调用 Gemini 2.5 Flash，中英混说、专业术语、智能标点的识别效果远超系统自带听写——并且在 Google 免费层额度内零成本。

## 演示

在任意位置——浏览器、编辑器、聊天框——按住 <kbd>⌥ Option</kbd> + <kbd>D</kbd>，自然说话（中英混说没问题），松开按键，约一秒后转写文字出现在光标处。

<!-- 此处放 demo.gif：录屏展示上述流程（菜单栏图标 空闲 → 录音 → 转写 的变化，文字插入文本框） -->

## 功能

- **按住即说的全局热键** —— 默认 <kbd>⌥ Option</kbd> + <kbd>D</kbd>，设置中可完全自定义，保存即生效无需重启。
- **Gemini 2.5 Flash 转写** —— 中英混合识别极佳，智能标点，自动过滤"呃""嗯""那个"等语气词。模型名可配置。
- **Google Cloud Speech-to-Text V2 (Chirp 3) 转写** —— 支持商用级最新 Chirp 3 语音大模型，对长语音、中英混合、多语种场景有极佳的识别率。
- **自定义 prompt 与提示词表** —— 把你的专业术语（产品名、行业词汇）教给模型，保证拼写分毫不差。
- **光标处智能插入** —— 优先走 macOS 辅助功能接口，失败时回退剪贴板粘贴，且会完整备份并恢复你的剪贴板（含图片）。
- **隐私内建** —— API 密钥存 macOS 钥匙串，音频转写完成立即删除，日志只记事件不记内容（可在 Console.app 查看）。无统计、无遥测、无中间服务器：音频从你的 Mac 直达 Google。
- **不打扰** —— 仅菜单栏图标，无 Dock 图标。录音上限 5 分钟（API 限制），自动停止前 30 秒菜单栏预警。
- **开机自启**，界面支持英文与简体中文。

## 安装

### 下载（推荐）

1. 从 **Releases** 页面下载最新 `PressTalk.zip` 并解压。
2. 把 `PressTalk.app` 拖入「应用程序」文件夹。
3. **首次启动：右键点击应用 → 打开 → 打开。** 开源版本为 ad-hoc 签名（无 Apple 开发者证书），首次双击会被 Gatekeeper 拦截；右键打开是标准且安全的方式，只需做一次。

### 从源码构建

需要 macOS 13+ 与 Xcode 命令行工具。

```bash
git clone <本仓库>
cd PressTalk
./build_app.sh        # 产出 ad-hoc 签名的 PressTalk.app
```

开发期快速运行：`swift run`。

## 配置（自带密钥）

1. 到 [Google AI Studio](https://aistudio.google.com/apikey) 免费申请 API 密钥。
2. 点击菜单栏 PressTalk 图标 → **设置…** → 粘贴密钥 → **保存**。
3. 首次按住热键时 macOS 会请求**麦克风**权限，请允许。
4. 文本插入需要在 **系统设置 → 隐私与安全性 → 辅助功能** 中勾选 PressTalk；缺少权限时应用会通知引导。
5. 把光标放进任意文本框，按住 <kbd>⌥ Option</kbd> + <kbd>D</kbd> 说话，松开即可。

### 配置 Google Cloud STT (Chirp 3)

如果您想使用 Google Cloud 的 Chirp 3 语音转文字服务：
1. **启用 API**：在 Google Cloud Console 中为您的项目启用 **Cloud Speech-to-Text API**。
2. **获取凭据**：
   - 复制您的 GCP **项目 ID (Project ID)**。
   - 在 **凭据 (Credentials)** 页面创建一个 **API 密钥 (API Key)**，为了安全建议限制该密钥仅可调用 Cloud Speech-to-Text API。
3. **在应用中配置**：
   - 点击菜单栏 PressTalk 图标 → **设置…**。
   - 在“转写服务”中选择 **Google Cloud STT (Chirp)**。
   - 填写您的 Google Cloud API 密钥、GCP 项目 ID、区域（默认 `us-central1`）和模型名称（默认 `chirp_3`），然后点击**保存**即可。

## 隐私

听写敏感内容前请先阅读：

- **音频会发送到 Google 的 Gemini API** 进行转写，使用你自己的密钥鉴权。本地音频文件在转写完成的瞬间即被删除，PressTalk 不保留任何音频或文字历史。
- **Google 可能将免费层请求数据用于模型训练。** 这是 Google 对 AI Studio 免费层的政策，PressTalk 无法改变。敏感内容请使用付费层密钥。
- PressTalk 自身日志只记录事件（如"转写成功，42 字符"），绝不记录内容与密钥。
- 无账号、无遥测、无自建服务器。代码以 GPL 协议开放、可审计——这正是初衷。

## 系统要求

- macOS 13 Ventura 及以上（Apple Silicon 与 Intel 均支持）。

## 参与贡献

欢迎 PR —— 见 [CONTRIBUTING.md](CONTRIBUTING.md) 与 [good first issues](docs/good-first-issues.md) 列表。

## 许可证

[GPL-3.0](LICENSE)。依赖：[HotKey](https://github.com/soffes/HotKey)（MIT）。
