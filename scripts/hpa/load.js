import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 5 },
    { duration: '1m', target: 10 },
    { duration: '2m', target: 20 },
    { duration: '5m', target: 40 },
    { duration: '30s', target: 0 },
  ],
  thresholds: { http_req_failed: ['rate<0.01'] },
};

// Read-only business traffic. Authentication happens once, not in the load loop.
export function setup() {
  const base = __ENV.HPA_API_URL;
  const login = http.post(`${base}/api/auth/login`, JSON.stringify({
    username: __ENV.HPA_USERNAME || 'Patricia Almeida',
    password: __ENV.HPA_PASSWORD || 'senha123',
  }), { headers: { 'Content-Type': 'application/json' } });
  if (login.status !== 200) throw new Error('HPA test login failed');
  return { base, token: login.json('token') };
}

export default function (data) {
  const response = http.get(`${data.base}/api/ordens-servico`, {
    headers: { Authorization: `Bearer ${data.token}`, 'X-Correlation-Id': `hpa-${__VU}-${__ITER}` },
    tags: { name: 'HPA - consultar ordens de servico' },
    timeout: '15s',
  });
  check(response, { 'consulta OS retorna 200': r => r.status === 200 });
  sleep(0.05);
}
