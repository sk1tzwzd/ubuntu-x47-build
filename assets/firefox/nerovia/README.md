# Nerovia Firefox widget profile (Visual stack only)

Two borderless Firefox windows crop `https://app.nerovia.ai` to:

- Chart — `?x47=chart`
- Open Positions — `?x47=positions`

## One-time login

```bash
x47-nerovia-widgets login
```

Sign in once in the `nerovia` profile. Both widget windows share that session.

## Controls

```bash
x47-nerovia-widgets start|stop|status|login
```

Autostart runs only when desktop mode is **Visual** (stack installed as `visual` or `both`).

## Selector overrides

If a site redesign breaks cropping, set in the Nerovia profile’s console:

```js
localStorage.setItem('x47NeroviaSelectors', JSON.stringify({
  chart: '.your-chart-root',
  positions: '.your-positions-root',
}));
location.reload();
```

Geometry defaults live in `~/.config/x47/nerovia-widgets.json`.
