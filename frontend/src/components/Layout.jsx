import React from 'react';
import { NavLink, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';

export default function Layout({ children }) {
    const { userInfo, signOut } = useAuth();
    const navigate = useNavigate();

    const handleSignOut = () => {
        signOut();
        navigate('/login');
    };

    return (
        <div className="app-layout">
            <nav className="sidebar">
                <div className="sidebar-brand">
                    <div className="brand-icon">⚡</div>
                    <span className="brand-text">Infra Demo</span>
                </div>
                <div className="sidebar-nav">
                    <NavLink to="/" className="nav-link" end>
                        <span className="nav-icon">📋</span> Jobs
                    </NavLink>
                    {(userInfo?.role === 'ADMIN' || userInfo?.role === 'DOCTOR') && (
                        <NavLink to="/jobs/new" className="nav-link">
                            <span className="nav-icon">➕</span> New Job
                        </NavLink>
                    )}
                    {userInfo?.role === 'ADMIN' && (
                        <NavLink to="/team" className="nav-link">
                            <span className="nav-icon">👥</span> Team
                        </NavLink>
                    )}
                </div>
                <div className="sidebar-footer">
                    <div className="user-info">
                        <span className="user-email">{userInfo?.email}</span>
                        <span className="user-role">{userInfo?.role}</span>
                    </div>
                    <button className="btn-sign-out" onClick={handleSignOut}>Sign Out</button>
                </div>
            </nav>
            <main className="main-content">
                {children}
            </main>
        </div>
    );
}
