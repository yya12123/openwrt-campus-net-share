# 方法 B：纯手搓版（从 Breed 到可用，含原理）

> 适合：想搞清楚每一步在做什么；愿意花一两个晚上；看得懂 shell 和日志。
> 全流程约 10 个阶段，建议**每完成一段就验收一次**，别一口气全做完。

---

## 0. 前提与风险（先读）

**你需要准备：**

- 小米 AC2100（R2100）或红米 AC2100（RM2100），已刷 Breed 引导
- 一台电脑 + 网线（刷机阶段必须用网线，不能用 WiFi）
- 校园网账号（能正常登录）
- 半小时到一小时的不被打断的时间

**风险：**

> 刷 Bootloader 和写分区都可能**变砖**。断电、刷错镜像、用错布局都可能救不回来
> （需要拆机接编程器）。**动手前请完整备份整片 flash 和 EEPROM，并确认自己能承担后果。**

**本文的命令默认：**

- 路由器地址 `192.168.1.1`
- STA 客户端接口名 `phy1-sta0`（不同固件可能不同，用 `iwinfo` 确认）
- 认证服务器 `10.0.0.1`（**换成你自己的**）
- 校园 SSID、账号、密码全部是占位符

---

## 1. 刷机：从 Breed 到 OpenWrt

### 1.1 确认 Breed 版本

断电 → 按住 Reset → 插电 → 灯闪 5~8 秒后松手 → 浏览器开 `192.168.1.1`。

**版本必须是 r1416（2022-07-24）或更新**。旧版本的问题是：

- 没有「小米 R3G OpenWrt」这个闪存布局选项
- 引导不了 24.10 的内核

查看：Breed 首页的「修订信息」。升级：`固件更新 → Bootloader`（这一步**不能断电**）。

### 1.2 备份（必做）

Breed 的「固件备份」页可以导出：

- **EEPROM**（几十 KB）：里面是这台机器的 MAC 和无线校准数据，**丢了很麻烦**
- **整片 flash**（128MB）：最后的救命稻草

### 1.3 刷入

准备两个文件（OpenWrt 官方下载，型号选 `xiaomi_mi-router-ac2100`）：

```
openwrt-<版本>-ramips-mt7621-xiaomi_mi-router-ac2100-squashfs-kernel1.bin
openwrt-<版本>-ramips-mt7621-xiaomi_mi-router-ac2100-squashfs-rootfs0.bin
```

Breed 页面操作：

1. 「固件更新」→ **闪存布局选「小米 R3G OpenWrt」**
2. 会出现**两个**上传框：`kernel1` 传第一个文件，`rootfs0` 传第二个
3. 上传 → 确认 → 更新 → 等它写完自动重启

> **两个致命坑：**
> 1. **不要刷 `-squashfs-sysupgrade.bin`** —— Breed 不认这个布局，刷完无限重启。
>    `sysupgrade.bin` 只在**已经跑起 OpenWrt 之后**、在 LuCI 里升级时用。
> 2. 如果刷完起不来（无限重启），进 Breed 的「环境变量」设置
>    `xiaomi.r3g.bootfw = 2` 并保存 —— 这是告诉 Breed"从 kernel1 启动"。

### 1.4 首次启动

等 2~3 分钟，电脑 IP 改回自动获取，浏览器开 `192.168.1.1`（LuCI）。

> **OpenWrt 默认不开 WiFi**，别以为刷坏了，先用网线。

进去第一件事：**设置 root 密码**（系统 → 管理权），然后改中文界面。

---

## 2. 系统基础

```sh
# SSH 登录（首次无密码时可以直接 ssh，或用刚设的密码）
ssh root@192.168.1.1

# 时区 / 主机名
uci set system.@system[0].hostname='Campus-Router'
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci commit system

# 确认有 curl（后面脚本要用）
opkg update && opkg install curl
```

