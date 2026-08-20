import requests
import json
import os
import time
import re
import argparse
import wave
from datetime import datetime
from janome.tokenizer import Tokenizer

# ================= 連携設定 =================
VOICEVOX_URL = "http://127.0.0.1:50021"
OLLAMA_URL = "http://localhost:11434/api/generate"
# ============================================

def chunk_text_by_meaning(cleaned_lines):
    """
    形態素解析(Janome)を使って、「です・ます・た・だ・ない」と「。」のみで分割する
    ※ただし「〜ますが」「〜ですね」のように助詞が続く場合は、助詞を含めてから区切る
    """
    print("\n[形態素解析] テキストを「です・ます・た・だ・ない」と「。」の条件のみで分割しています...")
    tokenizer = Tokenizer()
    
    full_text = "".join(cleaned_lines)
    chunks = []
    current_chunk = ""
    tokens = list(tokenizer.tokenize(full_text))
    
    pending_break = False # 区切る「予約」フラグ
    
    for i, token in enumerate(tokens):
        current_chunk += token.surface
        pos = token.part_of_speech.split(',')
        
        # 条件A: 指定された助動詞の判定
        if pos[0] == '助動詞' and token.base_form in ['です', 'ます', 'た', 'だ', 'ない']:
            # 「〜た時」「〜ない事」「〜ないです」など、名詞や助動詞が続く場合は修飾とみなして予約しない
            if i + 1 < len(tokens):
                next_pos = tokens[i+1].part_of_speech.split(',')
                if next_pos[0] not in ['名詞', '助動詞']:
                    pending_break = True
            else:
                pending_break = True
                
        # 条件3: 句点（。）の判定
        elif pos[0] == '記号' and pos[1] == '句点':
            pending_break = True
            
        # 区切り予約が入っている場合の処理
        if pending_break:
            # 最後のトークンならそのまま区切る
            if i + 1 >= len(tokens):
                chunks.append(current_chunk.strip())
                current_chunk = ""
                pending_break = False
            else:
                next_pos = tokens[i+1].part_of_speech.split(',')
                # 次の単語が「助詞（ね、よ、が、など）」または「記号（句読点）」の場合はまだ区切らずに巻き込む
                if next_pos[0] in ['助詞', '記号']:
                    pass
                else:
                    # 助詞・記号以外が来るので、ここでチャンクを確定してスパッと区切る
                    chunks.append(current_chunk.strip())
                    current_chunk = ""
                    pending_break = False
                    
    # 余ったテキストがあれば追加
    if current_chunk.strip():
        chunks.append(current_chunk.strip())
        
    return [c for c in chunks if c]


def clean_youtube_vtt(input_file):
    """VTTからタグと重複を除去し、テキストのリストを返す"""
    if not os.path.exists(input_file):
        print(f"エラー: {input_file} が見つかりません。")
        return []
    with open(input_file, 'r', encoding='utf-8') as f:
        content = f.read()
    content = re.sub(r'<[^>]+>', '', content)
    lines = content.split('\n')
    cleaned_lines = []
    for line in lines:
        line = line.strip()
        if not line or '-->' in line or line == 'WEBVTT' or line.startswith('Kind:') or line.startswith('Language:') or line == '[音楽]':
            continue
        cleaned_lines.append(line)
    final_text = []
    for line in cleaned_lines:
        if not final_text or final_text[-1] != line:
            final_text.append(line)
    return final_text

