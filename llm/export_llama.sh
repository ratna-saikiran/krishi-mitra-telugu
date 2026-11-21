#!/usr/bin/env bash
# Export Llama 3.2 1B Instruct to an ExecuTorch .pte for Android (XNNPACK, Arm CPU).
# Follows the Arm Learning Path "Build a Llama 3 chat Android app using
# ExecuTorch and XNNPACK" (ExecuTorch release/1.0). Run on your Mac/Linux box
# (16 GB RAM is enough for 1B), NOT on the phone.
#
# Prereq (only you can do this): accept the Llama 3.2 license, then
#   pip install llama-stack && llama model download --source meta --model-id Llama3.2-1B-Instruct
# (paste the signed URL Meta e-mails you). Files land in ~/.llama/checkpoints/Llama3.2-1B-Instruct
set -euo pipefail
CKPT="${CKPT:-$HOME/.llama/checkpoints/Llama3.2-1B-Instruct}"
WORK="${WORK:-$HOME/krishi-et}"
SEQ="${SEQ:-2048}"   # Telugu tokenises long in Llama 3's vocab, so 2048 not 1024
OUT="llama3_2_1b_instruct_8da4w_g64_emb4_seq${SEQ}.pte"

mkdir -p "$WORK" && cd "$WORK"
if [ ! -d executorch ]; then
  python3 -m venv et-venv   # Python 3.10-3.12
  git clone https://github.com/pytorch/executorch.git
  (cd executorch && git checkout release/1.0 && git submodule sync && git submodule update --init --recursive)
fi
source et-venv/bin/activate
cd executorch
if ! python -c "import executorch" 2>/dev/null; then
  ./install_executorch.sh
  ./examples/models/llama/install_requirements.sh
fi

# 8da4w: INT4 weights (group 64) + INT8 dynamic activations, PTQ.
# 4-bit embedding (group 32) because Llama 3's 128k vocab makes it large.
# KV cache + custom SDPA; XNNPACK delegate (uses Arm KleidiAI micro-kernels).
python -m examples.models.llama.export_llama \
  --checkpoint "$CKPT/consolidated.00.pth" \
  --params "$CKPT/params.json" \
  -kv --use_sdpa_with_kv_cache -X --xnnpack-extended-ops -qmode 8da4w \
  --group_size 64 -d fp32 \
  --metadata '{"get_bos_id":128000, "get_eos_ids":[128009, 128001, 128006, 128007]}' \
  --embedding-quantize 4,32 \
  --max_seq_length "$SEQ" --max_context_length "$SEQ" \
  --output_name="$OUT"

cp "$CKPT/tokenizer.model" "$WORK/tokenizer.model"
mv "$OUT" "$WORK/"
ls -lh "$WORK/$OUT" "$WORK/tokenizer.model"
echo "Next: bash llm/push_to_phone.sh $WORK/$OUT $WORK/tokenizer.model"
