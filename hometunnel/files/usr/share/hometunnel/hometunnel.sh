#!/bin/sh
# hometunnel.sh — 核心子命令 CLI（向导后端/运维入口）
#
# 子命令:
#   job <name> <cmd...>     后台 job: setsid+nohup 执行，输出→/var/run/hometunnel/<name>.out，结束写 .rc
#   jobstatus <name>        查询 job: running|done:<rc>|missing
#   login                   cloudflared tunnel login（HOME=/etc/hometunnel），由向导以 job 形式调用
#   create                  tunnel create <name>（幂等: 已存在则复用），提取 UUID 写 UCI
#   route                   对每条 enabled ingress 执行 tunnel route dns
#   regen                   gen-yml.sh + 平滑重启数据面（若在运行）
#   bundle                  生成 Worker 部署包 /tmp/hometunnel-worker-<domain>.tar.gz
#   verify                  控制面连通性验证: /healthz + /cmd（带 key）
#   status                  人读状态汇总
#   cleanup                 tunnel delete + 清理指引
#   zones                   用 cert.pem 内的 apiToken 列出账户全部 Cloudflare zone（域名）
#   apply-mode              按 UCI mode 联动两个 init 的 enable 状态并 start/stop
#   genkey                  生成/重建 /etc/hometunnel/ctl.key
#   oauth-start             生成设备授权 URL（RFC 8628，扫码一次授权开关服务部署）
#   oauth-status            查询授权轮询状态（向导轮询用）
#   oauth-clear             清除本地保存的 OAuth 凭据（解绑/重授权用）
#   deploy [takeover]       自动部署控制面 Worker（takeover=用户确认接管冲突域名后传入）
#   oauth-deploy            oauth-start + 轮询等授权 + deploy 一条龙（向导调用）
#
# 灵感与协议来源: AI-X-Space/llm-ondemand-tunnel (Apache-2.0)
# OAuth 设备流实现参照 Cloudflare workers-sdk (wrangler) 公开源码:
#   client_id = wrangler 官方 OAuth 应用（workers-auth/src/wrangler/env.ts 公开常量）
#   端点 = dash.cloudflare.com/oauth2/{device/auth,token}（wrangler 同款）

set -u

SHARE=/usr/share/hometunnel
RUNDIR=/var/run/hometunnel
ETC=/etc/hometunnel
UCI_CONF=hometunnel
CF=/usr/bin/cloudflared
KEY_FILE=$ETC/ctl.key
OAUTH_JSON=$ETC/oauth.json
WORKER_NAME=hometunnel-ctl

# wrangler 官方 OAuth 应用（公开常量，无 client_secret）
OAUTH_CLIENT_ID=54d11594-84e4-41aa-b438-e81b8fa78ee7
OAUTH_DEVICE_URL=https://dash.cloudflare.com/oauth2/device/auth
OAUTH_TOKEN_URL=https://dash.cloudflare.com/oauth2/token
# 只申请部署控制面 Worker 必需的最小权限集（比 wrangler login 默认 30 个 scope 小得多）
OAUTH_SCOPES='account:read zone:read workers_scripts:write workers_routes:write offline_access'

log() { logger -t hometunnel "$*"; }
msg() { echo "$*"; }

die() { echo "ERROR: $*" >&2; exit 1; }

# 读取 UCI（带默认值）
get_() { uci -q get "hometunnel.global.$1" || echo "$2"; }

ctl_base_url() {
	echo "https://$(get_ ctl_hostname ctl).$(get_ domain '')"
}

genkey() {
	mkdir -p "$ETC"
	chmod 700 "$ETC"
	head -c 24 /dev/urandom | base64 | tr -d '\n' > "$KEY_FILE"
	chmod 600 "$KEY_FILE"
	msg "ctl.key generated"
}

# mark <flag> — 向导断点标记（/var/run/hometunnel/<flag>，tmpfs 重启清零=重做向导尾部）
cmd_mark() {
	mkdir -p "$RUNDIR"
	# 写入标记时刻：向导 probeState 判 st.size>0，空文件导致步骤永不推进
	date +%s > "$RUNDIR/$1"
	msg "marked: $1 ($(cat "$RUNDIR/$1"))"
}

# set <key> <value> — 向导轻量写 UCI（仅限 global 段已知键）
cmd_set() {
	local key val cur
	key="${1:-}"
	val="${2:-}"
	case "$key" in
		domain|tunnel_name)
			# 绑定后不可变（ingress hostname/DNS CNAME 派生自它们）。
			# 修改 = 断链；需先 cleanup 解绑。
			# 例外: cert.pem 不存在（重装路由器后恢复了 UCI 备份但授权丢失）→
			# 视为未绑定，允许重新选域名（create 自愈会重建隧道，route 加
			# --overwrite-dns 覆盖旧 CNAME，重装场景全链路可恢复）
			if [ -f "$ETC/.cloudflared/cert.pem" ]; then
				cur=$(get_ "$key" '')
				if [ -n "$cur" ]; then
					die "$key already bound to '$cur' — run 'hometunnel.sh cleanup' to unbind first"
				fi
			fi
			;;
		ctl_hostname)
			# 开关子域名: 部署前可改（向导⑦冲突后换名重试），
			# 部署后不可变（Worker 自定义域绑定派生自它）
			if [ -f "$RUNDIR/worker-deployed" ]; then
				cur=$(get_ ctl_hostname ctl)
				[ "$val" = "$cur" ] && { msg "OK: ctl_hostname unchanged"; return 0; }
				die "ctl_hostname already deployed as '$cur' — run 'hometunnel.sh cleanup' to unbind first"
			fi
			;;
		default_ttl|hard_cap)
			;;
		*)
			die "refusing to set unknown key: $key"
			;;
	esac
	case "$val" in
		*[!a-zA-Z0-9._-]*)
			die "invalid characters in value"
			;;
	esac
	uci set "$UCI_CONF.global.$key=$val"
	uci commit "$UCI_CONF"
	msg "OK: $key saved"
}

# ---- 后台 job 机制（向导异步长任务）----
# job <name> <cmd...>: setsid+nohup 运行, stdout+stderr 实时追加到 /var/run/hometunnel/<name>.out
#   （login 等长任务需要边跑边读输出，故不用 .part 原子改名）
#   命令结束后写 <name>.rc（退出码）；<name>.pid 存在且进程活着 = running
job_start() {
	local name="$1"; shift
	[ -n "$name" ] || die "job: missing name"
	mkdir -p "$RUNDIR"
	# 同名 job 在跑则拒绝
	if [ -f "$RUNDIR/$name.pid" ] && kill -0 "$(cat "$RUNDIR/$name.pid" 2>/dev/null)" 2>/dev/null; then
		die "job '$name' already running"
	fi
	rm -f "$RUNDIR/$name.rc" "$RUNDIR/$name.out"
	: > "$RUNDIR/$name.out"
	chmod 600 "$RUNDIR/$name.out"
	# setsid 脱离 rpcd 会话进程组（登录会话结束 job 不被杀）；无 setsid（busybox 未编）降级 nohup
	# 两分支统一参数序: _ <name> <rundir> <cmd...>；内部先取 name/rundir 再 shift 2 还原 "$@"
	if command -v setsid >/dev/null 2>&1; then
		setsid nohup sh -c '
			name=$1; rundir=$2; shift 2
			"$@" > "$rundir/$name.out" 2>&1
			echo $? > "$rundir/$name.rc"
		' _ "$name" "$RUNDIR" "$@" >/dev/null 2>&1 &
	else
		nohup sh -c '
			name=$1; rundir=$2; shift 2
			"$@" > "$rundir/$name.out" 2>&1
			echo $? > "$rundir/$name.rc"
		' _ "$name" "$RUNDIR" "$@" >/dev/null 2>&1 &
	fi
	echo $! > "$RUNDIR/$name.pid"
	msg "job '$name' started (pid $(cat "$RUNDIR/$name.pid"))"
}

