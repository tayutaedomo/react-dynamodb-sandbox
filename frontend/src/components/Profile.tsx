import React, { useState, useEffect } from 'react';
import { signOut, fetchAuthSession } from 'aws-amplify/auth';

interface ProfileProps {
  onLogout: () => void;
}

interface UserProfile {
  user_id: string;
  nickname: string;
  bio: string;
  created_at: string;
  updated_at?: string;
}

export const Profile: React.FC<ProfileProps> = ({ onLogout }) => {
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [isEditing, setIsEditing] = useState(false);
  const [editNickname, setEditNickname] = useState('');
  const [editBio, setEditBio] = useState('');
  const [loading, setLoading] = useState(true);
  const [errorMsg, setErrorMsg] = useState('');

  const apiUrl = import.meta.env.VITE_API_BASE_URL || 'http://localhost:8000';

  const fetchProfile = async () => {
    try {
      setLoading(true);
      const session = await fetchAuthSession();
      const token = session.tokens?.accessToken?.toString();
      if (!token) throw new Error('No access token found');

      const res = await fetch(`${apiUrl}/api/me/profile`, {
        headers: { Authorization: `Bearer ${token}` }
      });
      
      if (!res.ok) throw new Error(`API error: ${res.status}`);
      
      const data = await res.json();
      setProfile(data.profile);
      setEditNickname(data.profile.nickname);
      setEditBio(data.profile.bio);
    } catch (err: any) {
      setErrorMsg(`プロフィール取得失敗: ${err.message}`);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchProfile();
  }, []);

  const handleSave = async () => {
    try {
      setLoading(true);
      const session = await fetchAuthSession();
      const token = session.tokens?.accessToken?.toString();
      if (!token) throw new Error('No access token found');

      const res = await fetch(`${apiUrl}/api/me/profile`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          nickname: editNickname,
          bio: editBio
        })
      });

      if (!res.ok) throw new Error(`API error: ${res.status}`);
      
      const updatedData = await res.json();
      setProfile(updatedData.profile);
      setIsEditing(false);
    } catch (err: any) {
      setErrorMsg(`プロフィール更新失敗: ${err.message}`);
    } finally {
      setLoading(false);
    }
  };

  const handleLogoutClick = async () => {
    try {
      await signOut();
      onLogout();
    } catch (err: any) {
      setErrorMsg(`ログアウト失敗: ${err.message}`);
    }
  };

  if (loading && !profile) {
    return <div>読み込み中...</div>;
  }

  return (
    <div style={{ maxWidth: '500px' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h2>プロフィール</h2>
        <button onClick={handleLogoutClick}>ログアウト</button>
      </div>

      {errorMsg && <p style={{ color: 'red' }}>{errorMsg}</p>}

      {profile && (
        <div style={{ background: '#f9f9f9', padding: '20px', borderRadius: '8px' }}>
          {isEditing ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
              <label>
                <strong>Nickname:</strong><br />
                <input 
                  type="text" 
                  value={editNickname} 
                  onChange={e => setEditNickname(e.target.value)} 
                  style={{ width: '100%' }}
                />
              </label>
              <label>
                <strong>Bio:</strong><br />
                <textarea 
                  value={editBio} 
                  onChange={e => setEditBio(e.target.value)} 
                  style={{ width: '100%', height: '80px' }}
                />
              </label>
              <div style={{ display: 'flex', gap: '10px', marginTop: '10px' }}>
                <button onClick={handleSave} disabled={loading}>保存</button>
                <button onClick={() => setIsEditing(false)} disabled={loading}>キャンセル</button>
              </div>
            </div>
          ) : (
            <div>
              <p><strong>ID:</strong> {profile.user_id}</p>
              <p><strong>Nickname:</strong> {profile.nickname}</p>
              <p><strong>Bio:</strong> {profile.bio}</p>
              <p style={{ fontSize: '0.8em', color: '#666' }}>
                更新日: {profile.updated_at ? new Date(profile.updated_at).toLocaleString() : 'なし'}
              </p>
              <button onClick={() => setIsEditing(true)} style={{ marginTop: '10px' }}>プロフィールを編集</button>
            </div>
          )}
        </div>
      )}
    </div>
  );
};
