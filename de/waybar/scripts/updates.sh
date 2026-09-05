#!/usr/bin/env bash
count=$(checkupdates 2>/dev/null | wc -l)
if [ "$count" -gt 0 ]; then
    tooltip=$(checkupdates 2>/dev/null | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')
    echo "{\"text\": \"󰚰 ${count}\", \"tooltip\": \"${tooltip}\", \"class\": \"pending\", \"alt\": \"pending\"}"
else
    echo "{\"text\": \"󰚰 0\", \"tooltip\": \"System up to date\", \"class\": \"updated\", \"alt\": \"updated\"}"
fi
