# Backend lifecycle / DNS discovery

## Frontend contract

No new RPC is required. Use existing UCI `homekms.main.auto_discovery` (boolean,
default `0`) with `enabled` and `port`. Save & Apply reloads HomeKMS.
When enabled and running, HomeKMS owns only `dhcp.homekms`, a `srvhost` section
with `srv=_vlmcs._tcp.<dnsmasq-domain>`, `target=<system-hostname>.<domain>`,
and the configured TCP port. Defaults are `lan` and `OpenWrt` when absent.
Clients must use the router's DNS/search domain; this does not configure client
DNS settings or perform Windows/Office activation. WAN access remains separate.

Stop removes the owned SRV section. Off/repeated off is idempotent, and changing
the port updates it. No unrelated DNS sections are deleted. dnsmasq reload is
requested only when the owned record changes. DNS uses the first dnsmasq
instance's domain; multi-instance/split-DNS is not automatically inferred.

## Why stop previously broke Save & Apply

Read-only inspection of the actual router's `/etc/rc.common` and
`/lib/functions/procd.sh` confirmed this order:
`stop_service` -> `procd_kill` -> `service_stopped`. `procd_kill` issues service
`delete`, removing triggers too. Registering triggers in `stop_service` is too
early. `service_stopped` now registers a service with zero instances via
`rc_procd service_triggers_only`; procd's close-service automatically attaches
`service_triggers`. No idle Python process or WAN rule is kept. A subsequent
config event runs the ordinary reload/start transaction. Plain temporary stop
is intentionally not a persistent disabled latch; Save & Apply may resume it.

## Verification boundary

Local isolated shell tests first reproduced lost triggers (exit 1), then passed
after the hook fix. DNS helper was RED before implementation, GREEN after;
integration initially failed with `start did not publish DNS`, then passed.
Tests model the exact observed rc.common order but do not claim live procd
acceptance. Router access was read-only; no package/configuration was deployed.
Run `bash homekms/tests/test_lifecycle.sh` and
`bash homekms/tests/test_discovery.sh`. Packaging unittest also passes its two
source checks; archive hash verification requires HOMEKMS_ARCHIVE.
Firmware/IPK build and deployed DNS/procd acceptance remain parent/build steps.
