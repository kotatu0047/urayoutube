#!/usr/bin/env bash
# 初回セットアップ（venv・依存・外部ツールの確認/取得）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3}"
USE_GPU=1
PYTHON_ONLY=0
SKIP_DOCKER=0
SKIP_OLLAMA=0
SKIP_YTDLP=0

usage() {
  cat <<'EOF'
Usage: ./setup.sh [options]

  （引数なし）  Python venv 作成 + yt-dlp / Docker イメージ / Ollama モデルの準備
  --python-only Python venv と pip のみ
  --gpu         VOICEVOX Docker は GPU 版を pull（デフォルト）
  --cpu         VOICEVOX Docker は CPU 版を pull
  --skip-docker Docker イメージの pull をスキップ
  --skip-ollama Ollama モデルの pull をスキップ
  --skip-yt-dlp yt-dlp の導入/確認をスキップ
  --help        このヘルプを表示

環境変数:
  OLLAMA_MODEL  pull するモデル名（既定: llama3）
EOF
}

for arg in "$@"; do
  case "$arg" in
    --python-only) PYTHON_ONLY=1 ;;
    --gpu) USE_GPU=1 ;;
    --cpu) USE_GPU=0 ;;
    --skip-docker) SKIP_DOCKER=1 ;;
    --skip-ollama) SKIP_OLLAMA=1 ;;
    --skip-yt-dlp) SKIP_YTDLP=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "不明な引数: $arg" >&2; usage; exit 1 ;;
  esac
done

ok()   { echo "[ok] $*"; }
info() { echo "[info] $*"; }
warn() { echo "[warn] $*"; }
fail() { echo "[error] $*" >&2; }

echo "=== urayoutube セットアップ ==="
echo "プロジェクト: ${ROOT}"

# --- 実行権限 ---
chmod +x "${ROOT}/start.sh" "${ROOT}/update.sh" "${ROOT}/setup.sh" 2>/dev/null || true
ok "スクリプトに実行権限を付与"

# --- Python ---
echo
echo "=== Python / venv ==="
if ! command -v python3 >/dev/null 2>&1; then
  fail "python3 が見つかりません。OS に合わせて Python 3 を入れてください。"
  exit 1
fi
ok "python3: $(python3 --version 2>&1)"

VV_DIR="${ROOT}/voicevox"
REQ="${VV_DIR}/requirements.txt"
PY="${VV_DIR}/venv/bin/python"

if [[ ! -f "$REQ" ]]; then
  fail "${REQ} がありません"
  exit 1
fi

if [[ ! -e "$PY" ]] || ! "$PY" -c "import sys" >/dev/null 2>&1 || ! "$PY" -m pip --version >/dev/null 2>&1; then
  info "voicevox/venv を作成します"
  rm -rf "${VV_DIR}/venv"
  python3 -m venv "${VV_DIR}/venv"
fi

info "pip / requirements をインストール"
"$PY" -m pip install -U pip
"$PY" -m pip install -r "$REQ"
ok "voicevox の Python 依存をインストール済み"
"$PY" -m pip list --format=columns | grep -E '^(Package|-----|requests|janome) ' || true

if [[ "$PYTHON_ONLY" -eq 1 ]]; then
  echo
  echo "セットアップ完了（--python-only）。"
  echo "次: ./start.sh で VOICEVOX / Ollama を起動"
  exit 0
fi

# --- 前提ツールの確認 ---
echo
echo "=== 前提ツールの確認 ==="
MISSING=0

if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    ok "Docker: 利用可能"
  else
    warn "docker はあるがデーモンに接続できません（Docker Desktop / WSL 連携を確認）"
    MISSING=1
  fi
else
  warn "Docker 未インストール → https://docs.docker.com/get-docker/"
  MISSING=1
fi

if command -v ollama >/dev/null 2>&1; then
  ok "Ollama: $(command -v ollama)"
else
  warn "Ollama 未インストール → https://ollama.com/"
  MISSING=1
fi

# --- yt-dlp ---
if [[ "$SKIP_YTDLP" -eq 0 ]]; then
  echo
  echo "=== yt-dlp ==="
  if command -v yt-dlp >/dev/null 2>&1; then
    ok "yt-dlp: $(yt-dlp --version)"
  elif command -v pipx >/dev/null 2>&1; then
    info "pipx で yt-dlp をインストールします"
    pipx install yt-dlp
    ok "yt-dlp: $(yt-dlp --version)"
  else
    warn "yt-dlp がありません。例: pipx install yt-dlp"
    warn "  https://github.com/yt-dlp/yt-dlp"
    MISSING=1
  fi
fi

# --- VOICEVOX Docker イメージ ---
if [[ "$SKIP_DOCKER" -eq 0 ]]; then
  echo
  echo "=== VOICEVOX Docker イメージ ==="
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if [[ "$USE_GPU" -eq 1 ]]; then
      IMAGE="voicevox/voicevox_engine:nvidia-ubuntu20.04-latest"
    else
      IMAGE="voicevox/voicevox_engine:cpu-ubuntu20.04-latest"
    fi
    info "docker pull ${IMAGE}"
    if docker pull "$IMAGE"; then
      ok "イメージ取得完了: ${IMAGE}"
    else
      warn "pull に失敗しました。ネットワークや Docker 設定を確認してください。"
      MISSING=1
    fi
  else
    warn "Docker が使えないためイメージ pull をスキップ"
  fi
fi

# --- Ollama モデル ---
if [[ "$SKIP_OLLAMA" -eq 0 ]]; then
  echo
  echo "=== Ollama モデル (${OLLAMA_MODEL}) ==="
  if command -v ollama >/dev/null 2>&1; then
    # serve していなくても pull できることが多い
    info "ollama pull ${OLLAMA_MODEL}"
    if ollama pull "$OLLAMA_MODEL"; then
      ok "モデル準備完了: ${OLLAMA_MODEL}"
    else
      warn "モデル pull に失敗。先に 'ollama serve' が必要な場合があります。"
      MISSING=1
    fi
  else
    warn "Ollama が無いためモデル pull をスキップ"
  fi
fi

# --- 任意: 音声再生 ---
echo
echo "=== 任意ツール ==="
if command -v aplay >/dev/null 2>&1; then
  ok "alsa-utils (aplay) あり"
else
  info "音声再生用: sudo apt install alsa-utils"
fi

echo
if [[ "$MISSING" -eq 0 ]]; then
  echo "セットアップ完了。"
else
  echo "セットアップは一通り終わりましたが、不足・警告があります（上の [warn] を確認）。"
fi
echo
echo "次のステップ:"
echo "  1. ./start.sh          # VOICEVOX + Ollama 起動（CPU なら ./start.sh --cpu）"
echo "  2. yt-dlp で字幕取得"
echo "  3. cd voicevox && source venv/bin/activate"
echo "     python vtt_to_voicevox.py \"字幕.ja.vtt\" --speaker 8 --output my_audio.wav"
