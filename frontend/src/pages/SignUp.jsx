import React, { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';

export default function SignUp() {
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [confirmCode, setConfirmCode] = useState('');
    const [step, setStep] = useState('register'); // 'register' | 'confirm'
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(false);
    const { signUp, confirmSignUp, signIn } = useAuth();
    const navigate = useNavigate();

    const handleRegister = async (e) => {
        e.preventDefault();
        setError('');
        setLoading(true);
        try {
            await signUp(email, password);
            setStep('confirm');
        } catch (err) {
            setError(err.message || 'Sign up failed');
        } finally {
            setLoading(false);
        }
    };

    const handleConfirm = async (e) => {
        e.preventDefault();
        setError('');
        setLoading(true);
        try {
            await confirmSignUp(email, confirmCode);
            await signIn(email, password);
            navigate('/');
        } catch (err) {
            setError(err.message || 'Confirmation failed');
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className="auth-page">
            <div className="auth-card">
                <div className="auth-header">
                    <div className="brand-icon large">⚡</div>
                    <h1>{step === 'register' ? 'Create account' : 'Verify email'}</h1>
                    <p>{step === 'register'
                        ? 'Get started with Infra Demo'
                        : `We sent a code to ${email}`
                    }</p>
                </div>
                {step === 'register' ? (
                    <form onSubmit={handleRegister}>
                        {error && <div className="alert alert-error">{error}</div>}
                        <div className="form-group">
                            <label>Email</label>
                            <input
                                type="email"
                                value={email}
                                onChange={(e) => setEmail(e.target.value)}
                                placeholder="you@company.com"
                                required
                            />
                        </div>
                        <div className="form-group">
                            <label>Password</label>
                            <input
                                type="password"
                                value={password}
                                onChange={(e) => setPassword(e.target.value)}
                                placeholder="Min 8 chars, uppercase + number"
                                required
                                minLength={8}
                            />
                        </div>
                        <button type="submit" className="btn btn-primary btn-block" disabled={loading}>
                            {loading ? 'Creating…' : 'Create Account'}
                        </button>
                    </form>
                ) : (
                    <form onSubmit={handleConfirm}>
                        {error && <div className="alert alert-error">{error}</div>}
                        <div className="form-group">
                            <label>Verification Code</label>
                            <input
                                type="text"
                                value={confirmCode}
                                onChange={(e) => setConfirmCode(e.target.value)}
                                placeholder="123456"
                                required
                                autoFocus
                            />
                        </div>
                        <button type="submit" className="btn btn-primary btn-block" disabled={loading}>
                            {loading ? 'Verifying…' : 'Verify & Sign In'}
                        </button>
                    </form>
                )}
                <p className="auth-footer">
                    Already have an account? <Link to="/login">Sign in</Link>
                </p>
            </div>
        </div>
    );
}
