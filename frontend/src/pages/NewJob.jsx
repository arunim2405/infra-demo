import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { api } from '../api';

export default function NewJob() {
    const [query, setQuery] = useState('');
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(false);
    const { getToken } = useAuth();
    const navigate = useNavigate();

    const handleSubmit = async (e) => {
        e.preventDefault();
        if (!query.trim()) return;
        setError('');
        setLoading(true);
        try {
            const token = await getToken();
            const data = await api.submitJob(token, query);
            navigate(`/jobs/${data.task_id}`);
        } catch (err) {
            setError(err.message || 'Failed to submit job');
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className="page-container">
            <div className="page-header">
                <h1>New Job</h1>
            </div>
            <div className="form-card">
                <form onSubmit={handleSubmit}>
                    {error && <div className="alert alert-error">{error}</div>}
                    <div className="form-group">
                        <label>Query</label>
                        <textarea
                            value={query}
                            onChange={(e) => setQuery(e.target.value)}
                            placeholder="Describe the task for the agent to execute…"
                            rows={4}
                            required
                        />
                    </div>
                    <div className="form-actions">
                        <button
                            type="button"
                            className="btn btn-outline"
                            onClick={() => navigate('/')}
                        >Cancel</button>
                        <button type="submit" className="btn btn-primary" disabled={loading}>
                            {loading ? 'Submitting…' : 'Submit Job'}
                        </button>
                    </div>
                </form>
            </div>
        </div>
    );
}
