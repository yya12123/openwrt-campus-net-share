# 致谢与出处

> 本仓库的方案不是原创发明，而是在下面这些作者的工作基础上，针对"无线接入 + 锐捷 eportal"
> 这一具体场景做的适配、排错与踩坑记录。**核心思路与工具都归他们。**

---

## 核心：防共享检测方案

### SunBK201（UA2F / UA3F 作者）

整个方案的源头。三篇必读：

- [关于某大学校园网共享上网检测机制的研究与解决方案](https://blog.sunbk201.site/crack-campus-network)
  —— 系统梳理 TTL、User-Agent、DPI、IPID、时钟偏移、Flash Cookie 六类检测手段
- [校园网防检测: UA3F - 新一代 UA 修改方法](https://blog.sunbk201.site/posts/ua3f/)
  —— UA3F 的设计原理：作为 SOCKS5 代理，借 Clash 捕获入站流量
- [全新方案-懒人福音-无需手动编译修改UA-校园网防检测](https://blog.sunbk201.site/posts/change-ua-by-proxy)
  —— 早期"DstPort 80 走代理"的替代思路

教程与项目：

- [猴子也能看懂的 UA3F 使用教程（Notion）](https://sunbk201public.notion.site/UA3F-2a21f32cbb4b80669e04ec1f053d0333)
- [OpenWrt 编译与防检测部署教程（Notion）](https://sunbk201public.notion.site/OpenWrt-f59ae1a76741486092c27bc24dbadc59)
- [OpenWrt 编译与防检测部署教程（博客）](https://blog.sunbk201.site/posts/openwrt-compile)
- [UA3F 源码](https://github.com/SunBK201/UA3F) · [UA3F Releases（各架构 ipk/apk）](https://github.com/SunBK201/UA3F/releases)

### Zxilly（UA2F 作者）

- [Zxilly/UA2F](https://github.com/Zxilly/UA2F)
  —— UA3F 的前一代方案，基于 `libnetfilter_queue` 改写 HTTP 的 User-Agent。
  优点是覆盖面广，缺点是构建门槛高、与 Clash 冲突（必须做二级路由）。

---

## 代理与分流（可选组件）

- [juewuy/ShellCrash](https://github.com/juewuy/ShellCrash)
  —— Shell 版 Clash 管理器，适合 OpenWrt / Padavan 等轻量系统
- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo/tree/Meta)
  —— Clash Meta 内核
- [MetaCubeX/Meta-Docs](https://github.com/MetaCubeX/Meta-Docs)
  —— mihomo 文档

> 本项目的场景（仅需改 UA + 固定 TTL）**不需要** Clash，UA3F v3 自带 nftables 透明代理。
> 只有当学校还做 DPI 检测、需要加密流量时才需要引入。

---

## 系统与刷机

- [OpenWrt 官网](https://openwrt.org/)
- [Xiaomi Redmi Router AC2100 设备页（含刷机与救砖）](https://openwrt.org/toh/xiaomi/xiaomi_redmi_router_ac2100)
- [OpenWrt 固件选择器](https://firmware-selector.openwrt.org/)
- [hackpascal/Breed 引导](https://breed.hackpascal.net/)
  —— AC2100 用的是 `breed-mt7621-xiaomi-r3g.bin`（"小米路由器 3G"版，
  官方 wiki 明确说明同时适配 R2100 / AC2100）

---

## 认证协议参考

锐捷 eportal 的接口（`InterFace.do?method=login` / `pageInfo` / `logout`）
是从其前端 JS（`AuthInterFace.js`）中读出来的，属于协议观察，非官方文档。

相关讨论可参考：

- [恩山无线论坛（right.com.cn）](https://www.right.com.cn/forum/) —— 大量 AC2100 刷机与 Portal 认证的实操帖
- [SunBK201 的讨论群组](https://t.me/crack_campus_network) —— 校园网防检测相关讨论

---

## 其它被借鉴的思路

| 思路 | 出处 |
|---|---|
| 用 nftables 的 `return` 让特定端口绕过代理 | UA3F 生成的规则里本身就有 skip 端口段（22/51080/51090），本项目沿用同一手法 |
| BBR + 加大 TCP 缓冲区提升长肥管道吞吐 | Linux 内核通用优化，非本项目原创 |
| 屏蔽 PCDN 域名让播放器回落官方 CDN | 中文社区的常见做法，非本项目原创 |
| 分流 DNS（公共 DNS + 校内 DNS） | 校园网环境的通用做法 |

---

## 本仓库新增的部分

在上述基础上，本项目补充的是**针对"无线 STA 接入 + 锐捷 eportal"的具体适配与排错**：

- `fw4` 在 WiFi 客户端上行时漏掉接口名，导致 UDP/ICMP 全丢的定位与修复
- UA3F 在 P2P 连接洪水下 fd 爆炸 / OOM 的成因与"端口绕过"方案
- STA 随机 MAC 导致设备名额被反复消耗的定位与钉死方法
- 用"重传率"而非"信号强度"评估 AP 的实测方法与数据
- eportal 改密码不踢会话的验证方法（`force` = 先 logout 再 login）
- 一整套看门狗 + 质量采样脚本

---

## 许可

本仓库文档与脚本以 MIT 发布。引用到的上游项目请遵循其各自许可证：

- UA3F / UA2F：见各自仓库
- OpenWrt：GPL-2.0
- Breed：作者声明"仅供个人免费使用，禁止用于商业目的"
- ShellCrash / mihomo：见各自仓库

---

## 如果这份笔记帮到你

请把感谢给上面的原作者。本仓库只是把他们的工作拼到了一个具体场景里，
并记录了我踩过的坑。
