import Foundation

enum EmbeddingGemmaCopy {
    static var title: String { copy("EmbeddingGemma 2 file transcription (experimental)", "EmbeddingGemma 2 파일 전사 (실험)", "EmbeddingGemma 2 ファイル文字起こし（実験）", "EmbeddingGemma 2 文件转写（实验）") }
    static var detail: String { copy("Transcribe an English audio file on this Mac using an independent open reproduction of the EmbeddingGemma 2 experiment. Results have no punctuation or capitalization. Accuracy varies with accents, noise and names.", "EmbeddingGemma 2 실험의 독립 공개 재현 모델로 영어 오디오 파일을 이 Mac에서 전사합니다. 문장부호·대소문자는 복원하지 않으며, 억양·잡음·고유명사에 따라 정확도가 달라집니다.", "EmbeddingGemma 2実験の独立した公開再現モデルで、英語の音声ファイルをこのMac上で文字起こしします。句読点・大文字小文字は復元せず、訛り・雑音・固有名詞で精度が変わります。", "使用 EmbeddingGemma 2 实验的独立公开复现模型，在此 Mac 上转写英语音频文件。不恢复标点或大小写，口音、噪声和专有名词会影响准确率。") }
    static var requirements: String { copy("Requires Apple Silicon and macOS 27 or later. Download the models once (about 935 MB); local compilation also needs free disk space. English audio only, up to 60 minutes / 2 GB. Audio is processed locally and never uploaded. This works separately from live captions.", "Apple Silicon·macOS 27 이상이 필요합니다. 모델을 한 번 다운로드하며(약 935MB), 로컬 컴파일용 여유 공간도 필요합니다. 영어 음원 전용이며 최대 60분/2GB입니다. 음원을 업로드하지 않고 기기에서 처리하며, 실시간 자막과 별도로 사용합니다.", "Apple SiliconとmacOS 27以降が必要です。モデルを一度ダウンロードします（約935 MB）。ローカルコンパイル用の空き容量も必要です。英語音声のみ、最大60分／2 GB。音声はアップロードせず端末内で処理し、ライブ字幕とは独立して動作します。", "需要 Apple Silicon 和 macOS 27 或更新版本。模型仅需下载一次（约 935 MB），本地编译还需额外磁盘空间。仅支持英语音频，最长 60 分钟／2 GB。音频在本机处理且不上传，与实时字幕独立运行。") }
    static var download: String { copy("Download models", "모델 다운로드", "モデルをダウンロード", "下载模型") }
    static var checking: String { copy("Checking model integrity…", "모델 무결성 확인 중…", "モデルの整合性を確認中…", "正在校验模型…") }
    static var downloading: String { copy("Downloading and verifying models…", "모델 다운로드·검증 중…", "モデルをダウンロード・検証中…", "正在下载并校验模型…") }
    static var ready: String { copy("Models verified · ready for local transcription", "모델 검증 완료 · 로컬 전사 준비됨", "モデル検証済み・ローカル文字起こし可能", "模型已校验 · 可本地转写") }
    static var choose: String { copy("Choose English audio…", "영어 음원 선택…", "英語音声を選択…", "选择英语音频…") }
    static var start: String { copy("Transcribe locally", "로컬 전사 시작", "ローカル文字起こし", "开始本地转写") }
    static var working: String { copy("Transcribing on this Mac… First model load may take longer.", "이 Mac에서 전사 중… 첫 모델 로딩은 시간이 더 걸릴 수 있습니다.", "このMacで文字起こし中…初回のモデル読み込みには時間がかかる場合があります。", "正在此 Mac 上转写…首次加载模型可能需要更长时间。") }
    static var cancel: String { copy("Cancel", "취소", "キャンセル", "取消") }
    static var stopping: String { copy("Stopping… Waiting for the current model call to finish.", "취소 중… 진행 중인 모델 호출이 끝나기를 기다립니다.", "停止中…実行中のモデル処理の完了を待っています。", "正在停止…等待当前模型调用结束。") }
    static var copyResult: String { copy("Copy transcript", "전사 복사", "文字起こしをコピー", "复制转写文本") }
    static var save: String { copy("Save text…", "텍스트 저장…", "テキストを保存…", "保存文本…") }
    static var unsupported: String { copy("This option requires Apple Silicon, macOS 27 and a build with Core AI support.", "이 옵션에는 Apple Silicon·macOS 27과 Core AI를 지원하는 빌드가 필요합니다.", "この機能にはApple Silicon、macOS 27、Core AI対応ビルドが必要です。", "此选项需要 Apple Silicon、macOS 27 和支持 Core AI 的构建。") }
    static var captureActive: String { copy("Stop live capture before running this experimental model to avoid competing for resources.", "실험 모델이 자원을 함께 사용하지 않도록 실시간 캡처를 종료한 뒤 실행하세요.", "実験モデルとのリソース競合を避けるため、ライブキャプチャを停止してから実行してください。", "请先停止实时采集，以免与实验模型争用资源。") }
    static var empty: String { copy("No English speech was recognized. Check the audio and language.", "인식된 영어 음성이 없습니다. 음원과 언어를 확인하세요.", "英語の音声を認識できませんでした。音源と言語を確認してください。", "未识别到英语语音。请检查音频和语言。") }
    static var source: String { copy("About the method and model", "방법·모델 정보", "手法とモデルについて", "方法与模型信息") }
    static func measurements(duration: Double, elapsed: Double) -> String {
        String(format: copy("Audio %.1f s · processing %.2f s (this run)", "음원 %.1f초 · 처리 %.2f초 (이번 실행)", "音声 %.1f秒・処理 %.2f秒（今回の実行）", "音频 %.1f 秒 · 处理 %.2f 秒（本次运行）"), duration, elapsed)
    }
    private static func copy(_ en: String, _ ko: String, _ ja: String, _ zh: String) -> String {
        AppText.localized(english: en, korean: ko, japanese: ja, chineseSimplified: zh)
    }
}
