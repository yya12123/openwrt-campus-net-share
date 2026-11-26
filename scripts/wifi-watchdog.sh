#!/bin/sh
# WiFi 客户端链路看门狗
#
# 背景：为了让客户端稳定连在某一个 AP 上，我们钉死了 BSSID（wireless.wwan1.bssid）。
#       副作用是那个 AP 挂了以后路由器不会自动漫游，必须有人把它拉回来。
#
# 逻辑：关联丢失 → reload 无线；
#       重连仍失败 → 自动删掉 BSSID 钉死，恢复自动漫游。
#
# 建议 cron: */5 * * * * /usr/bin/wifi-watchdog

STA_IFACE="${STA_IFACE:-$(uci get wireless.wwan1.device 2>/dev/null | xargs -I{} uci get wireless.{}.ifname 2>/dev/null)}"
STA_IFACE="${STA_IFACE:-phy1-sta0}"
LOG=/var/log/portal.log

info=$(iwinfo "$STA_IFACE" info 2>/dev/null)
if echo "$info" | grep -q "ESSID:"; then
    exit 0
fi

echo "$(date '+%F %T') [wifi] $STA_IFACE 关联丢失，reload 无线" >>"$LOG"
wifi reload >/dev/null 2>&1
sleep 20

if iwinfo "$STA_IFACE" info 2>/dev/null | grep -q "ESSID:"; then
    echo "$(date '+%F %T') [wifi] reload 后已恢复" >>"$LOG"
    /usr/bin/portal-login quiet >/dev/null 2>&1
else
    echo "$(date '+%F %T') [wifi] reload 失败，取消 BSSID 钉死" >>"$LOG"
    uci -q delete wireless.wwan1.bssid
    uci commit wireless
    wifi reload >/dev/null 2>&1
fi
