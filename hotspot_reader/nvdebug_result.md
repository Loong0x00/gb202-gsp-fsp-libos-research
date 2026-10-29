# NvDebugDump junction field check

The open KMD generated descriptor at
`/usr/src/nvidia-610.43.03/src/nvidia/generated/g_nvdebug_pb.h:164` defines
`GpuInfo.junction_temp` as repeated uint32 protobuf field 6.  A read-only
diagnostic dump was collected with:

```sh
sudo nvidia-debugdump --dumpall --device 0 --file /tmp/gb202_debugdump.zip
```

Decoding `system_info.pb` against the generated field descriptors showed one
GPU and populated GPU ID, UUID, device ID, PMC_BOOT0, and subdevice ID.  Field
6 `junction_temp` was absent; it was not a zero-valued reading.  The open KMD
source contains the generated descriptor but no reference that populates the
field.

Status: **VERIFIED** schema slot, **VERIFIED negative** value path on this
driver/GPU.  The dump and its process inventory were deleted after checking.
