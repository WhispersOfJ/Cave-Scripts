#!/usr/bin/env bash
# gpu-usage.sh — waybar custom-module: AMD 680M (iGPU) load + memory.
# Cheap local sysfs reads, no caching needed (unlike weather.sh's network call).
set -euo pipefail

BASE="${GPU_SYSFS_BASE:-/sys/class/drm/card1/device}"

read_stat() { cat "$BASE/$1" 2>/dev/null || echo ""; }

busy="$(read_stat gpu_busy_percent)"
vram_used="$(read_stat mem_info_vram_used)"
vram_total="$(read_stat mem_info_vram_total)"
gtt_used="$(read_stat mem_info_gtt_used)"
gtt_total="$(read_stat mem_info_gtt_total)"

if [ -z "$busy" ]; then
    jq -nc '{text: "󰢮 --%", tooltip: "GPU stats unavailable (sysfs path missing/changed)", class: "offline"}'
    exit 0
fi

mib() { awk -v b="${1:-0}" 'BEGIN{printf "%.0f", b/1048576}'; }

class="ok"
[ "$busy" -ge 85 ] 2>/dev/null && class="high"

jq -nc --arg text "󰢮 ${busy}%" \
       --arg tooltip "GPU busy: ${busy}%
VRAM: $(mib "$vram_used")/$(mib "$vram_total") MiB
GTT: $(mib "$gtt_used")/$(mib "$gtt_total") MiB" \
       --arg class "$class" \
    '{text: $text, tooltip: $tooltip, class: $class}'
