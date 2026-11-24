import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { ipad, launch } from './launch.ts';

const xxxl = ['-UIPreferredContentSizeCategoryName', 'UICTContentSizeCategoryAccessibilityXXXL'];

test('at the largest text size the Picture in Picture tile shows its whole label', { tags: ['ipad'] }, async ({ device, screen, app }) => {
  await launch(device, [...ipad, '-SillSettings', '1', ...xxxl]);
  await expect(screen.getByText('Picture in Picture').first()).toBeVisible();
  await screen.getByRole('button', { name: 'Sheet Grabber' }).tap();
  const pip = await screen.getByText('Picture in Picture').first().boundingBox();
  const menus = await screen.getByText('Menus').first().boundingBox();
  await app.screenshot('01-deck-xxxl');
  expect(pip.height).toBeGreaterThan(menus.height * 1.5);
});
