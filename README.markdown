# Docker Image Manager

一个简单易用的 Bash 脚本，用于自动化备份和恢复 Docker 镜像，保留完整标签信息。

## 📋 简介

Docker Image Manager 让 Docker 镜像管理变得轻松高效。通过交互式菜单，用户可以一键备份所有镜像或从备份文件恢复，支持 gzip、zstd 和 xz 压缩，并提供实时进度条。适用于开发、测试和生产环境中的镜像管理需求。

## ✨ 核心功能

- **🖥️ 交互式菜单**：简单选择操作，无需复杂命令
- **🤖 自动化流程**：自动备份所有镜像或从备份恢复，省时省力
- **🗜️ 压缩支持**：提供 gzip、zstd 和 xz 压缩选项，并估算压缩率
- **📊 进度显示**：实时进度条，清晰展示操作状态
- **🛡️ 健壮性**：自动检查 Docker 可用性，支持通过 Docker 容器运行压缩工具

## 🎯 使用场景

- **开发环境**：快速备份镜像，便于在不同开发环境间迁移
- **测试环境**：在测试前备份镜像，确保测试不影响原始数据
- **生产环境**：定期备份镜像，防止系统故障或更新导致数据丢失

## 📋 要求

- **Bash shell**：脚本在 Bash 环境下运行
- **Docker**：必须安装并运行，用户需有 Docker 命令权限（可能需要 root 或 docker 组权限）
- **可选工具**：gzip、zstd、xz（若缺失，脚本通过 Docker 容器运行）
- **bc 工具**：用于压缩率计算（通常 Linux 系统默认包含）

**权限设置**：
```bash
sudo usermod -aG docker $USER
```
重新登录以应用权限。

## 🚀 安装

1. 从 GitHub 仓库下载脚本（建议命名为 `docker_image_manager.sh`）
2. 赋予执行权限：
   ```bash
   chmod +x docker_image_manager.sh
   ```
3. 运行脚本：
   ```bash
   ./docker_image_manager.sh
   ```
   

## 📖 使用方法

运行脚本后，会显示交互式菜单：

<div align="center">
  <img src="示例/主菜单.png" alt="脚本主菜单" width="600" style="border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);">
  <p><em>脚本主菜单界面</em></p>
</div>

选择菜单选项：
- **1. 备份所有 Docker 镜像**：自动保存所有镜像到压缩文件，文件名包含时间戳（如 `docker_images_20250727_235000.tar.gz`）
- **2. 从备份文件恢复镜像**：从脚本目录选择备份文件，解压并恢复镜像
- **3. 退出**：关闭脚本

### 🔄 备份流程

1. **列出所有镜像**（排除 `<none>` 标签）
2. **保存每个镜像**为 `.tar` 文件，清理特殊字符
3. **打包为单一文件**，估算压缩率
4. **提供压缩选项**（无压缩、gzip、zstd、xz），显示压缩进度

<div align="center">
  <img src="示例/压缩选择.png" alt="压缩选择" width="500" style="border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);">
  <p><em>压缩选项选择界面</em></p>
</div>

<div align="center">
  <img src="示例/备份1.png" alt="备份过程示例" width="500" style="border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);">
  <p><em>备份过程示例</em></p>
</div>

<div align="center">
  <img src="示例/备份完成.png" alt="备份完成" width="500" style="border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);">
  <p><em>备份完成界面</em></p>
</div>

### 🔄 恢复流程

1. **列出脚本目录中的备份文件**（支持 `.tar`、`.tar.gz`、`.tar.zst`、`.tar.xz`）
2. **选择文件**，解压到临时目录，显示进度
3. **使用 `docker load` 恢复镜像**，保留标签
4. **显示恢复的镜像列表**，清理临时文件

<div align="center">
  <img src="示例/镜像恢复.png" alt="恢复过程示例" width="500" style="border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);">
  <p><em>镜像恢复过程</em></p>
</div>

<div align="center">
  <img src="示例/镜像恢复完成.png" alt="镜像恢复完成" width="500" style="border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);">
  <p><em>镜像恢复完成界面</em></p>
</div>

## 💡 示例

### 备份示例

1. 运行脚本，选择选项 1
2. 脚本显示镜像保存进度：
   ```
   保存镜像 (1/5): nginx:latest
   ```
3. 估算压缩率并选择压缩方式（如 zstd）：
   ```
   原始备份文件大小: 500M
   gzip压缩: 60% (约 300MB)
   zstd压缩: 55% (约 275MB)
   xz压缩: 50% (约 250MB)
   ```
4. 生成备份文件：`docker_images_20250727_235000.tar.zst`

### 恢复示例

1. 选择选项 2，查看备份文件：
   ```
   可用的备份文件:
   1. docker_images_20250727_235000.tar.zst
   ```
2. 选择文件，显示恢复进度：
   ```
   恢复镜像 (1/5): nginx:latest
   ```
3. 完成并列出恢复的镜像

## ⚠️ 注意事项

- **💾 磁盘空间**：确保脚本目录有足够空间存储备份文件
- **🐳 Docker 依赖**：若使用 Docker 容器运行压缩工具，需确保 Docker 服务正常
- **🖥️ 兼容性**：脚本为 Linux 环境设计，部分命令（如 `stat`）可能需调整以支持非 GNU 系统（如 macOS）
- **⏱️ 超时**：操作超时设为 15 秒，适合大文件处理
- **📊 采样**：压缩率估算使用 20MB 数据采样，提高准确性

## 📄 许可证

本项目采用 [MIT 许可证](LICENSE)。请根据需要添加 LICENSE 文件。

## 🤝 贡献

欢迎提交 Pull Request 或 Issue，提出新功能或修复建议。

## 📞 联系

通过 GitHub 仓库的 Issue 联系我们，我们会尽快回复。

## 📚 资源

- [Docker 官方文档](https://docs.docker.com/)
- [Bash 脚本指南](https://www.gnu.org/software/bash/manual/)
