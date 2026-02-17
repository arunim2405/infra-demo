import React, { useState, useEffect, useCallback } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { api } from '../api';

export default function JobDetail() {
    const { taskId } = useParams();
    const { getToken } = useAuth();
    const [job, setJob] = useState(null);
    const [logs, setLogs] = useState([]);
    const [logsLoading, setLogsLoading] = useState(false);
    const [error, setError] = useState('');
    const [tab, setTab] = useState('details'); // 'details' | 'logs'

    const fetchJob = useCallback(async () => {
        try {
            const token = await getToken();
            const data = await api.getJob(token, taskId);
            setJob(data);
        } catch (err) {
            setError(err.message || 'Failed to load job');
        }
    }, [getToken, taskId]);

    const fetchLogs = useCallback(async () => {
        setLogsLoading(true);
        try {
            const token = await getToken();
            const data = await api.getJobLogs(token, taskId, 500);
            setLogs(data.events || []);
        } catch (err) {
            if (err.status === 400 || err.status === 404) {
                setLogs([]); // Task not started yet
            } else {
                setError(err.message || 'Failed to load logs');
            }
        } finally {
            setLogsLoading(false);
        }
    }, [getToken, taskId]);

    useEffect(() => {
        fetchJob();
        const interval = setInterval(fetchJob, 5000);
        return () => clearInterval(interval);
    }, [fetchJob]);

    useEffect(() => {
        if (tab === 'logs') fetchLogs();
    }, [tab, fetchLogs]);

    if (!job && !error) return <div className="loading-center"><div className="spinner" /></div>;

    return (
        <div className="page-container">
            <div className="page-header">
                <div>
                    <Link to="/" className="back-link">← Back to jobs</Link>
                    <h1>Job {taskId.slice(0, 8)}…</h1>
                </div>
            </div>

            {error && <div className="alert alert-error">{error}</div>}

            <div className="tab-bar">
                <button
                    className={`tab ${tab === 'details' ? 'active' : ''}`}
                    onClick={() => setTab('details')}
                >Details</button>
                <button
                    className={`tab ${tab === 'logs' ? 'active' : ''}`}
                    onClick={() => setTab('logs')}
                >Logs</button>
            </div>

            {tab === 'details' && job && (
                <div className="detail-grid">
                    <div className="detail-card">
                        <h3>Status</h3>
                        <span className="status-badge large" style={{
                            backgroundColor: {
                                PENDING: '#f59e0b', QUEUED: '#f59e0b', PROVISIONING: '#3b82f6',
                                PROVISIONED: '#3b82f6', RUNNING: '#8b5cf6',
                                COMPLETED: '#10b981', FAILED: '#ef4444',
                            }[job.status] || '#6b7280'
                        }}>{job.status}</span>
                    </div>
                    <div className="detail-card">
                        <h3>Query</h3>
                        <p>{job.query}</p>
                    </div>
                    <div className="detail-card">
                        <h3>Task ID</h3>
                        <p className="mono">{job.task_id}</p>
                    </div>
                    <div className="detail-card">
                        <h3>Created</h3>
                        <p>{new Date(job.created_at).toLocaleString()}</p>
                    </div>
                    {job.ecs_task_id && (
                        <div className="detail-card">
                            <h3>ECS Task</h3>
                            <p className="mono">{job.ecs_task_id}</p>
                        </div>
                    )}
                    {job.outputs && (
                        <div className="detail-card full-width">
                            <h3>Outputs</h3>
                            <div className="output-links">
                                {Object.entries(job.outputs).map(([name, url]) => (
                                    <a key={name} href={url} target="_blank" rel="noreferrer" className="btn btn-outline">
                                        📎 {name}
                                    </a>
                                ))}
                            </div>
                        </div>
                    )}
                </div>
            )}

            {tab === 'logs' && (
                <div className="logs-container">
                    <div className="logs-toolbar">
                        <button className="btn btn-outline btn-sm" onClick={fetchLogs} disabled={logsLoading}>
                            {logsLoading ? 'Loading…' : '↻ Refresh'}
                        </button>
                        <span className="text-muted">{logs.length} events</span>
                    </div>
                    {logs.length === 0 ? (
                        <div className="empty-state small">
                            <p>No logs yet — the task may not have started.</p>
                        </div>
                    ) : (
                        <div className="log-viewer">
                            {logs.map((evt, i) => (
                                <div key={i} className="log-line">
                                    <span className="log-time">{new Date(evt.timestamp).toLocaleTimeString()}</span>
                                    <span className="log-msg">{evt.message}</span>
                                </div>
                            ))}
                        </div>
                    )}
                </div>
            )}
        </div>
    );
}
