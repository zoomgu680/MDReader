# MDReader macOS 构建指南

本文档面向 macOS 平台的开发与发布，适用于 MDReader **0.2.1**（Tauri 1.5 / WKWebView）。
Windows 平台的构建方式见 [README](../README.md#构建指南)。

---

## 1. 总体说明

- 桌面框架为 **Tauri 1.x**，macOS 端使用系统自带的 **WKWebView**，无需额外运行时。
- 前端为原生 HTML / CSS / JavaScript，**没有 npm 依赖、没有前端构建步骤**，`resources/` 下的
  marked、DOMPurify、highlight.js、KaTeX、Mermaid、docx 等库均已随仓库提供。
- Tauri 加载的运行目录是 `dist/`，而源码在根目录的 `index.html` + `resources/`，**构建前必须先同步**。
- macOS 产物为 `.app` 与 `.dmg`；**不能在 Windows 上交叉编译**，反之亦然。
- 支持的架构：Apple Silicon（`aarch64-apple-darwin`）、Intel（`x86_64-apple-darwin`），也可构建通用包。

---

## 2. 环境准备

| 项目 | 要求 | 说明 |
|---|---|---|
| macOS | 构建机建议 12 (Monterey) 及以上；运行最低 10.15 | 见 `tauri.conf.json` 的 `bundle.macOS.minimumSystemVersion` |
| Xcode Command Line Tools | 必需 | 提供 `cc`、`clang`、macOS SDK、`hdiutil`、`codesign` |
| Rust | 1.70 及以上（含 cargo） | 项目 `edition = "2021"` |
| Tauri CLI | 1.5.x | 通过 cargo 安装，与 `Cargo.toml` 中 `tauri = "1.5"` 匹配 |
| Git | 任意较新版本 | 拉取源码 |
| GitHub CLI | 可选 | 仅发布 Release 时需要 |

### 2.1 安装命令行工具与 Rust

```bash
# 1) Xcode 命令行工具（含许可协议）
xcode-select --install
sudo xcodebuild -license accept

# 2) Rust（rustup 官方安装脚本）
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
rustc --version
cargo --version

# 3) Tauri CLI 1.5（与项目版本对应，不要装 2.x）
cargo install tauri-cli --version "^1.5" --locked
cargo tauri --version    # 期望输出 1.5.x
```

> 若 `cargo tauri` 提示找不到命令，确认 `~/.cargo/bin` 已在 `PATH` 中。

### 2.2 按目标架构添加 Rust 标准库

```bash
# Apple Silicon 本机构建（默认）
rustup target add aarch64-apple-darwin

# Intel 构建（Apple Silicon 上交叉编译 Intel 包时也需要）
rustup target add x86_64-apple-darwin
```

### 2.3 可选：GitHub CLI

```bash
brew install gh
gh auth login
gh auth status
```

---

## 3. 获取源码

```bash
git clone https://github.com/zoomgu680/MDReader.git
cd MDReader
git checkout v0.2.1        # 或 main
```

> **注意**：仓库的 `.gitignore` 排除了 `release.sh`、`sync-dist.sh`、`update.sh`、`*.ps1`
> 等发布/同步脚本（属本地工具，不入库）。克隆后看不到这些脚本是正常的，
> 请按下文命令手工执行，或自行在本地创建。

---

## 4. 同步 dist 目录（构建前必做）

`tauri.conf.json` 中 `build.distDir` 为 `../dist`，Tauri 只认这个目录。

```bash
mkdir -p dist/resources
cp index.html dist/index.html
cp -R resources/* dist/resources/

# 若本地存在同步脚本（未入库，按需自建）
# ./sync-dist.sh

# 校验：两边文件数应一致（当前为 80）
find resources -type f | wc -l
find dist/resources -type f | wc -l
```

如需彻底一致（清理已删除的旧资源）：

```bash
rsync -a --delete resources/ dist/resources/
```

> 忘记同步的典型表现：`cargo tauri dev` 白屏、导出 Word 报 `docx is not defined`、
> 导出的 HTML 缺少样式。

---

## 5. 开发模式运行

```bash
cd src-tauri
cargo tauri dev
```

- 首次编译会拉取并编译数百个 crate，耗时约 5–15 分钟；之后为增量编译。
- 窗口尺寸由 `src-tauri/src/main.rs` 的 `setup` 钩子设定：按当前屏幕逻辑尺寸的 90% 并居中。
- 修改前端（`index.html` / `resources/`）后需重新同步 `dist/` 再刷新窗口。

---

## 6. 正式构建

```bash
# 先同步 dist（见第 4 节）
cd src-tauri
cargo tauri build --bundles app,dmg
```

`tauri.conf.json` 中 `bundle.targets` 为 `"all"`，省略 `--bundles` 时 macOS 也会同时产出
`.app` 与 `.dmg`。

### 6.1 产物位置

| 产物 | 路径 |
|---|---|
| 应用包 | `src-tauri/target/release/bundle/macos/MDReader.app` |
| 磁盘镜像 | `src-tauri/target/release/bundle/dmg/MDReader_0.2.1_aarch64.dmg`（Intel 为 `_x64.dmg`） |

### 6.2 构建通用包（Universal）

同时兼容 Apple Silicon 与 Intel：

```bash
rustup target add aarch64-apple-darwin x86_64-apple-darwin

cd src-tauri
cargo tauri build --target universal-apple-darwin --bundles app,dmg
```

产物位于 `src-tauri/target/universal-apple-darwin/release/bundle/`，
DMG 文件名形如 `MDReader_0.2.1_universal.dmg`。

- 通用包体积约为单架构的两倍。
- 使用 `--target universal-apple-darwin` 时，Tauri 会分别编译两种架构再用 `lipo` 合并，
  首次耗时会明显增加。

### 6.3 快速验证构建结果

```bash
open src-tauri/target/release/bundle/macos/MDReader.app
```

---

## 7. `tauri.conf.json` 中与 macOS 相关的配置

| 配置项 | 当前值 | macOS 下的作用 |
|---|---|---|
| `package.productName` | `MDReader` | 生成 `MDReader.app`，即 CFBundleName |
| `package.version` | `0.2.1` | 写入 `CFBundleShortVersionString`，**必须与 `Cargo.toml` 一致** |
| `tauri.bundle.identifier` | `com.mdreader.app` | CFBundleIdentifier，签名/公证时不可随意变更 |
| `tauri.bundle.icon` | 含 `icons/icon.icns` | macOS 应用图标（文件有效，约 630 KB） |
| `src-tauri/Info.plist` | `CFBundleDocumentTypes` + `UTImportedTypeDeclarations` | 注册 Markdown 文档类型，Finder 双击 `.md` / `.markdown` 即用 MDReader 打开（Tauri 1.x 不支持 `bundle.fileAssociations`，需用此方式扩展） |
| `tauri.bundle.targets` | `all` | macOS 产出 `.app` + `.dmg` |
| `tauri.bundle.macOS.minimumSystemVersion` | `10.15` | 写入 `LSMinimumSystemVersion` |
| `tauri.bundle.macOS.frameworks` | `[]` | 不额外链接系统框架 |
| `tauri.bundle.copyright` | 中国邮政版权声明 | 写入 `NSHumanReadableCopyright` |
| `tauri.bundle.windows.webviewInstallMode` | `offlineInstaller` | **仅 Windows 生效**，macOS 忽略 |
| `build.withGlobalTauri` | `true` | 前端通过 `window.__TAURI__` 调用命令与对话框 |
| `build.distDir` | `../dist` | 打包内容来源 |
| `allowlist.dialog.open` / `save` | `true` | 打开文件对话框、导出 Word 的保存对话框（缺一不可） |
| `allowlist.window.all` | `true` | 运行期调整窗口大小、居中 |
| `allowlist.shell.open` | `true` | 外部链接交给默认浏览器 |
| `allowlist.fs.scope` | `["**"]` | 仅为 scope 声明；实际文件读写走 `main.rs` 自定义命令 |
| `security.csp` | `null` | 允许内联脚本、KaTeX/Mermaid 动态插入 |
| `windows[0]` | 1280×800、最小 800×600、`fileDropEnabled: true` | 主窗口初始尺寸与拖放打开文件 |

### 7.1 后端命令的跨平台情况

`src-tauri/src/main.rs` 中的命令均为跨平台实现：

- `read_file` / `write_file` / `read_binary_file` / `write_binary_file`：标准库文件读写，
  Word 导出走 base64 解码写盘。
- `get_recent_files` / `add_recent_file` / `get_last_file`：路径由 `dirs::config_dir()`
  解析，macOS 下为 `~/Library/Application Support/mdreader/recent.json`。
- `get_startup_file`：读取命令行第一个 `.md` / `.markdown` 参数。
- `file_owner`：已分别实现 Windows（PowerShell ACL）、
  **macOS（`stat -f %Su`）**、其他 Unix（`stat -c %U`）三套分支，macOS 可正常编译。

### 7.2 当前未配置的 macOS 项目

| 缺失项 | 影响 | 说明 |
|---|---|---|
| `bundle.macOS.signingIdentity` | 产物未签名 | Gatekeeper 会拦截，见第 8 节 |
| `bundle.macOS.entitlements` | 无自定义权限声明 | 未启用沙箱时通常不需要 |
| DMG 外观（`bundle.macOS.dmg`） | 使用默认磁盘镜像布局 | 可用 `background` / `windowSize` 等定制 |

### 7.3 文件关联（`src-tauri/Info.plist`）

Tauri 1.x 的 `bundle` 配置中**没有** `fileAssociations` 字段（Tauri 2.x 才有），
因此文件关联通过官方支持的方式实现：在 `src-tauri/Info.plist` 中声明文档类型，
构建时 CLI 会把它与自动生成的 `Info.plist` 合并。

当前注册内容：

| 键 | 值 |
|---|---|
| `CFBundleDocumentTypes[0].CFBundleTypeName` | `Markdown Document` |
| `CFBundleTypeRole` | `Editor` |
| `LSHandlerRank` | `Alternate`（不抢占用户已设置的默认程序） |
| `CFBundleTypeExtensions` | `md`、`markdown` |
| `LSItemContentTypes` | `net.daringfireball.markdown`（由 `UTImportedTypeDeclarations` 声明，遵循 `public.plain-text`） |

验证构建产物：

```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes" \
  src-tauri/target/release/bundle/macos/MDReader.app/Contents/Info.plist
```

如需改为默认打开程序（抢占关联），把 `LSHandlerRank` 由 `Alternate` 改为 `Default`，并增大版本号重新构建；
系统会缓存旧关联，必要时执行：

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user
```

---

## 8. 未签名应用的分发与首次启动

未签名的 `.app` / `.dmg` 在 macOS 上会被 Gatekeeper 拦截：
「无法打开"MDReader"，因为无法验证开发者」。

用户侧解决办法（任选其一）：

```bash
# 方式 1：右键点击应用 → 打开 → 再次确认「打开」

# 方式 2：移除隔离属性
xattr -dr com.apple.quarantine /Applications/MDReader.app
```

### 8.1 可选：签名与公证（面向对外分发）

需要 Apple Developer Program 账号（Developer ID Application 证书）。

```bash
# 查看可用签名证书
security find-identity -v -p codesigning
```

在 `tauri.conf.json` 的 `bundle.macOS` 中增加：

```json
"macOS": {
  "minimumSystemVersion": "10.15",
  "signingIdentity": "Developer ID Application: 你的公司名 (TEAMID)"
}
```

重新构建后（Tauri 1.x 会自动对 `.app` 签名），对 DMG 做公证：

```bash
xcrun notarytool submit MDReader_0.2.1_aarch64.dmg \
  --apple-id "your@apple.id" \
  --team-id "TEAMID" \
  --password "app-specific-password" \
  --wait

xcrun stapler staple MDReader_0.2.1_aarch64.dmg
spctl -a -vvv -t install MDReader_0.2.1_aarch64.dmg
```

> 公证与签名会写入 Apple 账号凭据，请勿把密码提交到仓库；建议用环境变量或钥匙串传递。

---

## 9. 版本号与发布流程

### 9.1 版本号一致性

发布前需保证三处一致（`Cargo.lock` 由 cargo 自动更新）：

| 位置 | 字段 |
|---|---|
| `src-tauri/Cargo.toml` | `version = "0.2.1"` |
| `src-tauri/tauri.conf.json` | `package.version` |
| `index.html` | 关于弹窗中的 `版本 0.2.1` 文本 |

修改后可校验：

```bash
grep -n '^version' src-tauri/Cargo.toml
grep -n '"version"' src-tauri/tauri.conf.json
grep -o '版本 [0-9.]*' index.html
```

### 9.2 手工发布步骤（对应 Windows 的 `release.ps1`）

```bash
# 1) 修改版本号：Cargo.toml、tauri.conf.json、index.html（关于弹窗）

# 2) 同步 dist
mkdir -p dist/resources && cp index.html dist/index.html && cp -R resources/* dist/resources/

# 3) 构建 macOS 包（先构建，成功后再提交）
cd src-tauri && cargo tauri build --bundles app,dmg && cd ..

# 4) 提交（含构建后更新的 Cargo.lock）
git add -A
git commit -m "Bump version to 0.2.1"

# 5) 打 tag 并推送（tag 已存在则跳过）
git tag -a v0.2.1 -m "MDReader v0.2.1"
git push origin main
git push origin v0.2.1

# 6) 创建或补充 Release
#    新版本：
gh release create v0.2.1 \
  "src-tauri/target/release/bundle/dmg/MDReader_0.2.1_aarch64.dmg" \
  --title "MDReader v0.2.1" --notes-file notes.md --latest

#    已有 Release（如 v0.2.1 已发布 Windows 安装包）时追加 macOS 产物：
gh release upload v0.2.1 \
  "src-tauri/target/release/bundle/dmg/MDReader_0.2.1_aarch64.dmg"
```

### 9.3 命名与平台分工

- 建议统一资产名：`MDReader_<版本>_arm64.dmg`、`MDReader_<版本>_x64.dmg`、`MDReader_<版本>_universal.dmg`。
- Windows 安装包（`*_x64-offline_setup.exe` / `*_x64-online_setup.exe`）只能在 Windows 构建；
  macOS 的 `.dmg` 只能在 macOS 构建，两者合并到同一个 Release。

### 9.4 关于本地 `release.sh`

仓库根目录的 `release.sh`（未入库）可完成
「改版本号 → 同步 dist → 构建 dmg → 提交 → 打 tag → 创建 Release」，
与 Windows 的 `release.ps1` 流程一致：

```bash
chmod +x release.sh
./release.sh 0.2.2
```

要点：

1. 版本号会同步更新 `tauri.conf.json`、`Cargo.toml` 与 `index.html` 关于弹窗文本；
2. **先构建、后提交并打 tag**，构建失败不会在远程留下孤立 tag；
3. 提交发生在构建之后，构建更新的 `Cargo.lock` 会一并纳入，工作区保持干净；
4. `gh` 可用性与认证检查放在最后一步，未就绪时前面的构建与 tag 已完成，可按提示补发 Release。

---

## 10. 构建后验证清单

- [ ] `cargo tauri --version` 为 1.5.x
- [ ] `dist/resources` 与 `resources` 文件数一致（80）
- [ ] `.app` 可正常启动，窗口为屏幕 90% 且居中
- [ ] 打开 `.md`、拖放文件、目录跳转、代码高亮、KaTeX、Mermaid 正常
- [ ] 打印（Ctrl/Cmd+P）无 URL 页眉页脚
- [ ] 导出 HTML：保存后浏览器打开可**上下滚动**
- [ ] 导出 Word：保存对话框默认目录为当前文档所在目录，`.docx` 可被 Word / Pages 打开
- [ ] `~/Library/Application Support/mdreader/recent.json` 能正常记录最近文件
- [ ] 文档信息弹窗能显示文件所有者（macOS 走 `stat -f %Su`）

---

## 11. 常见问题

| 现象 | 原因与处理 |
|---|---|
| `xcrun: error: invalid active developer path` | 执行 `xcode-select --install`；或 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| `error: linker 'cc' not found` | 未安装 Xcode Command Line Tools |
| `error: failed to run custom build command for ...` | 多为缺少命令行工具或 SDK，先确认 `xcode-select -p` 输出有效路径 |
| `cargo tauri: command not found` | `~/.cargo/bin` 不在 `PATH`，执行 `source "$HOME/.cargo/env"` |
| 启动白屏 / 样式缺失 | `dist/` 未同步，按第 4 节重新复制 |
| 导出 Word 报 `docx is not defined` | `dist/resources/docx.min.js` 缺失，重新同步 `resources/` |
| `hdiutil: create failed - Resource busy` | 已挂载同名卷：`hdiutil detach /Volumes/MDReader` |
| 提示应用「已损坏，无法打开」 | 未签名且带隔离属性：`xattr -dr com.apple.quarantine /Applications/MDReader.app` |
| 通用包构建报某依赖无 aarch64/x64 版本 | 该依赖不支持目标架构；先分别验证单架构 `cargo build --target ...` |
| `security find-identity` 为空 | 钥匙串中没有代码签名证书，只能产出未签名包 |
| Intel Mac 上构建 universal 失败 | 确认两个 target 均已 `rustup target add`，并清理 `target/` 后重试 |

---

## 12. 附：项目配置文件检查结论（2026-11-09）

针对 macOS 构建可行性检查了 `src-tauri/tauri.conf.json`、`src-tauri/Cargo.toml`、
`src-tauri/src/main.rs`、`resources/tauri-bridge.js`、`.gitattributes`、`.gitignore`
以及 `dist/` 同步状态，结论如下：

**可以构建的部分**

1. `src-tauri/src/main.rs` 的 `file_owner` 已包含 `#[cfg(target_os = "macos")]` 分支
   （`stat -f %Su`），不存在 macOS 编译缺失符号的问题。
2. 前端的路径处理同时兼容 `/` 与 `\`（`tauri-bridge.js` 中 `split(/[\\\/]/)`、
   保存对话框的 `sep` 判断），macOS 下路径正常。
3. `src-tauri/icons/icon.icns` 文件头为 `icns`，约 630 KB，图标有效。
4. `.gitattributes` 强制 `*.sh` 为 LF、`*.ps1` 为 CRLF，脚本在 macOS 上不会因换行符报错。
5. `dist/` 与源目录完全同步：`index.html` 哈希一致，`resources` 与 `dist/resources` 均为 80 个文件。
6. 版本号三处一致（`Cargo.toml`、`tauri.conf.json`、`index.html` 均为 0.2.1），
   `Cargo.lock` 中 `mdreader` 也是 0.2.1。
7. 依赖（tauri 1.5、serde、dirs、base64）均支持 macOS，无平台限定依赖。
8. 已通过 `src-tauri/Info.plist` 注册 `.md` / `.markdown` 文档类型（role `Editor`）：
   Tauri 1.x 的 `bundle` 配置没有 `fileAssociations` 字段（该字段为 Tauri 2.x 新增，
   写入会直接编译失败），故改用官方支持的 Info.plist 合并方式。生产构建时 CLI 会合并该文件，
   `cargo tauri dev` 时由核心层嵌入；构建产物的 `Info.plist` 中含 `CFBundleDocumentTypes`。

**需要留意的部分**

1. 未配置 `signingIdentity` / `entitlements`：产物未签名，需按第 8 节处理 Gatekeeper。
2. 发布脚本（`release.sh` / `sync-dist.sh` / `update.sh`）被 `.gitignore` 排除，
   克隆仓库后不存在，需按本文档命令手工执行。
3. `tauri.conf.json` 中 `bundle.windows.webviewInstallMode` 仅对 Windows 生效，
   macOS 构建时可忽略，无需改动。
