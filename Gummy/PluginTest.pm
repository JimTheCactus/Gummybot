package Gummy::PluginTest;
use POE::Component::IRC::Plugin qw( :ALL );

#sub get_dependancies {
#        return {
#                "Gummy::Core"=>1
#        };
#}

sub init {
	my $class = shift;
        print "Starting test plugin...\n";
	return bless {@_}, $class;
}

# Required entry point for PoCo-IRC
sub PCI_register {
        my ($self, $irc) = @_;

	print "Regsitering test plugin...\n";

        # Register events we are interested in
        $irc->plugin_register( $self, 'SERVER', qw(public) );

        # Return success
        return 1;
}

# Required exit point for PoCo-IRC
sub PCI_unregister {
        my ($self, $irc) = @_;
        return 1;
}

sub S_public {
	print "Ping1\n";
	my ($self, $irc) = splice @_, 0, 2;
	print "Ping2\n";
	my $nickhost   = ${ $_[0] };
	my $channel = ${ $_[1] }->[0];
	my $text  = ${ $_[2] };
	print "Ping3\n";
        my ($target, $host) = split(/ !/,$nickhost);
	print "Ping4\n";
        my ($prefix,$cmd, $args) = split(/\s+/,$text,3);
	print "Ping5\n";
	
        print "<$target> @ $channel: $text\n";

        return PCI_EAT_NONE;
}


# Default handler for events that do not have a corresponding plugin
# method defined.
sub _default {
        my ($self, $irc, $event) = splice @_, 0, 3;
        print "Default called for $event\n";

        # Return an exit code
        return PCI_EAT_NONE;
}

1;
