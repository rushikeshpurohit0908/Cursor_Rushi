# Qwen FPGA Example Design User Guide

This guide describes the model-to-DDR flow for the public Qwen2.5 FPGA
reference design and answers common questions about retrieval offload. It is
an integration guide, not a substitute for the converter, runtime, register
map, and bitstream that belong to a particular FPGA build.

## Scope and verified model

The published KV260 example uses **Qwen2.5-0.5B** on a Xilinx Kria KV260. The
Qwen model card describes the 0.5B checkpoint as 0.49 billion parameters
(0.36 billion excluding embeddings), with 24 decoder layers. The FPGA
reference paper calls the model `Qwen2.5-0.5B`; it does not identify an
instruction-tuned checkpoint, so do not assume `Qwen2.5-0.5B-Instruct` unless
the supplied model manifest or converter says so.

The design uses Activation-aware Weight Quantization (AWQ), with:

- INT4 quantized weights;
- FP16 scales and INT4 zero points;
- group size 64;
- hardware-specific `AWQ_MACRO` packing; and
- four independent 128-bit AXI channels feeding four MAC units.

The reported packed model size is 443.81 MB, reduced from a 988 MB baseline.
These figures describe the published implementation and are not universal
requirements for every Qwen FPGA design.

## Important distinction: datasets and weights

A custom dataset cannot be copied directly into the FPGA weight region.
There are three different artifacts:

1. **Training or fine-tuning data** changes model parameters through training.
2. **Calibration data** helps AWQ choose quantization scales; it does not
   train the model.
3. **Runtime RAG documents** are converted into a retrieval index and remain
   separate from Qwen model weights.

If the custom data is only used for RAG, leave the Qwen weights unchanged and
build a FAISS, BM25, or hybrid index. If it is used to fine-tune Qwen, produce
a complete compatible checkpoint before conversion.

## Supported checkpoint contract

Before converting a checkpoint, obtain the hardware release's machine-readable
contract. At minimum it must define:

- model identity, tensor names, shapes, and layer count;
- supported quantization method, bit widths, and group size;
- matrix traversal order and tiling;
- `AWQ_MACRO` field order and padding;
- byte order and AXI-lane interleaving;
- required tensor and section alignment;
- DDR capacity, reserved regions, and address width; and
- runtime/bitstream compatibility version.

Do not infer this contract from model dimensions alone. A valid AWQ file can
still produce incorrect output if its packing order differs from the RTL
unpacker.

## End-to-end workflow

### 1. Prepare a compatible model

Start from the exact checkpoint expected by the design. For a fine-tuned
model:

1. Use the same Qwen2.5 architecture and tokenizer as the supported base
   model.
2. Fine-tune without changing hidden size, layer count, vocabulary size, or
   tensor shapes.
3. If using LoRA or another adapter, merge it into the base model unless the
   runtime explicitly implements adapters.
4. Save a full checkpoint and tokenizer.
5. Run a CPU-framework inference test and record several prompts and logits
   as golden data.

Changing the architecture requires a new hardware build or, at minimum, a
converter and runtime that explicitly support the new dimensions.

### 2. Select calibration samples

Build a small, representative calibration set from the deployment workload.
It should cover expected prompt lengths, languages, and domains. Remove
secrets and personal data before processing it.

Calibration samples should use the model's normal chat template and tokenizer.
Keep a separate evaluation set; using the same samples for calibration and
quality evaluation hides quantization regressions.

### 3. Quantize with the release converter

Use the AutoAWQ version and options pinned by the hardware release. The public
design uses INT4 weights and group size 64. A generic invocation has this
shape:

```text
<release-quantizer> \
  --model <full-checkpoint-directory> \
  --calibration <calibration-dataset> \
  --weight-bits 4 \
  --group-size 64 \
  --output <quantized-checkpoint-directory>
```

The command name and remaining options are release-specific. Do not replace
the supplied converter with a generic AWQ exporter unless its output has been
shown to match the hardware packer.

After quantization, compare the quantized software model with the floating
point golden data. Check task quality as well as token-level output.

### 4. Pack weights for the FPGA

Run the hardware release's packer to transform the quantized checkpoint into
the exact DDR layout:

```text
<release-packer> \
  --model <quantized-checkpoint-directory> \
  --layout <hardware-layout-or-manifest> \
  --weights-out qwen_weights.bin \
  --manifest-out qwen_weights.json
```

The packer should:

- reject missing, extra, or incorrectly shaped tensors;
- reorder and tile each matrix for the processing-element array;
- pack qweights, scales, and zero points into `AWQ_MACRO` records;
- interleave records for the four AXI channels;
- insert required alignment padding; and
- emit offsets, lengths, checksums, quantization metadata, and a format
  version in the manifest.

For reproducibility, preserve the base model revision, adapter revision,
tokenizer files, calibration-data revision, converter commit, and bitstream
identifier alongside the output.

### 5. Validate before loading

Before touching the board:

1. Check that every manifest range lies inside the binary and does not overlap
   another range.
