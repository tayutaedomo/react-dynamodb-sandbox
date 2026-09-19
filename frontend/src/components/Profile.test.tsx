import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import * as auth from 'aws-amplify/auth';
import { Profile } from './Profile';

vi.mock('aws-amplify/auth', () => ({
  signOut: vi.fn(),
  fetchAuthSession: vi.fn(),
}));

describe('Profile Component', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(auth.fetchAuthSession).mockResolvedValue({
      tokens: { accessToken: { toString: () => 'dummy-token' } as any }
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('マウント時にプロフィールを取得して表示すること', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
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

    render(<Profile onLogout={vi.fn()} />);
    
    // データ取得を待つ
    await waitFor(() => {
      expect(screen.getByText('Test Nickname')).toBeDefined();
    });
    expect(screen.getByText('Test Bio')).toBeDefined();
    
    // fetch が正しいURLとヘッダで呼ばれたか
    expect(fetch).toHaveBeenCalledWith(expect.stringContaining('/api/me/profile'), {
      headers: { Authorization: 'Bearer dummy-token' }
    });
  });

  it('編集モードへの切り替えと保存ができること', async () => {
    // 最初のGETリクエスト
    globalThis.fetch = vi.fn().mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        status: "success",
        profile: {
          user_id: 'dummy-id',
          nickname: 'Old Nickname',
          bio: 'Old Bio',
          created_at: '2026-01-01T00:00:00Z',
          updated_at: '2026-01-01T00:00:00Z'
        }
      })
    });

    render(<Profile onLogout={vi.fn()} />);
    
    await waitFor(() => {
      expect(screen.getByText('Old Nickname')).toBeDefined();
    });

    // 編集ボタンを押す
    fireEvent.click(screen.getByRole('button', { name: 'プロフィールを編集' }));

    // Inputが表示される
    const nicknameInput = screen.getByDisplayValue('Old Nickname');
    const bioInput = screen.getByDisplayValue('Old Bio');
    
    // 値を変更
    fireEvent.change(nicknameInput, { target: { value: 'New Nickname' } });
    fireEvent.change(bioInput, { target: { value: 'New Bio' } });

    // 保存ボタンを押したときのPUTリクエストのモック
    const updatedData = {
      user_id: 'dummy-id',
      nickname: 'New Nickname',
      bio: 'New Bio',
      created_at: '2026-01-01T00:00:00Z',
      updated_at: '2026-01-02T00:00:00Z'
    };
    
    globalThis.fetch = vi.fn().mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        status: "success",
        profile: updatedData
      })
    });

    fireEvent.click(screen.getByRole('button', { name: '保存' }));

    // 更新後の値が表示されるのを待つ
    await waitFor(() => {
      expect(screen.getByText('New Nickname')).toBeDefined();
    });

    // PUTリクエストのボディが正しいか
    expect(fetch).toHaveBeenCalledWith(expect.stringContaining('/api/me/profile'), expect.objectContaining({
      method: 'POST',
      body: JSON.stringify({
        nickname: 'New Nickname',
        bio: 'New Bio'
      })
    }));
  });
});
