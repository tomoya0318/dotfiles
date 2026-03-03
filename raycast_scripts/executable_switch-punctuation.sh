#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title switch punctuation mark
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author mizuki_baba
# @raycast.authorURL https://raycast.com/mizuki_baba

# 参考：https://qiita.com/kompeki/items/e1cc9edf0399b8d5e8d0

prop=`defaults read com.apple.inputmethod.Kotoeri JIMPrefPunctuationTypeKey`
if [ $prop -eq 0 ]; then
    defaults write com.apple.inputmethod.Kotoeri JIMPrefPunctuationTypeKey -int 3
    echo "句読点を, . に切り替えました"
else
    defaults write com.apple.inputmethod.Kotoeri JIMPrefPunctuationTypeKey -int 0

    echo "句読点を、。 に切り替えました"
fi
killall -HUP JapaneseIM-RomajiTyping