2. Check total size against the DDR region reserved by the hardware design.
3. Verify checksums.
4. Unpack a sample from every tensor and compare it with the software
   quantizer's qweights, scales, and zero points.
5. If the release provides a software model of the RTL data path, run the
   golden prompts through it.

Never continue after a format-version, shape, size, or checksum mismatch.

### 6. Transfer the image to the board

Copy `qwen_weights.bin`, its manifest, the model architecture JSON, and
tokenizer artifacts to persistent storage on the target. Verify checksums
after transfer. Program the matching FPGA bitstream before starting the
runtime.

### 7. Load the image into DDR

Use the release runtime or driver. A correct loader normally performs this
sequence:

1. Validate bitstream, runtime, and weight-format versions.
2. Allocate or map the reserved DMA-capable DDR region.
3. Copy each manifest section to its assigned offset.
4. Flush CPU caches or synchronize the DMA buffer for the device.
5. Program physical base addresses and section lengths in accelerator
   registers.
6. Issue the start/load command and wait with a timeout.
7. Check completion and error status.

Example pseudocode:

```c
manifest = validate_manifest("qwen_weights.json", "qwen_weights.bin");
buffer = fpga_alloc_dma(manifest.total_size, manifest.required_alignment);
copy_file_to_buffer("qwen_weights.bin", buffer);
fpga_sync_for_device(buffer);
fpga_program_weight_regions(buffer.physical_address, manifest);
fpga_start();
fpga_wait_ready(TIMEOUT_MS);
fpga_check_status();
```

Do not write to arbitrary physical addresses with `/dev/mem` unless the
hardware release explicitly requires it. A runtime-owned DMA buffer or
reserved-memory driver prevents collisions with Linux and handles cache
coherency.

### 8. Run a smoke test

Start with deterministic decoding and a short known prompt. Compare:

- first-token logits or top-k token IDs, if exposed;
- generated token IDs and text;
- accelerator status counters;
- bytes read from DDR; and
- timeout, AXI, ECC, or decode errors.

Small floating-point differences are expected after INT4 quantization, so
task-level quality and perplexity should also be evaluated. A gross mismatch
on the first layer usually indicates an offset, byte-order, interleaving, or
packing error rather than quantization quality.

## Updating the model safely

Treat a packed model as an immutable, versioned release. If the platform
supports two DDR slots, load and validate the inactive slot before atomically
switching the active base address. Otherwise stop inference before replacing
weights. Never overwrite a region while the accelerator can read it.

Retain the previous known-good binary and manifest for rollback.

## Can FAISS or BM25 be offloaded to the FPGA?

**Yes, selected retrieval kernels can be offloaded, but FAISS and BM25 cannot
be moved to the FPGA as unmodified software libraries.** They need
hardware-specific kernels, index layouts, and host/runtime integration.

Good FPGA candidates include:

- exact inner-product or L2 vector scans (`IndexFlat`-like search);
- IVF list scanning and product-quantization lookup/accumulation;
- streaming BM25 posting-list scoring; and
- top-k selection.

CPU-side work should normally retain:

- document ingestion, tokenization, and index construction/update;
- query planning and metadata filters;
- graph traversal with irregular memory access, such as HNSW;
- result assembly and RAG prompt construction; and
- control flow and error handling.

A practical hybrid pipeline is:

```text
CPU: tokenize query / create query embedding
  -> FPGA: vector or posting-list scan + top-k
  -> CPU: merge FAISS and BM25 scores, filter, fetch document text
  -> Qwen runtime: prompt prefill and generation
```

For hybrid retrieval, normalize the vector and BM25 scores before fusion, or
use reciprocal-rank fusion. Returning only document IDs and scores keeps
FPGA-to-CPU traffic small.

Offload is worthwhile only after measuring end-to-end latency. Index transfer,
DMA setup, and synchronization can outweigh kernel savings for a small index
or one query at a time. On a shared-DDR SoC such as KV260, retrieval and Qwen
also compete for memory bandwidth; benchmark concurrent and sequential
schedules. Large, persistent indexes, batched queries, regular access
patterns, and reusable top-k hardware make FPGA acceleration more attractive.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Loader rejects the image | Manifest/bitstream version, size, or checksum mismatch |
| AXI fault or immediate hang | Invalid physical address, alignment, or section length |
| Output is random from the first token | Wrong tensor order, byte order, lane interleave, or tokenizer |
| Output is coherent but quality is lower | Poor calibration coverage, wrong group size, or excessive quantization error |
| Fine-tuned behavior is absent | Adapter was not merged or packed |
| Retrieval offload is slower | Transfer/setup overhead or DDR contention exceeds kernel savings |

## References

- Qwen team, [Qwen2.5-0.5B-Instruct model
  card](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct)
- Xiang et al., [On-Device Qwen2.5: Efficient LLM Inference with Model
  Compression and Hardware
  Acceleration](https://arxiv.org/abs/2504.17376)
- Qwen team, [Qwen2.5 release
  overview](https://qwenlm.github.io/blog/qwen2.5/)
