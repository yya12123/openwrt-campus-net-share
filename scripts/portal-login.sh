#!/bin/sh
# 锐捷 eportal 自动认证 / 掉线重连
#
# 用法:
#   portal-login           检测并登录（给 cron 用）
#   portal-login status    只看状态
#   portal-login force     先主动登出，再用当前配置重新登录（改密码后验证用）
#   portal-login logout    只退出当前会话
#
# 依赖: curl（opkg install curl）
# 配置: /etc/portal.conf（权限 600）

CONF=/etc/portal.conf
LOG=/var/log/portal.log
STATE=/tmp/portal.fail
COOKIE=/tmp/portal.cookie

log() { echo "$(date '+%F %T') $*" >>"$LOG"; }
[ -f "$CONF" ] || { log "缺少 $CONF"; exit 1; }
. "$CONF"

# ---- 必填项检查 ----
[ -n "$PORTAL_HOST" ] || { log "PORTAL_HOST 未设置"; exit 1; }
[ -n "$PORTAL_USER" ] || { log "PORTAL_USER 未设置"; exit 1; }
PROBE="${PROBE_URL:-http://www.baidu.com}"
BASE="http://${PORTAL_HOST}/eportal"

last_userindex() {
    grep -o '"userIndex":"[^"]*"' "$LOG" 2>/dev/null | tail -1 | sed 's/.*:"//;s/"$//'
}

do_logout() {
    ui=$(last_userindex)
    if [ -z "$ui" ]; then
        log "logout: 日志里没有 userIndex"
        return 1
    fi
    r=$(curl -s -m 15 --data-urlencode "userIndex=$ui" \
        "$BASE/InterFace.do?method=logout" 2>/dev/null)
    log "logout resp: $r"
    printf '%s\n' "$r"
}

case "$1" in
    logout) do_logout; exit 0 ;;
    force)
        log "=== force: 先登出再登录 ==="
        do_logout >/dev/null 2>&1
        rm -f "$STATE"
        sleep 3
        ;;
esac

# ---- 判断是否需要认证：被劫持到 Portal 就说明没登录 ----
BODY=$(curl -s -m 10 "$PROBE" 2>/dev/null)
URL=$(printf '%s' "$BODY" | tr -d '\r\n' \
      | grep -o "http://[0-9.]*/eportal/index\.jsp[^']*" | head -1)

if [ -z "$URL" ]; then
    log "already online"
    [ "$1" = "status" ] && echo "ONLINE"
    exit 0
fi
if [ "$1" = "status" ]; then
    echo "OFFLINE（出现 Portal 重定向）"
    exit 0
fi

QS="${URL#*\?}"
case "$QS" in
    *wlanuserip*) ;;
    *) log "重定向格式不认识: $URL"; exit 1 ;;
esac
# queryString 要整体 URL 编码后再作为表单字段提交
ENC=$(printf '%s' "$QS" | sed 's/&/%26/g; s/=/%3D/g')

# ---- 失败退避：避免密码错时每两分钟撞一次导致账号被锁 ----
if [ -f "$STATE" ]; then
    FAILS=$(cat "$STATE" 2>/dev/null)
    LASTS=$(stat -c %Y "$STATE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    case "$FAILS" in ''|*[!0-9]*) FAILS=0 ;; esac
    if [ "$FAILS" -ge 3 ] && [ $((NOW - LASTS)) -lt 1800 ]; then
        log "退避中（已失败 $FAILS 次），跳过"
        exit 0
    fi
else
    FAILS=0
fi

# ---- 先取一次首页拿 Cookie，再提交登录 ----
rm -f "$COOKIE"
curl -s -m 15 -c "$COOKIE" -H "User-Agent: Mozilla/5.0" "$URL" -o /dev/null 2>/dev/null

RESP=$(curl -s -m 20 -b "$COOKIE" -c "$COOKIE" \
    -H "Referer: $URL" -H "User-Agent: Mozilla/5.0" \
    -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
    --data-urlencode "userId=$PORTAL_USER" \
    --data "password=$PORTAL_PASS" \
    --data "service=" \
    --data "queryString=$ENC" \
    --data "operatorPwd=" \
    --data "operatorUserId=" \
    --data "validcode=" \
    --data "passwordEncrypt=false" \
    "$BASE/InterFace.do?method=login" 2>/dev/null)
log "login resp: $RESP"

case "$RESP" in
    *'"result":"success"'*)
        rm -f "$STATE"
        log "登录成功"
        [ "$1" != "status" ] && echo "LOGIN SUCCESS" ;;
    *)
        echo $((FAILS + 1)) >"$STATE"
        log "登录失败"
        echo "LOGIN FAILED: $RESP" ;;
esac

sleep 2
BODY2=$(curl -s -m 10 "$PROBE" 2>/dev/null)
if printf '%s' "$BODY2" | grep -q "eportal/index.jsp"; then
    log "复核：仍然离线"
    echo "VERIFY: STILL OFFLINE"
else
    log "复核：在线"
    echo "VERIFY: ONLINE OK"
fi
