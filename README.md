# MDReader - Markdown 阅读器

> 版权所有 © 2026 中国邮政集团有限公司浙江省信息技术中心  
> (China Post Group Co., Ltd. Zhejiang IT Center)  
> 本软件遵循 MIT / Apache-2.0 开源协议发布。

基于 Tauri 构建的全功能 Markdown 阅读器，专为 Windows / macOS 桌面环境设计。

## 功能特性

- **Markdown 渲染**：支持 CommonMark 规范、表格、任务列表、脚注等
- **代码高亮**：基于 highlight.js，支持 190+ 编程语言
- **数学公式**：基于 KaTeX，支持行内与块级 LaTeX 公式
- **Mermaid 图形**：流程图、时序图、甘特图、类图等，点击可全屏查看
- **图片全屏**：点击图片放大显示，对比度跟随主题自适应
- **多主题切换**：浅色、深色、护眼、Nord、Solarized、Dracula 等
- **字体控制**：实时调整显示字体大小，不影响打印与 Mermaid 渲染
- **编辑保存**：内置编辑器，自动换行，保存后即时写回磁盘
- **目录大纲**：自动生成文档目录，点击跳转
- **最近文件**：自动记录最近打开的 10 个文件
- **文件关联**：双击 .md 文件可直接打开
- **拖放打开**：支持拖放 .md 文件到窗口
- **打印输出**：通过 iframe 隔离打印，避免 URL 页眉页脚
- **导出 HTML**：单文件导出，样式内嵌，浏览器打开即可全文滚动阅读
- **导出 Word**：按党政机关公文格式导出（A4 版心、仿宋三号正文、固定行距 28 磅、页码居中），支持标题层级字体、表格、图片与 Mermaid 图形；顶栏与设置面板均提供入口

## 技术栈

| 层 | 技术 |
|---|---|
| 桌面框架 | Tauri 1.5 (Rust) |
| 前端 | 原生 HTML / CSS / JavaScript（无构建步骤） |
| Markdown 解析 | marked.js v12 |
| HTML 净化 | DOMPurify |
| 代码高亮 | highlight.js v11 |
| 数学公式 | KaTeX |
| 图形渲染 | Mermaid v11 |
| Word 导出 | docx v8.5.0 |
| 后端依赖 | serde, dirs, base64 |

第三方组件版权信息详见 [THIRD_PARTY_LICENSES](./THIRD_PARTY_LICENSES)。

## 目录结构

```
MDReader/
├── index.html              # 前端入口（HTML + JS 主逻辑）
├── dist/                   # Tauri 加载的运行目录（index.html + resources 的副本）
│   ├── index.html
│   └── resources/
├── resources/              # 前端资源源目录
│   ├── style.css           # 样式（多主题、打印样式）
│   ├── marked.min.js
│   ├── purify.min.js
│   ├── highlight.min.js
│   ├── katex.min.js
│   ├── katex.min.css
│   ├── auto-render.min.js
│   ├── mermaid.min.js
│   ├── docx.min.js         # Word 导出（公文格式）
│   ├── tauri-bridge.js      # Tauri 前后端桥接
│   └── hljs-themes/         # 代码高亮主题
├── src-tauri/              # Rust 后端
│   ├── src/main.rs          # 入口：文件读写命令、窗口管理
│   ├── Cargo.toml
│   ├── tauri.conf.json      # Tauri 应用配置
│   ├── build.rs
│   └── icons/              # 应用图标（ico/icns/png）
├── docs/
│   └── BUILD-macOS.md      # macOS 构建 / 签名 / 发布指南
├── THIRD_PARTY_LICENSES    # 第三方组件许可证
├── LICENSE                 # 本软件许可证（MIT / Apache-2.0）
└── README.md
```

## 环境要求

### 构建环境

