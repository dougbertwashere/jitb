#!/usr/bin/perl -w

# apt-get install libheap-perl libio-async-loop-epoll-perl libplack-perl
# cpan install Net::Prometheus
# cpan install Net::Async::HTTP::Server

use strict;
use IO::Async::Timer::Countdown;
use IO::Async::Loop;
use Net::Prometheus;
use Plack::Builder;
use Storable qw(lock_store lock_retrieve);

my $prom_port = 9127;
my $store = "./data/jitb.dat";
my $debug = 1;

#
# set up the prometheus exporter and prime it
#
my $prom = Net::Prometheus->new;
builder {
        mount "/metrics" => $prom->psgi_app;
};
my $loop = IO::Async::Loop->new;
my %gauges;
update_gauges();

#
# schedule gauge updates
#
my $timer = IO::Async::Timer::Countdown->new(
        delay => 5,
        on_expire => sub {
                my $self = shift;
                update_gauges();
                $self->start;
        },
);

$timer->start;

#
# start the web server and run the async loop
#
$prom->export_to_IO_Async($loop, (port => $prom_port));
$loop->add($timer);
$loop->run;

exit();

sub update_gauges {
	my $t = lock_retrieve($store);

	#
	# pack telemetry
	#
	update_gauge("soc", $t->{pack}->{soc});
	update_gauge("voltage", $t->{pack}->{voltage});
	update_gauge("current", $t->{pack}->{current});
	update_gauge("amphours", $t->{pack}->{amphours});
	update_gauge("nr_modules", $t->{pack}->{nr_modules});

	for ("low", "avg", "high") {
		update_gauge("cell_voltage_$_", $t->{pack}->{cells}->{$_});
	}

	for ("max", "min") {
		update_gauge("temp_$_", $t->{pack}->{temps}->{$_});
	}
	#
	# jitb telemetry
	#
	for my $s (sort keys %{$t->{jitb}->{status}}) {
		update_gauge("status_$s", $t->{jitb}->{status}->{$s});
	}
	for my $f (sort keys %{$t->{jitb}->{fault}}) {
		update_gauge("fault_$f", $t->{jitb}->{fault}->{$f});
	}
	#
	# module telemetry
	#
	for (my $m = 0; $m < $t->{pack}->{nr_modules}; $m++) {
		my $mod = $t->{module_voltages}->[$m];
		for (my $i = 0; $i < 6; $i++) {
			update_gauge("module_${m}_cell_${i}", $mod->[$i]);
		}
	}
}

sub update_gauge {
	my ($gauge, $value) = @_;

	my $g = get_gauge($gauge);

	$g->set($value);
}

sub get_gauge {
	my $name = shift;

	return $gauges{$name} if $gauges{$name};

	$gauges{$name} = $prom->new_gauge(name => "jitb_$name",
		help => "Jack in The Box UDP telemetry - $name",
	);
	die "$name: failed to create gauge\n" unless $gauges{$name};

	return $gauges{$name};
}
