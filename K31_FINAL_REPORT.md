# K3-1 实机测试最终报告 — 2026-09-29 深夜

## 结论

K3-1 staging 溢出**漏洞存在**但**无法精确利用**:
- 溢出确认工作(GSP crash)
- 但溢出区域(staging 之后)包含关键堆结构
- 任何写入(零/gadget/任意值)都在回调触发前导致 crash
- crash 位置固定: pc=0x1b8ffbc, stval=0x4fe6(a0=NULL 的解引用)

## 测试矩阵

| 测试 | 元素数 | 元素17-32内容 | 结果 |
|------|--------|---------------|------|
| nelem=17 无写入 | 17 | 旧数据 | crash 0x1b8ffbc |
| nelem=18 无写入 | 18 | 旧数据 | ★ 不 crash |
| nelem=19 无写入 | 19 | 旧数据 | crash 0x1b8ffbc |
| nelem=20 无写入 | 20 | 旧数据 | crash 0x1b8ffbc |
| nelem=33 全零+P1@32 | 33 | 零+P1 | crash 0x1b8ffbc |
| nelem=33 sparse(只写0和32) | 33 | 旧数据+P1@32 | crash 0x1b8ffbc |
| nelem=18 只写+0xb8@17 | 18 | 旧数据+gadget | crash 0x1b8ffbc |
| nelem=18 只写任意偏移@17 | 18 | 旧数据+任意 | crash 0x1b8ffbc |
| P6(benign callback)@32 | 33 | 零+P6 | crash 0x1b8ffbc |
| ck=0(强制重试路径) | 33 | 零+P1 | crash 0x1b8ffbc |

## 关键发现

1. **溢出确实发生**: nElements=33 时 GSP crash = 溢出到达 GSP 侧
2. **nelem=18 是唯一安全点**: 不 crash = 2 元素溢出被容忍
3. **nelem≥19 或写入 17 都 crash**: 溢出超过 2 元素就碰到关键结构
4. **crash 位置恒定**: a0=NULL 的 load fault = 某个被溢出零化的指针
5. **回调从未触发**: gadget 从未执行(sepc 从未等于 0x1B52246)

## 静态分析 vs 实机

```
静态分析预期:
  溢出 → 覆盖 msgqMetadata → 回调劫持 → gadget 执行
  
实机实际:
  溢出 → 覆盖未知堆结构 → 指针 NULL → crash 在 0x1b8ffbc
  (msgqMetadata 不在预期位置 或 中间有其他关键结构)
```

## 已排除的方向

- ✗ 直接写零到 17-31(规格方法)— crash
- ✗ Sparse 模式(跳过不写)— 旧数据也 crash(超出 18)
- ✗ 单字段写入(只改 +0xb8)— crash
- ✗ P6 benign callback — crash
- ✗ ck=0 强制重试路径 — crash
- ✗ 610.57(已知布局版本)— 和 615.71 同样 crash

## 剩余路径

1. **分析 0x1b8ffbc 的代码**: 找到被 NULL 化的指针来自哪个结构,
   绕过它
2. **55MB TOCTOU**: 已证明可以控制 GSP crash 位置
3. **GSP RPC fuzzing**: 找其他 handler 的溢出
4. **堆风水(heap grooming)**: 在溢出前操纵堆布局,
   使 metadata 落在安全位置
