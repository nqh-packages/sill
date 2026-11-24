import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { ipad, launch } from './launch.ts';

test('the iPad chrome launches with its controls', { tags: ['ipad'] }, async ({ device, screen, app }) => {
  await launch(device, ipad);
  for (const label of ['Apps', 'Text size', 'Keyboard', 'Trackpad', 'Controls', 'Minimize controls']) {
    await expect(screen.getByText(label)).toBeVisible();
  }
  await app.screenshot('smoke-pad-bottom');
});