job_status() {
	local name="$1" pid
	if [ -f "$RUNDIR/$name.rc" ]; then
		rm -f "$RUNDIR/$name.pid"
		msg "done:$(cat "$RUNDIR/$name.rc")"
		return 0
	fi
	pid=$(cat "$RUNDIR/$name.pid" 2>/dev/null) || { msg "missing"; return 0; }
	if kill -0 "$pid" 2>/dev/null; then
		msg "running"
	else
		# 进程消失但无 .rc（异常退出/被 kill -9）——写 rc=999 避免向导死等
		echo 999 > "$RUNDIR/$name.rc"
		msg "done:999"
	fi
}

# ---- cloudflared 操作（全部 HOME=/etc/hometunnel，凭据收敛）----
cf_run() {
	HOME=$ETC "$CF" --no-autoupdate "$@"
}

cmd_login() {
	# 由向导以 job 形式调用；stdout 会打印 auth URL 供用户点击
	log "tunnel login starting"
	cf_run tunnel login
}

cmd_create() {
	local name id creds out state
	name=$(get_ tunnel_name hometunnel)
	mkdir -p "$ETC/.cloudflared"
	chmod 700 "$ETC/.cloudflared"

	id=$(get_ tunnel_id '')

	# ---- 自愈分支: CF 侧已删 / 本地凭据丢失 → 清理后重建 ----
	if [ -n "$id" ]; then
		if [ ! -f "$ETC/.cloudflared/$id.json" ]; then
			# 本地凭据丢失（或隧道在 CF 侧被刷新令牌后凭据失效）:
			# CF 侧若还存在，先删掉再重建（凭据无法重新下载，重建是唯一恢复路径）
			state=$(cf_tunnel_state "$id")
			msg "credentials file missing; CF state: $state"
			case "$state" in
				exists|unknown:*)
					# 不能确认 CF 侧状态时不盲删——保守处理: 按同名查找并删除
					out=$(cf_run tunnel list -o json 2>/dev/null | grep -oE "\"name\":\"$name\"[^}]*\"id\":\"[0-9a-f-]{36}\"" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -n1)
					if [ -n "$out" ]; then
						msg "deleting stale tunnel '$name' ($out) before recreate"
						cf_run tunnel delete -f "$out" 2>&1 | grep -v '^$' || true
					fi
					;;
				missing|auth-failed)
					# CF 侧确认已删（或 cert 失效，tunnel create 会失败并提示）
					;;
			esac
			rm -f "$ETC/.cloudflared/$id.json"
			uci -q delete "$UCI_CONF.global.tunnel_id"
			uci commit "$UCI_CONF"
			rm -f "$RUNDIR/dns-routed" "$RUNDIR/worker-verified" "$RUNDIR/worker-deployed"
			msg "cleared stale tunnel state (old id: $id) — recreating"
		elif [ "$(cf_tunnel_state "$id")" = "missing" ]; then
			# 隧道在 CF 侧被删除: 旧凭据已是孤儿，重建
			rm -f "$ETC/.cloudflared/$id.json"
			uci -q delete "$UCI_CONF.global.tunnel_id"
			uci commit "$UCI_CONF"
			rm -f "$RUNDIR/dns-routed" "$RUNDIR/worker-verified" "$RUNDIR/worker-deployed"
			msg "tunnel $id was deleted on Cloudflare — recreating"
		else
			msg "OK: tunnel already exists (id=$id)"
			return 0
		fi
	fi

	out=$(cf_run tunnel create "$name" 2>&1) || die "tunnel create failed: $out"
	# Created tunnel <name> with id <uuid>
	id=$(echo "$out" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -n1)
	[ -n "$id" ] || die "cannot parse tunnel id from: $out"
	creds="$ETC/.cloudflared/$id.json"
	[ -f "$creds" ] || die "credentials file not found: $creds"
	chmod 600 "$creds" 2>/dev/null
	chmod 600 "$ETC/.cloudflared/cert.pem" 2>/dev/null
	uci set "$UCI_CONF.global.tunnel_id=$id"
	uci commit "$UCI_CONF"
	# 重建后旧 config.yml 指向旧凭据，直接重生成；数据面在跑则平滑重启
	[ -f "$ETC/config.yml" ] && cmd_regen
	msg "OK: tunnel '$name' created (id=$id)"
}

cmd_route() {
	local name id domain i=0 subdomain hostname out rc=0 cmd_rc
	name=$(get_ tunnel_name hometunnel)
	id=$(get_ tunnel_id '')
	domain=$(get_ domain '')
	[ -n "$id" ] || die "tunnel_id empty (run create first)"
	[ -n "$domain" ] || die "domain empty"

	while uci -q show hometunnel | grep -q "^hometunnel.@ingress\[$i\]="; do
		enabled=$(uci -q get "hometunnel.@ingress[$i].enabled" || echo 1)
		if [ "$enabled" = "1" ] || [ "$enabled" = "true" ]; then
			subdomain=$(uci -q get "hometunnel.@ingress[$i].subdomain" || echo '')
			if [ -n "$subdomain" ]; then
				hostname="$subdomain.$domain"
				out=$(cf_run tunnel route dns --overwrite-dns "$name" "$hostname" 2>&1)
				cmd_rc=$?
				case "$out" in
					*"Already routed"*|*"already exists"*)
						msg "OK: $hostname (already routed)"
						;;
					*)
						if [ "$cmd_rc" -eq 0 ]; then
							msg "OK: $hostname routed"
						else
							msg "FAIL: $hostname: $out"
							rc=1
						fi
						;;
				esac
			fi
		fi
		i=$((i + 1))
	done
	return "$rc"
}

cmd_regen() {
	"$SHARE/gen-yml.sh" || die "gen-yml failed"
	# 数据面在运行则平滑重启
	if /etc/init.d/hometunnel running 2>/dev/null; then
		/etc/init.d/hometunnel restart
		msg "OK: config regenerated, tunnel service restarted"
	else
		msg "OK: config regenerated (tunnel service not running)"
	fi
}

cmd_bundle() {
	local domain ctl_host key out tmp f
	domain=$(get_ domain '')
	ctl_host=$(get_ ctl_hostname ctl)
	key=$(cat "$KEY_FILE" 2>/dev/null)
	[ -n "$domain" ] || die "domain empty"
	[ -n "$key" ] || die "ctl.key missing (run genkey)"

	out="/tmp/hometunnel-worker-$domain.tar.gz"
	tmp=$(mktemp -d /tmp/hometunnel-bundle.XXXXXX) || die "mktemp failed"
	mkdir -p "$tmp/hometunnel-worker/src"

	for f in worker.js wrangler.toml deploy.sh README.txt; do
		sed -e "s|@@DOMAIN@@|$domain|g" \
		    -e "s|@@CTL_HOSTNAME@@|$ctl_host|g" \
		    -e "s|@@CTL_KEY@@|$key|g" \
		    -e "s|@@DEFAULT_TTL@@|$(get_ default_ttl 45)|g" \
		    -e "s|@@MAX_TTL@@|$(get_ max_ttl 240)|g" \
		    -e "s|@@RENEW_TTL@@|$(get_ renew_ttl 45)|g" \
		    "$SHARE/worker/$f.tpl" > "$tmp/hometunnel-worker/$f"
	done
	# worker.js 放 src/（wrangler.toml main = src/worker.js）
	mv "$tmp/hometunnel-worker/worker.js" "$tmp/hometunnel-worker/src/worker.js"
	chmod +x "$tmp/hometunnel-worker/deploy.sh"
	# 控制密钥副本（与路由器 /etc/hometunnel/ctl.key 同值）
	printf '%s\n' "$key" > "$tmp/hometunnel-worker/ctl.key.txt"
	chmod 600 "$tmp/hometunnel-worker/ctl.key.txt"

	tar -C "$tmp" -czf "$out" hometunnel-worker
	rm -rf "$tmp"
	chmod 600 "$out"
	msg "$out"
}

cmd_verify() {
	local base key resp
	base=$(ctl_base_url)
	key=$(cat "$KEY_FILE" 2>/dev/null)
	[ -n "$key" ] || die "ctl.key missing"

	resp=$(curl -fsS --max-time 10 "$base/healthz" 2>&1) || die "healthz failed: $resp"
	echo "$resp" | grep -q '"ok": *true' || die "healthz unexpected: $resp"
	msg "healthz: OK"

	resp=$(curl -fsS --max-time 10 -H "x-ctl-key: $key" "$base/cmd" 2>&1) || die "/cmd failed: $resp"
	echo "$resp" | grep -q '"on"' || die "/cmd unexpected: $resp"
	msg "/cmd: OK ($resp)"
}