**建议同时装 SSH 公钥**，避免空密码/密码改动后进不去：

```sh
# 本机
ssh-keygen -t ed25519 -N "" -f ./router_key
cat router_key.pub | ssh root@192.168.1.1 \
  'mkdir -p /etc/dropbear && cat > /etc/dropbear/authorized_keys && chmod 600 /etc/dropbear/authorized_keys'
```

---

## 3. 无线：客户端 + 热点

### 3.1 分工

这台机器有两个射频（2.4G + 5G）。推荐：

| 射频 | 角色 | 理由 |
|---|---|---|
| 5G | **STA**（连学校 AP） | 信道宽、干扰少、客户端链路质量最好 |
| 2.4G | **AP**（给宿舍用） | 覆盖好，给手机/笔记本够用 |

### 3.2 先扫描，别瞎选

```sh
iwinfo phy1 scan | grep -E "ESSID|Channel|Signal"
```

记下每个候选 AP 的：**BSSID、信道、信号强度**。

### 3.3 配置 STA

```sh
# 5G 射频做客户端
uci set wireless.radio1.channel='auto'
uci set wireless.radio1.htmode='VHT80'
uci set wireless.wwan1=wifi-iface
uci set wireless.wwan1.device='radio1'
uci set wireless.wwan1.network='wwan'
uci set wireless.wwan1.mode='sta'
uci set wireless.wwan1.ssid='你的校园SSID'
uci set wireless.wwan1.encryption='none'          # 开放网络；若是 WPA2 换成 psk2 + key
uci set wireless.wwan1.disabled='0'

# 建 wwan 接口，走 DHCP
uci set network.wwan=interface
uci set network.wwan.proto='dhcp'

# 加进防火墙 wan 区
uci add_list firewall.@zone[1].network='wwan'
uci commit wireless && uci commit network && uci commit firewall
wifi reload
```

验证：

```sh
iwinfo phy1-sta0 info | grep -E "ESSID|Channel|Signal|Bit Rate"
ifstatus wwan | grep -E '"up"|"address"'
```

> **如果拿不到 IP**：检查校园网是不是需要 802.1X（企业认证）。
> 开放 SSID + 网页认证是最好办的一种；企业认证要另外配 `wpa_supplicant` 的 EAP 参数。

### 3.4 判断这个 AP 到底好不好（核心方法论）

**信号强 ≠ 好用。** 必须看**重传率**：

```sh
snap() { iw dev phy1-sta0 station dump | awk '/tx packets/{p=$3} /tx retries/{r=$3} END{print p" "r}'; }

a=$(snap); sleep 60; b=$(snap)
echo "$a $b" | awk '{dp=$3-$1; dr=$4-$2; printf "重传率 %.1f%% (tx=%d)\n", dr*100/dp, dp}'
```

判读：

| 重传率 | 结论 |
|---|---|
| < 8% | 好 |
| 8~15% | 一般，游戏会偶尔卡 |
| > 20% | 差，换 AP |

实战数据（同一位置的两个 AP）：

```
ch149 的 AP，-23 dBm，重传率 43.3%  ← 信号最强，但整层楼都连它
ch157 的 AP，-49 dBm，重传率  7.5%  ← 信号弱一些，反而好用
```

**所以：优先选"信号够用且重传率低"的 AP，而不是信号最强的那个。**

### 3.5 钉死 BSSID（防止乱漫游）

```sh
uci set wireless.wwan1.bssid='AA:BB:CC:DD:EE:FF'
uci commit wireless && wifi reload
```

副作用：那个 AP 挂了不会自动漫游。用 [wifi-watchdog.sh](../scripts/wifi-watchdog.sh) 兜底。

### 3.6 钉死客户端 MAC（很重要，关系到"设备名额"）

OpenWrt 默认会给 STA **随机生成 MAC**（首字节带本地管理位，如 `2a:...`）。
每次重连都变 → 学校会把它当成**一台新设备**，反复消耗设备名额。

