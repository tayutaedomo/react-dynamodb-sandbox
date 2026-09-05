import React, { useState, useEffect } from 'react';
import { Amplify } from 'aws-amplify';
import { signIn, signOut, fetchAuthSession, getCurrentUser } from 'aws-amplify/auth';

Amplify.configure({
  Auth: {
    Cognito: {
      userPoolId: import.meta.env.VITE_COGNITO_USER_POOL_ID || '',
      userPoolClientId: import.meta.env.VITE_COGNITO_CLIENT_ID || ''
    }
  }
});

const App: React.FC = () => {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [user, setUser] = useState<any>(null);
  const [message, setMessage] = useState('');
  const [apiResponse, setApiResponse] = useState('');

  // 画面の初回読み込み時に、すでにログイン済みか（セッションが残っているか）チェックする
  useEffect(() => {
    getCurrentUser()
      .then((currentUser) => {
        setUser(currentUser);
        setMessage(`ログイン済み: ${currentUser.username}`);
      })
      .catch(() => {
        // 未ログイン状態（セッションなし）の場合はエラーが飛んでくるので無視する
      });
  }, []);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await signIn({ username, password });
      const currentUser = await getCurrentUser();
      setUser(currentUser);
      setMessage(`ログイン成功: ${currentUser.username}`);
    } catch (err: any) {
      setMessage(`ログイン失敗: ${err.message}`);
    }
  };

  const handleLogout = async () => {
    try {
      await signOut();
      setUser(null);
      setMessage('ログアウトしました');
      setApiResponse('');
    } catch (err: any) {
      setMessage(`ログアウト失敗: ${err.message}`);
    }
  };

  const callApi = async () => {
    try {
      const session = await fetchAuthSession();
      const token = session.tokens?.accessToken?.toString();
      
      if (!token) {
        setApiResponse('トークンが見つかりません');
        return;
      }

      const apiUrl = import.meta.env.VITE_API_BASE_URL || 'http://localhost:8000';
      const res = await fetch(`${apiUrl}/api/me`, {
        headers: {
          Authorization: `Bearer ${token}`
        }
      });
      const data = await res.json();
      setApiResponse(JSON.stringify(data, null, 2));
    } catch (err: any) {
      setApiResponse(`API呼び出しエラー: ${err.message}`);
    }
  };

  return (
    <div style={{ padding: '20px', fontFamily: 'sans-serif' }}>
      <h1>React DynamoDB Sandbox</h1>
      <p style={{ color: 'blue' }}>{message}</p>

      {!user ? (
        <form onSubmit={handleLogin} style={{ display: 'flex', flexDirection: 'column', width: '300px', gap: '10px' }}>
          <input
            type="text"
            placeholder="Username"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
          />
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
          <button type="submit">ログイン</button>
        </form>
      ) : (
        <div>
          <button onClick={handleLogout}>ログアウト</button>
          <hr />
          <button onClick={callApi}>バックエンドAPIを叩く (/api/me)</button>
          {apiResponse && (
            <pre style={{ background: '#f4f4f4', padding: '10px', marginTop: '10px' }}>
              {apiResponse}
            </pre>
          )}
        </div>
      )}
    </div>
  );
};

export default App;
