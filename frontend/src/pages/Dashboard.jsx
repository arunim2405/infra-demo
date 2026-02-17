import React, { useState, useEffect, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { api } from '../api';

const STATUS_COLORS = {
    PENDING: '#f59e0b',
    QUEUED: '#f59e0b',
    PROVISIONING: '#3b82f6',
    PROVISIONED: '#3b82f6',
    RUNNING: '#8b5cf6',
    COMPLETED: '#10b981',
    FAILED: '#ef4444',
};

export default function Dashboard() {
    const { getToken, userInfo } = useAuth();
    const [jobs, setJobs] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');

    const fetchJobs = useCallback(async () => {
        try {
            const token = await getToken();
            const data = await api.listJobs(token, 50);
            setJobs(data.jobs || []);
        } catch (err) {
            setError(err.message || 'Failed to load jobs');
        } finally {
            setLoading(false);
        }
    }, [getToken]);

    useEffect(() => {
        fetchJobs();
        const interval = setInterval(fetchJobs, 10000);
        return () => clearInterval(interval);
    }, [fetchJobs]);

    return (
        <div className="page-container">
            <div className="page-header">
                <div>
                    <h1>Jobs</h1>
                    <p className="text-muted">Tenant: {userInfo?.tenant_id?.slice(0, 8)}…</p>
                </div>
                {(userInfo?.role === 'ADMIN' || userInfo?.role === 'DOCTOR') && (
                    <Link to="/jobs/new" className="btn btn-primary">+ New Job</Link>
                )}
            </div>

            {error && <div className="alert alert-error">{error}</div>}

            {loading ? (
                <div className="loading-center"><div className="spinner" /></div>
            ) : jobs.length === 0 ? (
                <div className="empty-state">
                    <span className="empty-icon">📋</span>
                    <h3>No jobs yet</h3>
                    <p>Submit your first job to get started.</p>
                </div>
            ) : (
                <div className="table-container">
                    <table className="data-table">
                        <thead>
                            <tr>
                                <th>Task ID</th>
                                <th>Query</th>
                                <th>Status</th>
                                <th>Created</th>
                            </tr>
                        </thead>
                        <tbody>
                            {jobs.map((job) => (
                                <tr key={job.task_id}>
                                    <td>
                                        <Link to={`/jobs/${job.task_id}`} className="link-primary">
                                            {job.task_id.slice(0, 8)}…
                                        </Link>
                                    </td>
                                    <td className="query-cell">{job.query}</td>
                                    <td>
                                        <span
                                            className="status-badge"
                                            style={{ backgroundColor: STATUS_COLORS[job.status] || '#6b7280' }}
                                        >
                                            {job.status}
                                        </span>
                                    </td>
                                    <td className="text-muted">
                                        {new Date(job.created_at).toLocaleString()}
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
