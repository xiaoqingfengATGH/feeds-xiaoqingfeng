#!/bin/sh
# gen-yml.sh — UCI ingress 规则 → /etc/hometunnel/config.yml（locally-managed cloudflared 配置）
# 语义: 每条 enabled ingress 一个 ingress 块；path/httpHostHeader/noTLSVerify/connectTimeout 透传；
#       尾部恒有 http_status:404 兜底（未匹配一律 404，不转发）。
# 用法: gen-yml.sh [输出路径]   （默认 /etc/hometunnel/config.yml）

set -u

CONF_DIR=/etc/hometunnel
OUT="${1:-$CONF_DIR/config.yml}"
WORK="${OUT}.tmp"

log() { logger -t hometunnel "$*"; }

[ -x /sbin/uci ] || { echo "uci not found" >&2; exit 1; }

# 生成到临时文件，成功后原子替换（cloudflared 不会读到半截配置）
mkdir -p "$CONF_DIR"
: > "$WORK"

tunnel_id=$(uci -q get hometunnel.global.tunnel_id || true)
if [ -z "$tunnel_id" ]; then
	log "gen-yml: tunnel_id empty, abort"
	echo "tunnel_id empty" >&2
	rm -f "$WORK"
	exit 1
fi

# cloudflared tunnel create 将凭据写到 $HOME/.cloudflared/<uuid>.json（HOME=/etc/hometunnel）
creds="$CONF_DIR/.cloudflared/$tunnel_id.json"
if [ ! -f "$creds" ]; then
	log "gen-yml: credentials $creds missing"
	echo "credentials missing: $creds" >&2
	rm -f "$WORK"
	exit 1
fi

cat > "$WORK" <<EOF
# 由 gen-yml.sh 自动生成，请勿手工编辑（改 UCI: hometunnel.@ingress[i]）
tunnel: $tunnel_id
credentials-file: $creds
EOF

# 首个规则前需要 ingress: 键（否则 YAML 结构非法）
INGRESS_KEY_WRITTEN=0

count=0
i=0
while uci -q show hometunnel 2>/dev/null | grep -q "^hometunnel.@ingress\[$i\]="; do
	enabled=$(uci -q get "hometunnel.@ingress[$i].enabled" || echo 1)
	if [ "$enabled" = "1" ] || [ "$enabled" = "true" ]; then
		name=$(uci -q get "hometunnel.@ingress[$i].name" || echo "rule$i")
		subdomain=$(uci -q get "hometunnel.@ingress[$i].subdomain" || echo '')
		domain=$(uci -q get hometunnel.global.domain || echo '')
		service=$(uci -q get "hometunnel.@ingress[$i].service" || echo '')
		path=$(uci -q get "hometunnel.@ingress[$i].path" || echo '')
		hhh=$(uci -q get "hometunnel.@ingress[$i].http_host_header" || echo '')
		# HTTP(S) 源站默认使用服务 URL 的主机名；显式 Host 始终优先。
		# 不要把公网入口 hostname 透传给只识别内网 Host 的源站。
		if [ -z "$hhh" ]; then
			case "$service" in
				http://*|https://*)
					origin=${service#*://}
					origin=${origin%%/*}
					origin=${origin%%\?*}
					origin=${origin##*@}
					case "$origin" in
						\[*\]*) hhh="${origin%%]*}]" ;;
						*) hhh=${origin%%:*} ;;
					esac
					;;
			esac
		fi
		ntv=$(uci -q get "hometunnel.@ingress[$i].no_tls_verify" || echo 0)
		ct=$(uci -q get "hometunnel.@ingress[$i].connect_timeout" || echo 30)

		if [ -z "$subdomain" ] || [ -z "$domain" ] || [ -z "$service" ]; then
			log "gen-yml: ingress[$i] ($name) missing subdomain/domain/service, skipped"
			i=$((i + 1))
			continue
		fi

		hostname="${subdomain}.${domain}"
		{
			[ "$INGRESS_KEY_WRITTEN" -eq 0 ] && { echo ""; echo "ingress:"; INGRESS_KEY_WRITTEN=1; }
			echo "  # $name"
			echo "  - hostname: $hostname"
			[ -n "$path" ] && echo "    path: '$path'"
			echo "    service: $service"
			if [ "$ntv" = "1" ] || [ -n "$hhh" ] || [ -n "$ct" ]; then
				echo "    originRequest:"
				[ "$ntv" = "1" ] && echo "      noTLSVerify: true"
				[ -n "$hhh" ] && echo "      httpHostHeader: $hhh"
				[ -n "$ct" ] && echo "      connectTimeout: ${ct}s"
			fi
		} >> "$WORK"
		count=$((count + 1))
	fi
	i=$((i + 1))
done

if [ "$count" -eq 0 ]; then
	log "gen-yml: no enabled ingress rules, abort (keeping old config)"
	echo "no enabled ingress rules" >&2
	rm -f "$WORK"
	exit 1
fi

# 兜底: 未匹配的路径一律 404
cat >> "$WORK" <<EOF

  # 兜底: 其余请求一律 404
  - service: http_status:404
EOF

mv -f "$WORK" "$OUT"
chmod 600 "$OUT"
log "gen-yml: wrote $OUT ($count ingress rules)"
echo "OK: $count rules -> $OUT"
