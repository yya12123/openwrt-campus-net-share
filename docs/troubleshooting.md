# 排错手册：18 个真实故障

> 全部来自实际部署过程，**每条都包含"现象 → 根因 → 验证命令 → 处置"**。
> 建议：卡住时先按"现象"在表里找，别从第一条开始读。

---

## 速查表

| # | 现象 | 根因 | 跳到 |
|---|---|---|---|
| 1 | Breed 里刷 Bootloader 报"无效" | 刷错槽位 / 传了 OpenWrt 镜像 | [1](#1-breed-刷-bootloader-报无效) |
| 2 | 刷完无限重启 | 没设 `bootfw=2` / 刷了 sysupgrade | [2](#2-刷完无限重启) |
| 3 | 老毛子网页"固件升级"刷不进 OpenWrt | 镜像头不匹配 | [3](#3-老毛子刷不进-openwrt) |
| 4 | 电脑能看视频，但游戏/加速器全废 | UDP/ICMP 被 FORWARD 默认 drop | [4](#4-udpicmp-全废但网页正常) |
| 5 | 停 UA3F 排查后整个局域网断网 | 残留重定向指向死端口 | [5](#5-停-ua3f-导致全网断) |
| 6 | 路由器越来越卡，最后 OOM | P2P 连接洪水撑爆 UA3F | [6](#6-p2p-洪水把路由器打爆) |
| 7 | 网页转圈 1~3 秒，测速正常 | 学校 DNS 指向远处 CDN | [7](#7-网页转圈但测速正常) |
| 8 | 校内域名、自助服务页打不开 | dnsmasq 防重绑保护拦截私网地址 | [8](#8-校内域名打不开) |
| 9 | 换了信号更强的 AP，反而更卡 | 强信号 AP 客户端太多，重传率高 | [9](#9-换了信号更强的-ap-反而更卡) |
| 10 | 手机刷视频卡 | 2.4G 信道挤爆 | [10](#10-手机刷视频卡) |
| 11 | 看 B 站特别卡 | 播放器 PCDN 开几百条 STUN | [11](#11-b-站特别卡) |
| 12 | 游戏更新慢，Steam 却很快 | 国际源 vs 国内 CDN | [12](#12-游戏更新慢steam-快) |
| 13 | 改密码后路由器掉线且再也登不上 | 配置里还是旧密码 | [13](#13-改密码后登不上) |
| 14 | 设备名额莫名其妙被吃光 | STA 用了随机 MAC | [14](#14-设备名额被吃光) |
| 15 | 认证成功但很快又掉 | 同一账号在别处登录被踢 | [15](#15-认证成功但很快掉线) |
| 16 | 电脑换网线后反而断网 | 新网卡抢了默认路由 | [16](#16-换网口后电脑断网) |
| 17 | 网页能开，但视频一直缓冲 | 代理/加速器把流量带偏 | [17](#17-视频一直缓冲) |
| 18 | 重启后一切正常，但 UDP 又废了 | 开机顺序导致 fw4 规则缺接口 | [18](#18-重启后-udp-又废) |

---

## 1. Breed 刷 Bootloader 报"无效"

**现象**：Breed → 固件更新 → 选 Bootloader → 上传报"无效"。

**根因**（按常见度）：

1. 把 OpenWrt 的 `kernel1.bin` 传进了 Bootloader 槽
2. 传的是压缩包，或者改过名的文件
3. `固件类型` 没选成 `Bootloader`

**验证**：文件 MD5 要和官网一致；文件名形如 `breed-mt7621-xxx.bin`，大小 ~130KB。

**处置**：只上传官方下载的 `.bin` 原文件，且必须选对固件类型。

> ⚠️ 写 Bootloader 期间断电 = 真砖（要拆机接编程器）。用网线、别用 WiFi。

---

## 2. 刷完无限重启

**现象**：刷完 OpenWrt 后灯一直闪，进不去系统。

**根因**：Breed 还在从旧分区启动。必须告诉它"从 kernel1 启动"。

**处置**：进 Breed → 环境变量 →

```
xiaomi.r3g.bootfw = 2
```

或

```
autoboot.command = boot flash 0x600000
```

保存后重启。

**另一个原因**：在 Breed 里刷了 `sysupgrade.bin`（Breed 不认这个布局）。
正确做法是「小米 R3G OpenWrt」布局 + `kernel1` + `rootfs0` 两个文件。

---

## 3. 老毛子刷不进 OpenWrt

**现象**：Padavan 的「固件升级」上传 OpenWrt 镜像，报 `Incorrect image header!`。

**根因**：Padavan 的升级页只接受它自己的镜像格式。

**处置**：必须进 Breed 刷。断电 → 按住 Reset → 上电 → 灯闪 5~8 秒松手 → `192.168.1.1`。

> 注意地址：**Breed 是 `192.168.1.1`，老毛子是 `192.168.123.1`**，别记混。

---

## 4. UDP/ICMP 全废但网页正常

**现象**：

- 网页、下载、视频都正常
- `ping` 公网不通
- 所有游戏、语音、加速器全废
- 加速器报"无法识别网络"/100% 丢包

**根因**：上行是 WiFi 客户端接口，但 `fw4` 生成的规则里只有物理网口 `wan`，
匹配不上。UDP/ICMP 走 `FORWARD` 被默认 `drop`。
TCP 之所以正常，是因为 **UA3F 把它重定向到本机，走的是 `INPUT`**，绕过了这个问题。

**验证**：

```sh
nft list ruleset | grep -c phy1-sta0     # 返回 0 = 中招
ping -c 3 223.5.5.5                       # 从客户端测
```

**处置**：

```sh
fw4 reload
```

并装 `/etc/hotplug.d/iface/99-wwan-fw4-reload` 防止重启复发。

---

## 5. 停 UA3F 导致全网断

**现象**：执行 `/etc/init.d/ua3f stop` 后，局域网所有设备立刻断网，路由器本身还有网。

**根因**：UA3F 的 nft 重定向规则还在，所有 TCP 被指向一个已关闭的本地端口。

**处置**：

```sh
/etc/init.d/ua3f restart          # 只能重启，不能停
```

> **永远不要远程停 UA3F**。停掉后你连 SSH 都可能进不去（如果 SSH 走的是被重定向的流量）。

---

## 6. P2P 洪水把路由器打爆

**现象**：路由器越来越卡，网页转圈、视频卡、SSH 变慢，最后彻底失联。

**根因**：游戏启动器 / PCDN 向成百上千个节点发起 TCP 连接，UA3F 逐条在用户态 dial，
全部卡在 `SYN_SENT`，堆积上千 fd 直到 OOM。

**验证**：

```sh
cat /proc/loadavg                                              # 明显偏高
ls /proc/$(pgrep -f "^/usr/bin/ua3f" | head -1)/fd | wc -l     # > 500 警惕，>1500 危险
free -m                                                        # 可用 < 5MB 危险
grep -oE "dport=[0-9]+" /proc/net/nf_conntrack | sort | uniq -c | sort -rn | head
```

**处置**：

1. `/etc/init.d/ua3f restart` 释放资源
2. 部署 `ua3f-bypass.sh`，把 P2P 端口从 UA3F 摘出去
3. 用完启动器后关掉它，或在设置里关掉「P2P/做种」

---

## 7. 网页转圈但测速正常

**现象**：打开网页要等 1~3 秒，但测速、ping、下载都正常。

**根因**：学校 DNS 返回的 CDN 节点在几百公里外。TLS 握手要 2~3 个 RTT，
延迟被放大成秒级。

**验证**：

```sh
# 对比两个 DNS 给的 IP 的延迟
ip1=$(nslookup -type=A www.taobao.com 10.0.0.53 | awk '/^Address: [0-9]/{x=$2}END{print x}')
ip2=$(nslookup -type=A www.taobao.com 223.5.5.5   | awk '/^Address: [0-9]/{x=$2}END{print x}')
ping -c 3 $ip1; ping -c 3 $ip2
```

实测差异：82.9ms vs 14.3ms。

**处置**：见 [方法 B 第 7 章 DNS 分流](method-b-hands-on.md#7-dns-分流解决网页打开慢)。

---

## 8. 校内域名打不开

**现象**：配了分流 DNS 后，`www.bilibili.com` 正常，但学校自助服务页解析失败。

**根因**：校内域名解析到**私网地址**（如 `10.0.0.10`），
dnsmasq 的**防 DNS 重绑保护**会直接拒绝。

**验证**：

```sh
logread | grep -i "rebind"     # possible DNS-rebind attack detected: xxx.edu.cn
```

**处置**：

```sh
uci add_list dhcp.@dnsmasq[0].rebind_domain='你的学校域名'
uci commit dhcp && /etc/init.d/dnsmasq restart
```

---

## 9. 换了信号更强的 AP 反而更卡

**现象**：扫描到一个 `-23 dBm` 的 AP，切过去之后延迟反而飙高。

**根因**：信号强说明它就贴在旁边，也就意味着**整层楼的人都连着它**。
客户端多 → 抢不到发送机会 → 重传暴增。

实测对比：

| AP | 信号 | 重传率 | 结论 |
|---|---|---|---|
| ch149 | -23 dBm | **43.3%** | 信号最强，但抢不到空口 |
| ch157 | -49 dBm | **7.5%** | 信号弱，反而好用 |

**验证**：压 60 秒流量，算 `tx retries / tx packets` 增量。

**处置**：选"信号够用且重传率低"的 AP，钉死 BSSID。

---

## 10. 手机刷视频卡

**现象**：电脑（有线）正常，手机连 WiFi 卡。

**根因**：2.4G 信道拥挤。实测某次信道 1 上有 **56 个 AP**。

**验证**：

```sh
iwinfo phy0 scan | grep -oE "Channel: [0-9]+" | awk '{print $2}' | sort -n | uniq -c
```

**处置**：换到 AP 最少的信道（1/6/11 里选）。

---

## 11. B 站特别卡

**现象**：只有 B 站卡，其它网站正常。路由器负载偏高。

**根因**：播放器启用了 **PCDN（P2P 加速）**，
从其他用户的家庭宽带拉视频分片，同时开几百条 STUN 连接。

**验证**：

```sh
grep -c "dport=3478" /proc/net/nf_conntrack      # 几百条就是它
nslookup mcdn.bilivideo.com                      # 解析到 B 站 P2P CDN 域名
```

**处置**：屏蔽 PCDN 域名，强制回落到正规 CDN。

```sh
for d in mcdn.bilivideo.com mcdn.bilivideo.cn szbdyd.com pcdn.bilivideo.com; do
  uci add_list dhcp.@dnsmasq[0].address="/$d/127.0.0.1"
done
uci commit dhcp && /etc/init.d/dnsmasq restart
# 然后必须完全刷新 B 站页面（Ctrl+F5），播放器缓存了旧节点列表
```

---

## 12. 游戏更新慢，Steam 快

**现象**：Steam 下载能跑满带宽，某游戏启动器只有几十 Mbps。

**根因**：Steam 有国内 CDN 节点；而很多国外游戏只有欧洲/北美源，
瓶颈是**国际出口**，不是校园网带宽。

**验证**：

```sh
ps w | grep -i launcher        # 找启动器进程
# 在客户端看它连的远端 IP，再用 ping 测延迟
```

**处置**（按有效性）：

1. 开 VPN/加速器更新（若有专线，通常显著更快）
2. 路由器侧开 BBR + 加大 TCP 缓冲区（见 [方法 B 8.3](method-b-hands-on.md#83-国际线路提速可选)）
3. 改用 Steam 版游戏（走 Steam 的国内 CDN）
4. 避开晚高峰

---

## 13. 改密码后登不上

**现象**：学校密码改了，路由器掉线后再也认证不上。

**根因**：`/etc/portal.conf` 里还是旧密码。
更隐蔽的是：**改密码不会让学校踢掉已建立的会话**，
所以路由器可能还靠旧会话活着，直到某次掉线才暴露问题。

**处置**：

```sh
# 改配置
vi /etc/portal.conf
# 立刻验证新密码真的能用
/usr/bin/portal-login force
```

---

## 14. 设备名额被吃光

**现象**：学校显示设备数超限，但实际只有一台路由器在线。

**根因**：OpenWrt 默认给 STA **随机生成 MAC**（首字节带本地管理位，如 `2a:...`），
每次重连都变 → 学校当成新设备。

**验证**：

```sh
cat /sys/class/net/phy1-sta0/address
# 首字节第二位是 2/6/a/e（如 2a、06）说明是本地管理/随机 MAC
```

**处置**：

```sh
uci set wireless.wwan1.macaddr='设备真实WAN口MAC'
uci commit wireless && wifi reload
```

---

## 15. 认证成功但很快掉线

**现象**：日志显示登录成功，但过一会儿又离线。

**根因**：同一账号在别处登录，学校踢掉了先登录的那个。

**验证**：看日志里是否反复出现"登录成功 → 又离线"。

**处置**：

- 把手机/电脑上的校园网登录退掉
- 确认没开"无感登录"之类的常驻工具
- 若学校允许 2 台，合理分配（路由器 1 台 + 手机 1 台）

---

## 16. 换网口后电脑断网

**现象**：把路由器从 LAN 口换到另一个口，或者路由器重启后，电脑反而上不了网。

**根因**：路由器发了 DHCP 并带网关，Windows 把默认路由切到了这张网卡，
而路由器那时没有 WAN，于是断网。

**处置**：

```powershell
# 把该网卡优先级压到最低，或用静态地址且不设网关
Set-NetIPInterface -InterfaceIndex <索引> -InterfaceMetric 9999
Get-NetRoute -DestinationPrefix '0.0.0.0/0'     # 确认默认路由还在 WiFi 上
```

---

## 17. 视频一直缓冲

**现象**：网页能开，测速正常，但视频一直转圈。

**根因**（按常见度）：

1. 播放器选了质量差的 CDN 节点（B 站 PCDN、或远端节点）
2. 代理/VPN 把视频流量带到了绕远的路由
3. 分片请求被 QoS 限速

**验证**：

```sh
# 看客户端在连哪些 IP，逐个测延迟
netstat -tn | grep ESTABLISHED | awk '{print $5}' | sort | uniq -c | sort -rn | head
```

**处置**：屏蔽 PCDN 域名（见 #11）、关掉不必要的代理、换 CDN。

---

## 18. 重启后 UDP 又废

**现象**：昨天修好了，重启之后游戏又连不上。

**根因**：开机时 `fw4` 先于 WiFi 关联生成规则，缺了 STA 接口。

**验证**：

```sh
nft list ruleset | grep -c phy1-sta0     # 0 = 复发
```

**处置**：`fw4 reload` 临时修复；装 hotplug 钩子永久修复（见 #4）。

---

## 通用排查顺序

遇到"卡"先按这个顺序过一遍，能排掉 80% 的问题：

```sh
# 1. 路由器还活着吗
uptime; cat /proc/loadavg; free -m

# 2. 老毛病复发了吗
ls /proc/$(pgrep -f "^/usr/bin/ua3f" | head -1)/fd | wc -l    # UA3F fd
nft list ruleset | grep -c phy1-sta0                            # 防火墙出口
/usr/bin/portal-login status                                     # 认证

# 3. 链路本身如何
iwinfo phy1-sta0 info | grep -E "Signal|Bit Rate"
iw dev phy1-sta0 station dump | awk '/tx packets/{p=$3}/tx retries/{r=$3}END{printf "重传 %.1f%%\n", r*100/p}'

# 4. 是不是 P2P/异常连接
grep -oE "dport=[0-9]+" /proc/net/nf_conntrack | sort | uniq -c | sort -rn | head

# 5. 历史趋势
tail -30 /var/log/net-quality.log
```