# ctl on|off — 路由器侧直接开关（LuCI 按钮用；key 走 header 不落 URL/进程参数）
cmd_ctl() {
	local action="${1:-}" base key min resp
	base=$(ctl_base_url)
	key=$(cat "$KEY_FILE" 2>/dev/null)
	[ -n "$key" ] || die "ctl.key missing"
	case "$action" in
		on)
			min=$(get_ default_ttl 45)
			resp=$(curl -fsS --max-time 10 -H "x-ctl-key: $key" "${base}/on?min=${min}" 2>&1) \
				|| die "/on failed: $resp"
			msg "$resp"
			;;
		off)
			resp=$(curl -fsS --max-time 10 -H "x-ctl-key: $key" "${base}/off" 2>&1) \
				|| die "/off failed: $resp"
			msg "$resp"
			;;
		*)
			die "usage: hometunnel.sh ctl on|off"
			;;
	esac
}

cmd_status() {
	local mode tunnel_id domain base
	mode=$(get_ mode ondemand)
	tunnel_id=$(get_ tunnel_id '')
	domain=$(get_ domain '')
	base=$(ctl_base_url)
	echo "--- hometunnel status ---"
	echo "mode:        $mode"
	echo "tunnel_id:   ${tunnel_id:-<empty>}"
	echo "domain:      ${domain:-<empty>}"
	echo "ctl url:     $base"
	if /etc/init.d/hometunnel running >/dev/null 2>&1; then echo "tunnel svc:  running"; else echo "tunnel svc:  stopped"; fi
	if /etc/init.d/hometunnel-ctl running >/dev/null 2>&1; then echo "ctl svc:     running"; else echo "ctl svc:     stopped"; fi
	if [ -f "$KEY_FILE" ]; then echo "ctl key:     present"; else echo "ctl key:     MISSING"; fi
	if [ -n "$tunnel_id" ] && [ -n "$domain" ] && [ -f "$KEY_FILE" ]; then
		resp=$(curl -fsS --max-time 8 -H "x-ctl-key: $(cat "$KEY_FILE")" "$base/cmd" 2>/dev/null) \
			&& echo "control:     $resp" || echo "control:     unreachable"
	fi
	# CF 侧 tunnel 存在性（cert.pem token）
	if [ -n "$tunnel_id" ]; then
		echo "cf-tunnel:   $(cf_tunnel_state "$tunnel_id")"
	fi
	if [ -f "$OAUTH_JSON" ]; then
		echo "oauth:       token present"
	fi
}

# 从 cert.pem 的 ARGO TUNNEL TOKEN 解出 JSON 字段（apiToken/accountID/zoneID）
cert_json_field() {
	awk '/BEGIN ARGO TUNNEL TOKEN/{f=1;next} /END ARGO TUNNEL TOKEN/{f=0} f' \
		"$ETC/.cloudflared/cert.pem" 2>/dev/null | tr -d '\n' | base64 -d 2>/dev/null \
		| grep -oE "\"$1\":\"[^\"]+\"" | cut -d'"' -f4
}

cert_api_token() { cert_json_field apiToken; }

# OAuth 凭据里保存的 access_token（600 权限 /etc/hometunnel/oauth.json）
oauth_access_token() {
	grep -oE '"access_token":"[^"]+"' "$OAUTH_JSON" 2>/dev/null | cut -d'"' -f4
}

oauth_refresh_token() {
	grep -oE '"refresh_token":"[^"]+"' "$OAUTH_JSON" 2>/dev/null | cut -d'"' -f4
}

# 有效（未过期、必要时能刷新）的 access token；失败 die。
# oauth.json 结构: {"access_token":"...","expires_at":<epoch>,"refresh_token":"...","account_id":"..."}
oauth_valid_token() {
	local tok exp now resp
	rm -f "$RUNDIR/oauth-error"
	[ -f "$OAUTH_JSON" ] || { echo "no-file" > "$RUNDIR/oauth-error"; die "not authorized (run oauth-start)"; }
	tok=$(oauth_access_token)
	exp=$(grep -oE '"expires_at":[0-9]+' "$OAUTH_JSON" 2>/dev/null | grep -oE '[0-9]+')
	now=$(date +%s)
	if [ -n "$tok" ] && [ -n "$exp" ] && [ "$exp" -gt $((now + 60)) ]; then
		echo "$tok"
		return 0
	fi
	# 过期 → 用 refresh_token 刷新（wrangler 同款 grant_type=refresh_token）
	oauth_refresh
}

# 用 refresh token 换新 access token（旋转后覆盖保存）
oauth_refresh() {
	local rt resp tok exp new_rt
	rt=$(oauth_refresh_token)
	[ -n "$rt" ] || { echo "no-refresh-token" > "$RUNDIR/oauth-error"; die "oauth: no refresh token saved — re-authorize (oauth-start)"; }
	resp=$(curl -sS --max-time 15 -X POST "$OAUTH_TOKEN_URL" \
		-H 'User-Agent: wrangler/4.40.0' \
		--data-urlencode "grant_type=refresh_token" \
		--data-urlencode "refresh_token=$rt" \
		--data-urlencode "client_id=$OAUTH_CLIENT_ID" 2>&1)
	echo "$resp" > "$RUNDIR/oauth-error"
	case "$resp" in
		*invalid_grant*|*revoked*) die "oauth refresh: token revoked/expired — re-authorize (oauth-start)" ;;
	esac
	[ -n "$(echo "$resp" | grep -oE '"access_token":"[^"]+"')" ] || die "oauth refresh failed: $resp"
	tok=$(echo "$resp" | grep -oE '"access_token":"[^"]+"' | cut -d'"' -f4)
	exp=$(echo "$resp" | grep -oE '"expires_in":[0-9]+' | grep -oE '[0-9]+')
	new_rt=$(echo "$resp" | grep -oE '"refresh_token":"[^"]+"' | cut -d'"' -f4)
	[ -n "$tok" ] && [ -n "$exp" ] || die "oauth refresh: cannot parse response"
	# 保留原 account_id（刷新响应不带）
	local acct
	acct=$(grep -oE '"account_id":"[^"]+"' "$OAUTH_JSON" 2>/dev/null | cut -d'"' -f4)
	{
		printf '{"access_token":"%s","expires_at":%s,"refresh_token":"%s","account_id":"%s"}\n' \
			"$tok" "$(( $(date +%s) + exp ))" "${new_rt:-$rt}" "${acct:-}"
	} > "$OAUTH_JSON"
	chmod 600 "$OAUTH_JSON"
	rm -f "$RUNDIR/oauth-error"
	msg "oauth: token refreshed"
	echo "$tok"
}

# 查询 tunnel 在 CF 侧的存在性（cert.pem apiToken 调 API v4）。
# 输出: exists | missing | auth-failed | unknown:<reason>
cf_tunnel_state() {
	local token acct id http
	id="${1:-$(get_ tunnel_id '')}"
	[ -n "$id" ] || { echo "unknown:no-tunnel-id"; return; }
	[ -f "$ETC/.cloudflared/cert.pem" ] || { echo "unknown:no-cert"; return; }
	token=$(cert_api_token)
	acct=$(cert_json_field accountID)
	[ -n "$token" ] && [ -n "$acct" ] || { echo "unknown:bad-cert"; return; }
	http=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
		-H "Authorization: Bearer $token" \
		"https://api.cloudflare.com/client/v4/accounts/$acct/cfd_tunnel/$id" 2>/dev/null)
	case "$http" in
		200)   echo "exists" ;;
		404)   echo "missing" ;;
		401|403) echo "auth-failed" ;;
		*)     echo "unknown:http-$http" ;;
	esac
}

# check — 校验本地 tunnel_id 与 CF 侧一致性（人读 + 向导可解析）
cmd_check() {
	local state
	state=$(cf_tunnel_state)
	msg "cf-tunnel: $state"
	case "$state" in
		exists)
			return 0 ;;
		missing)
			msg "tunnel was deleted on Cloudflare — run 'create' to recreate it"
			return 1 ;;
		auth-failed)
			msg "cert.pem token rejected — re-run wizard step 1 (cloudflared tunnel login)"
			return 1 ;;
		*)
			msg "cannot verify: $state"
			return 2 ;;
	esac
}

