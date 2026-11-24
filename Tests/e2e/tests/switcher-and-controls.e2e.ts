import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { ipad, launch } from './launch.ts';

test('the switcher picks the Desktop, then Control Center opens', { tags: ['ipad'] }, async ({ device, screen, app }) => {
  await launch(device, ipad);
  await screen.getByText('Apps').tap();
  await expect(screen.getByText('Done')).toBeVisible();
  await expect(screen.getByText('Windows')).toBeVisible();
  await app.screenshot('01-switcher-open');

  await screen.getByText('Desktop').first().tap();
  await expect(screen.getByText('Controls')).toBeVisible();
  await app.screenshot('02-desktop-active');

  await screen.getByText('Controls').tap();
  await expect(screen.getByText('Streaming')).toBeVisible();
  await expect(screen.getByText('This iPad')).toBeVisible();
  await app.screenshot('03-control-center-root');
  await screen.scrollUntilVisible(screen.getByText('Disconnect from Mac mini'));
  await app.screenshot('04-control-center-bottom');
});
