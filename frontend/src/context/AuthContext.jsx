import React, { createContext, useState, useContext, useEffect, useCallback } from 'react';
import {
    CognitoUser,
    AuthenticationDetails,
} from 'amazon-cognito-identity-js';
import { userPool, API_URL } from '../config';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
    const [user, setUser] = useState(null);
    const [userInfo, setUserInfo] = useState(null); // { tenant_id, role, email }
    const [loading, setLoading] = useState(true);

    const getToken = useCallback(() => {
        return new Promise((resolve, reject) => {
            const cognitoUser = userPool.getCurrentUser();
            if (!cognitoUser) return reject(new Error('No user'));
            cognitoUser.getSession((err, session) => {
                if (err) return reject(err);
                resolve(session.getIdToken().getJwtToken());
            });
        });
    }, []);

    const registerTenant = useCallback(async (token, tenantName) => {
        const res = await fetch(`${API_URL}/tenants/register`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                Authorization: `Bearer ${token}`,
            },
            body: JSON.stringify({ tenant_name: tenantName || undefined }),
        });
        return res.json();
    }, []);

    // Check session on mount
    useEffect(() => {
        const cognitoUser = userPool.getCurrentUser();
        if (!cognitoUser) {
            setLoading(false);
            return;
        }
        cognitoUser.getSession(async (err, session) => {
            if (err || !session?.isValid()) {
                setLoading(false);
                return;
            }
            setUser(cognitoUser);
            try {
                const token = session.getIdToken().getJwtToken();
                const data = await registerTenant(token);
                setUserInfo({
                    tenant_id: data.tenant_id,
                    role: data.role,
                    email: session.getIdToken().payload.email,
                });
            } catch (e) {
                console.error('Failed to register tenant:', e);
            }
            setLoading(false);
        });
    }, [registerTenant]);

    const signUp = (email, password) => {
        return new Promise((resolve, reject) => {
            userPool.signUp(email, password, [
                { Name: 'email', Value: email },
            ], null, (err, result) => {
                if (err) return reject(err);
                resolve(result);
            });
        });
    };

    const confirmSignUp = (email, code) => {
        const cognitoUser = new CognitoUser({ Username: email, Pool: userPool });
        return new Promise((resolve, reject) => {
            cognitoUser.confirmRegistration(code, true, (err, result) => {
                if (err) return reject(err);
                resolve(result);
            });
        });
    };

    const signIn = (email, password) => {
        const cognitoUser = new CognitoUser({ Username: email, Pool: userPool });
        const authDetails = new AuthenticationDetails({ Username: email, Password: password });

        return new Promise((resolve, reject) => {
            cognitoUser.authenticateUser(authDetails, {
                onSuccess: async (session) => {
                    setUser(cognitoUser);
                    try {
                        const token = session.getIdToken().getJwtToken();
                        const data = await registerTenant(token);
                        setUserInfo({
                            tenant_id: data.tenant_id,
                            role: data.role,
                            email,
                        });
                    } catch (e) {
                        console.error('Failed to register tenant:', e);
                    }
                    resolve(session);
                },
                onFailure: reject,
            });
        });
    };

    const signOut = () => {
        const cognitoUser = userPool.getCurrentUser();
        if (cognitoUser) cognitoUser.signOut();
        setUser(null);
        setUserInfo(null);
    };

    return (
        <AuthContext.Provider value={{
            user, userInfo, loading, signUp, confirmSignUp, signIn, signOut, getToken
        }}>
            {children}
        </AuthContext.Provider>
    );
}

export function useAuth() {
    const context = useContext(AuthContext);
    if (!context) throw new Error('useAuth must be used within AuthProvider');
    return context;
}