# 列出账户全部 zone（域名）。输出: <name> <status> 每行一个；失败 die。
cmd_zones() {
	local token resp
	[ -f "$ETC/.cloudflared/cert.pem" ] || die "cert.pem not found (run login first)"
	token=$(cert_api_token)
	[ -n "$token" ] || die "cannot parse apiToken from cert.pem"
	resp=$(curl -fsS --max-time 15 -H "Authorization: Bearer $token" \
		"https://api.cloudflare.com/client/v4/zones?per_page=50" 2>&1) \
		|| die "cloudflare api unreachable: $resp"
	# jsonfilter 为 OpenWrt 原生 JSON 工具；-e 提取数组元素
	names=$(jsonfilter -s "$resp" -e '@.result[*].name' 2>/dev/null)
	stats=$(jsonfilter -s "$resp" -e '@.result[*].status' 2>/dev/null)
	[ -n "$names" ] || die "no zones in account (or parse error)"
	# BusyBox 无 paste；awk 双文件按行号配对 name/status
	tmp=$(mktemp /tmp/ht-zones.XXXXXX)
	printf '%s\n' "$names" > "$tmp.n"
	printf '%s\n' "$stats" > "$tmp.s"
	awk 'NR==FNR { n[NR]=$0; next } { print n[FNR], $0 }' "$tmp.n" "$tmp.s" 2>/dev/null \
		|| printf '%s\n' "$names"
	rm -f "$tmp.n" "$tmp.s"
}

cmd_unbind() {
	local name id domain ctl_host ans tok acct zone_id i subdomain
	name=$(get_ tunnel_name hometunnel)
	id=$(get_ tunnel_id '')
	domain=$(get_ domain '')
	ctl_host=$(get_ ctl_hostname ctl)

	# 确认: CLI 交互式（Type DELETE）; LuCI job 路径传 yes（UI 已有二次确认框）
	if [ "${1:-}" != "yes" ]; then
		echo "About to delete tunnel '$name' and ALL published records from Cloudflare:"
		[ -n "$id" ] && echo "  - tunnel $name ($id)"
		[ -n "$domain" ] && echo "  - DNS CNAME records for enabled ingress rules"
		[ -n "$domain" ] && echo "  - switch service Worker (ctl: $ctl_host.$domain)"
		echo "Ingress rules and Settings are kept locally."
		printf 'Type DELETE to confirm: '
		read -r ans
		[ "$ans" = "DELETE" ] || { msg "aborted"; exit 1; }
	fi

	# 1) 停服务
	/etc/init.d/hometunnel stop 2>/dev/null
	/etc/init.d/hometunnel-ctl stop 2>/dev/null

	# 2) 删 DNS CNAME（cert.pem token 逐规则删除；失败不阻断——幂等重试安全）
	if [ -n "$id" ] && [ -n "$domain" ]; then
		i=0
		while uci -q show hometunnel | grep -q "^hometunnel.@ingress\[$i\]="; do
			subdomain=$(uci -q get "hometunnel.@ingress[$i].subdomain" || echo '')
			[ -n "$subdomain" ] && delete_dns_record "$subdomain.$domain" || true
			i=$((i + 1))
		done
	fi

	# 3) 删 Worker（OAuth token；域绑定随之消失；未授权或已删则跳过）
	tok=$(oauth_valid_token 2>/dev/null)
	if [ -n "$tok" ] && [ -n "$domain" ]; then
		delete_worker "$tok" || msg "WARN: worker delete skipped (not authorized or already gone)"
	fi

	# 4) 删隧道（凭据恢复路径）
	if [ -n "$id" ]; then
		cf_run tunnel delete "$id" 2>&1 || msg "WARN: tunnel delete failed (delete in CF dashboard)"
	fi

	# 5) 清本地
	rm -f "$ETC/config.yml" "$KEY_FILE"
	rm -f "$ETC/.cloudflared/"*.json
	rm -f "$RUNDIR/dns-routed" "$RUNDIR/worker-verified" "$RUNDIR/worker-deployed"
	uci -q delete "$UCI_CONF.global.tunnel_id"
	uci -q delete "$UCI_CONF.global.domain"
	uci commit "$UCI_CONF"
	msg "unbound: tunnel, DNS records, switch service deleted; wizard marks reset."
	msg "ingress rules kept (subdomains only, hostnames re-computed on rebind); cert.pem kept (Cloudflare authorization survives)."
}

# 删除单条 DNS CNAME（cert.pem token + API v4 按名称查删）
delete_dns_record() {
	local hostname="$1" ztok zone_id rec_id resp
	ztok=$(cert_api_token) || return 1
	[ -n "$ztok" ] || return 1
	zone_id=$(cert_json_field zoneID) || return 1
	resp=$(curl -fsS --max-time 15 -H "Authorization: Bearer $ztok" \
		"https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=CNAME&name=$hostname&per_page=5" 2>/dev/null) || {
		msg "WARN: DNS lookup failed for $hostname"; return 1; }
	rec_id=$(echo "$resp" | jsonfilter -e '@.result[0].id' 2>/dev/null)
	[ -n "$rec_id" ] || { msg "OK: no DNS record for $hostname (already clean)"; return 0; }
	curl -fsS --max-time 15 -X DELETE -H "Authorization: Bearer $ztok" \
		"https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$rec_id" >/dev/null 2>&1 \
		&& msg "OK: DNS record $hostname deleted" \
		|| msg "WARN: DNS delete failed for $hostname"
}

# 删除 Worker（OAuth token + 域绑定级联；WSR 帐号级脚本删除）
delete_worker() {
	local tok="$1" acct
	acct=$(grep -oE '"account_id":"[^"]+"' "$OAUTH_JSON" 2>/dev/null | cut -d'"' -f4)
	[ -n "$acct" ] || { acct=$(oauth_query_account_id "$tok") || return 1; }
	curl -fsS --max-time 20 -X DELETE \
		-H "Authorization: Bearer $tok" \
		"https://api.cloudflare.com/client/v4/accounts/$acct/workers/scripts/$WORKER_NAME" \
		>/dev/null 2>&1 || return 1
	msg "OK: switch service Worker deleted"
	return 0
}

cmd_apply_mode() {
	local mode
	mode=$(get_ mode ondemand)
	case "$mode" in
		ondemand)
			# 数据面不 enable（只被守护拉起），控制面守护启用
			/etc/init.d/hometunnel-ctl enable
			/etc/init.d/hometunnel-ctl restart 2>/dev/null || true
			# 刻意不 stop 数据面——由守护按控制面状态决定（避免误杀使用中会话）
			msg "OK: ondemand mode applied (ctl daemon enabled)"
			;;
		alwayson)
			/etc/init.d/hometunnel-ctl stop 2>/dev/null || true
			/etc/init.d/hometunnel-ctl disable
			/etc/init.d/hometunnel enable
			/etc/init.d/hometunnel restart
			msg "OK: alwayson mode applied"
			;;
		*) die "unknown mode: $mode" ;;
	esac
}

# ===================== OAuth 设备流（RFC 8628）=====================
# 复刻 wrangler login 的设备授权流（wrangler 同款 client_id/端点/scope 集），
# 让用户在手机上扫一次码完成授权；之后 Worker 部署全部由路由器 curl 完成。
# 凭据存 /etc/hometunnel/oauth.json（600）。

