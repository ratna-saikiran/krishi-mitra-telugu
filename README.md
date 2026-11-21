# కృషి మిత్ర (Krishi Mitra) — offline crop disease & pest advisor in Telugu

Fully on-device app for the Bharat AI SoC challenge. Target: **POCO X5 Pro 5G**
(Snapdragon 778G, 1x Cortex-A78 @2.4 GHz + 3x A78 + 4x A55, Armv8.2-A, arm64-v8a).

```
 photo ──► [1] vision: MobileNetV3-L INT8 TFLite (XNNPACK, Arm CPU)  ──► crop + disease (38 classes)
       ──► [2] severity: HSV leaf/lesion segmentation, lesion-area ratio ──► mild / moderate / urgent
       ──► [3] retrieval: curated Telugu advisory DB (TNAU / ICAR guidance) ──► verified steps
       ──► [4] advisory: Llama 3.2 1B Instruct, 8da4w, ExecuTorch + XNNPACK ──► Telugu advice
       ──► [5] guardrail: Telugu-ratio + dose check, else verified template; Telugu TTS
```
Stages run **sequentially** (never in parallel) to bound RAM and CPU. Only structured
text (crop, disease, severity, lesion %, retrieved steps) is sent to Llama, never the image.
No network permission is used at runtime.

## Repo layout
| Path | What |
|---|---|
| `ml/train_classifier.py` | MobileNetV3-Large transfer learning on PlantVillage (+ PlantDoc field images) |
| `ml/convert_int8.py` | Post-training full-integer INT8 quantization to TFLite |
| `ml/eval_tflite.py` | Accuracy / precision / recall / F1 on PlantVillage (lab) and PlantDoc (field) |
| `ml/severity.py`, `ml/eval_severity.py` | Severity reference implementation + evaluation |
| `ml/build_advisory_db.py` | Builds `app/assets/advisory_te.json` (Telugu advisory DB) |
| `llm/export_llama.sh` | Llama 3.2 1B → ExecuTorch `.pte` (Arm learning path flags) |
| `llm/push_to_phone.sh`, `llm/measure_power.sh` | Deploy model, sample battery power |
| `app/` | Flutter app; `android/.../LlmBridge.kt` is the ExecuTorch `LlmModule` bridge |
| `docs/` | Technical report, demo video shot list |

## Build and run (on your Mac)
1. **Flutter + Android SDK**: install Flutter (stable) and Android Studio (SDK 35+, NDK installed by Gradle). `flutter doctor` must be green for Android.
2. **APK**: `cd app && flutter pub get && flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`.
3. **Phone**: enable Developer options + USB debugging on the POCO, then `adb install -r build/app/outputs/flutter-apk/app-release.apk`.
   The app works now with the vision pipeline and Telugu template advice.
4. **Llama** (needs your Meta license acceptance): `bash llm/export_llama.sh` then
   `bash llm/push_to_phone.sh ~/krishi-et/llama3_2_1b_instruct_8da4w_g64_emb4_seq2048.pte ~/krishi-et/tokenizer.model`.
   Reopen the app: the top-right chip changes to "ఆఫ్‌లైన్ · Llama".
5. **Turn on airplane mode** for the demo.

## Reproduce the vision model
```
git clone --depth 1 --filter=blob:none --sparse https://github.com/spMohanty/PlantVillage-Dataset data/pv && (cd data/pv && git sparse-checkout set raw/color)
git clone --depth 1 https://github.com/pratikkayal/PlantDoc-Dataset data/pd
pip install tensorflow pillow scikit-learn
python ml/train_classifier.py --pv data/pv/raw/color --plantdoc_train data/pd/train --out ml/out --train_per_class 700 --epochs_head 3 --epochs_ft 4
python ml/eval_tflite.py ml/out data/pd/test
cp ml/out/classifier_int8.tflite app/assets/models/ && cp ml/out/labels.txt app/assets/ ml/
```
`cd app && flutter test` checks the Dart severity port against the Python reference and the LLM guardrail.

## Safety
Advice comes only from the curated DB; the LLM rephrases it and is rejected if it
introduces any number (dose) not present in the verified facts or is not mostly Telugu.
Every screen shows: verify doses with your local AEO / Rythu Bharosa Kendra.
