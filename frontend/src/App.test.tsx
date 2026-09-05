import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import * as auth from 'aws-amplify/auth';
import App from './App';

// Cognito との実際の通信が発生しないように aws-amplify の関数をモック
vi.mock('aws-amplify/auth', () => ({
  signIn: vi.fn(),
  signOut: vi.fn(),
  fetchAuthSession: vi.fn(),
  getCurrentUser: vi.fn(),
}));

describe('App Component', () => {
  beforeEach(() => {
    // 各テストの前にモックの呼び出し履歴をリセットする
    vi.clearAllMocks();
  });

  it('タイトルとログインフォームが正常にレンダリングされること', () => {
    render(<App />);
    expect(screen.getByText('React DynamoDB Sandbox')).toBeDefined();
    expect(screen.getByRole('button', { name: 'ログイン' })).toBeDefined();
  });

  it('フォームを入力して送信すると、signIn APIが呼ばれてログイン後の画面になること', async () => {
    // ログイン成功時に返ってくるユーザー情報のモックを設定
    vi.mocked(auth.getCurrentUser).mockResolvedValue({ 
      username: 'testuser1',
      userId: 'dummy-id',
      signInDetails: {}
    });
    
    render(<App />);
    
    // 1. フォームの要素を取得
    const usernameInput = screen.getByPlaceholderText('Username');
    const passwordInput = screen.getByPlaceholderText('Password');
    const loginButton = screen.getByRole('button', { name: 'ログイン' });

    // 2. ユーザーの入力アクションをシミュレート
    fireEvent.change(usernameInput, { target: { value: 'testuser1' } });
    fireEvent.change(passwordInput, { target: { value: 'Password123!' } });
    
    // 3. ログインボタンをクリック
    fireEvent.click(loginButton);

    // 4. 検証: Amplifyの signIn が入力した値で正しく呼び出されたか
    expect(auth.signIn).toHaveBeenCalledWith({
      username: 'testuser1',
      password: 'Password123!'
    });

    // 5. 検証: 非同期処理の完了後、画面が切り替わっているか（ログアウトボタンが出現しているか）
    await waitFor(() => {
      expect(screen.getByText('ログイン成功: testuser1')).toBeDefined();
    });
    expect(screen.getByRole('button', { name: 'ログアウト' })).toBeDefined();
  });
});
