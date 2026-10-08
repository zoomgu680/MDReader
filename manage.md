## GitHub更新管理脚本
### 脚本 1：源码更新管理
| 文件       | 平台               |
| ---------- | ------------------ |
| update.ps1 | Windows PowerShell |
| update.sh  | macOS / Linux bash |

**功能** ：自动同步 dist → 暂存变更 → 提交 → 推送

**用法** ：

```PowerShell
1 # Windows —— 自动生成提交信息（取变更文件名）
2  .\update.ps1
3
4 # 指定提交信息
5  .\update.ps1 -Message "修复 Mermaid 全屏对比度问题"
6
7 # 只提交不推送（本地检查）
8  .\update.ps1 -NoPush
9
10 # 跳过 dist 同步（纯代码变更时）
11  .\update.ps1 -NoSync
```
```Bash
1 # macOS / Linux
2 ./update.sh
3 ./update.sh -m "修复xxx"
4 ./update.sh --no-push
5 ./update.sh --no-sync`
```
### 脚本 2：Release 发布管理

| 文件        | 平台               |
| ----------- | ------------------ |
| release.ps1 | Windows PowerShell |
| release.sh  | macOS / Linux bash |

 **功能** ：一站式发布——改版本号 → 同步 dist → 提交 → 打 tag → 推送 → 构建双安装包 → 创建 GitHub Release → 上传安装包

**用法** （Windows）：

```PowerShell
1 # 完整发布 0.1.1（构建 offline + online 两个安装包并上传）
2 .\release.ps1 -Version 0.1.1
3
4 # 跳过构建（已有安装包，只创建 Release）
5 .\release.ps1 -Version 0.1.1 -SkipBuild
6
7 # 自定义 Release Notes
8 .\release.ps1 -Version 0.1.1 -Notes "修复了打印溢出和图片显示问题"
9
10 # 创建为草稿（不立即公开）
11 .\release.ps1 -Version 0.1.1 -Draft
```
**release.ps1 执行流程**：

1. 校验版本号格式`X.Y.Z`
2. 检查`git` 和`gh` 可用性及认证状态
3. 同步更新`tauri.conf.json` +`Cargo.toml` 中的版本号
4. 同步 dist，提交 "Bump version to X.Y.Z"
5. 创建 annotated tag`vX.Y.Z` 并推送
6. 切换`webviewInstallMode` 为`offlineInstaller` → 构建离线包 → 重命名
7. 切换为`downloadBootstrapper` → 构建在线包 → 重命名
8. 恢复默认配置为`offlineInstaller`
9. 用`gh release create` 创建 Release，附带两个安装包
**前置条件**：`gh auth login` 已完成认证。

## 典型工作流
```Plain Text
1 日常开发：
2   改代码 -> .\update.ps1 -m "描述"          # 同步dist + 提交 + 推送
3
4 发版本：
5   .\release.ps1 -Version 0.1.1              # 全自动：改版本+构建+打tag+发Release`
```
## 注意事项
- **PowerShell 执行策略**：如遇 "无法加载脚本...禁止运行"，执行一次`Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`
- **首次构建耗时**：release 脚本中的`cargo tauri build` 首次约 3-5 分钟，增量构建约 30 秒
- **macOS 构建**：`release.sh` 在 macOS 上生成`.dmg` ，Windows`.exe` 包必须在 Windows 上构建（WebView2 依赖）
- **版本号同步**：脚本会同时更新`tauri.conf.json` 和`Cargo.toml` 的 version 字段