#!/usr/bin/env bash
# Copy the exported model + tokenizer to the phone where the app looks for them.
# Phone: USB debugging on (Settings > About phone > tap MIUI/OS version 7x,
# then Additional settings > Developer options > USB debugging).
set -euo pipefail
PTE="$1"; TOK="$2"
adb shell mkdir -p /data/local/tmp/llama
adb push "$PTE" /data/local/tmp/llama/
adb push "$TOK" /data/local/tmp/llama/tokenizer.model
adb shell chmod 644 /data/local/tmp/llama/*
# Fallback location if your Android build blocks app reads of /data/local/tmp:
adb shell mkdir -p /sdcard/Android/data/com.krishimitra.krishi_mitra/files/llama
adb push "$PTE" /sdcard/Android/data/com.krishimitra.krishi_mitra/files/llama/
adb push "$TOK" /sdcard/Android/data/com.krishimitra.krishi_mitra/files/llama/tokenizer.model
adb shell ls -l /data/local/tmp/llama
