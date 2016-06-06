#!/usr/bin/perl
#
# Copyright 2016 Steffen Ullrich <sullr@cpan.org>
#   This program is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.

use strict;
use warnings;
use Mojo::UserAgent;
use Mojolicious::Lite;
use Mojo::IOLoop;
use Getopt::Long qw(:config posix_default bundling);

sub usage {
    print STDERR "ERROR: @_\n" if @_;
    print <<USAGE;

Usage: $0 [-h|--help] [-T|--tunnel URL] [listen_ip]:port
    -h|--help        this help
    -T|--tunnel URL  use URL as entry to tunnel, must be ws:// or wss://

Example:

  # start es server on 127:0.0.1:3001
  perl wstunnel.pl :3001

  # connect to tunnel entry using wss:// and authorization
  # connections to local 127.0.0.1:11022 will be passed to 127.0.0.1:22 
  # at tunnel endpoint
  perl wstunnel.pl \
     --tunnel 'wss://user:pass@example.org/tunnel/127.0.0.1:22' \
     :11022


USAGE
    exit(2);
}

my $tunnel;
GetOptions(
    'h|help'   => sub { usage() },
    'tunnel=s' => \$tunnel,
) or usage();

my $listen = shift(@ARGV) or usage('no listen address');
@ARGV and usage('too much arguments');

$listen =~m{^(.*?):(\d+)\z} or usage('bad listen address');
my %listen = ( port => $2, address => $1||'127.0.0.1' );

if ($tunnel) {
    my $ua = Mojo::UserAgent->new;
    $tunnel =~m{^ws(s)?://}i or usage('URL should be ws:// or wss://');
    if ($1) {
	# Workaround the problem that Mojo::UserAgent disables certificate
	# validation unless an explicit CA store is given :(
	require IO::Socket::SSL;
	IO::Socket::SSL::set_args_filter_hack(sub {
	    my (undef,$args) = @_;
	    $args->{SSL_verify_mode} = 1;
	    $args->{SSL_verifycn_scheme} = 'http';
	    IO::Socket::SSL::default_ca(),
	});
    }
    Mojo::IOLoop->server(\%listen, sub {
	my ($loop,$tcp) = @_;
	warn "new connection\n";
	$tcp->stop;

	$ua->websocket($tunnel, sub {
	    my (undef,$tx) = @_;
	    $tx->res->code == 101 or die $tx->res->code;
	    $tcp->start;
	    \&_transfer(\$tcp,\$tx);
	});
    });
    Mojo::IOLoop->start;

} else {
    websocket '/*dst' => sub {
	my $c = shift;
	$c->render_later->on(finish => sub { warn 'websocket closing' });

	my $tx = $c->tx;
	# $tx->with_protocols('binary');

	my $dst = $c->stash('dst');
	$dst =~s{.*/}{};
	my ($host,$port) = $dst =~m{^(.*):(\d+)\z} or do {
	    $tx->finish(4500, "invalid dst $dst");
	    warn "invalid dst $dst";
	    return;
	};

	Mojo::IOLoop->client(address => $host, port => $port, sub {
	    my ($loop, $err, $tcp) = @_;
	    $tx->finish(4500, "TCP connection error: $err") if $err;
	    \&_transfer(\$tcp,\$tx);
	});
    };
    app->start('daemon','-l','http://'.$listen{address}.":$listen{port}")
}


sub _transfer {
    my ($rtcp,$rtx) = @_;
    $$rtcp->on(error => sub { 
	warn "connection error\n";
	$$rtx->finish(4500, "TCP error: $_[1]") 
    });

    $$rtcp->on(close => sub { 
	warn "connection closed\n";
	$$rtx->finish(4500, "TCP close") 
    });

    $$rtcp->on(read => sub {
	my (undef, $bytes) = @_;
	$$rtx->send({binary => $bytes});
    });

    $$rtx->on(binary => sub {
	my (undef, $bytes) = @_;
	$$rtcp->write($bytes);
    });

    $$rtx->on(finish => sub {
	$$rtcp->close;
	$$rtcp = $$rtx = undef;
    });
}
