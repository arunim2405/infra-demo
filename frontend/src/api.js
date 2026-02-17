import { API_URL } from './config';

async function apiFetch(path, { method = 'GET', body, token } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers['Authorization'] = `Bearer ${token}`;

  const res = await fetch(`${API_URL}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  const data = await res.json();
  if (!res.ok) throw { status: res.status, ...data };
  return data;
}

export const api = {
  // Jobs
  listJobs: (token, limit = 20, nextToken) => {
    let path = `/jobs?limit=${limit}`;
    if (nextToken) path += `&next_token=${encodeURIComponent(nextToken)}`;
    return apiFetch(path, { token });
  },
  submitJob: (token, query) =>
    apiFetch('/jobs', { method: 'POST', body: { query }, token }),
  getJob: (token, taskId) =>
    apiFetch(`/jobs/${taskId}`, { token }),
  getJobLogs: (token, taskId, limit = 200, nextToken) => {
    let path = `/jobs/${taskId}/logs?limit=${limit}`;
    if (nextToken) path += `&next_token=${encodeURIComponent(nextToken)}`;
    return apiFetch(path, { token });
  },

  // Tenants
  registerTenant: (token, tenantName) =>
    apiFetch('/tenants/register', { method: 'POST', body: { tenant_name: tenantName }, token }),

  // Users
  listUsers: (token) =>
    apiFetch('/tenants/users', { token }),
  addUser: (token, email, role) =>
    apiFetch('/tenants/users', { method: 'POST', body: { email, role }, token }),
  removeUser: (token, cognitoId) =>
    apiFetch(`/tenants/users/${cognitoId}`, { method: 'DELETE', token }),
};
