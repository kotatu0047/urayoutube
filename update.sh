#!/usr/bin/env bash
# 各種依存ライブラリ・ツールをアップデートする
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DO_PYTHON=0
DO_YTDLP=0
DO_DOCKER=0
DO_OLLAMA=0
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3}"

usage() {
  cat <<'EOF'
Usage: ./update.sh [options]

  （引数なし）  Python 依存 + yt-dlp を更新
  --all         すべて更新（Python / yt-dlp / VOICEVOX Docker / Ollama モデル）
  --python      voicevox の pip パッケージを更新
  --yt-dlp      yt-dlp を更新
  --docker      VOICEVOX Engine の Docker イメージを pull
  --ollama      Ollama モデルを pull（既定: llama3、OLLAMA_MODEL で変更可）
  --help        このヘルプを表示
EOF
}

if [[ $# -eq 0 ]]; then
  DO_PYTHON=1
  DO_YTDLP=1
else
  for arg in "$@"; do
    case "$arg" in
      --all) DO_PYTHON=1; DO_YTDLP=1; DO_DOCKER=1; DO_OLLAMA=1 ;;
      --python) DO_PYTHON=1 ;;
      --yt-dlp) DO_YTDLP=1 ;;
      --docker) DO_DOCKER=1 ;;
      --ollama) DO_OLLAMA=1 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "不明な引数: $arg" >&2; usage; exit 1 ;;
    esac
  done
fi

update_venv() {
  local dir="$1"
  local req="${dir}/requirements.txt"
  local py="${dir}/venv/bin/python"

  echo
  echo "=== Python: ${dir} ==="

  if [[ ! -f "$req" ]]; then
    echo "[skip] requirements.txt がありません"
    return 0
  fi

  # shebang が壊れている古い venv も、python -m pip で動くか確認する
  if [[ ! -e "$py" ]] || ! "$py" -c "import sys" >/dev/null 2>&1 || ! "$py" -m pip --version >/dev/null 2>&1; then
    echo "[info] venv を作り直します"
    rm -rf "${dir}/venv"
    python3 -m venv "${dir}/venv"
  fi

  echo "[run] python -m pip install -U pip"
  "$py" -m pip install -U pip
  echo "[run] python -m pip install -U -r requirements.txt"
  "$py" -m pip install -U -r "$req"
  echo "[ok] ${dir} のパッケージを更新しました"
  "$py" -m pip list --format=columns | grep -E '^(Package|-----|requests|janome) ' || true
}

echo "=== urayoutube アップデート ==="
echo "プロジェクト: ${ROOT}"

if [[ "$DO_PYTHON" -eq 1 ]]; then
  update_venv "${ROOT}/voicevox"
fi

if [[ "$DO_YTDLP" -eq 1 ]]; then
  echo
  echo "=== yt-dlp ==="
  if command -v yt-dlp >/dev/null 2>&1; then
    if command -v pipx >/dev/null 2>&1 && pipx list 2>/dev/null | grep -q 'package yt-dlp'; then
      pipx upgrade yt-dlp
      echo "[ok] yt-dlp (pipx): $(yt-dlp --version)"
    elif yt-dlp -U; then
      echo "[ok] yt-dlp: $(yt-dlp --version)"
    elif python3 -m pip install --user -U yt-dlp; then
      echo "[ok] yt-dlp (pip --user): $(yt-dlp --version)"
    else
      echo "[warn] yt-dlp の自動更新に失敗。入れ方に合わせて手動更新してください。"
      echo "       例: pipx upgrade yt-dlp"
      echo "           または https://github.com/yt-dlp/yt-dlp の手順"
    fi
  else
    echo "[warn] yt-dlp が見つかりません。環境に合わせてインストールしてください。"
  fi
fi

if [[ "$DO_DOCKER" -eq 1 ]]; then
  echo
  echo "=== VOICEVOX Docker イメージ ==="
  if ! command -v docker >/dev/null 2>&1; then
    echo "[warn] docker が見つかりません"
  elif ! docker info >/dev/null 2>&1; then
    echo "[warn] Docker デーモンに接続できません（Desktop 起動 / WSL 連携を確認）"
  else
    for image in \
      voicevox/voicevox_engine:nvidia-ubuntu20.04-latest \
      voicevox/voicevox_engine:cpu-ubuntu20.04-latest
    do
      echo "[run] docker pull ${image}"
      docker pull "$image" || echo "[warn] pull 失敗: ${image}"
    done
    echo "[ok] VOICEVOX イメージの更新を試行しました"
  fi
fi

if [[ "$DO_OLLAMA" -eq 1 ]]; then
  echo
  echo "=== Ollama モデル (${OLLAMA_MODEL}) ==="
  if command -v ollama >/dev/null 2>&1; then
    echo "[run] ollama pull ${OLLAMA_MODEL}"
    ollama pull "$OLLAMA_MODEL"
    echo "[ok] モデルを更新しました"
  else
    echo "[warn] ollama が見つかりません"
  fi
fi

echo
echo "アップデート処理が完了しました。"
