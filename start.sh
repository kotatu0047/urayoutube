#!/usr/bin/env bash
# VOICEVOX Engine と Ollama を起動する
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VOICEVOX_PORT=50021
OLLAMA_PORT=11434
CONTAINER_NAME="voicevox-engine"
USE_GPU=1

usage() {
  cat <<'EOF'
Usage: ./start.sh [--gpu|--cpu] [--help]

  --gpu   VOICEVOX を GPU 版で起動（デフォルト）
  --cpu   VOICEVOX を CPU 版で起動
  --help  このヘルプを表示
EOF
}

for arg in "$@"; do
  case "$arg" in
    --gpu) USE_GPU=1 ;;
    --cpu) USE_GPU=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "不明な引数: $arg" >&2; usage; exit 1 ;;
  esac
done

service_ready() {
  local kind="$1"
  if ! command -v curl >/dev/null 2>&1; then
    local port
    [[ "$kind" == ollama ]] && port="$OLLAMA_PORT" || port="$VOICEVOX_PORT"
    (echo >/dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1
    return $?
  fi
  case "$kind" in
    ollama) curl -sf "http://127.0.0.1:${OLLAMA_PORT}/api/tags" >/dev/null 2>&1 ;;
    voicevox) curl -sf "http://127.0.0.1:${VOICEVOX_PORT}/speakers" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

wait_for_service() {
  local name="$1" kind="$2" retries="${3:-60}"
  echo -n "[wait] ${name}"
  for ((i = 0; i < retries; i++)); do
    if service_ready "$kind"; then
      echo " OK"
      return 0
    fi
    echo -n "."
    sleep 1
  done
  echo " TIMEOUT"
  return 1
}

echo "=== urayoutube 起動 ==="
echo "プロジェクト: ${ROOT}"

# --- Ollama ---
if service_ready ollama; then
  echo "[ok] Ollama は既に起動しています (port ${OLLAMA_PORT})"
elif command -v ollama >/dev/null 2>&1; then
  echo "[start] Ollama をバックグラウンド起動..."
  nohup ollama serve >/tmp/urayoutube-ollama.log 2>&1 &
  wait_for_service "Ollama" ollama 30
else
  echo "[warn] ollama コマンドが見つかりません。手動で 'ollama serve' を起動してください。"
fi

# --- VOICEVOX ---
if service_ready voicevox; then
  echo "[ok] VOICEVOX は既に起動しています (port ${VOICEVOX_PORT})"
elif ! command -v docker >/dev/null 2>&1; then
  echo "[error] docker コマンドが見つかりません。" >&2
  echo "        Docker Desktop の WSL 連携を有効にしてください。" >&2
  exit 1
elif ! docker info >/dev/null 2>&1; then
  echo "[error] Docker デーモンに接続できません。" >&2
  echo "        Docker Desktop を起動し、WSL 連携を確認してください。" >&2
  exit 1
else
  if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "[start] 既存コンテナ ${CONTAINER_NAME} を起動..."
    docker start "$CONTAINER_NAME" >/dev/null
  else
    if [[ "$USE_GPU" -eq 1 ]]; then
      IMAGE="voicevox/voicevox_engine:nvidia-ubuntu20.04-latest"
      echo "[start] VOICEVOX (GPU) を起動: ${IMAGE}"
      docker run -d --rm --name "$CONTAINER_NAME" --gpus all \
        -p "${VOICEVOX_PORT}:50021" "$IMAGE"
    else
      IMAGE="voicevox/voicevox_engine:cpu-ubuntu20.04-latest"
      echo "[start] VOICEVOX (CPU) を起動: ${IMAGE}"
      docker run -d --rm --name "$CONTAINER_NAME" \
        -p "${VOICEVOX_PORT}:50021" "$IMAGE"
    fi
  fi
  wait_for_service "VOICEVOX" voicevox 90
fi

# --- venv 確認 ---
if [[ -f "${ROOT}/voicevox/venv/bin/activate" ]]; then
  echo "[ok] voicevox/venv があります"
else
  echo "[hint] voicevox/venv がありません。初回は次を実行してください:"
  echo "       cd voicevox && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
fi

echo
echo "準備完了。"
echo "  Ollama:    http://127.0.0.1:${OLLAMA_PORT}"
echo "  VOICEVOX:  http://127.0.0.1:${VOICEVOX_PORT}"
echo
echo "例:"
echo "  cd voicevox && source venv/bin/activate"
echo "  python speakers.py"
echo "  python vtt_to_voicevox.py \"字幕.ja.vtt\" --speaker 8 --output my_audio.wav --log my_log.txt"
