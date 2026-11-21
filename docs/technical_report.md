# Krishi Mitra: offline crop disease and pest advisor in Telugu on an Arm phone

**Bharat AI SoC challenge, technical report (draft).** Team: sai kiran. Code: https://github.com/ratna-saikiran/krishi-mitra-telugu

## 1. Problem and summary
Smallholder farmers in Andhra Pradesh and Telangana often have no reliable data connection in the field and
little access to extension officers. Krishi Mitra runs entirely on an Arm Android phone (POCO X5 Pro 5G,
Snapdragon 778G): a farmer photographs a leaf, the app identifies the crop and disease or pest, grades the
severity (mild / moderate / urgent), and gives actionable advice in Telugu, written by Llama 3.2 1B running
through ExecuTorch, grounded in a curated advisory database and read aloud with Telugu text-to-speech.
It also gives fertiliser, irrigation and post-harvest tips per crop. No network permission is used at runtime.

## 2. System architecture
Two separate pipelines, run strictly one after another to bound peak memory and CPU contention:

| Stage | Model / method | Runtime on device | Output |
|---|---|---|---|
| 1. Detection | MobileNetV3-Large (ImageNet init), fine-tuned, **INT8 PTQ** | TFLite + XNNPACK on Arm CPU | crop + disease/pest, top-3 + confidence |
| 2. Severity | HSV leaf segmentation, largest component, hole fill; lesion = leaf pixels outside healthy-green range | Pure Dart | lesion area %, red overlay, level |
| 3. Retrieval | Curated Telugu advisory DB (38 classes) keyed by class label | JSON asset | verified steps for that severity |
| 4. Advisory | **Llama 3.2 1B Instruct**, 8da4w (INT4 weights, INT8 dynamic activations), 4-bit embeddings | **ExecuTorch 1.0 + XNNPACK** (KleidiAI micro-kernels) on Arm CPU | Telugu advice, streamed |
| 5. Guardrail | Telugu-script ratio ≥ 0.6, no number absent from verified facts, repetition check | Dart | accept LLM text or fall back to verified template |

Only structured text (crop, disease, severity, lesion %, retrieved steps) is sent to Llama, never the image.
Severity rules: lesion ratio < 10% mild, 10–25% moderate, ≥ 25% urgent; fast-spreading or incurable diseases
(late blight, TYLCV, mosaic virus, citrus greening) are raised one level. Healthy class → no severity.

## 3. Datasets
| Dataset | Use | Size used | Notes |
|---|---|---|---|
| PlantVillage (color) | train / val / test | 38 classes, up to 700 train, 40 val, 100 test images per class | lab images, uniform background |
| PlantDoc | train (field images, ×3 oversampled) and **separate field test set** | 2,342 train, 236 test, 27 classes mapped onto PlantVillage labels | real-field images, cluttered backgrounds |
| IP102 (pests) | not used (hosted on Google Drive, unreachable from our build environment within the deadline) | — | pests covered so far: two-spotted spider mite; whitefly-borne TYLCV and psyllid-borne HLB via their vectors |
| Advisory DB | retrieval for Llama | 26 diseases + 12 healthy crops, Telugu | condensed from TNAU Agritech Portal, ICAR-NCIPM / ICAR-IIHR, ANGRAU/PJTSAU package of practices |

## 4. Training and quantization
Transfer learning in TensorFlow 2.21 on CPU: stage 1 frozen backbone + new softmax head (3 epochs, Adam 1e-3),
stage 2 fine-tune the top 60 layers with BatchNorm frozen (4 epochs, Adam 1e-4). Augmentation: flips,
±15% rotation, zoom, translation, brightness, contrast (to narrow the lab-to-field gap).
Post-training full-integer quantization with 300 representative training images: all weights and activations
INT8, float32 I/O so the whole graph is XNNPACK-delegable (a uint8 input QUANTIZE node was not).

Llama: Arm learning path recipe (ExecuTorch release/1.0): `export_llama -kv --use_sdpa_with_kv_cache -X
--xnnpack-extended-ops -qmode 8da4w --group_size 64 --embedding-quantize 4,32`, max sequence 2048 (Telugu
tokenizes into many tokens with Llama 3's vocabulary, so 1024 was too short for prompt + answer).

## 5. Results
### 5.1 Detection accuracy (TFLite models, host evaluation)
{{ACCURACY_TABLE}}

### 5.2 Severity
No public dataset has pixel-level lesion labels for these classes, so we report how well the lesion ratio
separates healthy from diseased leaves on 600 PlantVillage test images: {{SEVERITY}}.
The Dart implementation matches the Python reference within ±0.03 lesion ratio (unit test `app/test`).

### 5.3 Latency on POCO X5 Pro (Snapdragon 778G)
Measured in the app (timing line under each result and the LLM stats line), release APK, airplane mode,
median of 10 runs. Fill in after on-device runs:

| Stage | Median latency |
|---|---|
| Image decode + resize | __ ms |
| Classification (INT8, 4 threads) | __ ms |
| Severity (Dart) | __ ms |
| Llama model load (first time) | __ s |
| Llama time to first token | __ ms |
| Llama decode speed | __ tok/s |
| End to end (photo to full advice) | __ s |

Model sizes: classifier INT8 {{INT8_MB}} MB (FP32 {{FP32_MB}} MB); Llama .pte ≈ 1.1 GB; peak app RAM __ MB (Android Studio profiler or `adb shell dumpsys meminfo com.krishimitra.krishi_mitra`).

### 5.4 Power
`llm/measure_power.sh` samples battery current and voltage over adb Wi-Fi while the phone runs on battery;
`llm/power_summary.py` reports mean/peak W and energy. Fill in: idle __ W, vision __ W (__ J per image),
Llama __ W (__ J per advice).

### 5.5 Advice quality
{{LLM_QUALITY}}

## 6. Limitations
- **Field accuracy**: PlantVillage-style lab images dominate training. Accuracy on PlantDoc field photos is far
  lower than on lab images (section 5.1); the app asks for a close, single-leaf photo and shows top-3 when
  confidence is below 50%.
- **Coverage**: 14 crops from PlantVillage; key Telugu-state crops such as rice, cotton, chilli (except bell
  pepper), groundnut and redgram are not yet covered, and dedicated pest classes (IP102) are not yet in the model.
- **Severity** is a colour heuristic: shadows, soil, dry margins or multiple overlapping leaves inflate the ratio;
  thresholds are not calibrated against agronomist ratings.
- **Llama 3.2 1B Telugu**: Telugu is not one of Llama 3.2's officially supported languages, so fluency is limited
  and generation is slower because Telugu takes many tokens. The guardrail falls back to the verified template
  when output is not mostly Telugu or contains an unverified number.
- **Advisory DB** is a condensed summary of extension guidance; doses must be confirmed by a local
  agriculture officer (shown on every screen). Chemicals banned or restricted in India were avoided.

## 7. Future work
LoRA fine-tune of Llama 3.2 1B on Telugu advisory pairs generated from the DB; add rice, cotton, chilli and
groundnut datasets and IP102 pests; a small UNet/DeepLabV3+ for lesion segmentation; Telugu speech input;
Qualcomm/QNN backend for ExecuTorch to use the Hexagon NPU.
