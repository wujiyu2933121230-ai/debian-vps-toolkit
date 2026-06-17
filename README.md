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

## SSH 管理

```bash
bash <(curl -s https://raw.githubusercontent.com/wujiyu2933121230-ai/debian-vps-toolkit/main/modules/01_ssh.sh)
```

功能：修改 SSH 端口、开启/关闭密码登录、修改密码、开启/关闭密钥登录、添加/查看公钥
