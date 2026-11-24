import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { ipad, launch } from './launch.ts';

test('the connect screen opens and closes Add a Mac', { tags: ['ipad'] }, async ({ device, screen, app }) => {
  await launch(device, [...ipad, '-SillConnectCase', 'methods']);
  await expect(screen.getByText('Add a Mac')).toBeVisible();
  await expect(screen.getByText('Reconnect automatically').first()).toBeVisible();
  await app.screenshot('01-connect-methods');
  await screen.getByText('Add a Mac').tap();
  await expect(screen.getByText('Cancel').first()).toBeVisible();
  await app.screenshot('02-add-a-mac-sheet');
  await screen.getByText('Cancel').first().tap();
  await expect(screen.getByText('Reconnect automatically').first()).toBeVisible();
});
