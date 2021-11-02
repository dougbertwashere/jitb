#!/usr/bin/perl -w

use strict;
use IO::Socket;
use Storable qw(lock_store lock_retrieve);

my $udp_spray_port = 6750;
my $store = "/t/jitb.dat";
my $debug = 0;

#
# set up to receive the jack in the box udp spray socket
#
my $sock = IO::Socket::INET->new(
           LocalPort => $udp_spray_port, 
       Proto => 'udp') or die "socket: $@";

print "receiving UDP on port $udp_spray_port\n";

my %telemetry;

my $msg;
while ($sock->recv($msg, 512)) {
	my ($pport, $peer) = sockaddr_in($sock->peername);
	my $nr = length $msg;

	printf("%s:$pport length=$nr %s", inet_ntoa($peer), hexdump($msg)) if $debug;

	my ($d1, $d2, $msg_id, $fam_id, $ts, $rtr, $prio, $ext, $len) =	unpack("L5C4", $msg);
	my @dat = unpack("C8", $msg);

	#printf(" MSG_ID %-4x D1 %10d D2 %10d DATA %s \"%s\"\n", $msg_id, $d1, $d2, join(",", @dat), $msg) if $debug;

	printf(" MSG_ID %-4x D1 %10d D2 %10d\n", $msg_id, $d1, $d2) if debug;

	grok_msg($msg_id, $d1, $d2, @dat);
}

sub grok_msg {
	my ($id, $d1, $d2, @dat) = @_;

	if ($id == 0x650) {
		$telemetry{pack}->{soc} = ($d1 & 0xff) / 2;
	} elsif ($id == 0x150) {
		$telemetry{pack}->{voltage} = (($d1 >> 16) & 0xFFFF) / 10;

		my $current = $d1 & 0xFFFF;
		$current = $current - 65536 if $current > 0x7FFF;
		$telemetry{pack}->{current} = $current;

		my $amphrs = $d2 & 0xFFFF;
		$amphrs = $amphrs - 65536 if $amphrs > 0x7FFF;
		$amphrs /= 10;
		$telemetry{pack}->{amphours} = $amphrs;

		$telemetry{pack}->{temps}->{min} = ($d2 >> 24) & 0xFF;
		$telemetry{pack}->{temps}->{max} = ($d2 >> 16) & 0xFF;
		#
		# store once per msg 0x150
		#
		lock_store(\%telemetry, $store);
	} elsif ($id == 0x651) {
		$telemetry{pack}->{cells}->{low} = ($d1 & 0xFFFF) / 1000;
		$telemetry{pack}->{cells}->{high} = (($d1 >> 16) & 0xFFFF) / 1000;
		$telemetry{pack}->{cells}->{avg} = ($d2 & 0xFFFF) / 1000;
	} elsif ($id == 0x652) {
		$telemetry{pack}->{cutoff}->{high} = ($d2 & 0xFFFF) / 10;
		$telemetry{pack}->{cutoff}->{low} = (($d2 >> 16) & 0xFFFF) / 10;
	} elsif ($id == 0x654) {
		$telemetry{jitb}->{status}->{neg_contactor} = ($d1 & 1 ? 1 : 0);
		$telemetry{jitb}->{status}->{pos_contactor} = ($d1 & 2 ? 1 : 0);
		$telemetry{jitb}->{status}->{charge_enable} = ($d1 & 4 ? 1 : 0);
		$telemetry{jitb}->{status}->{heat_enable} = ($d1 & 8 ? 1 : 0);
		$telemetry{jitb}->{status}->{neg_confirmed} = ($d1 & 0x10 ? 1 : 0);
		$telemetry{jitb}->{status}->{pos_confirmed} = ($d1 & 0x20 ? 1 : 0);
		$telemetry{jitb}->{status}->{p12v_available} = ($d1 & 0x40 ? 1 : 0);
		$telemetry{jitb}->{fault}->{voltage_limit} = ($d2 & 0x80 ? 1 : 0);
		$telemetry{jitb}->{fault}->{temp} = ($d2 & 0x40);
		my $reason = ($d1 >> 8) & 0x3f;
		$telemetry{jitb}->{fault}->{reason} = $reason;
		$telemetry{jitb}->{fault}->{no_fault} = $reason == 0 ? 1 : 0;
		$telemetry{jitb}->{fault}->{cell_low} = $reason == 1 ? 1 : 0;
		$telemetry{jitb}->{fault}->{cell_high} = $reason == 2 ? 1 : 0;
		$telemetry{jitb}->{fault}->{module_cold} = $reason == 3 ? 1 : 0;
		$telemetry{jitb}->{fault}->{module_hot} = $reason == 4 ? 1 : 0;
		$telemetry{jitb}->{fault}->{voltage_variance} = $reason == 5 ? 1 : 0;
	} elsif ($id == 0x68f) {
		$telemetry{pack}->{nr_modules} = $dat[1];
		my $module = $dat[0];
		for (my $i = 0; $i < 6; $i++) {
			$telemetry{module_voltages}->[$module]->[$i] = $dat[$i + 2] / 100 + 2;
		}
	} else {
		printf("MSG 0x%x unknown\n", $id) if $debug;
	}
}

sub hexdump {
	my $data = shift;

	my @a = $msg =~ /([\0-\377]{1})/g;
	my $dump = "";
	for (@a) {
		$dump .= unpack "H*", $_;
	}

	return $dump;
}