# oauth-start: 发起设备授权。输出 JSON（向导读取）:
#   {"user_code":"XXXX","verification_url":"https://...?user_code=XXXX","expires_in":300,"interval":5}
# 同时生成二维码 SVG → /var/run/hometunnel/oauth-qr.svg（向导内联显示；无 qrencode 则跳过）
cmd_oauth_start() {
	local resp dc uc vu interval tok exp
	mkdir -p "$ETC"
	chmod 700 "$ETC"
	# 已有有效凭据 → 直接告诉向导（幂等; 真验有效性，refresh 被吊销则清掉）
	if tok=$(oauth_valid_token 2>/dev/null) && [ -n "$tok" ]; then
		msg '{"already_authorized":true}'
		return 0
	fi
	case "$(oauth_last_error)" in
		*invalid_grant*|*revoked*)
			rm -f "$OAUTH_JSON"
			;;
	esac
	resp=$(curl -fsS --max-time 20 -X POST "$OAUTH_DEVICE_URL" \
		-H 'User-Agent: wrangler/4.40.0' \
		--data-urlencode "client_id=$OAUTH_CLIENT_ID" \
		--data-urlencode "scope=$OAUTH_SCOPES" 2>&1) || die "device auth request failed: $resp"
	dc=$(echo "$resp" | grep -oE '"device_code":"[^"]+"' | cut -d'"' -f4)
	uc=$(echo "$resp" | grep -oE '"user_code":"[^"]+"' | cut -d'"' -f4)
	vu=$(echo "$resp" | grep -oE '"verification_uri_complete":"[^"]+"' | cut -d'"' -f4)
	[ -n "$dc" ] && [ -n "$uc" ] || die "device auth: cannot parse response: $resp"
	[ -n "$vu" ] || vu=$(echo "$resp" | grep -oE '"verification_uri":"[^"]+"' | cut -d'"' -f4)
	# device_code + 轮询参数存 RUNDIR（tmpfs，重启即失效=重新授权，安全默认）
	mkdir -p "$RUNDIR"
	{
		printf 'device_code=%s\n' "$dc"
		printf 'user_code=%s\n' "$uc"
		printf 'interval=%s\n' "$(echo "$resp" | grep -oE '"interval":[0-9]+' | grep -oE '[0-9]+' || echo 5)"
		printf 'deadline=%s\n' "$(( $(date +%s) + 290 ))"
	} > "$RUNDIR/oauth-device"
	chmod 600 "$RUNDIR/oauth-device"
	# 二维码 SVG（手机扫码授权；qrencode 未安装则向导只显示链接）
	if command -v qrencode >/dev/null 2>&1; then
		qrencode -t SVG -o "$RUNDIR/oauth-qr.svg" "$vu" 2>/dev/null || true
	else
		rm -f "$RUNDIR/oauth-qr.svg"
	fi
	# 向导读的 JSON（verification_uri_complete 优先——用户不用手输 code）
	printf '{"user_code":"%s","verification_url":"%s","expires_in":300}\n' "$uc" "$vu"
}

# oauth-status: 查询轮询状态。输出 JSON:
#   {"state":"pending"}                      用户还没在浏览器点 Allow
#   {"state":"authorized"}                   拿到 token（oauth.json 已写）
#   {"state":"expired"}                      设备码过期（5 分钟）
#   {"state":"failed","error":"..."}         出错
cmd_oauth_status() {
	local dc interval now resp tok rt exp acct
	# 已授权 → 幂等返回（真验有效性: 过期自动 refresh; refresh 被吊销 → 清死凭据走设备流）
	if tok=$(oauth_valid_token 2>/dev/null) && [ -n "$tok" ]; then
		msg '{"state":"authorized"}'
		return 0
	fi
	case "$(oauth_last_error)" in
		*invalid_grant*|*revoked*)
			rm -f "$OAUTH_JSON"
			msg '{"state":"failed","error":"stored credentials revoked — cleared, restart authorization"}'
			return 0
			;;
	esac
	[ -f "$RUNDIR/oauth-device" ] || { msg '{"state":"failed","error":"no device flow in progress"}'; return 0; }
	. "$RUNDIR/oauth-device"
	now=$(date +%s)
	if [ "${deadline:-0}" -le "$now" ]; then
		rm -f "$RUNDIR/oauth-device"
		msg '{"state":"expired"}'
		return 0
	fi
	resp=$(curl -sS --max-time 15 -X POST "$OAUTH_TOKEN_URL" \
		-H 'User-Agent: wrangler/4.40.0' \
		--data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:device_code' \
		--data-urlencode "device_code=$device_code" \
		--data-urlencode "client_id=$OAUTH_CLIENT_ID" 2>&1)
	tok=$(echo "$resp" | grep -oE '"access_token":"[^"]+"' | cut -d'"' -f4)
	if [ -n "$tok" ]; then
		exp=$(echo "$resp" | grep -oE '"expires_in":[0-9]+' | grep -oE '[0-9]+')
		rt=$(echo "$resp" | grep -oE '"refresh_token":"[^"]+"' | cut -d'"' -f4)
		# account_id 从 /memberships 取（首次授权时；刷新时保留）
		acct=$(oauth_query_account_id "$tok")
		{
			printf '{"access_token":"%s","expires_at":%s,"refresh_token":"%s","account_id":"%s"}\n' \
				"$tok" "$(( now + ${exp:-3600} ))" "${rt:-}" "${acct:-}"
		} > "$OAUTH_JSON"
		chmod 600 "$OAUTH_JSON"
		rm -f "$RUNDIR/oauth-device"
		msg '{"state":"authorized"}'
		return 0
	fi
	# RFC 8628 错误分类
	case "$resp" in
		*'"authorization_pending"'*|*'"authorization_pending"'*)
			msg '{"state":"pending"}'
			;;
		*'"slow_down"'*)
			msg '{"state":"pending"}'
			;;
		*'"expired_token"'*|*'"expired_token"'*)
			msg '{"state":"expired"}'
			;;
		*)
			msg '{"state":"failed","error":"'"$(echo "$resp" | head -c 300 | tr -d '\n"')"'"}'
			;;
	esac
}

# refresh 失败原因（oauth-status/oauth-start 快速通道用; RUNDIR tmpfs 自动清）
oauth_last_error() {
	cat "$RUNDIR/oauth-error" 2>/dev/null || echo ''
}

# 用 access token 查账户（wrangler 用 memberships，但 account:read scope 下
# /memberships 403 —— /accounts 实测可用且返回同款 account id）
oauth_query_account_id() {
	local tok="$1" resp
	resp=$(curl -fsS --max-time 15 -H "Authorization: Bearer $tok" \
		"https://api.cloudflare.com/client/v4/accounts" 2>/dev/null) || return 1
	jsonfilter -s "$resp" -e '@.result[0].id' 2>/dev/null
}

# 开关域名占用检测（部署前预检）。
# 返回 0 = 干净可绑; 1 = 被占。stdout 给出占用详情（向导/日志用）:
#   clean                 无任何占用
#   worker:<script>       已挂在本账号其他 Worker（100116 场景）
#   dns:<type>            已有普通 DNS 记录（100117 场景）
#   foreign               已挂在别的 Cloudflare 账号（PUT 会报不可覆盖）
ctl_domain_check() {
	local tok="$1" acct="$2" hostn="$3" zone_id="$4" resp i h s found rectype
	# a) custom domain 绑定表（账号级，一次查全）
	resp=$(curl -fsS --max-time 15 -H "Authorization: Bearer $tok" \
		"https://api.cloudflare.com/client/v4/accounts/$acct/workers/domains?per_page=100" 2>/dev/null) || return 0
	# jsonfilter 逐行输出 hostname 与 service（同序）——配对找 hostn
	i=0; found=''
	while IFS= read -r h; do
		i=$((i+1))
		[ "$h" = "$hostn" ] || continue
		s=$(jsonfilter -s "$resp" -e "@.result[$((i-1))].service" 2>/dev/null)
		found="worker:${s:-unknown}"
	done <<EOF
$(jsonfilter -s "$resp" -e '@.result[*].hostname' 2>/dev/null)
EOF
	if [ -n "$found" ]; then echo "$found"; return 1; fi
	# b) 普通 DNS 记录（cert.pem DNS token 可读）
	local ztok
	ztok=$(cert_api_token)
	if [ -n "$ztok" ] && [ -n "$zone_id" ]; then
		resp=$(curl -fsS --max-time 15 -H "Authorization: Bearer $ztok" \
			"https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=$hostn&per_page=5" 2>/dev/null) || return 0
		rectype=$(jsonfilter -s "$resp" -e '@.result[0].type' 2>/dev/null)
		[ -n "$rectype" ] && { echo "dns:$rectype"; return 1; }
	fi
	echo "clean"
	return 0
}

