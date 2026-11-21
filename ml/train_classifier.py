"""Train MobileNetV3-Large on PlantVillage, then PTQ to INT8 TFLite.

Usage: python ml/train_classifier.py --pv data/pv/raw/color --out ml/out
Two stages: (1) frozen backbone + new head, (2) fine-tune top blocks.
Heavy augmentation narrows the lab->field gap (evaluated on PlantDoc).
"""
import argparse, json, os, random, time
import numpy as np
import tensorflow as tf

p = argparse.ArgumentParser()
p.add_argument("--pv", required=True)
p.add_argument("--out", default="ml/out")
p.add_argument("--plantdoc_train", default=None, help="PlantDoc train dir: field images mixed into training")
p.add_argument("--pd_repeat", type=int, default=3)
p.add_argument("--train_per_class", type=int, default=300)
p.add_argument("--val_per_class", type=int, default=40)
p.add_argument("--test_per_class", type=int, default=100)
p.add_argument("--epochs_head", type=int, default=3)
p.add_argument("--epochs_ft", type=int, default=2)
p.add_argument("--img", type=int, default=224)
p.add_argument("--bs", type=int, default=32)
a = p.parse_args()
os.makedirs(a.out, exist_ok=True)
random.seed(0); tf.random.set_seed(0)

classes = sorted(d for d in os.listdir(a.pv) if os.path.isdir(os.path.join(a.pv, d)))
split = {"train": [], "val": [], "test": []}
for ci, c in enumerate(classes):
    fs = sorted(os.listdir(os.path.join(a.pv, c))); random.shuffle(fs)
    fs = [os.path.join(a.pv, c, f) for f in fs]
    nt = min(a.test_per_class, len(fs) // 5); nv = min(a.val_per_class, len(fs) // 10)
    split["test"] += [(f, ci) for f in fs[:nt]]
    split["val"] += [(f, ci) for f in fs[nt:nt + nv]]
    split["train"] += [(f, ci) for f in fs[nt + nv:nt + nv + a.train_per_class]]
if a.plantdoc_train:
    import sys; sys.path.insert(0, os.path.dirname(__file__)); from plantdoc_map import PD2PV
    pd = []
    for d, lab in PD2PV.items():
        dd = os.path.join(a.plantdoc_train, d)
        if os.path.isdir(dd):
            pd += [(os.path.join(dd, f), classes.index(lab)) for f in sorted(os.listdir(dd))]
    print("plantdoc train", len(pd))
    split["train"] += pd * a.pd_repeat
for k, v in split.items():
    print(k, len(v))
with open(os.path.join(a.out, "labels.txt"), "w") as f:
    f.write("\n".join(classes) + "\n")
with open(os.path.join(a.out, "split.json"), "w") as f:
    json.dump({k: [x[0] for x in v] for k, v in split.items()}, f)

def load(path, label):
    img = tf.io.decode_image(tf.io.read_file(path), channels=3, expand_animations=False)
    img = tf.image.resize(img, (a.img, a.img))
    return img, label

aug = tf.keras.Sequential([
    tf.keras.layers.RandomFlip("horizontal_and_vertical"),
    tf.keras.layers.RandomRotation(0.15),
    tf.keras.layers.RandomZoom((-0.1, 0.3)),
    tf.keras.layers.RandomTranslation(0.1, 0.1),
    tf.keras.layers.RandomBrightness(0.25, value_range=(0, 255)),
    tf.keras.layers.RandomContrast(0.3),
])

def ds(items, train):
    paths, labels = zip(*items)
    d = tf.data.Dataset.from_tensor_slices((list(paths), list(labels)))
    if train: d = d.shuffle(len(items), seed=0)
    d = d.map(load, num_parallel_calls=tf.data.AUTOTUNE).batch(a.bs)
    if train:
        d = d.map(lambda x, y: (tf.clip_by_value(aug(x, training=True), 0, 255), y),
                  num_parallel_calls=tf.data.AUTOTUNE)
    return d.prefetch(tf.data.AUTOTUNE)

tr, va, te = ds(split["train"], True), ds(split["val"], False), ds(split["test"], False)

base = tf.keras.applications.MobileNetV3Large(
    input_shape=(a.img, a.img, 3), include_top=False, weights="imagenet",
    include_preprocessing=True, pooling="avg")
base.trainable = False
inp = tf.keras.Input((a.img, a.img, 3))
x = base(inp, training=False)
x = tf.keras.layers.Dropout(0.3)(x)
out = tf.keras.layers.Dense(len(classes), activation="softmax")(x)
model = tf.keras.Model(inp, out)
model.compile(tf.keras.optimizers.Adam(1e-3), "sparse_categorical_crossentropy", metrics=["accuracy"])
t = time.time(); model.fit(tr, validation_data=va, epochs=a.epochs_head, verbose=2)
print("stage1 s", time.time() - t)

base.trainable = True
for l in base.layers[:-60]:
    l.trainable = False
for l in base.layers:
    if isinstance(l, tf.keras.layers.BatchNormalization): l.trainable = False
model.compile(tf.keras.optimizers.Adam(1e-4), "sparse_categorical_crossentropy", metrics=["accuracy"])
t = time.time(); model.fit(tr, validation_data=va, epochs=a.epochs_ft, verbose=2)
print("stage2 s", time.time() - t)
model.save(os.path.join(a.out, "classifier.keras"))
print("keras test", model.evaluate(te, verbose=0))

# ---- TFLite export: FP32 here, full-integer INT8 PTQ in convert_int8.py ----
conv = tf.lite.TFLiteConverter.from_keras_model(model)
open(os.path.join(a.out, "classifier_fp32.tflite"), "wb").write(conv.convert())

import subprocess, sys
subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "convert_int8.py"), a.out], check=True)
print("done")
