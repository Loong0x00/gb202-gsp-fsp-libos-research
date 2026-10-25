# MODS SUL=5 补丁技术规格

日期: 2026-09-30
适用: MODS 570.215 (SHA256: 6645d5de5e0ce0c9dacd79e264e46398cb1296107d4dba15cbb3a84ea82e5856)

---

## 背景

MODS 的 SecurityUnlockLevel (SUL) 控制特权操作:
- Level 1: 默认(无网络认证)
- Level 4: NVIDIA网络认证通过
- Level 5: 最高级

SUL > 3 才能调用 SetSwFuses / ProgramSwFusePlan 等工厂级写操作。

## 补丁位置

### 570.215 二进制

```
文件偏移 = VA - 0x400000 (text段: file 0x0 → VA 0x400000)

补丁1 (setter 立即数):
  VA 0xd81d7b = file 0x981d7b
  原始: 01 00 00 00  (mov dword[SUL], 1)
  补丁: 05 00 00 00  (mov dword[SUL], 5)
  位置: setter 函数内的立即数 (函数入口 VA 0xd81d70)

补丁2 (NOP 二次覆盖):
  VA 0xd81d9b = file 0x981d9b
  原始: 89 1d d3 d6 9d 17  (mov [rip+rel32], ebx — 覆盖SUL为input)
  补丁: 90 90 90 90 90 90  (NOP×6 — 不覆盖, 保留初始值5)
```

## setter 函数逻辑 (原始)

```c
// VA 0xd81d70
void setSUL(NvU32 input) {
    SUL_dword = 1;          // ← 补丁1: 改为 5
    if (network_check()) {   // 0x8c0c1e0
        has_network = 0;    // c6 05 ...
        SUL_dword = input;  // ← 补丁2: NOP掉这行
        if (input > 3) {
            if (input == 4) SUL_dword = input + 1;  // 4→5
            else if (input == 3) SUL_xdigPostInit = 1;
            SUL_dword = input + 4;  // 跳转到更复杂的路径
        }
        // ... 设置日志ID等
    } else {
        // 网络失败 → 保留input (写入SUL)
        SUL_dword = input;  // ← 这个也被NOP(在另一分支)
    }
}
```

## 补丁后行为

```
1. 驱动启动 → 解析器无 -b 参数 → input = 1
2. 调用 setter(1)
3. setter 写 SUL = 5 (补丁1的立即数)
4. NOP的代码不再覆盖 (补丁2)
5. JS 的 SecurityUnlockLevel 读取 SUL → 返回 5
6. MODS 显示 "INTERNAL ONLY MODS UNLOCKED"
```

## 验证方法

```bash
# 在 VM 里运行打补丁的 MODS
cd ~/mf215
sudo ./mods -nc -m 'Print("SUL=" + SecurityUnlockLevel);' \
  gputest.jse -skip_azalia_init -null_display -no_vga -no_gold -no_test
# 输出: SUL=5
```

## 注意事项

1. **必须用 570.215 的 JSE 文件** — 570.151 的 JSE 会报 "Decompression failed -3"
2. **两个补丁必须同时打** — 只打补丁1会被补丁2的写入覆盖
3. **mods.ko 必须先加载** — 否则 MODS 无法初始化 GPU
4. **nouveau 必须卸载** — 否则抢占 GPU

## 编译环境要求

```
guest 内核: 5.15.0-194-generic (Ubuntu 22.04.5)
编译工具: gcc 11.4.0, make
内核头: linux-headers-5.15.0-194-generic
安装: apt install build-essential linux-headers-$(uname -r)
```

## 生成补丁二进制的脚本

```python
import subprocess
src = '/home/user/.cache/mods570215-powertrace.GC5pNs/mods'  # 原始 570.215
data = bytearray(open(src,'rb').read())
out = subprocess.run(['readelf','-lW',src],capture_output=True,text=True).stdout
def va2fo(va):
    for line in out.splitlines():
        if line.strip().startswith('LOAD'):
            s=line.split()
            o,v,f=int(s[1],16),int(s[2],16),int(s[4],16)
            if v<=va<v+f: return o+(va-v)

off1 = va2fo(0xd81d7b)
data[off1:off1+4] = bytes.fromhex('05000000')

off2 = va2fo(0xd81d9b)
data[off2:off2+6] = bytes.fromhex('909090909090')

open('mods_sul5','wb').write(bytes(data))
```
