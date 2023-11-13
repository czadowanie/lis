# LIS

A simple, statically linked utility for setting display brightness.

# Usage
show current brightness:
```
lis
```

set current brightness (in decimal):
```
lis 234
```

set current brightness (in hex):
```
lis h8c
```

# Building from source

You only need `zig-0.11`.

```
git clone --depth=1 https://github.com/czadowanie/lis
cd lis
zig build install -Dptimize=ReleaseFast --prefix $HOME/.local
```
