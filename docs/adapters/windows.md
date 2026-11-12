# Windows の定期実行連携

`docs/ai-workflow-adapters/windows/` は Git/GitHub 対象の Issue runner と Windows Task Scheduler の連携素材。非 Git の配布先に runner を向けない。適用先の実行権限・認証・Git・Codex CLI・必要な Python/PowerShell とログ出力先を事前に確認する。runner の設定は `examples/windows-issue-review.json` を複製した JSON を利用者が指定する。パス・基準 branch・実行ユーザーを各環境に合わせ、設定ファイルに秘密を含めない。手順で読む TOML とは自動同期しない。

runner はモデルを呼ばない preflight を提供し、同一状態領域のロック、状態・最終メッセージ、cleanup 記録の監視、失敗記録を使用する。共有ロックではなく、他の PC や別状態領域との並列実行を防がない。Git の基準・対象 repo・設定に不備があれば実行を保留する。

設定は JSON オブジェクトで `repo_root`、`state_root`、`codex_path`、`prompt_path`、`base_branch` の5キーのみを指定し、すべて空でない文字列とする。先頭4つは絶対パス、repo、CLI、prompt は実在が必要。CLI は `.ps1` または `.exe`、base_branch は正しいローカル Git ブランチ名。未知キー、欠落、制御文字、引用符、無効名を拒否する。

事前確認は `powershell.exe -NoProfile -NonInteractive -File <配布先>/docs/ai-workflow-adapters/windows/run_issue_review.ps1 -ConfigPath <JSON絶対パス> -Preflight`。実行時は `-Preflight` を除く。非表示 launcher は `pythonw.exe <配布先>/docs/ai-workflow-adapters/windows/run_issue_review_hidden.py --config <JSON絶対パス>` を使う。パスを引数で渡す際は各実行環境に適した引用を行う。

タスクの事前確認は `register_issue_review_task.ps1 -ConfigPath <JSON絶対パス> -PythonwPath <pythonw絶対パス> -TaskName <名前> -TimeZoneId <WindowsタイムゾーンID> -StartAt <日時> -Interval <ISO8601期間> -WhatIf`。実登録には独立確認後の `-Validated` と実行時の許可が必要。指定ゾーンとマシンゾーンの一致と1分以上の間隔を要する。

タスクの実登録とスケジュール変更は適用先の権限を確認してから行う。非表示起動の設定、子プロセスのコンソール接続状態、ログ、ユーザー権限と時刻は実機で検証する。Windows の子プロセスは非表示・コンソールを生成しない構成とし、確認のためウィンドウを自動表示しない。タスク構成のテストで成功しても実際にユーザーのフォーカスを奪わないことを保証しない。

認証を GCM で行う環境では、実行ユーザーと資格情報の有無を確認し、`GCM_INTERACTIVE=never` をプロセス内で設定して対話ログインを避ける。資格情報を変数に受け、必要時のみ `GH_TOKEN` を一時設定し、接続確認後に `try/finally` で環境変数を元に戻して資格情報変数を解除する。値はログ・ファイル・Issue に出さない。失敗時は操作を進めず理由を報告する。
