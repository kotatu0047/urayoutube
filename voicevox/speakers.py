import requests

def print_voicevox_speakers():
    url = "http://127.0.0.1:50021/speakers"
    try:
        response = requests.get(url)
        response.raise_for_status()
        speakers = response.json()
        
        print("--- VOICEVOX 話者ID一覧 ---")
        for speaker in speakers:
            name = speaker["name"]
            for style in speaker["styles"]:
                style_name = style["name"]
                speaker_id = style["id"]
                print(f"ID: {speaker_id:>3} | {name} ({style_name})")
                
    except requests.exceptions.RequestException as e:
        print(f"エラー: VOICEVOXが起動していないか、接続できません。\n詳細: {e}")

if __name__ == "__main__":
    print_voicevox_speakers()