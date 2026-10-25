# 下次Session入口 — 2026-10-07 23:15

## 最高优先: 模拟宿主RPC → RM自然启动
- fn=72 GSP_SET_SYSTEM_INFO 是第一条RPC(len=0x3d8)
- 需要构造RPC消息写入staging队列 → 内核处理 → RM自然启动
- 自然启动后: 完整syscall序列/每任务表/内核交互全可见

## 弹药库(全部实弹验证)
读RM✓ | 任意调✓ | a1控制✓ | 写staging+0x8C✓ | 写staging_ptr到任意✓

## 关键认知
- syscall不能假返回值(副作用缺失→RM跑飞)
- RPC序列: fn72(系统信息) → fn73(注册表) → 后续
- PMP竞争: 需要大buffer扫描函数,未找到可用入口
