import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    // Vite のデフォルトポートに対してテストを実行
    baseURL: 'http://localhost:5173',
    // 全てのテストでトレース（各アクションごとのスクリーンショットやDOMスナップショット）を記録する
    trace: 'on',
    // テスト終了時にスクリーンショットを保存する
    screenshot: 'on',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
