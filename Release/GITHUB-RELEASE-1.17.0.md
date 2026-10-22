# AirTranslate 1.17.0

AirTranslate 1.17.0 / build 1170 adds **EmbeddingGemma 2 file transcription (experimental)** in Settings > General. It transcribes an English audio file locally on a supported Mac, with explicit model download, cancellation, copying, and text export. Apple Mode remains the default workflow.

## How the method works

The [Google Gemma post](https://x.com/googlegemma/status/2113294644222259486) introduces the [Embedding Gemma Transcribe experiment](https://eg2.haku.sh/). Its audio encoder stays frozen: it turns audio into a sequence of representations over time. A trained reader maps those representations into the text-embedding space and selects the closest English word or a blank label at each step. CTC decoding collapses consecutive repetitions and removes blank labels to form the transcript.

The original app's code and reader weights are not public. AirTranslate uses the [independent open reproduction](https://github.com/john-rocky/eg2-transcribe) and its [public Core AI reader v2 models](https://huggingface.co/mlboydaisuke/EmbeddingGemma-2-Transcribe-CoreAI). This reader uses a fixed English word vocabulary; it is not a general speech-language model. Its weights, vocabulary, and processing differ from the original app. The original developer's claim of **one hour of audio in about 13 seconds is not an AirTranslate performance guarantee**.

## Added

- **Local English file transcription:** an optional tool separate from live captions. Supports audio files up to 60 minutes / 2 GB on Apple Silicon with macOS 27 or later. It does not restore punctuation or capitalization, translate the audio, or identify speakers. Accent, noise, unfamiliar names, and words outside the vocabulary affect accuracy.
- **Explicit model installation:** Download models fetches about 935 MB from Hugging Face only when requested. A fixed revision, file sizes, and SHA-256 hashes are checked before installation is accepted. Installation needs at least 2 GiB of free space; local model compilation also uses disk space. Download failure or cancellation does not turn a partial download into an installed model.
- **Local data handling:** no API key is required. This option does not upload the selected audio or transcript. Once models are installed, transcription runs on the Mac using Core AI.
- **Progress and export:** cancel a download or transcription, copy the transcript, or save UTF-8 text. The view shows the chosen audio's length and processing time for the current run, including decoding and model loading. The first load may take longer while models compile. Cancellation discards the result after any active model call finishes.

## Use it

1. Open **Settings > General > EmbeddingGemma 2 file transcription (experimental)** on a supported Mac and stop live capture.
2. Choose **Download models** and wait for verification to finish.
3. Choose **Choose English audio…**, then **Transcribe locally**.
4. Review the result, then use **Copy transcript** or **Save text…**. Use **Cancel** to stop the operation.

The tool leaves the existing engine and language selections in place. See the [method, setup, privacy and limitations guide](https://github.com/himomohi/AirTranslate/blob/master/docs/embeddinggemma-transcription.md).

## 한국어 안내: 방법과 사용법

이번 추가 옵션은 고정된 오디오 인코더가 만든 시간별 표현을 학습된 reader로 영어 단어 임베딩에 연결하는 방식입니다. 시점별 단어 또는 blank를 선택하고, CTC가 연속 중복과 blank를 정리해 전사 결과를 만듭니다. Google Gemma가 소개한 원 앱의 코드·reader 가중치는 공개되지 않았으므로, AirTranslate는 독립 공개 재현의 reader v2와 Core AI 모델을 사용합니다. 원 실험의 “1시간 약 13초”를 이 앱의 속도로 보장하지 않습니다.

**설정 > 일반 > EmbeddingGemma 2 파일 전사 (실험)**에서 실시간 캡처를 종료하고, **모델 다운로드**로 약 935MB를 받은 뒤 **영어 음원 선택… → 로컬 전사 시작**을 누르세요. Apple Silicon·macOS 27 이상이 필요하고, 영어 음원 최대 60분/2GB를 지원합니다. 모델 설치에는 2GiB 이상의 여유 공간이 필요하며 파일 크기·SHA-256을 확인합니다. 음원·전사 결과는 업로드하지 않습니다. 진행 중 취소할 수 있고 결과는 복사하거나 UTF-8 텍스트로 저장할 수 있습니다. 문장부호·대소문자 복원과 번역·화자 구분은 제공하지 않습니다. 앱 자체는 계속 macOS 26 이상에서 실행됩니다. [자세한 방법·설정·개인정보 안내](https://github.com/himomohi/AirTranslate/blob/master/docs/embeddinggemma-transcription.md).

## Existing improvements retained

The caption and translation improvements introduced in **1.16.0** remain available: floating-only capture and window restoration, previous-caption history, caption reading position, bounded display work, recognition context, final-segment preservation, duplicate-translation reuse, and protection against late results from stopped sessions. Apple translation quality/protected-term choices and opt-in Jev candidate selection also remain available. These are retained features, not new fixes in 1.17.0.

## Compatibility and distribution

The app's minimum system remains **macOS 26**. Only the new local file-transcription option requires **Apple Silicon and macOS 27+** with Core AI support. Existing Apple and cloud workflows remain available under their existing requirements.

DMG and ZIP artifacts are **ad-hoc signed and not Apple-notarized**. macOS may show an unidentified-developer warning on first launch; follow the [installation guide](https://github.com/himomohi/AirTranslate/blob/master/docs/GETTING-STARTED.md). Compare the DMG with its `.sha256` file before installing. Permission inheritance across updates is not guaranteed.

AirTranslate is an independent Apache-2.0 project and is not affiliated with Google or other model providers. The public reproduction and model attribution are included in NOTICE; model use follows the [Gemma Prohibited Use Policy](https://ai.google.dev/gemma/prohibited_use_policy).

## Download

- [Repository](https://github.com/himomohi/AirTranslate)
- [AirTranslate 1.17.0 release](https://github.com/himomohi/AirTranslate/releases/tag/v1.17.0)
- [Latest stable DMG download](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)
- [AirTranslate-1.17.0.zip](https://github.com/himomohi/AirTranslate/releases/download/v1.17.0/AirTranslate-1.17.0.zip)

Version: **1.17.0 / build 1170**. Released **2026-10-23**.