```sh
# 用设备真实的 WAN 口 MAC（看 EEPROM 或机身标签）
uci set wireless.wwan1.macaddr='AA:BB:CC:DD:EE:FF'
uci commit wireless && wifi reload
cat /sys/class/net/phy1-sta0/address      # 确认已固定
```

### 3.7 开 AP 给宿舍

```sh
uci set wireless.radio0.channel='6'        # 先用扫描确认哪个信道最空
uci set wireless.radio0.htmode='HT20'
uci set wireless.radio0.disabled='0'
uci set wireless.default_radio0.ssid='Dorm-WiFi'
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.default_radio0.key='你的WiFi密码'
uci set wireless.default_radio0.disabled='0'
uci commit wireless && wifi reload
```

**2.4G 选信道**：扫描后统计每个信道的 AP 数，选 1/6/11 里最少的那个。

```sh
iwinfo phy0 scan | grep -oE "Channel: [0-9]+" | awk '{print $2}' | sort -n | uniq -c
```

> 实战数据：某次信道 1 上有 **56 个 AP**，信道 6 只有 24 个 —— 换一下立竿见影。

---

## 4. 校园网认证（锐捷 eportal）

### 4.1 先搞清是哪种 Portal

路由器已经连上校园网、拿到 IP，但访问网页会被劫持。执行：

```sh
curl -s -m 10 http://www.baidu.com
```

看返回内容：

- 返回一段 `<script>top.self.location.href='http://x.x.x.x/eportal/index.jsp?...'</script>`
  → **锐捷 eportal**（本文覆盖）
- 跳到 `/srun_portal` 之类 → 深澜
- 跳到 `drcom` → Dr.COM
- 跳到 `eportal` 但路径不同 → 也是锐捷，参数可能不同

### 4.2 找登录接口

瑞捷的登录页会加载 `AuthInterFace.js`，里面把接口写得很清楚：

```sh
curl -s http://<认证服务器>/eportal/interface/index_files/js/AuthInterFace.js
```

里面能看到：

```js
Url = url + "InterFace.do?method="
Url + "login"
Url + "keepalive"
Url + "logout"
Url + "pageInfo"
```

登录表单字段（从 `index.jsp` 里 grep `name=`）：

```
userId / password / service / queryString /
operatorUserId / operatorPwd / validcode / passwordEncrypt
```

### 4.3 用 pageInfo 探明规则（不需要账号）

```sh
# 先拿一次重定向里的 queryString
BODY=$(curl -s -m 10 http://www.baidu.com)
URL=$(printf '%s' "$BODY" | tr -d '\r\n' | grep -o "http://[0-9.]*/eportal/index\.jsp[^']*" | head -1)
QS="${URL#*\?}"
ENC=$(printf '%s' "$QS" | sed 's/&/%26/g; s/=/%3D/g')

curl -s -H "Referer: $URL" \
  "http://<认证服务器>/eportal/InterFace.do?method=pageInfo&queryString=$ENC"
```

返回的 JSON 里重点看三个字段：

| 字段 | 含义 | 处理 |
|---|---|---|
| `passwordEncrypt` | `"false"` 表示密码明文提交 | 直接传密码 |
| `"true"` | 需要 RSA 加密 | 要用 `publicKeyExponent/Modulus` 加密，复杂度上一档 |
| `service` | `{}` 表示没有套餐选择 | 传空 |
| `validCodeUrl` | 空表示没有验证码 | 传空 |

### 4.4 登录

```sh
curl -s -b /tmp/ck -c /tmp/ck \
  -H "Referer: $URL" -H "User-Agent: Mozilla/5.0" \
  --data-urlencode "userId=<学号>" \
  --data "password=<密码>" \
  --data "service=" \
  --data "queryString=$ENC" \
  --data "operatorPwd=" \
  --data "operatorUserId=" \
  --data "validcode=" \
  --data "passwordEncrypt=false" \
  "http://<认证服务器>/eportal/InterFace.do?method=login"
```

