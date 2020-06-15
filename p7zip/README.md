# Introduction
Makefile to create package p7zip for [LEDE](https://lede-project.org)/[OpenWrt](https://openwrt.org/).
Only `7z` is available, if you need `7za` or `7zr`, you might freedly modify the `MAKE_FLAGS` and the install section in file `Makefile`, don't foget to create`files/7za` or `files/7zr` using `files/7z` as template.

# Usage
```bash
cd lede-sdk/
git clone https://github.com/hubutui/p7zip-lede.git package/p7zip
make menuconfig
```

Check Ultilities->p7zip

```bash
make -j 1 V=s
```

And you'll get the ipk file under `bin` directory.
