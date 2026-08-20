# urayoutube

YouTube動画の日本語字幕を取得し、VOICEVOX で美少女ボイスに変換する。

## 構成

```
voicevox/           VTT → VOICEVOX 変換
  vtt_to_voicevox.py
  speakers.py       話者ID一覧
whisper_project/    字幕がない場合の Whisper 文字起こし
  run_whisper.py
```

## 準備

VOICEVOX Engine（GPU 推奨）:

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

依存関係:

```bash
cd voicevox
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Whisper を使う場合:

```bash
cd whisper_project
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