# 解绑其他 Worker 的 custom domain（接管语义: 从 domains 列表找 id 后 DELETE）
detach_worker_domain() {
	local tok="$1" acct="$2" hostn="$3" svc="$4" resp dom_id
	resp=$(curl -fsS --max-time 15 -H "Authorization: Bearer $tok" \
		"https://api.cloudflare.com/client/v4/accounts/$acct/workers/domains?per_page=100" 2>/dev/null) || return 1
	# 找 hostname 匹配且 service=$svc 的绑定 id
	local i=0 h s dom_id=''
	while IFS= read -r h; do
		i=$((i+1))
		[ "$h" = "$hostn" ] || continue
		s=$(jsonfilter -s "$resp" -e "@.result[$((i-1))].service" 2>/dev/null)
		[ "$s" = "$svc" ] || continue
		dom_id=$(jsonfilter -s "$resp" -e "@.result[$((i-1))].id" 2>/dev/null)
	done <<EOF
$(jsonfilter -s "$resp" -e '@.result[*].hostname' 2>/dev/null)
EOF
	[ -n "$dom_id" ] || { echo "ERROR: no custom domain binding found for $hostn on $svc" >&2; return 1; }
	curl -fsS --max-time 15 -X DELETE -H "Authorization: Bearer $tok" \
		"https://api.cloudflare.com/client/v4/accounts/$acct/workers/domains/$dom_id" >/dev/null 2>&1 \
		|| { echo "ERROR: DELETE workers/domains/$dom_id failed" >&2; return 1; }
	msg "OK: detached $hostn from '$svc'"
	return 0
}

cmd_oauth_clear() {
	rm -f "$OAUTH_JSON" "$RUNDIR/oauth-device"
	msg "OK: oauth credentials cleared"
}

# ===================== 自动部署（curl 直传 Worker）=====================
# deploy: 用 oauth token 上传控制面 Worker + 绑自定义域。
# 全程路由器内 curl（Workers Script Upload API multipart + workers/domains PUT），
# wrangler 完全不参与。幂等：重复执行 = 更新 Worker 版本。

# deploy-check: 向导⑦预检。返回 JSON:
#   {"state":"clean"}                              可直接部署
#   {"state":"conflict","kind":"worker","by":"llm-tunnel-ctl"}   域名挂在其他 Worker（需用户确认接管）
#   {"state":"conflict","kind":"dns","by":"CNAME"}               主机名已有普通 DNS 记录（需手工处理）
#   {"state":"error","error":"..."}
# probe — 锁定态配置总览 + 在线健康（向导锁定态/状态聚合用）。
# JSON 输出: bound, domain, ctl_hostname, ctl_url, mode, oauth, worker, dns, cert
cmd_probe() {
	local domain ctl_host base tok acct zone_id occ tunnel
	domain=$(get_ domain '')
	ctl_host=$(get_ ctl_hostname ctl)
	base=$(ctl_base_url)

	# oauth 授权态（文件在 + token 真有效; refresh 被吊销 → 清死文件统一报 missing）
	local oauth=unknown
	if [ -f "$OAUTH_JSON" ]; then
		tok=$(oauth_valid_token 2>/dev/null)
		if [ -n "$tok" ]; then
			oauth=ok
		else
			case "$(oauth_last_error)" in
				*invalid_grant*|*revoked*)
					rm -f "$OAUTH_JSON"
					oauth=missing
					;;
				*) oauth=expired ;;
			esac
		fi
	else
		oauth=missing
	fi

	# 未绑定则到此为止
	if [ -z "$(get_ tunnel_id '')" ] || [ -z "$domain" ]; then
		printf '{"bound":false,"oauth":"%s"}\n' "$oauth"
		return 0
	fi

	# worker 域名绑定 + 占用检查
	local worker=unknown dns=unknown
	if [ "$oauth" = "ok" ]; then
		acct=$(grep -oE '"account_id":"[^"]+"' "$OAUTH_JSON" 2>/dev/null | cut -d'"' -f4)
		[ -n "$acct" ] || acct=$(oauth_query_account_id "$tok") || acct=''
		zone_id=$(cf_zone_id "$tok" "$domain") || zone_id=''
		if [ -n "$acct" ]; then
			occ=$(ctl_domain_check "$tok" "$acct" "$ctl_host.$domain" "$zone_id")
			case "$occ" in
				clean) worker=missing ;;
				worker:$WORKER_NAME) worker=ok ;;
				worker:*) worker=foreign ;;
				dns:*) worker=blocked ;;
				*) worker=unknown ;;
			esac
		fi
	else
		worker=unknown
	fi

	# DNS CNAME（cert.pem token: 逐规则检查 enabled 规则的 CNAME 存在性）
	if [ -n "$(get_ tunnel_id '')" ]; then
		dns=$(check_dns_all)
	fi

	# 隧道存活（cert.pem token; 被删 = 配置失效, 需解绑重设）
	local tunnel
	tunnel=$(cf_tunnel_state)
	case "$tunnel" in
		exists) tunnel=ok ;;
		missing) tunnel=deleted ;;
		auth-failed) tunnel=auth-failed ;;
		*) tunnel=unknown ;;
	esac

	printf '{"bound":true,"domain":"%s","ctl_hostname":"%s","ctl_url":"%s","mode":"%s","oauth":"%s","worker":"%s","dns":"%s","tunnel":"%s"}\n' \
		"$domain" "$ctl_host" "$base" "$(get_ mode ondemand)" "$oauth" "$worker" "$dns" "$tunnel"
}

# route-and-regen — uci reload trigger 服务端联动入口:
# 增量发布 DNS CNAME + 重建 config.yml + 平滑重启数据面。
# bound=false 时 route 跳过（无远端可发布）、regen 无害（config.yml 仅含控制面占位）。
cmd_route_and_regen() {
	local rc=0
	if [ -n "$(get_ tunnel_id '')" ] && [ -n "$(get_ domain '')" ]; then
		cmd_route || rc=1
	fi
	cmd_regen || rc=1
	# TTL 漂移检测（改 max/renew 后自动重部署 Worker；详见 cmd_ttl_sync 注释）
	ttl_sync_check || true
	return "$rc"
}

# 检查全部 enabled 规则的 CNAME（返回 ok|missing:<n>|unknown）
check_dns_all() {
	local ztok zone_id i=0 subdomain hostname resp missing=0 checked=0
	ztok=$(cert_api_token) || { echo unknown; return; }
	[ -n "$ztok" ] || { echo unknown; return; }
	zone_id=$(cert_json_field zoneID) || { echo unknown; return; }
	while uci -q show hometunnel | grep -q "^hometunnel.@ingress\[$i\]="; do
		local enabled subdomain
		enabled=$(uci -q get "hometunnel.@ingress[$i].enabled" || echo 1)
		if [ "$enabled" = "1" ] || [ "$enabled" = "true" ]; then
			subdomain=$(uci -q get "hometunnel.@ingress[$i].subdomain" || echo '')
			if [ -n "$subdomain" ]; then
				hostname="$subdomain.$(get_ domain '')"
				resp=$(curl -fsS --max-time 10 -H "Authorization: Bearer $ztok" \
					"https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=CNAME&name=$hostname&per_page=1" 2>/dev/null)
				checked=$((checked + 1))
				echo "$resp" | jsonfilter -e '@.result[0].id' 2>/dev/null | grep -q . || missing=$((missing + 1))
			fi
		fi
		i=$((i + 1))
	done
	[ "$checked" -eq 0 ] && { echo "none"; return; }
	[ "$missing" -eq 0 ] && echo ok || echo "missing:$missing"
}

