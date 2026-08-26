// vite sets DEV when the app is served by the dev server (`rake web:vite`) and clears
// it for `vite build`, so this is the same flag the dev tab's title and favicon use
export const isDevelopment = import.meta.env.DEV;
