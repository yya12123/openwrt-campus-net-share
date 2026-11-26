#!/bin/sh
# 让 P2P / 游戏端口绕过 UA3F 的用户态转发
#
# 背景（本仓库最重要的一条教训）：
#   游戏启动器、B 站 PCDN 这类软件会向成百上千个随机节点发起 TCP 连接，
#   绝大多数对方不回、卡在 SYN_SENT。UA3F 是"终结式"代理，会把每条连接
#   都拉进用户态去 dial，对方不回就一直等 —— 几小时内堆积上千个 fd、
#   把 128MB 的路由器 OOM 掉，整机卡死。
#
#   这些端口的流量不需要 UA 改写（UA 改写只对明文 HTTP 有意义），
#   直接在 UA3F 的 nft 链最前面插一条 return，让它们走正常 NAT。
#
# 建议 cron: */5 * * * * /usr/bin/ua3f-bypass
# 原因：UA3F 重启/重载会重建自己的 nft 表，这条规则会被冲掉。

TABLE="UA3F"
CHAIN="PREROUTING"
PORTS="${BYPASS_PORTS:-27000-27100}"
LOG=/var/log/net-quality.log

nft list table inet "$TABLE" >/dev/null 2>&1 || exit 0

if nft list chain inet "$TABLE" "$CHAIN" 2>/dev/null | grep -q "$PORTS"; then
    exit 0
fi

if nft insert rule inet "$TABLE" "$CHAIN" tcp dport "$PORTS" counter return 2>/dev/null; then
    echo "$(date '+%F %T') [BYPASS] 插入 P2P 端口绕过规则 tcp dport $PORTS" >>"$LOG"
fi