cmd_deploy_check() {
	local tok acct domain ctl_host zone_id occ
	domain=$(get_ domain '')
	ctl_host=$(get_ ctl_hostname ctl)
	[ -n "$domain" ] || { msg '{"state":"error","error":"domain empty (wizard step 3)"}'; return 0; }
	tok=$(oauth_valid_token)
	[ -n "$tok" ] || { msg '{"state":"error","error":"not authorized (wizard step 4)"}'; return 0; }
	acct=$(grep -oE '"account_id":"[^"]+"' "$OAUTH_JSON" | cut -d'"' -f4)
	[ -n "$acct" ] || { acct=$(oauth_query_account_id "$tok") || acct=''; }
	[ -n "$acct" ] || { msg '{"state":"error","error":"cannot resolve account_id"}'; return 0; }
	zone_id=$(cf_zone_id "$tok" "$domain") || zone_id=''
	occ=$(ctl_domain_check "$tok" "$acct" "$ctl_host.$domain" "$zone_id")
	case "$occ" in
		clean) msg '{"state":"clean"}' ;;
		worker:hometunnel-ctl) msg '{"state":"clean"}' ;;
		worker:*) msg '{"state":"conflict","kind":"worker","by":"'${occ#worker:}'"}' ;;
		dns:*) msg '{"state":"conflict","kind":"dns","by":"'${occ#dns:}'"}' ;;
		*) msg '{"state":"clean"}' ;;
	esac
	return 0
}

cmd_deploy() {
	local confirmed="${1:-}"
	local tok acct domain ctl_host key zone_id resp
	domain=$(get_ domain '')
	ctl_host=$(get_ ctl_hostname ctl)
	# ctl.key 缺失则自动生成（首次部署前用户可能从未跑过 bundle/genkey）
	if [ ! -s "$KEY_FILE" ]; then
		msg "ctl.key missing — generating"
		genkey
	fi
	key=$(cat "$KEY_FILE" 2>/dev/null)
	[ -n "$key" ] || die "ctl.key unreadable"
	[ -n "$domain" ] || die "domain empty (run wizard step 3)"

	tok=$(oauth_valid_token)
	[ -n "$tok" ] || die "cannot obtain oauth token (authorize first)"
	acct=$(grep -oE '"account_id":"[^"]+"' "$OAUTH_JSON" | cut -d'"' -f4)
	[ -n "$acct" ] || { acct=$(oauth_query_account_id "$tok") || die "cannot resolve account_id"; }

	msg "deploy: account=$acct worker=$WORKER_NAME domain=$ctl_host.$domain"

	# 1) zone_id（cert.pem 里有 zoneID 但那是 login 时选的 zone；域名可能不同 → 用 API 查全称精确匹配）
	zone_id=$(cf_zone_id "$tok" "$domain") || die "zone lookup failed for $domain"
	msg "deploy: zone=$zone_id"

	# 1.5) 开关域名占用预检（冲突时需用户确认，见 deploy-check）
	occ=$(ctl_domain_check "$tok" "$acct" "$ctl_host.$domain" "$zone_id")
	case "$occ" in
		clean)
			;;
		worker:hometunnel-ctl)
			msg "deploy: switch domain already bound to $WORKER_NAME (idempotent rebind)"
			;;
		worker:*)
			# 100116 场景: 域名挂在其他 Worker 上（如旧原型）。
			# 默认拒绝；仅当向导拿到用户确认（takeover 参数）才接管
			old=${occ#worker:}
			if [ "$confirmed" != "takeover" ]; then
				die "SWITCH-DOMAIN-CONFLICT: '$ctl_host.$domain' is already bound to Worker '$old'. Run deploy-check in the wizard to confirm the takeover."
			fi
			msg "deploy: switch domain in use by '$old' — taking over (user confirmed)"
			detach_worker_domain "$tok" "$acct" "$ctl_host.$domain" "$old" \
				|| die "cannot take over switch domain from '$old' (detach failed — delete its custom domain in the Cloudflare dashboard, then retry)"
			;;
		dns:*)
			# 100117 场景: 该主机名已有普通 DNS 记录（用户手工建过）
			die "hostname '$ctl_host.$domain' has an existing ${occ#dns:} DNS record. Delete it first (DNS app in the Cloudflare dashboard), or change the switch hostname in Settings."
			;;
		*)
			# 查询失败等 — PUT 会给出权威错误，继续
			;;
	esac

	# 2) 上传 Worker（multipart: metadata + worker.js）
	upload_worker "$tok" "$acct" || die "worker upload failed"

	# 3) 绑自定义域（幂等 PUT，重复 = 更新路由）
	resp=$(curl -fsS --max-time 20 -X PUT \
		-H "Authorization: Bearer $tok" \
		-H 'Content-Type: application/json' \
		-d "{\"hostname\":\"$ctl_host.$domain\",\"service\":\"$WORKER_NAME\",\"zone_id\":\"$zone_id\",\"zone_name\":\"$domain\"}" \
		"https://api.cloudflare.com/client/v4/accounts/$acct/workers/domains" 2>&1) \
		|| die "workers/domains PUT failed: $resp"
	echo "$resp" | grep -q '"success": *true' || die "workers/domains unexpected: $resp"
	msg "OK: custom domain bound ($ctl_host.$domain)"

	# 4) 验证（healthz 轮询，证书签发需几秒）
	verify_worker_http
	msg "OK: deployed and verified"

	# 5) TTL 快照：记录本次烤进 Worker 的 TTL 三元组
	#    （ttl_sync_worker 据此检测 UCI 改动 → 自动重部署，无需用户感知）
	write_ttl_snapshot
}

# ---- TTL 配置同步（自动重部署）----
# Worker 代码里 MAX_MIN/REFRESH_MIN 是编译期常量，改 UCI 不会自动生效。
# 本机制: 部署成功即写快照；uci reload 触发的 route-and-regen 末尾比对，
# 漂移且 oauth 可用 → 后台 job 重传 Worker（幂等）。OAuth 失效只记日志，
# 快照不更新，下次保存自动重试。
TTL_SNAPSHOT="$ETC/worker-ttl.snapshot"

ttl_snapshot_line() {
	# 单行三元组: default max renew（get_ 带默认值，与 upload_worker 的 sed 一致）
	echo "$(get_ default_ttl 45) $(get_ max_ttl 240) $(get_ renew_ttl 45)"
}

write_ttl_snapshot() {
	ttl_snapshot_line > "$TTL_SNAPSHOT"
}

# 独立 job 体（route-and-regen 末尾调用；直接 cmd_deploy，不等待 oauth 流程）
cmd_ttl_sync() {
	local tok rc
	# oauth 无效 → 静默放弃（subshell 包裹防 die 穿透；重新授权后下次保存自动补同步）
	tok=$(oauth_valid_token) || tok=""
	if [ -z "$tok" ]; then
		msg "ttl-sync: no valid oauth token, skip (re-authorize to sync)"
		logger -t hometunnel "ttl-sync: no valid oauth token, skip"
		return 0
	fi
	msg "ttl-sync: redeploying worker with new TTL values"
	# subshell: cmd_deploy 内部 die 不穿透（失败要走到下面的失败日志分支）
	( cmd_deploy )
	rc=$?
	if [ $rc -eq 0 ]; then
		logger -t hometunnel "ttl-sync: worker redeployed with new TTL values"
	else
		logger -t hometunnel "ttl-sync: redeploy FAILED (rc=$rc), will retry on next config change"
	fi
	return $rc
}

# 漂移检测（reload 链调用）：快照存在且与当前 UCI 不一致 → 起 worker-sync job
ttl_sync_check() {
	# 快照缺失（从未部署/重装）→ 不动作，避免意外部署
	[ -f "$TTL_SNAPSHOT" ] || return 0
	local cur snap
	cur=$(ttl_snapshot_line)
	snap=$(cat "$TTL_SNAPSHOT")
	[ "$cur" = "$snap" ] && return 0
	# 防抖：oauth-deploy / worker-sync 任一在跑则跳过（本轮改动下轮再试）
	local j
	for j in oauth-deploy worker-sync; do
		if [ -f "$RUNDIR/$j.pid" ] && kill -0 "$(cat "$RUNDIR/$j.pid" 2>/dev/null)" 2>/dev/null; then
			logger -t hometunnel "ttl-sync: '$j' job already running, skip check"
			return 0
		fi
	done
	logger -t hometunnel "ttl-sync: TTL values changed (snapshot='$snap' uci='$cur'), scheduling worker redeploy"
	job_start worker-sync "$0" ttl-sync
}

