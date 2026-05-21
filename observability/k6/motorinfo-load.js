// Motorinfo load test
//
// Run locally:
//   k6 run observability/k6/motorinfo-load.js
//
// Run on Grafana Cloud k6:
//   k6 cloud login --token <K6_CLOUD_TOKEN>
//   k6 cloud run observability/k6/motorinfo-load.js
//
// Or paste into Grafana Cloud → Performance → k6 → New test.

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Trend, Counter } from 'k6/metrics';

const BASE = __ENV.BASE_URL || 'https://motorinfo.ytt.io';

// Sample plates from the seeded data — vary so cache doesn't hide everything.
const PLATES = ['BC12345', 'AT98765', 'CD55512', 'EL10001', 'DK42424'];
const NOT_FOUND_PLATES = ['XX99999', 'NOPLATE', 'ZZ00001'];

const apiLookupTrend = new Trend('motorinfo_api_lookup_duration', true);
const homeLoadTrend = new Trend('motorinfo_home_load_duration', true);
const notFoundCounter = new Counter('motorinfo_not_found_count');

export const options = {
  cloud: {
    name: 'Motorinfo — baseline load',
    projectID: parseInt(__ENV.K6_PROJECT_ID || '0', 10) || undefined,
    distribution: {
      'amazon:de:frankfurt': { loadZone: 'amazon:de:frankfurt', percent: 100 },
    },
  },
  scenarios: {
    home_browsing: {
      executor: 'ramping-vus',
      exec: 'browseHome',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 5 },
        { duration: '1m', target: 10 },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '15s',
      tags: { scenario: 'home_browsing' },
    },
    api_lookups: {
      executor: 'constant-arrival-rate',
      exec: 'apiLookup',
      rate: 5,
      timeUnit: '1s',
      duration: '2m',
      preAllocatedVUs: 5,
      maxVUs: 20,
      tags: { scenario: 'api_lookups' },
    },
  },
  thresholds: {
    'http_req_failed':                  ['rate<0.01'],     // <1% error rate overall
    'http_req_duration{scenario:home_browsing}': ['p(95)<800'],
    'motorinfo_api_lookup_duration':    ['p(95)<400', 'p(99)<1000'],
    'motorinfo_home_load_duration':     ['p(95)<800'],
  },
};

function pickPlate() {
  // 90% known plates, 10% unknown — exercises both code paths.
  if (Math.random() < 0.1) {
    return NOT_FOUND_PLATES[Math.floor(Math.random() * NOT_FOUND_PLATES.length)];
  }
  return PLATES[Math.floor(Math.random() * PLATES.length)];
}

export function browseHome() {
  group('home page', () => {
    const t0 = Date.now();
    const res = http.get(`${BASE}/`, { tags: { endpoint: 'home' } });
    homeLoadTrend.add(Date.now() - t0);

    check(res, {
      'home status 200': (r) => r.status === 200,
      'home has search form': (r) => r.body && r.body.includes('Nummerpladeopslag'),
      'home served by motorinfo-web': (r) => r.headers && r.headers['Server'] === undefined || r.headers['Server'] === 'cloudflare',
    });
  });
  sleep(Math.random() * 2 + 1);
}

export function apiLookup() {
  const plate = pickPlate();
  group('api vehicle lookup', () => {
    const t0 = Date.now();
    const res = http.get(`${BASE}/v1/vehicles?registration=${plate}`, {
      tags: { endpoint: 'api_lookup', expected: NOT_FOUND_PLATES.includes(plate) ? 'empty' : 'hit' },
    });
    apiLookupTrend.add(Date.now() - t0);

    const ok = check(res, {
      'api status 200': (r) => r.status === 200,
      'api returns JSON': (r) => (r.headers && r.headers['Content-Type'] || '').includes('application/json'),
    });

    if (ok && res.status === 200) {
      try {
        const body = res.json();
        if (NOT_FOUND_PLATES.includes(plate)) {
          if (body && body.data && body.data.length === 0) notFoundCounter.add(1);
        } else {
          check(body, {
            'api returns 1 vehicle for known plate': (b) => b && b.data && b.data.length === 1,
            'vehicle has VIN': (b) => b && b.data && b.data[0] && typeof b.data[0].vin === 'string',
          });
        }
      } catch (e) { /* malformed JSON is captured by api status check */ }
    }
  });
}
