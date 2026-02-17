import React from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { useAuth } from './context/AuthContext';
import Layout from './components/Layout';
import Login from './pages/Login';
import SignUp from './pages/SignUp';
import Dashboard from './pages/Dashboard';
import JobDetail from './pages/JobDetail';
import NewJob from './pages/NewJob';
import Team from './pages/Team';

function ProtectedRoute({ children, allowedRoles }) {
    const { user, userInfo, loading } = useAuth();

    if (loading) return <div className="loading-screen"><div className="spinner" /></div>;
    if (!user) return <Navigate to="/login" />;
    if (!userInfo?.tenant_id) return <Navigate to="/login" />;
    if (allowedRoles && !allowedRoles.includes(userInfo.role)) {
        return <div className="page-container"><p className="error-text">Access denied</p></div>;
    }
    return children;
}

export default function App() {
    const { user, loading } = useAuth();

    if (loading) return <div className="loading-screen"><div className="spinner" /></div>;

    return (
        <Routes>
            <Route path="/login" element={user ? <Navigate to="/" /> : <Login />} />
            <Route path="/signup" element={user ? <Navigate to="/" /> : <SignUp />} />
            <Route path="/" element={
                <ProtectedRoute><Layout><Dashboard /></Layout></ProtectedRoute>
            } />
            <Route path="/jobs/new" element={
                <ProtectedRoute allowedRoles={['ADMIN', 'DOCTOR']}>
                    <Layout><NewJob /></Layout>
                </ProtectedRoute>
            } />
            <Route path="/jobs/:taskId" element={
                <ProtectedRoute><Layout><JobDetail /></Layout></ProtectedRoute>
            } />
            <Route path="/team" element={
                <ProtectedRoute allowedRoles={['ADMIN']}>
                    <Layout><Team /></Layout>
                </ProtectedRoute>
            } />
            <Route path="*" element={<Navigate to="/" />} />
        </Routes>
    );
}
