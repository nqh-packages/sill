import type { E2EConfig } from 'e2e';
import { mobile } from '@e2e-dev/mobile';

const app = { bundleId: 'com.uxheavy.sill' };
const ipad = process.env.SILL_E2E_IPAD ?? 'iPad Pro 11-inch (M5)';
const phone = process.env.SILL_E2E_PHONE ?? 'iPhone 17 Pro';
const session = (device: string) => `e2e-${device.toLowerCase().replace(/[^a-z0-9]+/g, '-')}`;

export default {
  tests: 'tests/**/*.e2e.ts',
  workers: 1,
  targets: [
    { name: 'ipad', engine: mobile({ platform: 'ios', device: ipad, session: session(ipad) }), app },
    { name: 'phone', engine: mobile({ platform: 'ios', device: phone, session: session(phone) }), app },
  ],
} satisfies E2EConfig;
