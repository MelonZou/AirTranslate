# EmbeddingGemma 2 로컬 파일 전사

AirTranslate **1.17.0 / build 1170**의 **설정 → 일반 → EmbeddingGemma 2 파일 전사 (실험)**에서
영어 오디오 파일을 이 Mac 안에서 전사할 수 있습니다.
이 추가 옵션에는 Apple Silicon·macOS 27 이상과 Core AI 지원이 필요합니다.
앱 자체의 최소 요구 사항은 계속 macOS 26이며 기존 Apple·클라우드 처리 방식도 사용할 수 있습니다.

## 사용 방법

1. 실시간 캡처를 종료합니다.
2. **모델 다운로드**를 눌러 약 935MB의 모델과 보조 파일을 받습니다.
   설치를 시작하려면 2GiB 이상의 여유 공간이 필요하며, 모델 로딩 시 로컬 컴파일에도 공간을 사용합니다.
3. **영어 음원 선택…**에서 로컬 오디오 파일을 선택합니다.
4. **로컬 전사 시작**을 누릅니다. 첫 모델 로딩에는 시간이 더 걸릴 수 있습니다.
5. **전사 복사**로 결과를 복사하거나 **텍스트 저장…**으로 UTF-8 파일을 저장합니다.
   다운로드·전사 중에는 **취소**를 누를 수 있습니다. 진행 중 모델 호출은 완료를 기다린 뒤 결과를 버립니다.

이 옵션은 실시간 자막과 독립적이며 기존 엔진·언어 설정을 바꾸지 않습니다.
영어 전용이며 문장부호와 대소문자를 복원하지 않습니다. 한국어 인식·번역·
화자 구분은 제공하지 않습니다. 파일은 최대 2GB, 음원은 최대 60분입니다.
긴 음원은 문맥이 겹치는 30초 창으로 처리하며 파일 전체 PCM을 메모리에 쌓지 않습니다.
결과가 비거나 부정확하면 음원 언어·잡음·고유명사를 확인하세요. 고정된 단어 목록 밖의 표현이나
억양에 따라 오류가 생길 수 있으므로 중요한 이름·숫자·표현은 원음과 대조하세요.

## 방법과 성능의 범위

[Google Gemma가 소개한 게시물](https://x.com/googlegemma/status/2113294644222259486)은
[Embedding Gemma Transcribe](https://eg2.haku.sh/)의 실험입니다.
이 방식은 긴 음원을 생성형 모델이 처음부터 끝까지 문장으로 작성하는 대신,
시간에 따라 이어지는 오디오 표현에서 영어 단어를 골라 전사를 만듭니다.

1. **고정된 오디오 인코더:** 사전 학습된 EmbeddingGemma 2 오디오 인코더가 음원을 시간별 표현으로 바꿉니다. 이 재현의 reader 학습 과정에서 인코더 가중치는 바꾸지 않습니다.
2. **학습된 reader와 단어 비교:** reader가 각 시간의 오디오 표현을 영어 단어 임베딩과 연결합니다. 각 시점에서 가장 가까운 단어 또는 단어가 없는 상태인 blank를 고릅니다.
3. **CTC 디코딩:** 연속해서 반복된 같은 단어 라벨을 합치고 blank를 제거해 전사 문자열을 만듭니다. 문장부호나 대소문자를 복원하는 별도 언어 모델은 사용하지 않습니다.

원 앱의 코드·reader 가중치는 공개되지 않았습니다.

AirTranslate는 같은 방법의 [독립 공개 재현](https://github.com/john-rocky/eg2-transcribe)과
[Core AI 모델의 reader v2](https://huggingface.co/mlboydaisuke/EmbeddingGemma-2-Transcribe-CoreAI)를
사용합니다. 원 앱과 가중치·단어 목록·후처리가 다릅니다.
원 개발자의 “1시간 약 13초” 수치는 이 구현의 보장값이 아닙니다. Mac의 종류·음원·첫 로딩 여부에 따라 달라집니다.
화면에는 선택한 음원의 길이와 이번 실행의 디코딩·모델 로딩을 포함한 처리 시간을 표시합니다.

## 다운로드와 개인정보

다운로드는 사용자가 버튼을 누를 때만 Hugging Face에 요청합니다.
음원·전사 결과를 네트워크에 전송하지 않으며 API 키도 필요하지 않습니다.
모델의 고정 revision은 `76865ae46793e05617c2a7420454b0c7eb8541a4`이며,
설치 파일의 크기와 SHA-256을 검사합니다. 모델·보조 파일은 총 935,493,417바이트(약 935MB / 892MiB)이며,
Mac용 인코더·reader 번들과 단어 목록·오디오 변환 데이터 등을 포함합니다.
실패하거나 취소한 부분 다운로드는 정리하고 설치로 간주하지 않습니다. 검증된 모델이 있으면 재사용합니다.

모델은 Application Support의 AirTranslate 모델 폴더에 저장하며,
LICENSE·NOTICE를 함께 보존합니다. 코드와 모델은 Apache-2.0이며,
[Gemma Prohibited Use Policy](https://ai.google.dev/gemma/prohibited_use_policy)가 적용됩니다.

## 다운로드와 첫 실행

- [AirTranslate 저장소](https://github.com/himomohi/AirTranslate)
- [1.17.0 릴리즈와 변경 내용](https://github.com/himomohi/AirTranslate/releases/tag/v1.17.0)
- [최신 AirTranslate.dmg](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)

DMG와 ZIP은 ad-hoc 서명 배포이며 Apple 공증을 받지 않았습니다.
처음 실행할 때 macOS가 차단하면 [설치 안내](GETTING-STARTED.md)를 확인하세요.
