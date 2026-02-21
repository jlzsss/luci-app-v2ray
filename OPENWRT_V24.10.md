# luci-app-v2ray OpenWrt v24.10 适配说明

## 版本信息
- 当前版本: 3.2.0
- 适配 OpenWrt 版本: v24.10+

## 主要变更

### 1. 依赖项更新
- 添加了 `luci-compat` 依赖，用于兼容 OpenWrt v24.10 的新 LuCI 架构
- 保留了所有原有依赖项

### 2. 防火墙后端支持
- 完整支持 **nftables** 和 **iptables**
- 自动检测系统使用的防火墙后端
- 支持手动选择防火墙后端：
  - Auto（自动检测）
  - iptables
  - nftables

### 3. 新增协议支持
- WireGuard 协议完整支持
  - 入站配置（WireGuard 服务器）
  - 出站配置（WireGuard 客户端）
  - 支持多对等点配置
  - 所有 WireGuard 标准配置项

### 4. 现有功能
- VLESS 协议支持
- Trojan 协议支持
- XTLS 安全选项
- Reality 安全选项
- XRay 核心选择
- 完整的透明代理支持

## 防火墙后端说明

### nftables 支持
- OpenWrt v24.10 默认防火墙
- 更现代的防火墙框架
- 更好的性能和安全性
- 原生支持 IPv4/IPv6 双栈

### iptables 支持
- 传统防火墙框架
- 通过 iptables-nft 兼容层在 nftables 系统上运行
- 保持向后兼容性

### 配置方式
1. **自动模式（推荐）**：系统自动检测并使用当前系统的防火墙后端
2. **手动选择**：在 LuCI 界面中手动选择 nftables 或 iptables

## 编译安装

### 使用 GitHub Actions 编译
项目包含两个工作流：

1. **build.yml** - 完整编译
   - 使用 OpenWrt v24.10 SDK
   - 支持多种架构
   - 自动发布 Release

2. **fast-build.yml** - 快速编译
   - 通用架构包构建
   - 适合快速测试

### 本地编译
```bash
# Linux/macOS
./build.sh

# Windows
build.bat
```

### OpenWrt SDK 编译
```bash
# 进入 OpenWrt SDK 目录
cd openwrt-sdk

# 添加软件包
mkdir -p package/luci-app-v2ray
cp -r /path/to/luci-app-v2ray/* package/luci-app-v2ray/

# 更新 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 配置
make menuconfig
# 选择 LuCI -> Applications -> luci-app-v2ray

# 编译
make package/luci-app-v2ray/compile V=s
```

## 安装使用

### 安装依赖
```bash
opkg update
opkg install luci-compat
```

### 安装软件包
```bash
opkg install luci-app-v2ray_3.2.0-1_all.ipk
```

### 配置
1. 登录 LuCI 管理界面
2. 进入 Services -> V2Ray
3. 配置核心类型（V2Ray/XRay）
4. **选择防火墙后端**（Auto/nftables/iptables）
5. 添加入站/出站规则
6. 启用服务

## 兼容性说明

### 防火墙兼容性
- OpenWrt v24.10 默认使用 nftables
- 本项目同时支持 nftables 和 iptables
- 自动检测系统使用的防火墙后端
- 透明代理功能在两种防火墙上都完全正常

### LuCI 兼容性
- 通过 luci-compat 确保与新 LuCI 架构兼容
- 所有原有功能保持不变

## 文件结构
```
luci-app-v2ray/
├── Makefile                          # 包构建配置
├── build.sh                          # Linux/macOS 快速编译脚本
├── build.bat                         # Windows 快速编译脚本
├── luasrc/                           # LuCI 源代码
│   ├── controller/
│   ├── model/
│   └── view/
├── root/                             # 根文件系统
│   ├── etc/
│   │   ├── config/
│   │   ├── init.d/
│   │   ├── uci-defaults/
│   │   └── v2ray/
│   └── usr/
├── po/                               # 翻译文件
└── .github/
    └── workflows/
        ├── build.yml                 # 完整编译工作流
        └── fast-build.yml            # 快速编译工作流
```

## 更新日志

### v3.2.0
- 新增完整的 nftables 防火墙支持
- 新增防火墙后端选择选项（Auto/nftables/iptables）
- 自动检测系统防火墙后端
- 保持 iptables 兼容性
- 更新版本号到 3.2.0

### v3.1.0
- 新增 WireGuard 协议完整支持
- 更新版本号
- 优化 OpenWrt v24.10 兼容性

### v3.0.0
- 适配 OpenWrt v24.10
- 添加 luci-compat 依赖
- 新增 VLESS、Trojan、XTLS、Reality 支持
- 新增 XRay 核心选择

## 技术支持
如有问题，请访问项目主页或提交 Issue。