def process_text_with_llama3(target_text, context_before, context_after):
    """Ollama(Llama 3)を呼び出して、テキストの修正とパラメータ生成を行う"""
    context_b_str = "\n".join(context_before) if context_before else "(なし)"
    context_a_str = "\n".join(context_after) if context_after else "(なし)"
    
    # ★LLMが混乱しないよう、XMLタグと具体例(Example)を用いた強力なプロンプト
    prompt = f"""
あなたは優秀な音声読み上げの原稿作成アシスタントです。
あなたのタスクは、<TargetText>タグで囲まれたテキスト【のみ】を校正し、JSONフォーマットで出力することです。
<Context>タグで囲まれたテキストは文脈を把握するための参考情報です。絶対に出力結果に含めないでください。

[ルール]
1. <TargetText>内の不要なフィラー（あの、えっと等）を削除し、誤字を文脈から推測して修正し、句読点を補う。
2. <Context_Before> および <Context_After> の内容は出力の "text" に【絶対に含めない】。
3. ハキハキとして明るい快活な美少女の声をイメージし、speed(1.1〜1.3), pitch(-0.02〜0.02), intonation(0.8〜1.2)の数値を推測する。
4. JSON以外の説明は一切出力しない。

[入力例]
<Context_Before>
本日はお集まりいただきありがとうございます。
</Context_Before>
<TargetText>
えっとあの本日のテーマはですねあのAIについてです。
</TargetText>
<Context_After>
まず初めに歴史から振り返りましょう。
</Context_After>

[出力例]
{{
  "text": "本日のテーマは、AIについてです。",
  "speed": 1.1,
  "pitch": 0.01,
  "intonation": 1.2
}}

--- ここから本番 ---

<Context_Before>
{context_b_str}
</Context_Before>

<TargetText>
{target_text}
</TargetText>

<Context_After>
{context_a_str}
</Context_After>

[出力フォーマット（必ずこのJSONのみを出力）]
{{
  "text": "TargetTextの修正後のテキストのみ",
  "speed": 1.0,
  "pitch": 0.0,
  "intonation": 1.0
}}
"""
    payload = {
        "model": "llama3",
        "prompt": prompt,
        "stream": False,
        "format": "json" 
    }
    
    try:
        response = requests.post(OLLAMA_URL, json=payload)
        response.raise_for_status()
        result_data = json.loads(response.json()["response"])
        return True, result_data
    except Exception as e:
        return False, f"Llama 3の処理に失敗しました。({e})"

def generate_custom_voice(text, speed=1.0, pitch=0.0, intonation=1.0, speaker_id=8, output_file="output.wav"):
    """LLMから受け取ったパラメータを使ってVOICEVOXで音声を生成する"""
    try:
        query_payload = {"text": text, "speaker": speaker_id}
        r = requests.post(f"{VOICEVOX_URL}/audio_query", params=query_payload)
        if r.status_code != 200:
            return False, f"Audio Query作成失敗 (Status: {r.status_code})"
        query_data = r.json()

        query_data["speedScale"] = speed
        query_data["pitchScale"] = pitch
        query_data["intonationScale"] = intonation

        synth_payload = {"speaker": speaker_id}
        r = requests.post(f"{VOICEVOX_URL}/synthesis", params=synth_payload, json=query_data)
        if r.status_code != 200:
            return False, f"音声合成失敗 (Status: {r.status_code})"

        with open(output_file, "wb") as f:
            f.write(r.content)
        return True, "成功"
    except Exception as e:
        return False, f"VOICEVOX通信エラー ({e})"

