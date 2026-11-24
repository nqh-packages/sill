import type { E2EConfig } from 'e2e';
import { mobile } from '@e2e-dev/mobile';

const app = { bundleId: 'com.uxheavy.sill' };

export default {
  tests: 'tests/**/*.e2e.ts',
  workers: 1,
  targets: [
    { name: 'ipad', engine: mobile({ platform: 'ios', device: process.env.SILL_E2E_IPAD ?? 'iPad Pro 11-inch (M5)' }), app },
    { name: 'phone', engine: mobile({ platform: 'ios', device: process.env.SILL_E2E_PHONE ?? 'iPhone 17 Pro' }), app },
  ],
} satisfies E2EConfig;