# 用 token 按域名查 zone_id（精确匹配 zone name）
cf_zone_id() {
	local tok="$1" domain="$2" resp names ids name id i
	resp=$(curl -fsS --max-time 15 -H "Authorization: Bearer $tok" \
		"https://api.cloudflare.com/client/v4/zones?per_page=50" 2>/dev/null) || return 1
	# 逐行配对 name→id（jsonfilter 分别提取后 awk zip）
	names=$(jsonfilter -s "$resp" -e '@.result[*].name' 2>/dev/null)
	ids=$(jsonfilter -s "$resp" -e '@.result[*].id' 2>/dev/null)
	printf '%s\n' "$names" > /tmp/ht-zones-n.$$
	printf '%s\n' "$ids" > /tmp/ht-zones-i.$$
	id=$(awk -v d="$domain" 'NR==FNR { n[NR]=$0; next } { if (n[FNR]==d) { print; exit } }' /tmp/ht-zones-n.$$ /tmp/ht-zones-i.$$)
	rm -f /tmp/ht-zones-n.$$ /tmp/ht-zones-i.$$
	[ -n "$id" ] || return 1
	echo "$id"
}

# multipart 上传 Worker（curl -F 复刻 wrangler deploy 的 API 调用）
upload_worker() {
	local tok="$1" acct="$2" meta tmp resp rc mig
	# worker.js 模板先做 TTL 占位符替换（与 bundle 同款 sed），产物只存在 tmpfs
	tmp=$(mktemp /tmp/ht-worker.js.XXXXXX) || die "mktemp failed"
	sed -e "s|@@DEFAULT_TTL@@|$(get_ default_ttl 45)|g" \
	    -e "s|@@MAX_TTL@@|$(get_ max_ttl 240)|g" \
	    -e "s|@@RENEW_TTL@@|$(get_ renew_ttl 45)|g" \
	    "$SHARE/worker/worker.js.tpl" > "$tmp"
	# metadata: main_module + bindings(secret_text CTL_KEY + durable_object_namespace CTL_STATE)
	#   + compatibility_date + migrations —— 注意: multipart metadata 里 migrations 是
	#   单个对象（非 wrangler.toml 的数组），数组会被 API 以 10021 拒绝（实测）。
	# 同名 Worker 已存在 → DO 迁移 v1 已应用，重传不再发 migrations（幂等）
	if curl -sS --max-time 15 -H "Authorization: Bearer $tok" \
		"https://api.cloudflare.com/client/v4/accounts/$acct/workers/scripts" 2>/dev/null \
		| grep -q "\"$WORKER_NAME\""; then
		mig=""
		msg "deploy: worker exists — idempotent re-upload"
	else
		mig=',"migrations":{"new_tag":"v1","new_sqlite_classes":["CtlState"]}'
	fi
	meta='{"main_module":"worker.js","compatibility_date":"2026-08-01","bindings":[{"type":"secret_text","name":"CTL_KEY","text":"'"$key"'"},{"type":"durable_object_namespace","name":"CTL_STATE","class_name":"CtlState"}]'"$mig"'}'
	resp=$(curl -sS --max-time 60 -X PUT \
		-H "Authorization: Bearer $tok" \
		-F "metadata=$meta;type=application/json" \
		-F "worker.js=@$tmp;filename=worker.js;type=application/javascript+module" \
		"https://api.cloudflare.com/client/v4/accounts/$acct/workers/scripts/$WORKER_NAME" 2>&1)
	rc=$?
	rm -f "$tmp"
	[ $rc -eq 0 ] || die "workers/scripts PUT failed: $resp"
	echo "$resp" | grep -q '"success": *true' || die "worker upload unexpected: $resp"
	msg "OK: worker uploaded (script=$WORKER_NAME)"
}

# healthz 轮询验证（自定义域证书签发有延迟，最多等 ~80s）
verify_worker_http() {
	local base i resp
	base=$(ctl_base_url)
	i=0
	while [ $i -lt 16 ]; do
		resp=$(curl -fsS --max-time 8 "$base/healthz" 2>/dev/null)
		if echo "$resp" | grep -q '"ok": *true'; then
			msg "healthz: OK"
			return 0
		fi
		i=$((i + 1))
		sleep 5
	done
	die "healthz not reachable at $base after 80s (custom domain cert may still be issuing — retry verify later)"
}

# oauth-deploy: 向导一条龙 job（等待授权 + 部署）
cmd_oauth_deploy() {
	local arg="${1:-}"
	local i=0 st first
	msg "== waiting for authorization =="
	# 先发起（若未在途）；oauth-start 的 JSON（user_code/verification_url）透传到 job 输出，
	# 向导同时读 oauth-start 直连响应与 job 输出，两者取先到者
	first=$(cmd_oauth_start 2>&1)
	msg "$first"
	case "$first" in
		*'already_authorized'*)
			msg "== already authorized, deploying =="
			cmd_deploy "$arg"
			return $?
			;;
	esac
	while [ $i -lt 60 ]; do
		st=$(cmd_oauth_status 2>/dev/null || echo '{"state":"failed","error":"oauth-status error"}')
		case "$st" in
			*'"authorized"'*)
				msg "== authorized, deploying =="
				cmd_deploy "$arg"
				return 0
				;;
			*'"expired"'*)
				die "authorization expired (5 min) — restart the wizard step"
				;;
			*'"failed"'*)
				die "oauth failed: $st"
				;;
		esac
		sleep 5
		i=$((i + 1))
	done
	die "timeout waiting for authorization (5 min)"
}

case "${1:-}" in
	job)
		shift
		job_start "$@"
		;;
	jobstatus)
		shift
		job_status "$@"
		;;
	login)      cmd_login ;;
	create)     cmd_create ;;
	route)      cmd_route ;;
	regen)      cmd_regen ;;
	bundle)     cmd_bundle ;;
	verify)     cmd_verify ;;
	ctl)        shift; cmd_ctl "$@" ;;
	status)     cmd_status ;;
	check)      cmd_check ;;
	zones)      cmd_zones ;;
	unbind)     shift; cmd_unbind "$@" ;;
	route-and-regen) cmd_route_and_regen ;;
	ttl-sync)     cmd_ttl_sync ;;
	probe)      cmd_probe ;;
	apply-mode) cmd_apply_mode ;;
	mark)       shift; cmd_mark "$@" ;;
	set)        shift; cmd_set "$@" ;;
	genkey)     genkey ;;
	oauth-start)  cmd_oauth_start ;;
	oauth-status) cmd_oauth_status ;;
	oauth-clear)  cmd_oauth_clear ;;
	deploy)       shift; cmd_deploy "$@" ;;
	deploy-check) cmd_deploy_check ;;
	oauth-deploy) shift; cmd_oauth_deploy "$@" ;;
	*)
		cat <<'EOF'
usage: hometunnel.sh <command>
  job <name> <cmd...>   run command as background job (wizard backend)
  jobstatus <name>      running | done:<rc> | missing
  login                 cloudflared tunnel login (HOME=/etc/hometunnel)
  create                create tunnel (idempotent), write tunnel_id to UCI
  route                 route dns for all enabled ingress rules
  regen                 regenerate config.yml + smooth restart
  bundle                build worker deployment tarball to /tmp
  verify                verify control plane (healthz + /cmd)
  ctl on|off            turn tunnel on/off from the router side (LuCI buttons)
  status                human-readable status
  check                 verify tunnel_id against Cloudflare (via cert.pem token)
  zones                 list all Cloudflare zones (domains) via cert.pem token
  unbind                delete tunnel + DNS records + switch service (full unbind)
  route-and-regen       publish DNS CNAMEs + regen config (uci reload hook)
  probe                 bound config + online health (locked-state overview)
  apply-mode            apply UCI mode to init enable states
  set <key> <value>     set a global UCI option (wizard backend)
  genkey                (re)generate ctl.key
  oauth-start           start OAuth device flow (prints QR/verify URL)
  oauth-status          poll OAuth device flow state
  oauth-clear           clear saved OAuth credentials
  deploy [takeover]     deploy control-plane Worker via API (needs oauth)
  ttl-sync              redeploy worker after TTL values change (auto, job)
  deploy-check          pre-check switch domain conflicts (wizard step 7)
  oauth-deploy          wait for oauth + deploy (wizard one-shot job)
EOF
		exit 1
		;;
esac