def merge_wav_files(wav_files, output_filename):
    """複数のWAVファイルを1つのWAVファイルに結合する"""
    if not wav_files:
        print("結合するWAVファイルがありません。")
        return

    print(f"[結合処理] {len(wav_files)} 個のファイルを {output_filename} に結合中...")
    
    with wave.open(wav_files[0], 'rb') as w_in:
        params = w_in.getparams()
        
    with wave.open(output_filename, 'wb') as w_out:
        w_out.setparams(params)
        for wav_file in wav_files:
            with wave.open(wav_file, 'rb') as w_in:
                w_out.writeframes(w_in.readframes(w_in.getnframes()))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="VTT字幕をLlama3で校正し、VOICEVOXで1つの音声ファイルにするツール")
    parser.add_argument("input_vtt", type=str, help="入力するVTTファイルのパス")
    parser.add_argument("--speaker", type=int, default=8, help="VOICEVOXの話者ID (デフォルト: 8 春日部つむぎ)")
    parser.add_argument("--output", type=str, default="final_merged_output.wav", help="出力する結合済みWAVファイル名")
    parser.add_argument("--log", type=str, default="process_log.txt", help="処理のログを出力するテキストファイル名")
    args = parser.parse_args()

    print(f"--- 設定 ---")
    print(f"入力ファイル: {args.input_vtt}")
    print(f"話者ID: {args.speaker}")
    print(f"出力ファイル: {args.output}")
    print(f"ログファイル: {args.log}")
    print(f"------------\n")

    # ログファイルの初期化
    with open(args.log, "w", encoding="utf-8") as log_file:
        log_file.write(f"=== 処理開始: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ===\n")
        log_file.write(f"入力: {args.input_vtt} | 話者: {args.speaker} | 出力: {args.output}\n")
        log_file.write("=========================================================\n\n")

    cleaned_lines = clean_youtube_vtt(args.input_vtt)
    if not cleaned_lines:
        print("処理を終了します。")
        exit()

    chunked_texts = chunk_text_by_meaning(cleaned_lines)
    total_chunks = len(chunked_texts)
    print(f"抽出完了: 全 {total_chunks} ブロックを処理します。\n")
    
    # 処理結果を格納するリスト（フェーズ間の中継用）
    processed_data_list = []

    # ==========================================================
    # 【フェーズ 1】 LLMによるテキスト校正とパラメータ推測（一括処理）
    # ==========================================================
    print("========================================")
    print(" 【フェーズ1】 Llama 3 による全テキストの校正・推論")
    print("========================================")
    
    for i, raw_text in enumerate(chunked_texts):
        print(f"  [LLM {i+1}/{total_chunks}] 推論中: {raw_text[:20]}...")
        
        start_idx = max(0, i - 10)
        end_idx = min(total_chunks, i + 11)
        
        context_before = chunked_texts[start_idx:i]
        context_after = chunked_texts[i+1:end_idx]
        
        log_entry = f"[{i+1}/{total_chunks}]\n■元の文章:\n{raw_text}\n"
        
        # LLM処理
        llm_success, llm_result = process_text_with_llama3(
            target_text=raw_text,
            context_before=context_before,
            context_after=context_after
        )
        
        if llm_success and "text" in llm_result:
            process_text = llm_result["text"]
            speed = llm_result.get("speed", 1.0)
            pitch = llm_result.get("pitch", 0.0)
            intonation = llm_result.get("intonation", 1.0)
            
            log_entry += "■LLM処理: 成功\n"
            log_entry += f"■LLM出力:\n  - 修正後文章: {process_text}\n  - パラメータ: speed={speed}, pitch={pitch}, intonation={intonation}\n"
        else:
            process_text = raw_text
            speed, pitch, intonation = 1.0, 0.0, 1.0
            
            print(f"    [警告] ブロック {i+1} のLLM処理に失敗しました。元の文章を使用します。")
            log_entry += f"■LLM処理: 失敗 ({llm_result})\n"
            log_entry += f"■LLM出力: (元の文章とデフォルトパラメータを適用します)\n  - 文章: {process_text}\n  - パラメータ: speed={speed}, pitch={pitch}, intonation={intonation}\n"

        log_entry += "-" * 50 + "\n"
        
        with open(args.log, "a", encoding="utf-8") as log_file:
            log_file.write(log_entry)

        # データをリストに保存
        processed_data_list.append({
            "index": i,
            "raw_text": raw_text,
            "process_text": process_text,
            "speed": speed,
            "pitch": pitch,
            "intonation": intonation
        })

    # ★ バックアップ：LLMの処理結果をJSONファイルとして保存
    backup_file = "intermediate_data.json"
    with open(backup_file, "w", encoding="utf-8") as f:
        json.dump(processed_data_list, f, ensure_ascii=False, indent=2)
    print(f"\n[情報] LLMの推論結果を {backup_file} にバックアップしました。")


    # ==========================================================
    # 【フェーズ 2】 VOICEVOXによる音声合成（一括処理）
    # ==========================================================
    print("\n========================================")
    print(" 【フェーズ2】 VOICEVOX による音声の一括生成")
    print("========================================")
    
    generated_wav_files = []
    
    for data in processed_data_list:
        i = data["index"]
        process_text = data["process_text"]
        print(f"  [VOICEVOX {i+1}/{total_chunks}] 生成中: {process_text[:20]}...")
        
        temp_filename = f"temp_chunk_{i}.wav"
        vv_success, vv_msg = generate_custom_voice(
            text=process_text,
            speed=data["speed"], pitch=data["pitch"], intonation=data["intonation"],
            speaker_id=args.speaker,
            output_file=temp_filename
        )
        
        if vv_success:
            generated_wav_files.append(temp_filename)
        else:
            print(f"    [エラー] ブロック {i+1} の音声生成に失敗しました。スキップします。({vv_msg})")

    # ==========================================================
    # 【フェーズ 3】 音声結合とクリーンアップ
    # ==========================================================
    print("\n========================================")
    print(" 【フェーズ3】 音声ファイルの結合")
    print("========================================")
    
    merge_wav_files(generated_wav_files, args.output)

    print("一時ファイルを削除中...")
    for f in generated_wav_files:
        try:
            os.remove(f)
        except OSError:
            pass

    print(f"\nすべての処理が完了しました！")
    print(f"結合された音声: {os.path.abspath(args.output)}")
    print(f"処理ログ: {os.path.abspath(args.log)}")