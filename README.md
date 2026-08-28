<div align="center">
  <img src="Artwork/AppIcon-master.png" alt="WhoShitOnMyMac icon" width="144" />
  <h1>WhoShitOnMyMac</h1>
  <p>看清是谁把硬盘弄脏了。</p>
</div>

WhoShitOnMyMac 是一款安全优先的原生 macOS 清理与卸载工具。它通过磁盘快照对比解释空间变化，扫描可说明来源的垃圾文件，并在卸载应用前展示关联残留。

## 下载

[下载已签名并经过 Apple 公证的 v1.0.0 DMG](https://github.com/bennix/whoshitmymac/releases/download/v1.0.0/WhoShitOnMyMac-1.0.0.dmg)

- macOS 14 Sonoma 或更高版本
- 支持 Apple Silicon 与 Intel Mac
- Developer ID 签名与 Hardened Runtime

## 功能

- **快照对比**：保存文件系统快照，对比新增、增长、缩减与删除的文件。
- **垃圾扫描**：按缓存、日志、浏览器、开发工具、安装包和工程产物等类别检查空间。
- **应用卸载**：预览应用本体和关联残留，并识别共享数据与正在运行的应用。
- **安全保护**：系统路径黑名单、用户白名单、预览队列和操作历史。
- **可恢复删除**：默认只移动到废纸篓，不直接永久删除。

## 本地构建

```bash
xcodebuild test \
  -project WhoShitOnMyMac.xcodeproj \
  -scheme WhoShitOnMyMac \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:WhoShitOnMyMacTests \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build \
  -project WhoShitOnMyMac.xcodeproj \
  -scheme WhoShitOnMyMac \
  -configuration Release \
  -destination 'generic/platform=macOS'
```

正式分发需要 Apple Developer Program 的 `Developer ID Application` 证书，并在打包后通过 Apple Notary Service 公证。

## Landing Page

Landing Page 位于 [`site`](site)，使用 Sites/Vinext 构建。

```bash
cd site
npm install
npm run dev
```

## 安全说明

清理工具会接触文件系统。请先查看扫描结果和待处理队列，并为重要数据保留独立备份。无法证明安全、处于占用状态或受系统保护的目标会被跳过。
