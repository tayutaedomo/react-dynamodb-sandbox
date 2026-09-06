# 6. Cognito Post-Confirmation トリガーの仕様制限とAPI遅延初期化の採用

Date: 2026-09-06
Status: Accepted

## Context (背景と課題)
新規ユーザー作成時に、自動的に DynamoDB に初期プロフィールを作成する「ハイブリッド同期戦略 (ADR-0002)」を実装するにあたり、AWS Cognito の `PostConfirmation` (確認後トリガー) を利用する Lambda フックを実装・デプロイした。
しかし、本プロジェクトの Cognito は Terraform にて `allow_admin_create_user_only = true` (管理者作成のみ許可) に設定されている。
検証の結果、AWS Cognito の仕様として、`AdminCreateUser` や `AdminSetUserPassword` などの**管理者 API 経由でユーザーを承認 (CONFIRMED) した場合、`PostConfirmation` トリガーは一切発火しない**ことが判明した。

## Decision (決定事項)
1. **初期化責務の完全移行**:
   ユーザーのプロフィール初期化は、完全に API 側の「遅延初期化 (Lazy Initialization)」(ユーザーが初回ログイン後に初めて `/api/me/profile` を呼び出した際に作成する方式) に一本化し、これを正とする。
   
2. **Lambda Hook の技術的負債としてのあえての保存**:
   本プロジェクトは「検証（サンドボックス）」を目的としているため、発火しない Lambda Hook コード (`terraform/app/hook/main.py`) は削除せず、あえてリポジトリに残す。
   コード内には、なぜ発火しないのかを解説する `[NOTE]` コメントを明記する。

## Consequences (結果)
* **Good**: 「AWS の隠れた仕様（罠）」に気付くことができた。また、代替案として `PostAuthentication` を導入すると実装・管理コストが無駄に増大するため、シンプルで確実な API 遅延初期化に責務を寄せるという、より洗練されたアーキテクチャの決断を下すことができた。
* **Good**: 将来的にビジネス要件が変わり「セルフサービスサインアップ（一般ユーザーによる自己登録）」が有効化された場合、このコードは即座に機能し始める。
* **Good**: 「Terraform による軽量スクリプトの ZIP デプロイ戦略 (ADR-0005)」のリファレンス実装（技術サンプル）としてコードを残すことで、今後の知見として活用できる。

## References (参考資料)
* [AWS Official Documentation: Post confirmation Lambda trigger](https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-lambda-post-confirmation.html)
  > *"Amazon Cognito does not invoke the Post confirmation Lambda trigger if you use the AdminSetUserPassword API with the Permanent=True parameter."*
  > *(管理者が AdminSetUserPassword API でパスワードを永続化した場合、Post confirmation Lambda トリガーは起動されません。)*
