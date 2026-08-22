# Mumble Signal Lab

Signal Lab is a command-line companion for measuring Mumble's local speech engines on the
same audio. It is independent of the menu-bar app and writes a structured JSON report for
later inspection.

```bash
cd lab
swift run mumble-signal-lab record take1.wav
swift run mumble-signal-lab run take1.wav
```

Recording captures 16 kHz mono audio until Return is pressed. To score accuracy, write down
the words you actually said:

```bash
echo "the quick brown fox jumps over the lazy dog" > take1.txt
swift run mumble-signal-lab run take1.wav --ref take1.txt
```

Options:

- `--v2` selects Parakeet TDT v2, an English-focused model.
- `--int4` selects the smaller INT4 encoder.
- `--ref FILE` adds word and character error rates against a reference transcript.

A run prints a compact summary and writes `take1-results.json` beside the input. It measures
local processing, not the experience of seeing live words in the HUD.

## Measurements

**Load seconds** is model preparation and loading. It is reported separately because Apple
Speech assets are managed by macOS while Parakeet prepares local CoreML assets on first use.

**Process seconds** is wall-clock time from the start of transcription to final text.

**RTF** is audio seconds processed per wall-clock second. A result of 100x means a 60-second
recording was processed in 0.6 seconds.

**WER/CER** are word and character error rates calculated with Levenshtein distance. Scoring
normalizes case, punctuation, and whitespace so formatting differences do not overwhelm the
recognition result.

## Local models

FluidAudio manages Parakeet's CoreML model assets under:

`~/Library/Application Support/FluidAudio/Models/`

The app and Signal Lab reuse those local assets after their first preparation. No audio is
sent to a remote transcription service by this tool.

## Limits

Signal Lab uses whole-file processing for a reproducible throughput measurement. Apple Speech
also supports streaming in Mumble, while the current Parakeet path resolves after capture
ends. RTF therefore answers a throughput question, not which engine feels fastest while
speaking.
