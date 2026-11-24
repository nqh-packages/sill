import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launch, phone } from './launch.ts';

test('Control Center shows Quality as Auto from a Mac that offers it', { tags: ['phone'] }, async ({ device, screen, app }) => {
  await launch(device, [...phone, '-SillSettings', '1', '-SillSettingsCase', 'auto']);
  await expect(screen.getByText('Streaming')).toBeVisible({ timeout: 10_000 });
  await screen.getByRole('button', { name: 'Sheet Grabber' }).tap();
  await expect(screen.getByRole('button', { name: 'Quality, Auto' })).toBeVisible();
  await app.screenshot('01-quality-auto');
});
