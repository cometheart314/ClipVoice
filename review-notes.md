# App Store Review Notes

App Store Connect の「審査に関する情報 (App Review Information)」 → 「メモ (Notes)」欄に
以下をコピペして提出してください。日本語版と英語版のどちらかを使用します。
通常は英語推奨ですが、日本の審査員に当たった場合は日本語版を使っても問題ありません。
両方を併記しても構いません。

---

## English (recommended)

```
ClipVoice is a menu-bar utility that reads clipboard text aloud.

[How it works]
The "double ⌘C" trigger is implemented via NSPasteboard.changeCount polling.
It does NOT use CGEventTap, NSEvent global monitoring, or the Accessibility API.
No special system permissions are required.

[Sandbox & entitlements]
The app runs in the App Sandbox with only com.apple.security.network.client.

[Test procedure]
1. Launch the app — a speaker icon appears in the menu bar.
2. Click the icon and open "Settings...".
3. Turn on "Speak on Double Copy (⌘C ⌘C)".
4. Switch to any application, select some text, and press ⌘C twice quickly.
5. The selected text is read aloud using Apple's built-in voices.

[Google Cloud Text-to-Speech (optional feature)]
The "Advanced" button on the Settings window reveals an optional high-quality
TTS engine powered by Google Cloud Text-to-Speech.
- The user must supply their own Google Cloud API key.
- The key is stored in the user's local Keychain.
- Billing is handled directly between the user and Google Cloud.
- ClipVoice operates no servers and transmits no data to any server
  operated by the developer.
- When Google TTS is disabled (no API key), the app performs zero network I/O.

[Privacy]
- ClipVoice does not collect, log, or transmit the contents of the clipboard
  to any developer-operated server.
- Privacy policy: https://cometheart314.github.io/ClipVoice/en/privacy.html
```

---

## 日本語版

```
ClipVoice はメニューバー常駐の読み上げユーティリティです。

【動作原理】
「⌘C 二回連打」の検出は NSPasteboard.changeCount のポーリングで実装しています。
CGEventTap、NSEvent のグローバルモニタ、アクセシビリティ API は
いずれも使用しておらず、特別なシステム権限は不要です。

【サンドボックスと権限】
App Sandbox 有効、付与された entitlement は
com.apple.security.network.client のみです。

【テスト手順】
1. アプリを起動するとメニューバーにスピーカーアイコンが表示されます。
2. アイコンから「Settings...」を開きます。
3. 「Speak on Double Copy (⌘C ⌘C)」を ON にします。
4. 任意のアプリでテキストを選択し、⌘C を素早く 2 回連打します。
5. Apple 標準音声で選択テキストが読み上げられます。

【Google Cloud Text-to-Speech（オプション機能）】
設定画面の「Advanced」ボタンから高品質な TTS オプションを表示できます。
- Google Cloud の API キーはユーザー自身が取得・設定します。
- キーはローカルのキーチェーンに保存されます。
- 課金はユーザーと Google Cloud の間で直接行われます。
- ClipVoice は独自サーバーを運用せず、開発者のサーバーへデータを送信しません。
- Google TTS を使用しない設定（API キー未設定）では一切の通信を行いません。

【プライバシー】
- クリップボードの内容を開発者側サーバーに送信・記録することは一切ありません。
- プライバシーポリシー: https://cometheart314.github.io/ClipVoice/ja/privacy.html
```

---

## 補足（審査員への口頭的説明が必要な場合）

もしリジェクト理由に「Accessibility 権限の説明が不足」「Keyboard monitoring の目的が不明確」
といった誤解があった場合は、下記の旨を返信してください。

> We do not monitor keyboard events at all.
> Our "double ⌘C" detection is based on `NSPasteboard.changeCount`, which only
> increments when the system clipboard is modified — it does not observe any
> keystrokes. Please see StatusBarController.swift `checkClipboard()` for the
> exact implementation (~20 lines, polling every 0.1s).