成功返回：

```json
{"userIndex":"...","result":"success","keepaliveInterval":0}
```

> `keepaliveInterval` 为 0 表示不需要心跳，靠流量维持会话。

### 4.5 脚本化 + 看门狗

直接使用 [scripts/portal-login.sh](../scripts/portal-login.sh)：

```sh
# 部署
scp scripts/portal-login.sh root@192.168.1.1:/usr/bin/portal-login
ssh root@192.168.1.1 'chmod +x /usr/bin/portal-login'

# 配置（注意权限）
ssh root@192.168.1.1 'cat > /etc/portal.conf' <<'EOF'
PORTAL_HOST="10.0.0.1"
PORTAL_USER="你的学号"
PORTAL_PASS="你的密码"
PROBE_URL="http://www.baidu.com"
EOF
ssh root@192.168.1.1 'chmod 600 /etc/portal.conf'

# 测试
ssh root@192.168.1.1 '/usr/bin/portal-login force'

# 看门狗：每 2 分钟检查一次
ssh root@192.168.1.1 'echo "*/2 * * * * /usr/bin/portal-login" >> /etc/crontabs/root
                          /etc/init.d/cron restart'
```

脚本内置了**失败退避**：连续失败 3 次后暂停 30 分钟，避免密码错时把账号撞锁。

### 4.6 改密码之后必做

```sh
printf 'PORTAL_HOST="..."\nPORTAL_USER="..."\nPORTAL_PASS="新密码"\n' > /etc/portal.conf
/usr/bin/portal-login force      # 验证新密码真的能用
```

> **坑**：改密码**不会**让学校踢掉已建立的会话。所以路由器可能还靠旧会话活着，
> 一旦掉线才发现新密码是错的 —— 必须主动 `force` 验证一次。

---

## 5. 防共享检测：UA3F

### 5.1 原理

学校的检测手段通常有：TTL、User-Agent、IPID、时钟偏移、DPI。
UA3F 的做法是：**把局域网所有 TCP 流量劫持到本机的一个代理**，
解析出 HTTP 后统一改写 `User-Agent`，同时顺手改 TTL。

因为它工作在"代理"层，所以和 Clash 这类工具能共存（UA2F 的 iptables 方案就不行）。

### 5.2 装

```sh
opkg update
opkg install kmod-nft-queue kmod-nft-tproxy
# 再装 UA3F 的 ipk（按架构选，MT7621 是 mipsel_24kc）
# 从 https://github.com/SunBK201/UA3F/releases 下载对应架构的 .ipk
opkg install ./ua3f_<版本>_mipsel_24kc.ipk
```

### 5.3 一定要用 REDIRECT 模式

```sh
uci set ua3f.enabled.enabled='1'
uci set ua3f.main.server_mode='REDIRECT'      # ← 关键
uci set ua3f.main.l3_rewrite_ttl='1'
uci set ua3f.main.l3_rewrite_ttl_value='64'
uci commit ua3f
/etc/init.d/ua3f enable && /etc/init.d/ua3f restart
```

> **为什么不能用 TPROXY**：它会把转发流量 tproxy 到 `127.0.0.1:1080`，
> 而回环地址在转发路径上不是合法目标，包直接死掉 —— **客户端全部断网**。
> 表现为 `tracert` 第二跳就"目标协议不可达"。

验证：

```sh
nft list tables | grep -i ua3f          # 应有两张表
curl -s http://httpbin.org/user-agent   # 从局域网设备访问，看 UA 是否被改写
```

### 5.4 必须做的补丁：P2P 端口绕过

**这是本仓库最值钱的一条经验。** UA3F 会把**所有** TCP 拉进用户态，
而游戏启动器 / B 站 PCDN 会向成百上千个随机节点发起连接（大多连不上），
每条都占一个 fd 等超时：

