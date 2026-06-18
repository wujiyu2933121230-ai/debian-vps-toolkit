# debian-vps-toolkit

Debian VPS 初始化工具包

## 一键初始化 VPS

```bash
bash <(curl -s https://raw.githubusercontent.com/wujiyu2933121230-ai/debian-vps-toolkit/main/modules/00_init.sh)
```

包含：系统更新 → 安装基础工具 → 系统清理 → 配置 Swap → 设置时区 → 优化 DNS → IPv4 优先

## 一键安装 AnyTLS-go

```bash
bash <(curl -s https://raw.githubusercontent.com/wujiyu2933121230-ai/debian-vps-toolkit/main/proxy/anytls-go.sh)
```

## 一键安装 Hysteria 2

```bash
bash <(curl -s https://raw.githubusercontent.com/wujiyu2933121230-ai/debian-vps-toolkit/main/proxy/hysteria2.sh)
```

包含：环境检测 → 自动获取 IP → 交互配置 → AVX 检测下载 → 自签证书 + 指纹固定 → 端口跳跃 iptables → systemd 服务 → 输出 mihomo/URI 客户端配置

## SSH 管理

```bash
bash <(curl -s https://raw.githubusercontent.com/wujiyu2933121230-ai/debian-vps-toolkit/main/modules/01_ssh.sh)
```

功能：修改 SSH 端口、开启/关闭密码登录、修改密码、开启/关闭密钥登录、添加/查看公钥
