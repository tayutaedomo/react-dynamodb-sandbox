import { test, expect } from '@playwright/test';

test('ログインしてプロフィールを表示し、編集して保存できること', async ({ page }) => {
  // アプリケーションを開く
  await page.goto('/');

  // ログインページが表示されていることを確認
  await expect(page.getByRole('heading', { name: 'ログイン' })).toBeVisible();

  // テストユーザーでログイン (ローカルで実行しているユーザーの環境に依存)
  await page.fill('input[placeholder="Username"]', 'testuser2');
  await page.fill('input[placeholder="Password"]', 'Password123!');
  await page.click('button:has-text("ログイン")');

  // プロフィール画面への遷移を待機 (DynamoDB からの読み込みを含む)
  await expect(page.getByRole('heading', { name: 'プロフィール' })).toBeVisible({ timeout: 15000 });

  // 現在の Nickname が表示されていることを確認 (初期値または直前の値)
  // 何らかの文字が表示されているはずなので、要素が存在することを確認
  await expect(page.locator('text=Nickname:')).toBeVisible();

  // 編集モードに入る
  await page.click('button:has-text("プロフィールを編集")');

  // Nickname と Bio を新しい値に変更
  const timestamp = new Date().getTime();
  const newNickname = `Playwright User ${timestamp}`;
  const newBio = `Hello from E2E test at ${timestamp}`;

  // ラベルテキストから対象の input/textarea を特定して埋める
  // 実際は value がすでに入っているので fill で上書きする
  // 画面上に1つずつしかない input/textarea と想定
  await page.fill('input[type="text"]', newNickname);
  await page.fill('textarea', newBio);

  // 保存ボタンを押す
  await page.click('button:has-text("保存")');

  // 表示モードに戻り、新しい値が表示されていることを確認
  await expect(page.getByText(newNickname)).toBeVisible();
  await expect(page.getByText(newBio)).toBeVisible();
});