| 指标 | 被 P2P 打爆时 | 正常 |
|---|---|---|
| UA3F fd 数 | 1767 ~ 2205 | < 300 |
| 内存可用 | 6.5 MB | > 15 MB |
| 负载（2 核） | 5.08 | < 0.5 |

内存耗尽后触发 OOM，**整机卡死**（表现为网页转圈、视频卡、SSH 都慢）。

修法：把 P2P 端口从 UA3F 里摘出去。

```sh
# 部署 scripts/ua3f-bypass.sh 后
/usr/bin/ua3f-bypass
nft list chain inet UA3F PREROUTING | head -3   # 应看到 tcp dport 27000-27100 ... return
```

配 cron 每 5 分钟补一次（UA3F 重启会重建 nft 表）：

```sh
echo "*/5 * * * * /usr/bin/ua3f-bypass" >> /etc/crontabs/root
```

### 5.5 千万不要这样停 UA3F

```sh
# ❌ 全是错误示范
/etc/init.d/ua3f stop
/etc/init.d/ua3f disable
nft delete table inet UA3F
```

实测：停掉服务后，已建立的连接全部指向一个已关闭的本地端口，
**局域网内所有设备立刻断网**，而且远端无法恢复，必须人到路由器跟前重启服务。

> 唯一允许的操作是 `/etc/init.d/ua3f restart`，且**必须人在现场**。

---

## 6. 防火墙：那个让 UDP 全废的坑

### 6.1 现象

网页、下载、视频都正常，但是：

- `ping` 公网不通
- **所有游戏、语音、加速器全废**（它们走 UDP）
- 加速器显示"无法识别网络"或 100% 丢包

### 6.2 根因

上行是 WiFi 客户端接口（`phy1-sta0`），而 `fw4` 生成的规则里
如果只写了物理网口 `oifname "wan"`，就匹配不上。

**为什么 TCP 还能用？** 因为 UA3F 把 TCP 重定向到本机，走的是 `INPUT` 链，
根本不需要 `FORWARD` 规则 —— **它把这个问题完美掩盖了**。

### 6.3 验证与修复

```sh
nft list ruleset | grep -c phy1-sta0        # 返回 0 就是中招
nft list ruleset | grep -A2 accept_to_wan   # 应看到 oifname { "wan", "phy1-sta0" }
```

修复：

```sh
fw4 reload
```

持久化：装 [99-wwan-fw4-reload](../scripts/99-wwan-fw4-reload)，
在 wwan 接口 up 后自动重载（**否则每次重启都会复发**）。

```sh
cp scripts/99-wwan-fw4-reload /etc/hotplug.d/iface/
chmod +x /etc/hotplug.d/iface/99-wwan-fw4-reload
```

---

## 7. DNS 分流：解决"网页打开慢"

### 7.1 现象

网页要转圈 1~3 秒，但测速、ping、下载都正常。实测首字节：

```
京东 2.64s / 知乎 2.13s / 淘宝 1.53s
```

### 7.2 根因

学校 DNS 返回的 CDN 节点在几百公里外：

| 站点 | 学校 DNS | 延迟 | 公共 DNS | 延迟 |
|---|---|---|---|---|
| 淘宝 | ... | 82.9 ms | ... | 14.3 ms |
| 知乎 | ... | 65~148 ms | ... | 10.4 ms |

TLS 握手要 2~3 个 RTT，这点延迟被放大成一两秒。

### 7.3 配置

```sh
uci set dhcp.@dnsmasq[0].noresolv='1'
uci -q delete dhcp.@dnsmasq[0].server
uci add_list dhcp.@dnsmasq[0].server='223.5.5.5'
uci add_list dhcp.@dnsmasq[0].server='119.29.29.29'
# 校内域名仍然走校园 DNS
uci add_list dhcp.@dnsmasq[0].server='/你的学校域名/10.0.0.53'
# 关键：校内域名常解析到私网地址，会被防重绑保护拦下
uci add_list dhcp.@dnsmasq[0].rebind_domain='你的学校域名'
uci commit dhcp && /etc/init.d/dnsmasq restart
```

