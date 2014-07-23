package PluginEngine;
use List::Util qw(first);
use Module::Pluggable
	search_path=>"Gummy",
	require => 1,
	sub_name=>'enumerate_plugins';

my %loaded;

sub _load_plugin {
	my $irc = shift;
	my $plugin = shift;
	my $plugin_object;

	return 0 if (!defined $plugin);

	print "Starting plugin $plugin...\n";
	if ($plugin->can('init')) {
		$plugin_object = $plugin->init();
		if ($irc->plugin_add($plugin, $plugin_object)) {
			print "Loaded plugin.\n";
			$loaded{$plugin} = 1;
			return 1;
		}
		else {
			print "Error loading plugin.\n";
		}
	}
	return 0;
}


sub start_plugins {
	my $irc = shift;
	my @plugins = enumerate_plugins();
	my %depend_table;
	foreach my $plugin (@plugins) {
		my $depends;
		print "Getting dependancies for '$plugin'...\n";
		if ($plugin->can('get_dependancies')) {
			$depends=$plugin->can('get_dependancies');
		}

		if ($depends) {
			print "Adding dependancies $depends...\n";
			$depend_table{$plugin} = $depends;
		}
		else {
			_load_plugin($irc, $plugin);
		}
	}

	my $changed=1;
	while (defined $changed && %depend_table) {
		$changed = undef;
		# go through each plugin.
		foreach my $plugin (keys %plugins) {
			# get the dependancies table for this plugin.
			my $depends_list = $depend_table{$plugin};
			# for each dependancy
			foreach my $depend_on (keys %$depends_list) {
				# if we've loaded it.
				if (exists $loaded{$depend_on}) {
					# scratch it from the list of necessary dependancies
					delete $$depends_list{$depend_on};
				}
			}
			# if the plugin doesn't have any more dependancies
			if (!%$depends_list) {
				# remove it from the list of plugins we need to resolve dependancies for
				delete $depends_table{$plugin};
				# load it into memory
				_load_plugin($irc, $plugin);
				# and mark that we did stuff and should look again.
				$changed=1;
			}
		}
	}
	foreach my $plugin (keys %depends_list) {
		print "Unable to load module $plugin.";
		foreach my $depend (keys %{$depends_list{$plugin}}) {
			print "Missing $depend";
		}
	}
	
}

1;

