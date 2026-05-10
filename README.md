# Claude Code Termux 安装脚本

在官方安装脚本基础上，增加 **Termux (Android)** 环境支持。

## 为什么需要这个脚本？

Claude Code 官方二进制依赖 glibc，而 Termux 使用 Bionic libc，直接运行会报错。本脚本自动解决这一兼容性问题。

Claude Code 在 Termux 上直接装会报 glibc 错，以前大家要么用 proot 开虚拟 Linux，有点折腾。这个脚本帮你一键搞定，让 Claude Code 原生跑在 Termux 上，轻量、快速、自动适配官方更新。

## Termux 专属功能

### 1. 自动安装 glibc 环境
- 检测 Termux 环境，引导安装 ```glibc-repo```、```glibc```、```openssl-glibc```、```patchelf```

### 2. 自动修补二进制解释器
- 下载后自动将解释器改为 Termux glibc 加载器：```$PREFIX/glibc/lib/ld-linux-aarch64.so.1```
- 安装前先 patch 临时文件，确保 ```install``` 命令能正常执行

### 3. 启动自修复（核心）
- 在 ```~/.bashrc``` 注入 ```claude()``` 函数
- 每次启动自动检测解释器，若被更新重置则自动重新 patch
- 自动清空 ```LD_PRELOAD``` 避免 libc 冲突

## 使用方法

Linux/MacOS/Termux一键安装脚本
````bash
curl -fsSL https://cc.996855.xyz/ | bash
````

安装完成后执行：

````bash
source ~/.bashrc
````

## 非 Termux 环境

与官方脚本行为一致，支持 macOS / Linux。

## 展示

![自修复图片](https://edgeone.gh-proxy.org/https://raw.githubusercontent.com/masgzy/claude-code-termux/main/repair.jpg)
(上面两行命令为改为原二进制文件定义的lib文件路径)

## 注意

- 首次安装后**必须** ```source ~/.bashrc``` 或重启终端
- 官方更新后若无法运行，启动时自修复函数会自动修补
