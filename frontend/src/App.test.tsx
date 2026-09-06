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

describe('App Component (Routing)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('未ログイン時はログイン画面が表示されること', async () => {
    vi.mocked(auth.getCurrentUser).mockRejectedValueOnce(new Error('not signed in'));
    render(<App />);
    
    // Loading が終わるまで待機
    await waitFor(() => {
      expect(screen.queryByText('Loading...')).toBeNull();
    });

    expect(screen.getByText('React DynamoDB Sandbox')).toBeDefined();
    expect(screen.getByRole('button', { name: 'ログイン' })).toBeDefined();
  });

  it('ログイン済みの場合はプロフィール画面が表示されること', async () => {
    vi.mocked(auth.getCurrentUser).mockResolvedValueOnce({ 
      username: 'testuser1',
      userId: 'dummy-id',
      signInDetails: {}
    });
    // Profile コンポーネント内で fetchAuthSession と fetch が呼ばれるのでモック化
    vi.mocked(auth.fetchAuthSession).mockResolvedValueOnce({
      tokens: { accessToken: { toString: () => 'dummy-token' } as any }
    });
    
    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        status: "success",
        profile: {
          user_id: 'dummy-id',
          nickname: 'Test Nickname',
          bio: 'Test Bio',
          created_at: '2026-01-01T00:00:00Z',
          updated_at: '2026-01-01T00:00:00Z'
        }
      })
    });

    render(<App />);
    
    await waitFor(() => {
      expect(screen.queryByText('Loading...')).toBeNull();
    });

    // プロフィール画面の要素が表示されること
    await waitFor(() => {
      expect(screen.getByText('プロフィール')).toBeDefined();
    });
    expect(screen.getByRole('button', { name: 'ログアウト' })).toBeDefined();
    expect(screen.getByText('Test Nickname')).toBeDefined();
  });
});
