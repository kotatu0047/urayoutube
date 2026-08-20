import torch
import whisper
import sys

# 設定
AUDIO_FILE = "sample.mp3"  # 用意する音声ファイル名
MODEL_SIZE = "large-v3"   # RTX 4070なら迷わず最強モデル

def main():
    print("=== Whisper 文字起こし開始 ===")

    # 1. GPUチェック
    if torch.cuda.is_available():
        device = "cuda"
        vram = torch.cuda.get_device_properties(0).total_memory / 1e9
        print(f"✅ GPUを使用します: {torch.cuda.get_device_name(0)} ({vram:.1f}GB)")
    else:
        device = "cpu"
        print("⚠️ GPUが見つかりません。CPUで実行するため非常に遅くなります。")
        print("   (対処: pip install torch ... の手順を見直してください)")

    # 2. モデルロード
    print(f"モデル '{MODEL_SIZE}' をロード中...")
    try:
        model = whisper.load_model(MODEL_SIZE, device=device)
    except Exception as e:
        print(f"エラー: モデルのロードに失敗しました。\n{e}")
        return

    # 3. 音声ファイルがあるか確認
    import os
    if not os.path.exists(AUDIO_FILE):
        print(f"エラー: 音声ファイル '{AUDIO_FILE}' が見つかりません。")
        print("同じフォルダに wav または mp3 ファイルを置いてください。")
        return

    # 4. 文字起こし実行
    print("解析中... (音声の長さによっては時間がかかります)")
    result = model.transcribe(AUDIO_FILE, language="ja")

    # 5. 結果表示
    print("\n=== 結果 ===")
    print(result["text"])
    
    # ファイル保存
    with open("result.txt", "w", encoding="utf-8") as f:
        f.write(result["text"])
    print("\n=== result.txt に保存しました ===")

if __name__ == "__main__":
    main()