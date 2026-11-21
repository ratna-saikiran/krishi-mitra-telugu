"""PTQ: Keras -> full-integer INT8 TFLite (int8 weights+activations, float32 I/O).
Float I/O keeps the graph fully delegable to XNNPACK (a uint8 input QUANTIZE
node is not), at the cost of 2 tiny (de)quantize ops."""
import json, os, random, sys
import numpy as np, tensorflow as tf
from PIL import Image
out = sys.argv[1] if len(sys.argv) > 1 else "ml/out"
model = tf.keras.models.load_model(f"{out}/classifier.keras")
train = json.load(open(f"{out}/split.json"))["train"]
random.seed(0); rep_items = random.sample(train, 300)
def rep():
    for p in rep_items:
        yield [np.asarray(Image.open(p).convert("RGB").resize((224, 224)), np.float32)[None]]
conv = tf.lite.TFLiteConverter.from_keras_model(model)
conv.optimizations = [tf.lite.Optimize.DEFAULT]
conv.representative_dataset = rep
conv.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
open(f"{out}/classifier_int8.tflite", "wb").write(conv.convert())
it = tf.lite.Interpreter(model_path=f"{out}/classifier_int8.tflite"); it.allocate_tensors()
print("XNNPACK OK", it.get_input_details()[0]["dtype"])
