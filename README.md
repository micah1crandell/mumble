# Mumble

Mumble is a free, open-source Wispr Flow alternative for macOS that uses local speech models instead of sending your voice to a cloud transcription service. Hold a global push-to-talk key, speak naturally, and Mumble cleans up the result and types it into the text field you are using when you release the key.

### Features

* **Local transcription:** Choose Apple's real-time SpeechAnalyzer or the offline Parakeet model. Your audio and transcripts stay on your Mac.
* **Push-to-talk everywhere:** Use Right Option, Right Command, or Fn from any application without changing focus.
* **Smart cleanup:** Add punctuation, casing, and formatting with on-device Apple Foundation Models when available.
* **Personal dictionary:** Teach Mumble names, terms, and correction rules with deterministic longest-match replacements.
* **Quiet macOS experience:** Run as a menu-bar app with no Dock footprint, a compact blurred HUD, and automatic launch at login.
* **History and Signal Lab:** Review locally stored transcripts and compare the two local engines on identical recordings without inserting text.

---

### Getting Started

Install the app to `/Applications` with proper code-signing bindings:

```bash
make install
```

On first run, grant the system prompts:
* **Microphone Access:** Captures incoming audio streams during key presses.
* **Accessibility Access:** Listens for global hotkey toggles and inserts converted text into target UI elements.

*Tip: The default trigger key is **Right Option** (switchable to **Right Command** or **Fn** in Preferences). The app launches automatically at login by default.*

---

### Transcription Lifecycle

```
[Key Down] ──► Global Event Monitor (Preserves non-trigger input)
                 │
                 ▼
               AudioStreamer ──► HUD Waveform / Level Meter
                 │
                 ▼
               Inference Engine (Apple Speech streaming or on-device Parakeet)
                 │
                 ▼
               Text Normalization (Punctuation, casing, filler removal via Foundation Models)
                 │
                 ▼
               Vocabulary Matching (Deterministic longest-match override)
                 │
[Key Up]   ──► Active Element Injector (Accessibility API with Clipboard fallback)
```

* **Local Ledger:** Run histories are appended to `~/Library/Application Support/Mumble/runs.jsonl`. No audio or text leaves your machine.

---

### Core Components & Tooling

| Component | Responsibility | Technical Notes |
| :--- | :--- | :--- |
| **Apple Speech** | Real-time streaming transcription | Provides immediate visual feedback during dictation. |
| **Parakeet** | Offline transcription engine | Resolves the entire audio segment immediately upon key release. |
| **Foundation Cleanup** | Semantic grammar & styling | Uses on-device Apple Foundation Models to punctuate and format. |
| **Custom Lexicon** | Terminology & name substitutions | Longest-match deterministic replacement dictionary. |
| **Signal Lab** | Model benchmarking & comparison | Head-to-head engine comparison (WER/CER, throughput) without field insertion. |

---

### Development & Build Workflow

All build artifacts and staging bundles are isolated to `~/Library/Caches/MumbleBuild` to prevent conflicts with cloud-synced project directories.

**Command Reference:**
```bash
make build       # Compile Swift package targets
make app         # Package and sign the .app wrapper
make install     # Build, stage to /Applications, and execute
make clean       # Flush staging directory and cached builds
```

**Permission Debugging:**
TCC security bindings bind to the application's code signature. If testing requires clearing cached permission states:
```bash
tccutil reset Accessibility com.micahcrandell.mumble
tccutil reset Microphone com.micahcrandell.mumble
```

**Repository Map:**
* `app/runtime/`: Global key hooks, audio capture queues, and insertion dispatchers.
* `app/speech/`: Speech-to-text drivers for Apple Speech and Parakeet.
* `app/polish/`: Heuristic and Foundation Model cleanup logic.
* `app/vocabulary/`: Local vocabulary storage and dictionary integration.
* `app/interface/`: Menu bar delegate, settings pane, and capture overlay HUD.
* `app/platform/`: Config store, local event logging, and permission handlers.
* `kit/dictionary/`: Standalone vocabulary replacement package.
* `lab/`: Dedicated command-line utility for offline accuracy and latency evaluation.
* `qa/dictionary/`: Executable tests for the dictionary contract.

**Targeted Tests:**
Validate dictionary mapping against the synchronized spec:
```bash
swift test --filter VectorTests
```

---

### Technical Constraints

* Target text fields must exist in a focused, running macOS application; automated UI insertion cannot run in headless CI environments.
* macOS 26 or later is required to utilize native `SpeechAnalyzer` and local Foundation Models.
* Signal Lab evaluates pure engine throughput and error rates rather than end-to-end user-perceived stream latency.