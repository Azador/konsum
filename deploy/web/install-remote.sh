#!/bin/sh
# Teil von install.sh: läuft als root auf dem Zielrechner.
#
#   install-remote.sh benutzer host https-port http-port paketmanager|- quelle
#
# quelle enthält Caddyfile und web/ und wird am Ende gelöscht.
set -eu
user=$1 host=$2 https_port=$3 http_port=$4 pm=$5 src=$6
service=konsum-web
home=/var/lib/$user
trap 'rm -rf "$src"' EXIT

if [ "$pm" != - ]; then
	echo "Installiere Caddy …"
	case $pm in
	apt-get) apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y -q caddy ;;
	dnf) dnf install -y caddy ;;
	zypper) zypper --non-interactive install caddy ;;
	pacman) pacman -S --needed --noconfirm caddy ;;
	esac
	# Das Paket bringt einen eigenen Dienst auf Port 80 mit; der wird nicht
	# gebraucht.
	systemctl disable --now caddy.service 2>/dev/null || true
fi
caddy="$(command -v caddy)" || {
	echo "caddy nicht gefunden" >&2
	exit 1
}

if id "$user" >/dev/null 2>&1; then
	echo "Benutzer $user ist vorhanden."
else
	useradd --system --user-group --home-dir "$home" \
		--shell "$(command -v nologin || echo /bin/false)" "$user"
	echo "Benutzer $user angelegt."
fi
group="$(id -gn "$user")"

# Web-App und Caddyfile gehören root, der Dienst darf nur data/ und config/
# schreiben (dort liegt die lokale CA).
install -d -m 0755 "$home"
install -d -m 0700 -o "$user" -g "$group" "$home/data" "$home/config"
install -m 0644 "$src/Caddyfile" "$home/Caddyfile"
rm -rf "$home/web.new" "$home/web.old"
cp -R "$src/web" "$home/web.new"
chmod -R u=rwX,go=rX "$home/web.new"
[ -d "$home/web" ] && mv "$home/web" "$home/web.old"
mv "$home/web.new" "$home/web"
rm -rf "$home/web.old"

cat >"$home/konsum.env" <<EOF
KONSUM_HOST=$host
KONSUM_HTTPS_PORT=$https_port
KONSUM_HTTP_PORT=$http_port
KONSUM_ROOT=$home/web
KONSUM_CA_DIR=$home/data/caddy/pki/authorities/local
XDG_DATA_HOME=$home/data
XDG_CONFIG_HOME=$home/config
EOF
chmod 0644 "$home/konsum.env"

cat >/etc/systemd/system/$service.service <<EOF
[Unit]
Description=Konsum Web-App (Caddy)
After=network-online.target
Wants=network-online.target

[Service]
User=$user
Group=$group
EnvironmentFile=$home/konsum.env
ExecStart=$caddy run --config $home/Caddyfile --adapter caddyfile
Restart=on-failure
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$home/data $home/config
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --quiet "$service"
systemctl restart "$service"
sleep 2
if ! systemctl is-active --quiet "$service"; then
	echo "Der Dienst $service ist nicht gestartet:" >&2
	journalctl -u "$service" -n 30 --no-pager >&2
	exit 1
fi
echo "Dienst $service läuft (systemctl status $service)."

if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q 'Status: active'; then
	echo "Hinweis: ufw ist aktiv. Ports freigeben: ufw allow $https_port/tcp; ufw allow $http_port/tcp"
elif command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then
	echo "Hinweis: firewalld ist aktiv. Ports $https_port/tcp und $http_port/tcp freigeben."
fi
