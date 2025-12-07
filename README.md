# ext-msgwait

**基于 go-TelegramMessage 的 tdl 扩展（历史版本）**

[![GitHub](https://img.shields.io/badge/GitHub-55gY%2Fext--msgwait-blue)](https://github.com/55gY/ext-msgwait)

> ⚠️ **注意**：这是历史版本项目，推荐使用 [tdl-msgproce](https://github.com/55gY/tdl-msgproce) 代替。

## 📦 项目说明

`ext-msgwait` 是早期尝试融合 [go-TelegramMessage](https://github.com/55gY/go-TelegramMessage) 和 tdl 功能的扩展。

### ⚠️ 已知问题

- **需要 2 个 session**：go-TelegramMessage 和 tdl 各需要一个 session，需要登录两次
- **Session 冲突风险**：两个独立的 Telegram 客户端可能产生会话冲突
- **资源占用高**：需要维护两套客户端连接

### 🔄 推荐替代方案

建议使用 [tdl-msgproce](https://github.com/55gY/tdl-msgproce)，它完全基于 tdl 扩展：

- ✅ 只需 1 个 session（登录一次）
- ✅ 无会话冲突
- ✅ 资源占用更低
- ✅ 功能更完整

## 🔗 相关项目

| 项目 | 说明 | Session 数量 | 推荐度 |
|------|------|--------------|--------|
| [tdl-msgproce](https://github.com/55gY/tdl-msgproce) | 完全基于 tdl 的融合版 | 1 | ⭐⭐⭐⭐⭐ 推荐 |
| [go-TelegramMessage](https://github.com/55gY/go-TelegramMessage) | 纯 Go 消息监听器 | 1 | ⭐⭐⭐ 独立使用 |
| [go-bot](https://github.com/55gY/go-bot) | 转发机器人 | 1 | ⭐⭐⭐ 独立使用 |
| **ext-msgwait** (本项目) | 混合实现（已弃用） | 2 | ⭐ 不推荐 |

## 📖 原始功能

监听 Telegram 频道消息，过滤关键词并提交到订阅 API。

### 核心特性

- 监听指定频道实时消息
- 关键词过滤（如包含链接）
- 提取链接并提交到订阅系统
- 基于 go-TelegramMessage + tdl

## 🚀 安装（仅供参考）

> 再次提醒：推荐使用 [tdl-msgproce](https://github.com/55gY/tdl-msgproce)

### 编译

```bash
git clone https://github.com/55gY/ext-msgwait.git
cd ext-msgwait
go build -o tdl-msgwait main.go
```

### 安装

```bash
mkdir -p ~/.tdl/extensions/tdl-msgwait
cp tdl-msgwait ~/.tdl/extensions/tdl-msgwait/
```

### 安装扩展

```bash
# 安装扩展到 tdl（首次使用必须执行）
~/.tdl/tdl extension install --force ~/.tdl/extensions/tdl-msgwait/tdl-msgwait

# 验证安装
~/.tdl/tdl extension list
```

### 配置

```bash
mkdir -p ~/.tdl/extensions/data/msgwait
cp config.yaml ~/.tdl/extensions/data/msgwait/
nano ~/.tdl/extensions/data/msgwait/config.yaml
```

配置文件需要填写：
- API ID 和 API Hash（from https://my.telegram.org）
- 订阅 API 地址
- 监听的频道列表

## 📖 使用

### 登录（需要 2 次）

```bash
# 1. tdl 登录
~/.tdl/tdl login -n default -T qr

# 2. go-TelegramMessage 登录
# 运行扩展时会提示输入验证码
~/.tdl/tdl -n default msgwait
```

### 运行

```bash
~/.tdl/tdl -n default msgwait
```

## ⚠️ 为什么不推荐

1. **双重登录**：需要为 tdl 和 go-TelegramMessage 分别登录，麻烦
2. **Session 文件**：两个客户端可能争抢 session 文件锁
3. **维护困难**：需要协调两套不同的客户端逻辑
4. **资源浪费**：两个 Telegram 连接，内存占用翻倍

## 🎯 迁移到 tdl-msgproce

推荐迁移步骤：

```bash
# 1. 安装 tdl-msgproce
curl -sSL https://raw.githubusercontent.com/55gY/tdl-msgproce/main/install.sh | bash

# 2. 复制配置（字段兼容）
cp ~/.tdl/extensions/data/msgwait/config.yaml \
   ~/.tdl/extensions/data/msgproce/config.yaml

# 3. 运行新版本
~/.tdl/tdl -n default msgproce

# 4. 卸载旧版本（可选）
rm -rf ~/.tdl/extensions/tdl-msgwait
```

## 📄 开源协议

MIT License

## 🔗 相关链接

- **推荐项目**: https://github.com/55gY/tdl-msgproce
- **go-TelegramMessage**: https://github.com/55gY/go-TelegramMessage
- **tdl**: https://github.com/iyear/tdl
