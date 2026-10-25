# InfoROM 查询 — 最后一步状态 (2026-09-28 深夜)

## 当前完成度: 95%

### 已编译进驱动的函数
```c
// 在 src/nvidia/src/kernel/gpu/gpu.c 末尾
// 编译成功(0错误),在 gpu.o 里确认存在
NV_STATUS xdigQueryInforomObjectVersion(OBJGPU *pGpu, const char *objType, NvU8 *ver, NvU8 *subver)
{
    struct { char objectType[3]; NvU8 version; NvU8 subversion; } params = {0};
    RM_API *pRmApi = GPU_GET_PHYSICAL_RMAPI(pGpu);
    memcpy(params.objectType, objType, 3);  // 实际用的 portMemCopy
    status = pRmApi->Control(pRmApi,
               pGpu->hInternalClient,
               pGpu->hInternalSubdevice,
               0x2080014b,  // GET_INFOROM_OBJECT_VERSION
               &params, sizeof(params));
    *ver = params.version; *subver = params.subversion;
    return status;
}
```

### 需要做的最后一步
在 `kernel-open/nvidia/nv.c` 的 `nvidia_ioctl` 里加:
```c
// NR=0x78 时调用 xdigQueryInforomObjectVersion
// 需要解决: nv.c(GPL层)怎么调 gpu.c(RM core)的函数
// 方案: extern 声明 + 通过 rm_ioctl 或直接函数指针
```

### 为什么这个能成功
- `pGpu->hInternalClient` / `hInternalSubdevice` 是驱动自己用的内部句柄
- 跳过了用户空间 RM 连接建立的所有问题
- RM API 的 Control 直接走 GSP RPC 路径
- NVML 用同样的方式查 OEM 版本(成功返回 2.1)

### 如果成功后的路线
1. PRC InfoROM 版本确认 → 对象存在
2. 找 InfoROM 读/写的 RM 命令号
3. 直接读/写 InfoROM 的 PRC 对象
4. 在 Linux 上清 CC 状态

### 备用: F-1 GSP 代码执行
- GSP 固件有 `_inforomFsReadFile` 函数(已在固件字符串确认)
- F-1 溢出给 GSP 代码执行
- 直接调 inforomFsReadFile 读完整 InfoROM

### 驱动源码当前补丁清单
| 文件 | 补丁 | 状态 |
|------|------|------|
| os-interface.c | os_cc_enabled=TRUE | ✓ |
| kern_gpu_gb100.c | CC检查自然返回 | ✓ |
| kern_gpu_gb100.c | NVLE自然返回 | ✓ |
| kernel_gsp.c | WPR2 bypass | ✓ |
| conf_compute.c | CPU check skip | ✓ |
| conf_compute.c | CC_FEATURE_ENABLED强制 | ✓ |
| gpu.c | xdigQueryInforomObjectVersion | ✓ 新增! |
| nv.c | XINFOROM ioctl | ✗ 需要写 |

### RM API InfoROM 命令号
```
GET_INFOROM_OBJECT_VERSION = 0x2080014b
  参数: { char objectType[3]; NvU8 version; NvU8 subversion; }
  objectType: "PRC", "OEM", "ECC", "BBX" 等

GET_INFOROM_IMAGE_VERSION = 0x20800156
```

### 用户空间 RM 连接问题(已诊断)
- root client 分配成功(0xc1d003xx)
- device alloc 显示成功但实际可能失败
- subdevice alloc 显示成功但 control 返回 0x57(OBJECT_NOT_FOUND)
- 原因: ioctl 结构可能不完全正确(48字节布局)
- 解法: 不用用户空间连接,用驱动内部的 hInternalClient/hInternalSubdevice

### NVAPI 探索结果
- libnvidia-api.so 存在(800KB)
- 334 个函数在表中
- 没有 InfoROM 字符串
- Windows NVAPI ID 不适用
- 初始化/枚举GPU/获取名称 都工作
- 3 个函数返回数据(简单能力标志)

### 明天继续的入口
1. 读此文档
2. 在 nv.c 加 extern 调用 xdigQueryInforomObjectVersion
3. 编译 → 加载 → ioctl 测试 "PRC"
4. 成功 → 找 InfoROM 读写命令
5. 失败 → 走 F-1 GSP 路径
