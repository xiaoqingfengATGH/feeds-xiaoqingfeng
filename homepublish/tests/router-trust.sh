#!/bin/sh
# Run only in the isolated root-owned router fixture.
set -eu
R=/tmp/homepublish-test
trap 'chmod 700 "$R"; chmod 600 "$R/nginx.conf"' EXIT
chmod 600 "$R/nginx.conf" "$R/cert.pem" "$R/key.pem"
chmod 777 "$R"
if "$R/lease-supervisor" "$R" 1 >"$R/security-red.log" 2>&1; then
 echo 'FAIL SEC002: world-writable runtime accepted'; exit 1
fi
echo 'PASS SEC002: world-writable runtime rejected'
chmod 700 "$R"
reject() {
 if "$R/lease-supervisor" "$R" 1 >"$R/trust.log" 2>&1; then echo "FAIL SEC002: $1 accepted"; exit 1; fi
 echo "PASS SEC002: $1 rejected"
}
chmod 620 "$R/nginx.conf"; reject 'group-writable config'; chmod 600 "$R/nginx.conf"
chown 65534 "$R/nginx.conf"; reject 'attacker-owned config'; chown 0 "$R/nginx.conf"
for file in nginx.conf cert.pem key.pem; do
 mv "$R/$file" "$R/$file.real"
 ln -s "$R/$file.real" "$R/$file"
 reject "symlink $file"
 rm "$R/$file"; mv "$R/$file.real" "$R/$file"
done
chown 65534 "$R"; reject 'attacker-owned runtime'; chown 0 "$R"
chmod 770 "$R"; reject 'group-writable runtime'; chmod 700 "$R"
for file in cert.pem key.pem; do
 chmod 620 "$R/$file"; reject "group-writable $file"; chmod 600 "$R/$file"
 chmod 604 "$R/$file"; reject "world-readable $file"; chmod 600 "$R/$file"
 chown 65534 "$R/$file"; reject "attacker-owned $file"; chown 0 "$R/$file"
done
mv "$R" "$R-real"; ln -s "$R-real" "$R"
reject 'symlink runtime'
rm "$R"; mv "$R-real" "$R"
# Trusted original files are not reopened after validation or at nginx launch.
"$R/lease-supervisor" "$R" 3 >"$R/snapshot.log" 2>&1 &
p=$!
sleep 1
[ -f "$R/runner.lock/nginx.pid" ]
ls -l "$R/runner.lock/nginx.conf" | grep -q '^-r--------'
for file in nginx.conf cert.pem key.pem; do
 cp "$R/$file" "$R/$file.saved"
 [ "$(ls -l "$R/runner.lock/$file" | cut -c1-10)" = '-r--------' ]
 if [ "$file" != nginx.conf ]; then cmp "$R/$file.saved" "$R/runner.lock/$file"; fi
 printf '%s\n' 'invalid replacement' >"$R/$file"
done
# Exact snapshot is the -t and launch target, with copied private TLS material.
! grep -q 'invalid replacement' "$R/runner.lock/nginx.conf"
grep -q "$R/runner.lock/cert.pem" "$R/runner.lock/nginx.conf"
[ "$(curl --max-time 1 --noproxy '*' -sk -o /dev/null -w '%{http_code}' --resolve nas-stun-test.innonext.win:18443:127.0.0.1 https://nas-stun-test.innonext.win:18443/)" = 502 ]
wait "$p"
for file in nginx.conf cert.pem key.pem; do mv "$R/$file.saved" "$R/$file"; done
[ ! -d "$R/runner.lock" ]
echo 'PASS SEC002: private snapshot survives source replacement and cleans up'
