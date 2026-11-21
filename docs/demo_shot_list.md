# Demo video shot list (target 55 s, must stay under 60 s)

Record the phone screen with MIUI/HyperOS screen recorder (Control Centre > Screen recorder, sound from mic)
and a second phone/camera for the two "real world" shots. Keep the POCO in **airplane mode** throughout.

| # | Time | Shot | What is on screen / said (Telugu voice-over, English subtitle) |
|---|---|---|---|
| 1 | 0–4 s | Hand-held: farmer's hand holding a diseased tomato leaf in the field / balcony | Title card: "కృషి మిత్ర · Offline crop doctor on Arm (POCO X5 Pro, Snapdragon 778G)" |
| 2 | 4–8 s | Screen: pull down quick settings, **airplane mode ON**, Wi-Fi off | Subtitle: "No internet. Everything runs on the phone." |
| 3 | 8–14 s | Screen: open app, tap **ఫోటో తీయండి**, camera captures the leaf | VO: "ఆకు ఫోటో తీయండి" |
| 4 | 14–22 s | Screen: result card appears: crop + disease in Telugu, confidence, **severity chip**, red lesion overlay next to the photo, timing line (classification ms, severity ms) | Subtitle: "Vision: MobileNetV3 INT8 TFLite, ~X ms. Severity: lesion area Y% → moderate" |
| 5 | 22–40 s | Screen: AI advice streams in Telugu from Llama 3.2 1B; stats line shows tok/s | Subtitle: "Advice: Llama 3.2 1B, INT4, ExecuTorch + XNNPACK on the Arm CPU, Z tok/s" |
| 6 | 40–46 s | Screen: tap 🔊, Telugu TTS reads the advice; expand "ధృవీకరించిన చర్యలు" | Subtitle: "Grounded in TNAU/ICAR guidance; doses verified, never invented" |
| 7 | 46–52 s | Screen: second quick example from gallery (healthy leaf → green "ఆరోగ్యకరం", or late blight → red "తీవ్రం") | Shows severity levels change |
| 8 | 52–55 s | End card: architecture strip (Camera → Vision → Severity → Retrieval → Llama → Telugu) + repo URL | — |

Tips
- Do one full rehearsal first so Llama is already loaded (the first load takes several seconds); or cut the load wait.
- Use a clearly diseased leaf with good light; avoid a busy background (the severity mask assumes one main leaf).
- If shot 5 runs long, speed it up 2x in the editor and say so in a subtitle ("2x").
- Export 1080p, < 60 s. Put the exact latency numbers you see on screen into the subtitles and the report.