> **`rebind_domain` 不能省**：不加的话，校内域名会解析失败
> （日志：`possible DNS-rebind attack detected`），自助服务页打不开。

改完客户端要 `ipconfig /flushdns`。

---

## 8. 稳定性

### 8.1 三个看门狗

| 脚本 | 频率 | 作用 |
|---|---|---|
| `portal-login` | 每 2 分钟 | 认证掉了自动重登 |
| `wifi-watchdog` | 每 5 分钟 | STA 关联丢了自动找回 |
| `ua3f-bypass` | 每 5 分钟 | UA3F 重启后补 P2P 绕过规则 |

```sh
cat /etc/crontabs/root
# */2 * * * * /usr/bin/portal-login
# */5 * * * * /usr/bin/wifi-watchdog
# */5 * * * * /usr/bin/ua3f-bypass
# * * * * * /usr/bin/net-monitor
```

### 8.2 质量监控

`net-monitor.sh` 每分钟采样一次网关和公网延迟，只在异常时写日志：

```sh
tail -30 /var/log/net-quality.log
# 2026-11-21 23:10:11 gw=2.730/45.269/151.541 wan=... [SPIKE]
```

有了它，"刚才是不是真的卡"就从主观变成可回溯。

### 8.3 国际线路提速（可选）

UA3F 是终结式代理，所以"路由器 ↔ 远端"这一段的 TCP 参数**由路由器决定**。
默认 `cubic` + 176KB 缓冲在国际线路上很差：

```sh
opkg install kmod-tcp-bbr
cp scripts/99-speed.conf /etc/sysctl.d/
sysctl -p /etc/sysctl.d/99-speed.conf
```

实测某游戏启动器（欧洲源）下载：2.73 MB/s → 5.35 MB/s。

> 注意：BBR 对**国内** CDN 的提升不明显，主要收益在长肥管道（高 RTT × 高带宽）。

---

## 9. 设备名额策略（如果学校限 N 台）

很多学校限制"每个账号 N 台设备"（常见 2 台）。分配原则：

| 占名额 | 设备 | 说明 |
|---|---|---|
| 1 | 路由器（STA 客户端） | MAC 必须钉死，否则每次重连都算新设备 |
| 2 | 你的手机（直连校园网） | 追求最低延迟 |
| 不占 | 电脑、室友设备 | 藏在路由器 NAT 后面，学校只看到 1 个 MAC |

要点：

1. **STA 的 MAC 必须固定**（见 3.6），否则名额会被反复吃掉，且查不出原因
2. **路由器占掉的那 1 个名额，背后可以挂无限台设备** —— 这正是共享的原理
3. 手机直连校园网 vs 连路由器：直连抖动更低（实测 14ms vs 44ms），但占名额
4. 别让第三台设备去直连校园网，会超限

---

## 10. 最终验收清单

```sh
# 认证
/usr/bin/portal-login status                      # ONLINE

# 全协议
ping -c 3 223.5.5.5                               # 通
nft list ruleset | grep -c phy1-sta0              # > 0

# UA 改写
curl -s http://httpbin.org/user-agent             # 不是原始 UA

# 设备数（去学校自助服务页确认只占 1 个）

# 稳定性
cat /proc/loadavg                                 # < 0.5
ls /proc/$(pgrep -f "^/usr/bin/ua3f" | head -1)/fd | wc -l   # < 300
free -m                                           # 可用 > 10MB
```

---

## 想省事？

回到 [方法 A：AI 辅助版](method-a-ai-assisted.md)，把人要做的事压缩到"执行 + 验收"。
遇到问题先去 [排错手册](troubleshooting.md)。
