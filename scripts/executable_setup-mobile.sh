#!/usr/bin/env bash
set -euo pipefail

# RN / iOS / Android 開発環境の復元スクリプト
# 前提: brew bundle --file=~/Brewfile.mobile が適用済み

# --- Xcode Command Line Tools ---
if ! xcode-select -p >/dev/null 2>&1; then
    echo "→ Xcode Command Line Tools をインストールします"
    xcode-select --install
    echo "  ダイアログで完了後、このスクリプトを再実行してください"
    exit 1
fi

# --- Android SDK ---
ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
if [ ! -d "$ANDROID_HOME" ]; then
    echo "→ Android SDK が見つかりません ($ANDROID_HOME)"
    echo "  以下のいずれかで導入してください:"
    echo "    1. Android Studio:  brew install --cask android-studio"
    echo "    2. CLI のみ:        brew install --cask android-commandlinetools"
    exit 1
fi

SDKMANAGER="$(find "$ANDROID_HOME" -name sdkmanager -type f -perm -u+x 2>/dev/null | head -1)"
if [ -n "$SDKMANAGER" ] && [ -x "$SDKMANAGER" ]; then
    echo "→ Android SDK コンポーネントをインストール"
    yes | "$SDKMANAGER" --licenses >/dev/null
    "$SDKMANAGER" \
        "platform-tools" \
        "platforms;android-35" "platforms;android-36" \
        "build-tools;35.0.0" "build-tools;36.0.0" \
        "ndk;27.1.12297006" \
        "emulator"
else
    echo "! sdkmanager 未検出。Android Studio から GUI でコンポーネント追加してください"
fi

echo ""
echo "✓ Mobile 環境セットアップ完了"
echo ""
echo "新規プロジェクトでのビルド:"
echo "  cd ios && pod install"
echo "  cd android && ./gradlew :app:assembleDebug"
