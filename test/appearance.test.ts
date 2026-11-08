/**
 * 系统深浅色接入（纯逻辑层）单测 —— 2026-11-08 P0-1。
 *
 * 守的是私记 2026-10-25 / 10-26 华为复评踩过的三个坑：
 * 数值映射（DARK=0 不是 1）、跟随系统档要重算、显式选过的人不被系统覆盖。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  COLOR_MODE_DARK,
  COLOR_MODE_LIGHT,
  COLOR_MODE_NOT_SET,
  effectiveTheme,
  followSystemNeedsRefresh,
  isSystemDarkColorMode,
  SYSTEM_DARK_KEY
} from '../entry/src/main/ets/common/Appearance.ets';
import {
  THEME_AUTO, THEME_DARK, THEME_GREEN, THEME_LIGHT, THEME_SEPIA, THEME_SYSTEM, ThemeName
} from '../entry/src/main/ets/common/Theme.ets';

test('ConfigurationConstant.ColorMode 数值映射：DARK 是 0，不是 1', () => {
  assert.equal(COLOR_MODE_NOT_SET, -1);
  assert.equal(COLOR_MODE_DARK, 0);
  assert.equal(COLOR_MODE_LIGHT, 1);
  assert.equal(isSystemDarkColorMode(COLOR_MODE_DARK), true);
  assert.equal(isSystemDarkColorMode(COLOR_MODE_LIGHT), false);
  assert.equal(isSystemDarkColorMode(COLOR_MODE_NOT_SET), false);
  assert.equal(isSystemDarkColorMode(undefined), false);
});

test('AppStorage 键名固定（页面 @StorageProp 写字面量，两边要一起改）', () => {
  assert.equal(SYSTEM_DARK_KEY, 'systemDark');
});

test('六格真值表：system 跟系统深浅，其余档位不受系统影响', () => {
  const cases: [ThemeName, boolean, ThemeName][] = [
    [THEME_SYSTEM, false, THEME_LIGHT],
    [THEME_SYSTEM, true, THEME_DARK],
    [THEME_DARK, false, THEME_DARK],
    [THEME_DARK, true, THEME_DARK],
    [THEME_LIGHT, false, THEME_LIGHT],
    [THEME_LIGHT, true, THEME_LIGHT],
    [THEME_SEPIA, true, THEME_SEPIA],
    [THEME_GREEN, true, THEME_GREEN],
    [THEME_AUTO, true, THEME_LIGHT] // 10 点是白天，auto 按小时不受系统深浅影响
  ];
  for (const [mode, dark, want] of cases) {
    assert.equal(effectiveTheme(mode, 10, dark), want,
      `${mode} + 系统${dark ? '深' : '浅'} 应解出 ${want}`);
  }
  assert.equal(effectiveTheme(THEME_AUTO, 20, false), THEME_DARK);
});

test('followSystemNeedsRefresh：只有跟随系统档、且生效主题真的变了才重算', () => {
  assert.equal(followSystemNeedsRefresh(THEME_SYSTEM, true, 10, THEME_LIGHT), true);
  assert.equal(followSystemNeedsRefresh(THEME_SYSTEM, false, 10, THEME_DARK), true);
  assert.equal(followSystemNeedsRefresh(THEME_SYSTEM, true, 10, THEME_DARK), false);
  // 显式选了纸色 / 深色 / 自动昼夜的人，系统切深浅不该覆盖
  assert.equal(followSystemNeedsRefresh(THEME_SEPIA, true, 10, THEME_SEPIA), false);
  assert.equal(followSystemNeedsRefresh(THEME_DARK, false, 10, THEME_DARK), false);
  assert.equal(followSystemNeedsRefresh(THEME_AUTO, true, 10, THEME_LIGHT), false);
});
