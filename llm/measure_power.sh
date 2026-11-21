#!/usr/bin/env bash
# Samples battery current/voltage while you run the app (unplug USB power:
# use `adb tcpip 5555; adb connect <phone-ip>` so the phone runs on battery).
# Usage: bash llm/measure_power.sh 60 > power.csv   (60 s)
DUR="${1:-60}"
echo "t_ms,current_uA,voltage_uV"
end=$(( $(date +%s) + DUR ))
while [ "$(date +%s)" -lt "$end" ]; do
  c=$(adb shell cat /sys/class/power_supply/battery/current_now | tr -d '\r')
  v=$(adb shell cat /sys/class/power_supply/battery/voltage_now | tr -d '\r')
  echo "$(date +%s%3N),$c,$v"
  sleep 0.2
done
# Power (W) = |current_uA| * voltage_uV / 1e12. Subtract the idle baseline
# (app open, no inference) to get the inference cost; energy = mean W x seconds.
