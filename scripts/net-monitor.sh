#!/bin/sh
# 链路质量采样：每分钟测一次网关和公网延迟，只在异常时写日志
#
# 目的：把"卡"从主观感受变成可回溯的数据。
#       事后能回答"刚才那个时间点到底有没有尖峰"，而不是只靠印象。
#
# 建议 cron: * * * * * /usr/bin/net-monitor
# 查看:      tail -30 /var/log/net-quality.log

LOG=/var/log/net-quality.log
GW="${GW_ADDR:?请设置 GW_ADDR，例如你的校园网网关}"
WAN="${WAN_ADDR:-223.5.5.5}"
THRESHOLD="${SPIKE_MS:-50}"

touch "$LOG" 2>/dev/null

probe() {
    r=$(ping -c 5 -W 1 "$1" 2>/dev/null | grep -oE "min/avg/max = [0-9./]+")
    if [ -z "$r" ]; then
        echo "LOSS"
    else
        echo "${r#min/avg/max = }"
    fi
}

g=$(probe "$GW")
w=$(probe "$WAN")
ts=$(date '+%F %T')

gmax=$(echo "$g" | awk -F/ '{print $3}')
wmax=$(echo "$w" | awk -F/ '{print $3}')

flag=""
if [ "$g" = "LOSS" ] || [ "$w" = "LOSS" ]; then
    flag=" [LOSS]"
elif [ -n "$gmax" ] && [ -n "$wmax" ]; then
    if awk -v a="$gmax" -v b="$wmax" -v t="$THRESHOLD" \
         'BEGIN{exit !(a>t || b>t)}'; then
        flag=" [SPIKE]"
    fi
fi

# 只记异常；每小时整点补一条基线
if [ -n "$flag" ] || [ "$(date +%M)" = "00" ]; then
    echo "$ts gw=$g wan=$w$flag" >>"$LOG"
fi

# 控制体积：超过 2000 行只留最近 1000 行
lines=$(wc -l <"$LOG" 2>/dev/null || echo 0)
if [ "$lines" -gt 2000 ]; then
    tail -1000 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi
