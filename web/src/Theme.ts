// reads bootstrap's css custom properties off the root element. these track
// the active data-bs-theme (light/dark) so we don't have to hardcode colors.

export interface ThemeColors {
  bodyBg: string;
  bodyColor: string;
  primary: string;
  borderColor: string;
  secondaryBg: string;
}

export function readThemeColors(): ThemeColors {
  const styles = getComputedStyle(document.documentElement);
  const read = (name: string) => styles.getPropertyValue(name).trim();
  return {
    bodyBg: read("--bs-body-bg"),
    bodyColor: read("--bs-body-color"),
    primary: read("--bs-primary"),
    borderColor: read("--bs-border-color"),
    secondaryBg: read("--bs-secondary-bg"),
  };
}
