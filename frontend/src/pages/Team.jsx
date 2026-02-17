import React, { useState, useEffect, useCallback } from 'react';
import { useAuth } from '../context/AuthContext';
import { api } from '../api';

const ROLE_OPTIONS = ['READ_ONLY', 'DOCTOR', 'ADMIN'];

export default function Team() {
    const { getToken } = useAuth();
    const [users, setUsers] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const [showAdd, setShowAdd] = useState(false);
    const [addEmail, setAddEmail] = useState('');
    const [addRole, setAddRole] = useState('READ_ONLY');
    const [addLoading, setAddLoading] = useState(false);
    const [addError, setAddError] = useState('');

    const fetchUsers = useCallback(async () => {
        try {
            const token = await getToken();
            const data = await api.listUsers(token);
            setUsers(data.users || []);
        } catch (err) {
            setError(err.message || 'Failed to load team');
        } finally {
            setLoading(false);
        }
    }, [getToken]);

    useEffect(() => { fetchUsers(); }, [fetchUsers]);

    const handleAdd = async (e) => {
        e.preventDefault();
        setAddError('');
        setAddLoading(true);
        try {
            const token = await getToken();
            await api.addUser(token, addEmail, addRole);
            setAddEmail('');
            setAddRole('READ_ONLY');
            setShowAdd(false);
            fetchUsers();
        } catch (err) {
            setAddError(err.error || err.message || 'Failed to add user');
        } finally {
            setAddLoading(false);
        }
    };

    const handleRemove = async (cognitoId, email) => {
        if (!confirm(`Remove ${email} from the team?`)) return;
        try {
            const token = await getToken();
            await api.removeUser(token, cognitoId);
            fetchUsers();
        } catch (err) {
            setError(err.error || err.message || 'Failed to remove user');
        }
    };

    return (
        <div className="page-container">
            <div className="page-header">
                <h1>Team</h1>
                <button className="btn btn-primary" onClick={() => setShowAdd(!showAdd)}>
                    {showAdd ? 'Cancel' : '+ Add User'}
                </button>
            </div>

            {error && <div className="alert alert-error">{error}</div>}

            {showAdd && (
                <div className="form-card" style={{ marginBottom: '1.5rem' }}>
                    <form onSubmit={handleAdd}>
                        {addError && <div className="alert alert-error">{addError}</div>}
                        <div className="form-row">
                            <div className="form-group" style={{ flex: 2 }}>
                                <label>Email</label>
                                <input
                                    type="email"
                                    value={addEmail}
                                    onChange={(e) => setAddEmail(e.target.value)}
                                    placeholder="user@company.com"
                                    required
                                />
                            </div>
                            <div className="form-group" style={{ flex: 1 }}>
                                <label>Role</label>
                                <select value={addRole} onChange={(e) => setAddRole(e.target.value)}>
                                    {ROLE_OPTIONS.map((r) => (
                                        <option key={r} value={r}>{r}</option>
                                    ))}
                                </select>
                            </div>
                            <div className="form-group" style={{ alignSelf: 'flex-end' }}>
                                <button type="submit" className="btn btn-primary" disabled={addLoading}>
                                    {addLoading ? 'Adding…' : 'Add'}
                                </button>
                            </div>
                        </div>
                    </form>
                </div>
            )}

            {loading ? (
                <div className="loading-center"><div className="spinner" /></div>
            ) : users.length === 0 ? (
                <div className="empty-state">
                    <span className="empty-icon">👥</span>
                    <h3>No team members</h3>
                </div>
            ) : (
                <div className="table-container">
                    <table className="data-table">
                        <thead>
                            <tr>
                                <th>Email</th>
                                <th>Role</th>
                                <th>Added</th>
                                <th></th>
                            </tr>
                        </thead>
                        <tbody>
                            {users.map((u) => (
                                <tr key={u.cognito_id}>
                                    <td>{u.email}</td>
                                    <td>
                                        <span className={`role-badge role-${u.role?.toLowerCase()}`}>
                                            {u.role}
                                        </span>
                                    </td>
                                    <td className="text-muted">
                                        {u.created_at ? new Date(u.created_at).toLocaleDateString() : '—'}
                                    </td>
                                    <td>
                                        <button
                                            className="btn btn-danger btn-sm"
                                            onClick={() => handleRemove(u.cognito_id, u.email)}
                                        >Remove</button>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            )}
        </div>
    );
}
