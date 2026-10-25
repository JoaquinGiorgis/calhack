# YAMNet on Core ML

The app package is `ios/FortWatchListener/Models/YAMNet.mlpackage`. It contains
the original model's waveform frontend and all **521 AudioSet outputs**. No
TensorFlow library, network connection or custom Core ML operator is needed
on the phone. See `YAMNet-PROVENANCE.json` beside the model for source/package
hashes, versions, exact measurements and license provenance.

## Runtime contract

- Input: `waveform`, `MLMultiArray` Float32 `[15600]`, mono PCM at 16,000 Hz.
- Supply 15,600 consecutive samples (975 ms); recommended hop is 7,680 samples
  (480 ms). Convert PCM scaling to nominal `[-1, 1]`; do not normalize each
  window's volume. No spectrogram input or additional frontend is needed.
- Output: `scores`, Float32 `[521]`, indexed by `yamnet_class_map.csv`, 0–520.
  Scores are overlapping sigmoid outputs, not a mutually exclusive probability
  distribution. Ancestor and child classes can both score highly.
- Core ML MLProgram, iOS 16 minimum, Float32 computation. The verified runtime
  configuration is `.cpuOnly`; other compute configurations need their own
  parity check. Phone timing and microphone recognition remain separate tests.

The original frontend uses 400-sample periodic Hann windows, 160-sample hop,
512-point FFT magnitude, 64 mel bands (125–7,500 Hz), and `log(mel + 0.001)`.
One waveform input produces one 96 × 64 patch. These are the
[official YAMNet parameters](https://github.com/tensorflow/models/blob/master/research/audioset/yamnet/params.py)
and [feature operations](https://github.com/tensorflow/models/blob/master/research/audioset/yamnet/features.py).

## Reproduce conversion and validation

The existing repository environment already contains TensorFlow 2.20.0,
NumPy 2.4.6 and SciPy. Add the small conversion dependencies to a separate path
instead of duplicating TensorFlow:

```sh
uv pip install --python .venv/bin/python --target /tmp/fortwatch-yamnet-tools \
  --no-deps coremltools==9.0
uv pip install --python .venv/bin/python --target /tmp/fortwatch-yamnet-tools \
  sympy==1.14.0 tqdm==4.70.1 attrs==26.1.0 cattrs==26.2.1 pyaml==26.7.0
PYTHONPATH=/tmp/fortwatch-yamnet-tools .venv/bin/python tools/yamnet/convert.py \
  --output /tmp/fortwatch-yamnet-reproduced/YAMNet.mlpackage
python3 tools/yamnet/fetch_public_samples.py \
  --output-directory /tmp/fortwatch-yamnet-public
PYTHONPATH=/tmp/fortwatch-yamnet-tools .venv/bin/python tools/yamnet/validate.py \
  --model /tmp/fortwatch-yamnet-reproduced/YAMNet.mlpackage \
  --manifest /tmp/fortwatch-yamnet-public/evaluation-manifest.json \
  --output-directory /tmp/fortwatch-yamnet-validation
```

`convert.py` refuses to overwrite an existing output. The public sample fetch
is fixed at 26 files, about 11.5 MB, with per-file URLs, SHA-256 and attribution.
It uses the first two distinct source IDs in lexicographic filename order for
each selected class; predictions do not influence selection. No public audio
belongs in the app or repository. Validation saves all 521 raw scores per
window plus three small synthetic reference fixtures for Swift tests.

Apple's [TensorFlow conversion workflow](https://apple.github.io/coremltools/docs-guides/source/tensorflow-2.html)
supports fixed concrete functions. Two conversion-only bridges are used:

1. TensorFlow `ComplexAbs` maps to Core ML Tools' existing complex magnitude
   lowering.
2. The fixed 512-point RFFT becomes one-sided DFT matrix multiplication. Phase
   coefficients are computed in Float64 before storing Float32 constants. This
   avoids rounding phases in Float32 before sine/cosine. It is the same
   nonnormalized transform, with no learned-parameter tuning or retraining.

Core ML Tools 9.0 warns that TensorFlow 2.20 is newer than its tested 2.12. Actual
conversion and output comparison were completed with the versions above.

## Measured conversion evidence

On macOS 26.5.1, CPU-only inference over 26 public ESC-50 clips (234 windows)
and four synthetic windows gave:

| Measurement | Final package |
|---|---:|
| Maximum absolute score difference from original TensorFlow | 0.0000117123 |
| Mean absolute difference across all outputs | 0.000000007536 |
| Identical top-ranked class | 238 / 238 windows |
| Original acceptance bound, unchanged | Maximum difference < 0.001 |
| Warm prediction median / p95 | 1.52 / 1.66 ms |
| Model load / first prediction | 185 / 34.4 ms |
| Package bytes | 16,144,253 |

The first conversion using the generic FFT lowering **failed** the same 0.001
bound (maximum difference 0.001958). Its evidence remains in
`/tmp/fortwatch-yamnet-model/validation-initial.json`; the final comparison is
`validation.json`. No tolerance was widened. Timings exclude audio resampling
and file I/O and do not establish iPhone latency.

The final package was copied into the app and checked byte-for-byte against the
validated candidate. A later run of the portable conversion script reached the
converter but stopped with `Errno 28` when the host ran out of disk space; it did
not replace the validated package. Redundant temporary candidate packages were
removed, while their JSON reports and the synthetic reference fixtures remain.

These results validate conversion, not recognition accuracy. The broader
sample includes strong cat/rain/clapping outputs but also errors already made
by original YAMNet: one footsteps recording scored Fireworks strongly, and
washing-machine recordings resembled engines/trains. Public-data training
overlap is unknown. All 521 classes being available does not mean all 521 are
reliable in a room or suitable for alerts at one shared threshold.
