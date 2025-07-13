# lis

Utility for setting display brightness on linux.

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

```
git clone --depth=1 https://github.com/czadowanie/lis
cd lis
zig build install -Doptimize=ReleaseSmall --prefix $HOME/.local
```