- **Rust** ≥ 1.70（含 cargo）
- **Tauri CLI**：`cargo install tauri-cli --version "^1.5"`
- **Windows**：WebView2 Runtime、Visual Studio Build Tools（C++ 工作负载）
- **macOS**：Xcode Command Line Tools（最低系统版本 10.15）

### 运行环境

- **Windows 10** 及以上（WebView2 依赖）
- **macOS 10.15** 及以上

## 构建指南

> macOS 平台的完整构建、签名与发布流程见 [docs/BUILD-macOS.md](./docs/BUILD-macOS.md)。

### 1. 准备 dist 目录

项目根目录的 `index.html` 和 `resources/` 是源文件，Tauri 加载的是 `dist/` 目录。构建前需同步：

```powershell
# Windows PowerShell
Copy-Item .\index.html .\dist\index.html -Force
Copy-Item .\resources\* .\dist\resources\ -Recurse -Force
```

```bash
# macOS / Linux
cp ./index.html ./dist/index.html
cp -r ./resources/* ./dist/resources/
```

### 2. 开发模式运行

```bash
cd src-tauri
cargo tauri dev
```

### 3. 打包发布

```bash
cd src-tauri
cargo tauri build --bundles nsis
```

输出位置：`src-tauri/target/release/bundle/nsis/`

### 4. 生成两种安装包

`tauri.conf.json` 中的 `bundle.windows.webviewInstallMode.type` 控制是否内嵌 WebView2：

| 类型 | 配置值 | 安装包大小 | 说明 |
|---|---|---|---|
| 离线包 | `offlineInstaller` | ~210 MB | 内嵌 WebView2 Runtime，离线可装 |
| 在线包 | `downloadBootstrapper` | ~3 MB | 安装时联网下载 WebView2 |

切换配置后重新执行 `cargo tauri build --bundles nsis` 即可生成对应版本，建议重命名：

```
MDReader_0.2.1_x64-offline_setup.exe
MDReader_0.2.1_x64-online_setup.exe
```

### 5. 重新生成应用图标

如需更换图标，放入 `src-tauri/icons/icon.png`（≥ 512x512）后执行：

```bash
cargo tauri icon ./src-tauri/icons/icon.png
```

将自动生成 `.ico` / `.icns` / 各尺寸 `.png`。

## 打包注意事项

- **NSIS vs WiX**：NSIS 生成 `*-setup.exe`，无需 WiX 工具；WiX 生成 `.msi`，需下载 WiX 工具集（可能因 TLS 问题失败，推荐用 `--bundles nsis` 跳过）
- **跨平台构建**：macOS 包需在 macOS 环境构建，Windows 包需在 Windows 环境构建，无法交叉编译
- **首次构建**：Rust 编译依赖较多，首次约需 5-10 分钟，后续增量构建很快

## 更新日志

### 0.2.1

- 新增 **Word 文档导出**（党政机关公文格式）：A4 版心（上 37 / 下 35 / 左 28 / 右 26 mm）、正文仿宋三号、首行缩进两字符、固定行距 28 磅、页码居中；一级标题方正小标宋小二加粗居中且不缩进，二/三/四级标题分别为黑体/楷体/仿宋加粗；表格、图片、Mermaid 图形与代码块按公文样式转换
- 新增顶栏「导出 Word」按钮，与设置面板中的导出入口功能一致
- 修复设置面板导出的 HTML 文件无法滚动的问题（导出时覆盖应用内的固定视口样式）
- 更新第三方许可证清单，新增 docx v8.5.0（MIT）

## 许可证

本软件遵循 **MIT** 或 **Apache-2.0** 双协议发布，使用者可任选其一。

- [LICENSE](./LICENSE) — 完整许可证文本
- [THIRD_PARTY_LICENSES](./THIRD_PARTY_LICENSES) — 第三方组件版权声明

版权所有：中国邮政集团有限公司浙江省信息技术中心  
(China Post Group Co., Ltd. Zhejiang IT Center)
