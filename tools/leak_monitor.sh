#!/bin/bash
# FSP/Blackwell 泄漏监控 — 每周 cron, 关键词命中写入 hits.log
OUT=/home/user/rt_5090_project/leak_monitor
TS=$(date +%Y%m%d_%H%M)
echo "=== $TS run ===" >> $OUT/runs.log
for q in \
  "NVIDIA FSP firmware decrypt Blackwell" \
  "GB202 FSP_RUN reverse engineering" \
  "Firmware Security Processor NVIDIA hack" \
  "NVIDIA secure boot key leak 2026" \
  "RTX 5090 engineering sample BIOS ENG dump" \
  "Jetson r39 NvTestKey new" \
  "vgpu-unlock blackwell progress" \
  "nova-core FSP secure boot" \
  "NVIDIA booter key P-384 recovered" \
  "mrmcd gpu firmware NVIDIA talk" ; do
    curl -sL "https://duckduckgo.com/html/?q=$(echo $q | sed 's/ /+/g')" 2>/dev/null | grep -oE 'result__a[^>]*>[^<]+' | sed 's/result__a[^>]*>//' | head -5 >> $OUT/hits_$TS.log
done
grep -c . $OUT/hits_$TS.log 2>/dev/null >> $OUT/runs.log
