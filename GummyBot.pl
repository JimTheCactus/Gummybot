package GummyBot;
use strict;
use POE;
use POE::Component::IRC;
use PluginEngine;

our $cfg;
my $command_processor;

print "Loading config...\n";
do 'config.pl';

my $irc = POE::Component::IRC->spawn(
	Nick => $cfg->{'nick'},
	Ircname => $cfg->{'realname'},
	Username => $cfg->{'username'},
	Server  => $cfg->{'server'},
	Port => $cfg->{'port'}
);

POE::Session->create(
	inline_states => {
		_start	=> \&on_start,
		irc_001 => \&on_connect,
		irc_plugin_error => \&on_plugin_error,
	}
);

use sigtrap 'handler' => \&on_kill, 'normal-signals';

$poe_kernel->run();

sub on_start {
	print "Starting plugins...\n";
	PluginEngine::start_plugins($irc);

	print "Connecting to $irc->{'server'}...\n";
	$irc->yield(register => qw(001 irc_plugin_error));


	# No reason to hammer the IRC server while testing...
	$irc->yield(connect => {});
}

sub on_connect {
	print "Connected!\n";
	foreach my $channel (@{$cfg->{'channels'}}) {
		print "Joining $channel...\n";
		$irc->yield(join => $channel);
	}
}

sub on_plugin_error {
	my $msg = $_[ARG0];
	my $plugin = $_[ARG1];
	print "Error occured in plugin $plugin: $msg\n";
}

sub on_kill {
	POE::Kernel->signal($poe_kernel, 'POCOIRC_SHUTDOWN');
}

