import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import * as auth from 'aws-amplify/auth';
import { Login } from './Login';

vi.mock('aws-amplify/auth', () => ({
  signIn: vi.fn(),
  getCurrentUser: vi.fn(),
}));

describe('Login Component', () => {
  const mockOnLoginSuccess = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('フォームを入力して送信すると、signIn APIが呼ばれてonLoginSuccessが発火すること', async () => {
    render(<Login onLoginSuccess={mockOnLoginSuccess} />);
    
    const usernameInput = screen.getByPlaceholderText('Username');
    const passwordInput = screen.getByPlaceholderText('Password');
    const loginButton = screen.getByRole('button', { name: 'ログイン' });

    fireEvent.change(usernameInput, { target: { value: 'testuser1' } });
    fireEvent.change(passwordInput, { target: { value: 'Password123!' } });
    
    vi.mocked(auth.getCurrentUser).mockResolvedValueOnce({ 
      username: 'testuser1',
      userId: 'dummy-id',
      signInDetails: {}
    });

    fireEvent.click(loginButton);

    // signInが正しい引数で呼ばれたか
    expect(auth.signIn).toHaveBeenCalledWith({
      username: 'testuser1',
      password: 'Password123!'
    });

    // onLoginSuccess コールバックが正しいユーザー情報と共に呼ばれたか
    await waitFor(() => {
      expect(mockOnLoginSuccess).toHaveBeenCalledWith(expect.objectContaining({
        username: 'testuser1'
      }));
    });
  });

  it('ログインに失敗した場合、エラーメッセージが表示されること', async () => {
    render(<Login onLoginSuccess={mockOnLoginSuccess} />);
    
    const usernameInput = screen.getByPlaceholderText('Username');
    const passwordInput = screen.getByPlaceholderText('Password');
    const loginButton = screen.getByRole('button', { name: 'ログイン' });

    fireEvent.change(usernameInput, { target: { value: 'testuser1' } });
    fireEvent.change(passwordInput, { target: { value: 'WrongPassword!' } });
    
    // エラーをシミュレート
    vi.mocked(auth.signIn).mockRejectedValueOnce(new Error('Incorrect username or password.'));

    fireEvent.click(loginButton);

    // エラーメッセージが表示されるのを待つ
    await waitFor(() => {
      expect(screen.getByText('ログイン失敗: Incorrect username or password.')).toBeDefined();
    });

    // 成功コールバックは呼ばれていないこと
    expect(mockOnLoginSuccess).not.toHaveBeenCalled();
  });
});
