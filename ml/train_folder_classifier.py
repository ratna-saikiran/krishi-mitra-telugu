"""Generic folder-dataset trainer (used for pests): MobileNetV3-Large,
frozen-head then fine-tune with cosine LR, label smoothing, early stopping on
val, then FP32 + INT8-weight TFLite and a full metrics report on the held-out
test split (accuracy, macro P/R/F1, per-class, top-5, confusion matrix, ECE,
accuracy-vs-coverage, bootstrap 95% CI).
python ml/train_folder_classifier.py --data data/pests --out ml/out_pests
"""
import argparse, json, os, time
import numpy as np, tensorflow as tf

p = argparse.ArgumentParser()
p.add_argument("--data", required=True); p.add_argument("--out", required=True)
p.add_argument("--img", type=int, default=224); p.add_argument("--bs", type=int, default=64)
p.add_argument("--epochs_head", type=int, default=2); p.add_argument("--epochs_ft", type=int, default=5)
p.add_argument("--unfreeze", type=int, default=80); p.add_argument("--label_smoothing", type=float, default=0.1)
a = p.parse_args(); os.makedirs(a.out, exist_ok=True); tf.random.set_seed(0)

classes = sorted(os.listdir(os.path.join(a.data, "train")))
open(os.path.join(a.out, "labels.txt"), "w").write("\n".join(classes) + "\n")
def items(split):
    out = []
    for ci, c in enumerate(classes):
        d = os.path.join(a.data, split, c)
        if os.path.isdir(d): out += [(os.path.join(d, f), ci) for f in sorted(os.listdir(d))]
    return out
TEST_DIRS = sorted(d for d in os.listdir(a.data) if d.startswith("test"))
S = {k: items(k) for k in ["train", "val"] + TEST_DIRS}
print({k: len(v) for k, v in S.items()}, "classes", len(classes))

def load(path, label):
    img = tf.io.decode_image(tf.io.read_file(path), channels=3, expand_animations=False)
    return tf.image.resize(img, (a.img, a.img)), label
aug = tf.keras.Sequential([tf.keras.layers.RandomFlip("horizontal_and_vertical"), tf.keras.layers.RandomRotation(0.15),
                           tf.keras.layers.RandomZoom((-0.2, 0.5)), tf.keras.layers.RandomTranslation(0.1, 0.1),  # whole-plant / off-centre shots
                           tf.keras.layers.RandomBrightness(0.25, value_range=(0, 255)),
                           tf.keras.layers.RandomContrast(0.3)])
def ds(it, train):
    pa, la = zip(*it)
    d = tf.data.Dataset.from_tensor_slices((list(pa), list(la)))
    if train: d = d.shuffle(len(it), seed=0)
    d = d.map(load, num_parallel_calls=tf.data.AUTOTUNE).batch(a.bs)
    if train: d = d.map(lambda x, y: (tf.clip_by_value(aug(x, training=True), 0, 255), y), num_parallel_calls=tf.data.AUTOTUNE)
    return d.map(lambda x, y: (x, tf.one_hot(y, len(classes)))).prefetch(tf.data.AUTOTUNE)
tr, va = ds(S["train"], True), ds(S["val"], False)

base = tf.keras.applications.MobileNetV3Large(input_shape=(a.img, a.img, 3), include_top=False, weights="imagenet",
                                              include_preprocessing=True, pooling="avg")
base.trainable = False
inp = tf.keras.Input((a.img, a.img, 3)); x = base(inp, training=False)
out = tf.keras.layers.Dense(len(classes), activation="softmax")(tf.keras.layers.Dropout(0.3)(x))
model = tf.keras.Model(inp, out)
LOSS = tf.keras.losses.CategoricalCrossentropy(label_smoothing=a.label_smoothing)
model.compile(tf.keras.optimizers.Adam(1e-3), LOSS, metrics=["accuracy"])
t0 = time.time(); model.fit(tr, validation_data=va, epochs=a.epochs_head, verbose=2)
base.trainable = True
for l in base.layers[:-a.unfreeze]: l.trainable = False
for l in base.layers:
    if isinstance(l, tf.keras.layers.BatchNormalization): l.trainable = False
steps = a.epochs_ft * int(tr.cardinality().numpy())
model.compile(tf.keras.optimizers.Adam(tf.keras.optimizers.schedules.CosineDecay(2e-4, steps, alpha=0.05)), LOSS, metrics=["accuracy"])
h = model.fit(tr, validation_data=va, epochs=a.epochs_ft, verbose=2,
              callbacks=[tf.keras.callbacks.EarlyStopping(monitor="val_accuracy", patience=2, restore_best_weights=True)])
print("train seconds", time.time() - t0)
model.save(os.path.join(a.out, "classifier.keras")); json.dump(h.history, open(os.path.join(a.out, "history_ft.json"), "w"))

conv = tf.lite.TFLiteConverter.from_keras_model(model)
open(os.path.join(a.out, "classifier_fp32.tflite"), "wb").write(conv.convert())
conv = tf.lite.TFLiteConverter.from_keras_model(model); conv.optimizations = [tf.lite.Optimize.DEFAULT]
open(os.path.join(a.out, "classifier_dyn8.tflite"), "wb").write(conv.convert())

import sys; sys.path.insert(0, os.path.dirname(__file__)); from metrics_report import evaluate_tflite
crop = lambda i: classes[i].split("___")[0]
for m in ("classifier_fp32.tflite", "classifier_dyn8.tflite"):
    for t in TEST_DIRS:
        evaluate_tflite(os.path.join(a.out, m), S[t], classes, os.path.join(a.out, f"report_{m.split('.')[0]}_{t}"), img=a.img, group=crop)
