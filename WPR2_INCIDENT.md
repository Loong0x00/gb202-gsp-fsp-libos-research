# WPR2 事故记录(2026-09-28)

## 触发序列
1. 卸载驱动(GSP 停)
2. 发 COT 基线(ver=2, size=860, fmc=0x1000000, 全零签名字段)→ 静默消费
3. COT size fuzz: 0/1/859/861/2048/4096/32768/65535 → 全部静默消费,PRC 保持正常
4. COT version fuzz: 0/1/3/0xFFFF → PRC handler 死亡(MT=0 不再响应)
5. 重载驱动 → "unexpected WPR2 already up" → GSP 无法启动 → GPU 不可用

## 现场证据
- PRC handler 专属死亡(0x20/0x16 正常响应)
- WPR2_ADDR_HI(0x1fa828)= 0x07c6a400(非零)
- WPR2_ADDR_LO(0x1fa824)= 0x07b8aa00
- 软复位(modprobe 循环)不恢复 WPR2

## 分类
- 形态: setup-before-verify(FSP 先配置 WPR2 后验签,失败不回滚)
- 影响: handler 级 DoS → 硬件级 GSP 启动阻断
- 严重性: 高(需断电恢复,或未知恢复路径)
- 是否可利用: 待定(如果 WPR2 参数可控,可能影响 GSP 内存保护)

## 待定案
- [ ] WPR2 非零是 COT 触发还是 CC 补丁的启动路径差异?
- [ ] 断电后 WPR2 是否清零?
- [ ] 精确触发参数是哪个(size fuzz vs version fuzz)?
- [ ] WPR2 值(0x07c6a400)是否来自我们的输入?
