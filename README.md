This is a small tool to use WebSockets for tunneling.
It comes handy when behind some firewall which allows HTTP/HTTPS but blocks
access to SSH or other services.

This script includes both client and server.
The server is setup at the tunnel exit and will forward connections depending on
the URL. The client is run on the system where tunnel entry is needed.

Example:

    # Run the server (tunnel exit) on port 3001.
    # This broad access ist not recommended! See below for better setups.
    remote-sys$ perl wstunnel.pl 0.0.0.0:3001

    # Run the client (tunnel entry), so that it forwards connections to
    # local port 11022 to 127.0.0.1:22 on the remote system.
    local-sys$ perl wstunnel.pl \
      --tunnel ws://remote-sys:3001/127.0.0.1:22 \
      127.0.0.1:11022

    # Use ssh with this tunnel to log into the remote system.
    local-sys$ ssh -p11022 127.0.0.1

This simple tunnel setup does not provide any kind of security by itself and
allows arbitrary TCP forwardings. It is intended to be used together with a
web server which provides the necessary security, for example with nginx:

    location ~ /tunnel/ {
        proxy_pass           http://127.0.0.1:3001;
        proxy_http_version   1.1;
        proxy_set_header     Upgrade $http_upgrade;
        proxy_set_header     Connection "upgrade";
        auth_basic           "Restricted";
        auth_basic_user_file /home/user/wstunnel/.htpasswd;
    }

Assuming that this server has also setup https (recommended) tunnel exit and
entry could be run like this:

    # Run the server (tunnel exit) on port 3001, localhost only.
    remote-sys$ perl wstunnel.pl 127.0.0.1:3001

    # Run the client (tunnel entry), so that it forwards connections to
    # local port 11022 to 127.0.0.1:22 on the remote system.
    local-sys$ perl wstunnel.pl \
      --tunnel wss://user:pass@remote-sys/tunnel/127.0.0.1:22 \
      127.0.0.1:11022

    # Use ssh with this tunnel to log into the remote system.
    local-sys$ ssh -p11022 127.0.0.1

