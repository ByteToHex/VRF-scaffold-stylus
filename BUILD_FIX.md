# Fixing Build Issues

## Issue 1: Next.js Registry Error

Next.js tries to run `yarn config get registry` which doesn't work with Yarn 3. The registry is now set to the standard npm registry in `.yarnrc.yml`.

If you still get registry errors, set this environment variable:
```bash
export npm_config_registry=https://registry.npmjs.org/
```

## Issue 2: Native Module Build Failures

The build failures for `esbuild` and `unrs-resolver` are likely due to missing build tools on Linux/WSL.

### Install Required Build Tools

On Ubuntu/Debian (WSL):
```bash
sudo apt-get update
sudo apt-get install -y python3 make g++ nodejs npm
```

On Fedora/RHEL:
```bash
sudo dnf install -y python3 make gcc-c++ nodejs npm
```

### Alternative: Use Pre-built Binaries

If you continue to have build issues, you can try:

1. Clean and reinstall:
```bash
rm -rf node_modules packages/*/node_modules .yarn/cache
yarn install
```

2. If that doesn't work, try installing esbuild globally first:
```bash
npm install -g esbuild
yarn install
```

3. Check build logs for specific errors:
```bash
cat /tmp/xfs-8a386cae/build.log
cat /tmp/xfs-ef1b9576/build.log
```

### Permission Issues

If you see permission errors, try:
```bash
chmod +x node_modules/.bin/*
```

## Running the Project

After fixing the build issues:
```bash
yarn install
yarn start
```

