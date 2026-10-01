# urayoutube

YouTube動画の日本語字幕を取得し、VOICEVOX で美少女ボイスに変換する。

## 構成

```
voicevox/           VTT → VOICEVOX 変換
  vtt_to_voicevox.py
  speakers.py       話者ID一覧
```

## 事前インストール（環境に合わせて各自）

このプロジェクト自体には含まれないので、使うマシンに合わせて入れておく。

| もの | 用途 | メモ |
|------|------|------|
| [Docker](https://docs.docker.com/get-docker/) | VOICEVOX Engine の実行 | WSL2 なら Docker Desktop の WSL 連携を有効に |
| [VOICEVOX Engine](https://github.com/VOICEVOX/voicevox_engine) | 音声合成（ボイロ） | 通常は Docker イメージで起動。GPU なら NVIDIA Container Toolkit も |
| [Ollama](https://ollama.com/) | 字幕の校正・読み上げパラメータ推定 | `ollama pull llama3` など、スクリプトが呼ぶモデルも入れておく |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | YouTube 字幕の取得 | |
| Python 3 | 変換スクリプト | `venv` 推奨 |
| （任意）CUDA / 対応 GPU | VOICEVOX GPU 版 | 無い場合は CPU で可（遅い） |

Windows + WSL2 想定。パスやインストール方法は OS ごとに違うので、公式手順に従うこと。

## 準備

`setup.sh` / `start.sh` / `update.sh` は製作者の PC（Windows + WSL2 想定）向けの参考実装です。  
環境やパス・入れ方が違う前提なので、**中身を確認したうえで、自分のマシンに合わせて改変してから実行してください。** 無改造のまま動く保証はありません。

初回セットアップ:

```bash
./setup.sh              # venv + yt-dlp 確認 + VOICEVOX イメージ + Ollama モデル
./setup.sh --cpu        # VOICEVOX は CPU 版イメージを取得
./setup.sh --python-only  # Python venv のみ
```

依存の更新:

```bash
./update.sh              # Python パッケージ + yt-dlp
./update.sh --all        # 上記 + VOICEVOX Docker イメージ + Ollama モデル
./update.sh --python     # venv 内の pip のみ
./update.sh --docker     # VOICEVOX イメージのみ
./update.sh --ollama     # llama3 など（OLLAMA_MODEL で変更可）
```

依存サービス（VOICEVOX + Ollama）の起動:

```bash
./start.sh          # GPU 版 VOICEVOX（デフォルト）
./start.sh --cpu    # CPU 版
```

手動で起動する場合（GPU 推奨）:

```bash
docker run --rm --gpus all -p 50021:50021 voicevox/voicevox_engine:nvidia-ubuntu20.04-latest
```

CPU のみの場合:

```bash
docker run --rm -it -p 50021:50021 voicevox/voicevox_engine:cpu-ubuntu20.04-latest
```

字幕校正に使う Ollama:

```bash
ollama serve
```

依存関係（`./setup.sh` が自動で行う。手動なら）:

```bash
cd voicevox
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

音声再生（WSLg）:

```bash
sudo apt install alsa-utils
```

## 字幕の取得

```bash
# 利用可能な字幕を確認
yt-dlp --list-subs "https://www.youtube.com/watch?v=VIDEO_ID"

# 手動字幕
yt-dlp --skip-download --write-subs --sub-lang ja \
  --sleep-interval 5 --max-sleep-interval 15 \
  "https://www.youtube.com/watch?v=VIDEO_ID"

# 自動生成字幕
yt-dlp --write-auto-subs --sub-langs ja --skip-download \
  --sleep-interval 5 --max-sleep-interval 15 \
  "https://www.youtube.com/watch?v=VIDEO_ID"
```

## 音声化

```bash
cd voicevox
source venv/bin/activate
python speakers.py   # 話者ID確認
python vtt_to_voicevox.py "字幕ファイル名.ja.vtt" --speaker 8 --output my_audio.wav --log my_log.txt
```

デフォルト話者 ID `8` は春日部つむぎ。
