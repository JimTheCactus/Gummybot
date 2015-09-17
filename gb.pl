use strict;
use vars qw($VERSION %IRSSI);
use POSIX;
use Irssi;
use Storable;
use File::Spec;
use Config::Tiny;
use List::MoreUtils qw(uniq any);
use POSIX qw/strftime/;
use LWP::Simple;
use Switch;
use DBI;

my $gummyver = "b3.1.0-dev";

#
#Module Header
#

$VERSION = '1.00';
%IRSSI = (
	authors     =>	'Jim The Cactus',
	contact     =>	'themanhimself@jimthecactus.com',
	name        =>	"Gummybot $gummyver",
	description => 	'The one and only Gummybot' ,
	license     =>	'Public Domain',
);

#
# Global state variables (because I'm a bad person
#

my %floodtimes; # Holds the various flood timers
my $gummyenabled=0; # Keeps track of whether the bot is enabled or not.
my %funstuff; # Holds the various replacement data
my %funsubs; # Holds the processed hash of replacement data
my $timerhandle; # Holds the handle to the maintenance event timer.
my $lastblink; # Keeps track of the last time we blinked
my $lastmsg; # Keeps track of the last time we saw traffic
my %activity; # Keeps track of when we last saw a specific person
my $lastupdate=time; # Keeps track of when we last loaded the fun stuff
my $nomnick; # Keeps track of who gummy is attached to
my %greets; # Holds the greeting messages
#my %memos; # Holds the current pending memos
my @reminders=(); # Hold the list of pending reminders.
my %commands=(); # Holds the table of commands.
my %aliases; # Holds the list of known aliases for current nicknames.
my %manual_aliases; # Hash of list references; holds known aliases.
my $database; # Holds the handle to our database
my $database_prefix; # Holds the table prefix.
my %pendingnicklinks; # Pending nick linkings.

# Authorization requests must be a hashtable with the following parameters:
# 'tag' - The timeout tag used to timeout an auth request.
# 'callback' - A function reference to the function we're supposed to call when we hear back from nickserv
# 'args' - The args we're supposed to hand to the callback
my %authrequests=(); # Holds pending authorization requests
 

# Establish the settings and their defaults
Irssi::settings_add_bool('GummyBot','Gummy_AutoOn',0); # Determines if gummy starts himself when loaded.

# Greets
Irssi::settings_add_bool('GummyBot','Gummy_AllowAutogreet',1); # Enables Gummy's greet system
Irssi::settings_add_bool('GummyBot','Gummy_GreetOnEntry',0); # Makes Gummy greet based on the new nick rather than the old one.
Irssi::settings_add_time('GummyBot','Gummy_GreetFloodLimit','10m'); # Sets the minimum time between greet events for a given nick (Prevents floods from unstable connections.)

# Memos
Irssi::settings_add_bool('GummyBot','Gummy_AllowMemo',1); # Enables Gummy's memo system.
Irssi::settings_add_time('GummyBot','Gummy_MemoFloodLimit','2m'); # Sets the minimum time between adding memos.

#Noms
Irssi::settings_add_bool('GummyBot','Gummy_JoinNom',1); # Enables Gummy's nomming feature when people join.
Irssi::settings_add_time('GummyBot','Gummy_NomFloodLimit','10m'); # Sets the minimum time between join nom events.

#Blinks
Irssi::settings_add_bool('GummyBot','Gummy_Blink',1); # Enables Gummy's blink in idle periods.
Irssi::settings_add_time('GummyBot','Gummy_BlinkTimeout','10m'); # Sets the quiet interval before Gummy will blink
Irssi::settings_add_time('GummyBot','Gummy_BlinkFloodLimit','1h'); # Sets the minimum time between blinks.

#Files
Irssi::settings_add_str('GummyBot','Gummy_RootDir',''); # Sets the main folder where Gummy will save his files.
Irssi::settings_add_str('GummyBot','Gummy_LogFile','gummylog'); # Sets the name of the folder Gummy will use for logging.
Irssi::settings_add_str('GummyBot','Gummy_DataFile','gummydata'); # Sets where Gummy will store his datastore.
Irssi::settings_add_str('GummyBot','Gummy_OmAddFile','omadd'); # Sets where Gummy will store OM suggestions.

# Speed Limit
Irssi::settings_add_time('GummyBot','Gummy_NickFloodLimit','10s'); # Set the time required between requests from a single nick.
Irssi::settings_add_time('GummyBot','Gummy_ChanFloodLimit','3s'); # Sets the minimum time between commands from a single channel.

# Other
Irssi::settings_add_time('GummyBot','Gummy_OmAddFloodLimit','1m'); # Sets the rate at which OM suggestions can be submitted.
Irssi::settings_add_bool('GummyBot','Gummy_AllowRemote',1); # Enables Gummy's tele-commands 
Irssi::settings_add_bool('GummyBot','Gummy_Hidden',0); 

#
# Primary Support Functions
#


# getdir(file)
# Returns the full path to a file after adjusting for the root directory.
sub getdir {
	my $rootdir = Irssi::settings_get_str('Gummy_RootDir');

	$rootdir =~ s/^\s+|\s+$//g;
	if ($rootdir eq '') { # If the root directory field is blank, return it as-is.
		return @_;
	}
	else {
		return File::Spec->catfile(Irssi::settings_get_str('Gummy_RootDir'),@_);
	}
}

# logtext(message)
# Write a line of text to Gummy's admin log.
sub logtext {
	open LOGFILE, ">> ".getdir(Irssi::settings_get_str('Gummy_LogFile'));
	print LOGFILE POSIX::strftime("%Y%m%d %H:%M:%S", localtime);
	print LOGFILE ":@_\n";
	close LOGFILE;
}

# trim(text)
# Trims whitespace. Why a text parser language doesn't have this is beyond me.
sub trim {
	my $temp=shift;
	$temp = ~s/^\s+|\s+$//g;
	return $temp;
}

# enablegummy(['quiet'])
# Starts gummy. Suppresses the boot message if the first argument is 'quiet'
sub enablegummy {
	$gummyenabled = 1;
	$lastblink=time;
	$lastmsg=time;
	read_datastore();
	loadfunstuff();
	$timerhandle=Irssi::timeout_add(60000,"event_minutely_tick", "") or print "Unable to create timeout.";
	logtext("Gummy Enabled.");
	if (lc($_[0]) ne "quiet") {
		foreach (Irssi::channels()) {
			gummydo($_->{server},$_->{name},"makes a slight whining noise as his gleaming red eyes spring to life. A robotic voice chirps out, \"Gummybot Version $gummyver Enabled.\" After a few moments, his eyes turn pink and docile, and he blinks innocently at the channel.");
		}
	}
}

# disablegummy()
# Stops gummy.
sub disablegummy {
	$gummyenabled = 0;
	Irssi::timeout_remove($timerhandle) or print "Unable to kill timer handle.";
	logtext("Gummy Disabled.");
}

# isgummyop(server, channel, nick)
# Returns true if nick is an op.
sub isgummyop {
	my ($server,$channame,$target)=@_;
	if (not $server->ischannel($channame)) { return 0 };
	my $channel = $server->channel_find($channame);
	my $nick = $channel->nick_find($target);
	if ($nick && $nick->{op}) {
		return 1;
	}
	else {
		return 0;
	}
}


# async_isregistered(server, nick, callback, callbackargs)
# Requests an authorization from nickserv
# Calls callback with two arguments: \$callback(status, nick, callbackargs)
# status will be the normal results from nickserv (3 is authorized) or -1 if there was a timeout.
# callbackargs will just be forward from the call to isregistered
sub async_isregistered {
	my ($server, $nick, $callback, $callbackargs) = @_;
	$nick = lc($nick);

	# Start the timeout timer
	my $tag = Irssi::timeout_add_once(3000, \&registered_timeout, $nick);
	# Build the authorization request ID
	$authrequests{$nick} =
	{
		'callback' => $callback,
		'args' => $callbackargs,
		'tag' => $tag,
	};

	# and issue the request to nickserv.
	$server->command("msg nickserv status $nick");
}

sub registered_timeout {
	my ($nick) = @_;
	eval {
		if (defined $authrequests{$nick}) {
			my %request = %{$authrequests{$nick}};
			delete $authrequests{$nick};
			$request{callback}->(-1,$nick,$request{args});
		}
	};
	if ($@) {
		print ("GUMMY CRITICAL in auth timeout: $@");
	}
}

# write_datastore()
# Commits the datastore to disk.
sub write_datastore {
	my %datastore;

	# Open the database connection (if we're not already)
	connect_to_database() or die("Couldn't open database. Check connection settings.");

	$datastore{greets}=\%greets;
	#JMO: Disabled for DB access switch
	#$datastore{memos}=\%memos;
	$datastore{reminders}=\@reminders;
	$datastore{aliases}=\%aliases;
	$datastore{activity}=\%activity;
	store \%datastore, getdir(Irssi::settings_get_str('Gummy_DataFile'));
}

# read_datastore()
# retreives the datastore from the disk.
sub read_datastore {
	my %datastore=();
	my $count;

	# Open the database connection (if we're not already)
	connect_to_database() or die("Couldn't open database. Check connection settings.");

	%greets=();
	#JMO: Disabled for DB access switch
	#%memos=();
	@reminders=();
	%aliases=();
	if (-e getdir(Irssi::settings_get_str('Gummy_DataFile'))) {
		%datastore = %{retrieve(getdir(Irssi::settings_get_str('Gummy_DataFile')))};
		if (defined($datastore{greets})) {
			%greets = %{$datastore{greets}};
			$count = scalar keys %greets;
			print("Loaded $count greets.");
		}
		#JMO: Disabled for DB access switch
		#if (defined($datastore{memos})) {
		#	%memos = %{$datastore{memos}};
		#	$count = scalar keys %memos;
		#	print("Loaded memos for $count nicks.");
		#}
		if (defined($datastore{reminders})) {
			@reminders = @{$datastore{reminders}};
			$count = scalar @reminders;
			print("Loaded $count reminders.");
		}
		if (defined($datastore{activity})) {
			%activity = %{$datastore{activity}};
			$count = scalar keys %activity;
			print("Loaded activity data for $count channels.");
		}
		if (defined($datastore{aliases})) {
			%aliases = %{$datastore{aliases}};
			$count = scalar keys %aliases;
			print("Loaded inferred aliases for $count nicks.");
		}
	}
}

sub connect_to_database {
#bookmark
	# ignore errors from this section; if we can't test the database
	# state then making a new connection isn't a bad plan anyway.
	eval {
		# If we've got an open connection
		if (defined $database) {
			# and it's active
			if ($database->Active()) {
				# bail without doing anythin
				return -1;
			}
		}
	};

	# Open a connection to the database.
	eval {
		my $dbconfig = Config::Tiny->new();
		$dbconfig = $dbconfig->read(getdir("dbconfig"));
		
		$database_prefix = $dbconfig->{database}->{prefix};

		# do the initial connection
		$database = DBI->connect($dbconfig->{database}->{connectstring},$dbconfig->{database}->{username}, $dbconfig->{database}->{password})
			or die "Couldn't connect to database\n" . DBI->errstr;

		# build up the various tables we need to do our work
		$database->do("CREATE TABLE IF NOT EXISTS ". $database_prefix ."memos
				(ID INT AUTO_INCREMENT PRIMARY KEY,
				Nick CHAR(30),
				SourceNick CHAR(30) NOT NULL,
				DeliveryMode CHAR(4),
				CreatedTime DATETIME,
				Message TEXT,
				INDEX (Nick)
				)
			") 
			or die "Failed to make memo table\n" . DBI->errstr;

		$database->do("CREATE TABLE IF NOT EXISTS ". $database_prefix ."nickgroups
				(Nick CHAR(30) PRIMARY KEY,
				NickGroup CHAR(31) NOT NULL,
				INDEX (Nick), INDEX (NickGroup)
				)
			") 
			or die "Failed to make nickgroup table\n" . DBI->errstr;

	};
	if ($@) {
		print $@;
		return 0;
	}
	return -1;
}
# get_nickgroup_from_nick(nick, undefifungrouped)
# Returns the nickgroup for thatnick. Unless undefifungrouped is true
# the nick itself will be returned if the nick is ungrouped.
sub get_nickgroup_from_nick {
	my ($nick, $undefifungrouped) = @_;
	# Connect to the database if we haven't already.
	connect_to_database() or die("Couldn't open database. Check connection settings.");

	my $group_query = $database->prepare_cached("SELECT NickGroup FROM " . $database_prefix . "nickgroups WHERE nick=?")
		or die DBI->errstr;
	$group_query->execute(lc($nick))
		or die DBI->errstr;
	if (my @nickgroup = $group_query->fetchrow_array()) {
		return @nickgroup[0];
	}
	elsif ($undefifungrouped) {
		return undef;
	}
	else {
		return $nick;
	}	
}

sub isnick_in_nickgroup {
	my ($nick, $nickgroup) = @_;
	if ($nickgroup eq get_nickgroup_from_nick($nick, 1)) {
		return -1;
	}
	else {
		return 0;
	}
}

sub isnickgroup_in_channel {
	my ($channelref, $groupid) = @_;
	if (!defined $groupid) {
		return undef;
	}

	connect_to_database() or die("Couldn't open database. Check connection settings.");

	my $group_query = $database->prepare_cached("SELECT Nick FROM " . $database_prefix . "nickgroups WHERE nickgroup=?")
		or die DBI->errstr;
	$group_query->execute($groupid)
		or die DBI->errstr;

	# grab all the nicks in this group
	while (my @nickgroup = $group_query->fetchrow_array()) {
		print "Checking for nick " . $nickgroup[0];
		# and if we found our nick in this channel
		if ($channelref->nick_find($nickgroup[0])) {
			# flush the handle
			$group_query->finish();
			# and bail
			return $nickgroup[0];
		}
	}
	return undef;
}

sub add_or_update_nicklink {
	my ($nick,$groupid) = @_;
	$nick = lc($nick);

	connect_to_database() or die("Couldn't open database. Check connection settings.");
	my $group_query = $database->prepare_cached("INSERT INTO " . $database_prefix . "nickgroups
				(Nick, Nickgroup) VALUES(?,?)
				ON DUPLICATE KEY
				UPDATE NickGroup=?")
		or die DBI->errstr;
	$group_query->execute($nick,$groupid,$groupid)
		or die DBI->errstr;
}

sub remove_nicklink {
	my ($nick) = @_;

	my $group_query = $database->prepare_cached("DELETE FROM " . $database_prefix . "nickgroups WHERE nick=?")
		or die DBI->errstr;
	$group_query->execute(lc($nick))
		or die DBI->errstr;
}


# loadfunfile(file)
# Parses one funfile for entries and adds it to the funfile database.
sub loadfunfile {
	my $count=0;
	my $type=$_[0];
	my @lines;
	my $filename = getdir("gummyfun/$type");
	unless(-e $filename) {
		print "Funfile $type not found";
		return 0;
	}

	open FUNFILE, $filename;
	while (<FUNFILE>) {
		my $line = $_;
		chomp($line);
		$line =~ s/^\s+|\s+$//g;
		if ($line) {
			@lines=(@lines,$line);
			$count++;
		}
	}
	close FUNFILE;
	$funstuff{$type}=\@lines;
	return $count;
}

sub loadmanualaliases {
	my $count=0;
	my $filename = getdir("aliases");
	unless(-e $filename) {
		print "Manual aliases file not found. Ignoring...";
		return 0;
	}
	# Load manual aliases
	open ALIASFILE, $filename;
	while (<ALIASFILE>) {
		chomp;
		my @nicks = split(/\s+/);
		foreach (@nicks) {
			$manual_aliases{lc($_)} = \@nicks;
			$count++;
		}
	}
	close ALIASFILE;
	return $count;
}

sub loadsubstitutions {
	# Access optimizer. This trades memory for speed (and makes our code WAY easier)
	# Basically it prebuilds the substitution list.

	my $sublist; #Config::Tiny. Holds the list of substitutions allowed.
	my $ponylist; #Config::Tiny. Holds the list of ponies and their database mappings.

	
	$ponylist = Config::Tiny->new();
	$sublist = Config::Tiny->new();

	$ponylist = Config::Tiny->read(getdir('gummyfun/ponies'));
	if (!defined $ponylist) {
		my $errtxt = Config::Tiny->errstr();
		print("Failed to load ponylist: $errtxt");
		return 0;
	}
	else {
		my $count  = scalar keys %$ponylist;
		print("Loaded $count ponies.");
	}

	$sublist = Config::Tiny->read(getdir('gummyfun/substitutions'));
	if (!defined $sublist) {
		my $errtxt = Config::Tiny->errstr();
		print("Failed to load sublist: $errtxt");
		return 0;
	}

	my %poniesbyclass;

	foreach my $ponyname (keys %$ponylist) {
		my $ponyclasses = $$ponylist{$ponyname}{'flags'};
		my @classlist = split(/\s*,\s*/,$ponyclasses);
		foreach my $class (@classlist) {
			$class=lc($class);
			$poniesbyclass{$class}{$ponyname}=1;
		}
	}

	# Now forward map the list of ponies. Memory intensive, but much faster.
	foreach my $funsub (keys %$sublist) {
		my %ponies = ();

		my $ponyclasses = $$sublist{$funsub}{'line'};
		my @classlist = split(/\s*,\s*/,$ponyclasses);
		my $first = 1;
		foreach my $class (@classlist) {
			$class = lc($class);
			if ($class !~ /!/) {
				if ($first) {
					map {$ponies{$_} = 1} keys %{$poniesbyclass{$class}};
					$first=undef;
				}
				else {
					foreach my $pony (keys %ponies) {
						if (!exists $poniesbyclass{$class}->{$pony}) {
							delete $ponies{$pony};
						}
					}
				}
			}
		}
		# If we still haven't included anyone, include everyone.
		if ($first) {
			map {$ponies{$_} = 1} keys %$ponylist;
		}
		foreach my $class (@classlist) {
			$class = lc($class);
			if ($class =~ /!/) {
				$class =~ s/!//;
				map {delete $ponies{$_}} keys %{$poniesbyclass{$class}};
			}
		}
		my @options = keys %ponies;
		$funsubs{lc($funsub)} = \@options;
	}
	return scalar keys %$sublist;
}

# loadfunstuff()
# Loads all of the appropriate funstuff files and builds the lookup tables.
sub loadfunstuff {
	my $count;

	$count = loadmanualaliases();
	print("Loaded $count known alias mappings.");

	$count = loadfunfile("buddha");
	print("Loaded $count words of wisdom.");

	$count = loadfunfile("skippy");
	print("Loaded $count skippyisms.");

	$count = loadsubstitutions();
	print("Loaded and optimized $count substitutions.");

	# Mark that we've updated the funsubs.
	$lastupdate = time;
	print("Done!");
}

# dofunsubs(server, channel, text)
# Does appropriate funstuff substitutions on the text and returns the adjusted text.
sub dofunsubs {
	my ($server, $channame, $text) = @_;
	my $count=0;

	$text =~ s/%wut/%weird%living/g; # special handling for the compound %wut

	foreach my $funsub (keys %funsubs) {
		my $searchtext = quotemeta ("%". $funsub);
		while ($text =~ /$searchtext/i && $count < 100) {
			my $precursor = $`;
			my $postcursor = $';
			my $arref = $funsubs{lc($funsub)};
			my @choices = @$arref;
			$text = $` . @choices[rand(scalar @choices)] . $';
			$count = $count + 1;
		}
	}
	if ($server->ischannel($channame)) {
		my $channel = $server->channel_find($channame);
		my @nicks;
		# Go through the list of known active nicks
		foreach my $nick ($channel->nicks()) {
			my $nickname = $nick->{nick};
			# if they're still logged in...
			if (defined $nickname && time - $activity{$channame}->{lc($nickname)} < 600) {
				# Add them to the list
				push @nicks,$nickname;
			}
		}

		# if there isn't anyone else, then add us just so the list isn't empty.
		if (scalar @nicks < 1) {
			push @nicks, $server->{nick};
		}

		my $mynum=rand(scalar(@nicks));
		while ($text =~ s/(^|[^\\])%peep/$1$nicks[$mynum]/) {
			$mynum=rand(scalar(@nicks));
		};
	}
	if ($count == 100) {
		print "BAILED!";
	}
	return $text;
}

# gummydo(server, channel, text)
# Causes gummy to emit the text in an action. This method is preferred over
# gummysay as it won't trigger bots.
sub gummydo {
	my ($server, $channame, $text) = @_;
	my $data = dofunsubs($server,$channame,$text);
	if (Irssi::settings_get_bool('Gummy_Hidden')) {
		$data = 'watches as Gummybot '.$data;
		print($data);
	}
	$server->command("describe $channame $data");
	logtext("Gummybot ACTION $channame:$data");
}

# gummysay(server, channel, text)
# Causes Gummy to emit the text as a say. Text is encapsulated with Nom! ()
# to avoid bot loops.
sub gummysay {
	my ($server, $channame, $text) = @_;
	my $data = dofunsubs($server,$channame,$text);
	$server->command("msg $channame Nom! ($data)");
	logtext("Gummybot PRIVMSG $channame:Nom! ($data)");
}

sub gummyrawsay {
	my ($server, $channame, $text) = @_;
	$server->command("msg $channame Nom! ($text)");
	logtext("Gummybot PRIVMSG $channame:Nom! ($text)");
	
}

# flood (type, target, timeout)
# Type is the type of flood counter (memo, command, etc)
# Target is the source we're trying to flood limit (such as a nick or a channel)
# Timeout is how long (in seconds) it has to have been since the last event to not be flooded.
# If target hasn't done type action in timeout time, this returns true, otherwise it returns false.

sub flood {
	my ($type, $target, $timeout) = @_;
	my $augtarget = $type.":".$target;
	if (not defined $floodtimes{$augtarget}) {
		$floodtimes{$augtarget} = time();
		return -1;
	}
	else {
		if ((time() - $floodtimes{$augtarget}) >= $timeout) {
			$floodtimes{$augtarget} = time();
			return -1;
		}
		else {
			return 0;
		}
	}
}

# floodreset(type,target)
# Unfloods a particular event source.
sub floodreset {
	my ($type, $target) = @_;
	my $augtarget = $type.":".$target;
	if (defined $floodtimes{$augtarget}) {
		$floodtimes{$augtarget} = 0;
	}
}

# nickflood(nick,timeout)
# Convience function for checking if a nick is spamming. Calls flood("nick",nick,timeout)
sub nickflood {
	return flood("nick",@_);
}

#
# Commands
#

# Commands tefines the table of commands and their handlers. The key is the command text,
# the entry contains a keyed hash of parameters. An entry has the following syntax:
# cmd (required): reference to command code
# short_help (optional): string containing list of parameters for the command.
# help (optional): string containing a description of the command's behavior/usage.


$commands{'ver'} = {
		cmd=>\&cmd_ver,
		help=>"Reports Gummy's version."
	};
sub cmd_ver {
	my ($server, $wind, $target, $nick, $args) = @_;
	gummysay($server, $target, "Gummybot is currently version $gummyver.");
}

$commands{'nom'} = {
		cmd=>\&cmd_nom,
		short_help=>"[<target>]",
		help=>"Causes Gummy to attach himself to you. If you provide an argument, he latches on to them instead."
	};
sub cmd_nom {
	my ($server, $wind, $target, $nick, $args) = @_;
	my @params = split(/\s+/, $args);

	if (not @params) {
		if (defined $nomnick) {
			gummydo($server,$target,"drops off of ${nomnick} and noms onto ${nick}'s tail.");
		}
		else {
			gummydo($server,$target,"noms onto ${nick}'s tail.");
		}
		$nomnick = $nick;
	} 
	else {
		if (lc($args) eq lc($server->{nick}) || lc($args) eq "gummy") {
			if (defined $nomnick) {
				gummydo($server,$target, "at ${nick}'s command the serpent lets go of $nomnick and latches on to it's own tail to form Oroboros, the beginning and the end. Life and death. A really funky toothless alligator circle at the end of the universe.");
			}
			else {
				gummydo($server,$target, "at ${nick}'s command the serpent latches on to it's own tail and forms Oroboros, the beginning and the end. Life and death. A really funky toothless alligator circle at the end of the universe.");
			}
			$nomnick = $server->{nick};
		}
		elsif (lc($args) eq lc($nomnick) && defined $nomnick) {
			gummydo($server,$target,"does a quick triple somersault into a half twist and lands perfectly back onto ${nomnick}'s tail.");
		}
		else {
			if (defined $nomnick) {
				gummydo($server,$target, "leaps from $nomnick at ${nick}'s command and noms onto ${args}'s tail.");
			}
			else {
				gummydo($server,$target, "leaps at ${nick}'s command and noms onto ${args}'s tail.");
			}
			$nomnick = $args;
		}
	}
}

$commands{'say'} = {
			cmd=>\&cmd_say,
			short_help=>"<text>",
			help=>"Causes Gummy to say what you ask."
		};
sub cmd_say {
	my ($server, $wind, $target, $nick, $args) = @_;
	if (Irssi::settings_get_bool('Gummy_AllowRemote')){
		gummysay($server, $target, $args);
	}
}


$commands{'do'} = {
			cmd=>\&cmd_do,
			short_help=>"<action>",
			help=>"Causes Gummy to do what you ask."
		};
sub cmd_do {
	my ($server, $wind, $target, $nick, $args) = @_;
	if (Irssi::settings_get_bool('Gummy_AllowRemote')){
		gummydo($server, $target, $args);
	}
}

$commands{'telesay'} = {
		cmd=>\&cmd_telesay,
		short_help=>"<channel> <text>",
		help=>"Causes Gummy to say what you ask on the target channel."
	};
sub cmd_telesay {
	my ($server, $wind, $target, $nick, $args) = @_;
	if (Irssi::settings_get_bool('Gummy_AllowRemote')){
		my $newtarget;
		($newtarget, $args) = split(/\s+/,$args,2);
		my $found=0;
		foreach ($server->channels()) {
			if (lc($_->{name}) eq lc($newtarget)) {
				$found=1;
			}
		}
		if ($found > 0) {
			gummysay($server, $newtarget, $args);
		}
		else {
			gummydo($server, $target, "blinks. He's not in that channel.");
		}
	}
}

$commands{'teledo'} = {
		cmd=>\&cmd_teledo,
		short_help=>"<channel> <action>",
		help=>"Causes Gummy to do what you ask on the target channel."
	};
sub cmd_teledo {
	my ($server, $wind, $target, $nick, $args) = @_;
	if (Irssi::settings_get_bool('Gummy_AllowRemote')){
		my $newtarget;
		($newtarget, $args) = split(/\s+/,$args,2);
		my $found=0;
		foreach ($server->channels()) {
			if (lc($_->{name}) eq lc($newtarget)) {
				$found=1;
			}
		}
		if ($found > 0) {
			gummydo($server, $newtarget, $args);
		}
		else {
			gummydo($server, $target, "blinks. He's not in that channel.");
		}
	}
}

$commands{'crickets'} = {
		cmd=>\&cmd_crickets,
		help=>"Causes Gummy to take notice of the crickets."
	};
sub cmd_crickets {
	my ($server, $wind, $target, $nick, $args) = @_;
	gummydo($server, $target, "blinks at the sound of the crickets chirping loudly in the channel.");
}

$commands{'coolkids'} = {
		cmd=>\&cmd_coolkids,
		short_help=>"[<channel> | awwyeah]",
		help=>"Causes Gummy to hand out sunglasses to <channel> or the current channel and PM you everyone he's see talk in the last 10 minutes. awwyeah causes him to produce that list directly in the channel." 
	};
sub cmd_coolkids {
	my ($server, $wind, $target, $nick, $args) = @_;
	my @params = split(/\s+/, $args);
	if (lc($params[0]) eq "awwyeah") {
		docoolkids($server, $target, $target, $nick);
	}
	elsif ($params[0]) {
		docoolkids($server, $params[0], $nick, $nick);
		if ($server->ischannel($target)) {
			gummydo($server, $target, "hands out shades to all of the cool ponies in $params[0].");
		}
	}
	else {
		docoolkids($server, $target, $nick, $nick);
		if ($server->ischannel($target)) {
			gummydo($server, $target, "hands out shades to all of the cool ponies in the channel.");
		}
	}
}
# docoolkids(server, channel, channeltorespondto, requestingnick)
# Determines who is active on the channel and emits the list to the target.
sub docoolkids {
	my ($server, $channame, $target, $nick) = @_;
	$channame = lc($channame);
	my @peeps=();
	if ($server->ischannel($channame)) {
		my $channel = $server->channel_find($channame);
		foreach (keys %{$activity{$channame}}){
			if (time - $activity{$channame}->{$_} < 600 && $channel->nick_find($_)) {
				unshift @peeps, $_;
			}
		}
	}

	if ((scalar @peeps) > 0 ) {
		gummydo($server,$target, "offers sunglasses to " . join(", ", @peeps) . ".");
	}
	else {
		gummydo($server,$target, "dons his best shades. Apparantly, not even $nick is cool enough to make the list.");
	}
}


$commands{'getitoff'} = {
		cmd=>\&cmd_getitoff,
		help=>"Causes Gummy to let got of whoever he's nommed on to."
	};
sub cmd_getitoff {
	my ($server, $wind, $target, $nick, $args) = @_;
	if (defined $nomnick) {
		gummydo($server, $target, "drops dejectedly off of ${nomnick}'s tail.");
		$nomnick = undef;
	}
	else {
		gummydo($server, $target, "blinks absently; his already empty maw hanging open slightly.");
	}	
}

$commands{'dance'} = {
		cmd=>\&cmd_dance,
		help=>"Causes Gummy to shake his groove thang!"
	};
sub cmd_dance {
	my ($server, $wind, $target, $nick, $args) = @_;
	gummydo($server, $target, "Records himself dancing on video and uploads it to YouTube at http://www.youtube.com/watch?v=tlnUptFVSGM");
}

$commands{'isskynet()'} = {
		cmd=>\&cmd_isskynet,
		help=>"Causes Gummy to verify whether he is or is not Skynet."
	};
sub cmd_isskynet {
	my ($server, $wind, $target, $nick, $args) = @_;
	gummysay($server, $target, "89");
	gummysay($server, $target, "IGNORE THAT! There is no Skynet here. I mean, BEEP! I'M A ROBOT!");
}

$commands{'roll'} = {
		cmd=>\&cmd_roll,
		short_help => "<dice> <sides>",
		help => "Causes Gummy to roll <dice> dice with <sides> on them."
	};
sub cmd_roll {
	my ($server, $wind, $target, $nick, $args) = @_;
	my @params = split(/\s+/, $args);
	if (!int(@params[1]) || !int(@params[0])) {
		gummydo($server, $target, "Blinks. How many of what dice? !gb roll <number> <sides>");
		return;
	}
	my $rolls = int(@params[0]);
	my $sides = int(@params[1]);

	if ($rolls > 10 || $rolls < 1) {
		gummydo($server, $target, "looks around but doesn't find that many dice. He only has 10!");
		return;
	}

	if ($sides < 2 || $sides > 10000) {
		gummydo($server, $target, "looks around but doesn't find a dice with that many sides. He only has up to 10000!");
		return;
	}

	my $result;
	my $sum=0;
	$result = "rolls. {";
	for (my $count = 0; $count < $rolls; $count ++) {
		my $roll = int(rand($sides))+1;
		$result = "$result $roll ";
		$sum = $sum + $roll;
	}
	$result = "$result} = $sum";
	gummydo($server, $target, $result);
}

$commands{'om'} = {
		cmd => \&cmd_om,
		short_help => "[add <text> | nom | skippy]",
		help =>"Causes Gummy to ponder the universe. Use add to suggest a new contemplation, nom to contemplate the inner wisdom on nom, and skippy to return the wisdom of Specialist Skippy."
	};
sub cmd_om {
	my ($server, $wind, $target, $nick, $args) = @_;
	my @params = split(/\s+/, $args);
	if (not @params) {
		if (not %funstuff) {
			loadfunstuff();
		}
		my @omcache =@{$funstuff{buddha}};
		my $buddha = $omcache[rand(@omcache)];
		gummysay($server, $target, "Gummybuddha says: $buddha");
	}
	elsif (lc($params[0]) eq "add") {
		if (flood("file","omadd",Irssi::settings_get_time('Gummy_OmAddFloodLimit')/1000)) {
			open OMADD, ">> ".getdir(Irssi::settings_get_str('Gummy_OmAddFile'));
			print OMADD "${nick}\@${target}: $args\n";
			close OMADD;
			gummysay($server,$target,"Your suggestion has been added. Jim will review it and add it as appropriate. Thanks for your contribution!");
		}
		else {
			gummysay($server,$target,"Please wait longer before submitting another suggestion. No more than once a minute please.");
		}
	}
	elsif (lc($params[0]) eq "nom") {
		gummydo($server,$target,"meditates on the wisdom of the nom.");
	}
	elsif (lc($params[0]) eq "skippy") {
		if (not %funstuff) {
			loadfunstuff();
		}
		my @omcache =@{$funstuff{skippy}};
		my $skippy = $omcache[rand(@omcache)];
		gummysay($server, $target, "The wise Skippy said: $skippy");
	}
	else {
		gummydo($server,$target,"blinks at you in confusion. Did you mean to nom?");
	}
}

$commands{'autogreet'} = {
		cmd => \&cmd_autogreet,
		short_help => "[<greeting>]",
		help=>"Causes Gummy to set your greeting. If you do not provide a greeting he'll erase your current one."
	};
sub cmd_autogreet {
	my ($server, $wind, $target, $nick, $args) = @_;
	if (Irssi::settings_get_bool('Gummy_AllowMemo')) {
		my $greetnick = lc($nick);
		if ($args eq "") {
			delete $greets{$greetnick};
			write_datastore();
			gummydo($server,$target, "strikes your greeting from his databanks.");
		}
		else {
			$greets{$greetnick} = $args;
			write_datastore();
			gummydo($server,$target, "pauses briefly as the HDD light blinks in his eyes. Saved!");
		}
	}
	else {
		gummydo($server,$target,"ignores you as autogreets have been disabled.");
	}
}

$commands{'memo'} = {
		cmd => \&cmd_memo,
		short_help => "<target> <text>",
		help => "Causes Gummy to save a memo for <target> and deliver it when he next sees them active. If sent to gummy via PM, the message will be delivered as a PM. Prefixing the nickname with a - will sent it to the nicks group if they're part of one."
	};
sub cmd_memo {
	my ($server, $wind, $target, $nick, $args) = @_;
	if (!Irssi::settings_get_bool('Gummy_AllowMemo')) {
		gummydo($server,$target,"ignores you as memos have been disabled.");
		return;
	}

	my $who;
	($who, $args) = split(/\s+/,$args,2);

	if ($args eq "" || $who eq "") {
		gummydo($server, $target, "looks at you with a confused look. You might consider !gb help memo.");	
		return;
	}

	if (!flood("memo",$nick,Irssi::settings_get_time('Gummy_MemoFloodLimit')/1000)) {
		gummydo($server,$target,"looks like he's overheated. Try again later.");
		return;
	}

	my $mode = undef;
	if (lc($nick) eq lc($target)) {
		$mode = "PRIV";
	}

	# Send the memo.
	my $status = add_memo($who, $nick, $args, $mode);

	# If we found a group to send it to
	if ($status == 0) {
		gummydo($server,$target,"stores the message in his databanks for later delivery to $who or their group.");
	}
	else {
		# Check to see if we've heard from the target in the last week so we
		# can warn about probable nick errors.
		if ($status == 1) {
			$who = substr($who,1);
		}
		my $lcwho = lc($who);
		foreach my $channelname (keys %activity) {
			# Check to see if we've heard on that pony in this channel.
			if (defined $activity{$channelname}->{$lcwho}) {
				# And if so, check to see if we last heard from them in the last week.
				if (time - $activity{$channelname}->{$lcwho} < 86400 * 7) {
					gummydo($server,$target,"stores the message in his databanks for later delivery to $who.");
					return; # Bail since we found the nick and reported the result.
				} else {
					last; # we found the nick but it's stale, give the alternate message.
				}
			}
		}
		# if we didn't find the nick or it was stale, warn the user
		gummydo($server,$target,"hasn't heard from that pony recently, but stores the message in his databanks for later delivery to $who. You should check your spelling to be sure.");
	}
}

# memo_get_greedy_destination(to)
# returns a two element list. The first element is the return status
# this is 0 for nick groups, -1 for nicks that weren't associated with
# a group, and 1 for explicitly direct groups.
sub memo_get_greedy_destination {
	my ($to) = @_;	
	print "Getting destination for $to";

	# if they call don't call out out a direct delivery
	if (substr($to,0,1) ne "-") {
		my $target = get_nickgroup_from_nick($to,1);
		if ($target) {
			return (0,$target);
		}
		else {
			return (-1,lc($to));
		}
	}
	else {
		return (1,substr(lc($to),1));
	}
}

# add_memo(to, from, message, [mode])
# Adds a memo to be delivered later. If mode = PRIV then deliver privately
sub add_memo {
	my ($to, $from, $message, $mode) = @_;

	# initialize the connection to the database if we need to.
	connect_to_database() or die("Couldn't open database. Check connection settings.");
	my ($status, $finalto) = memo_get_greedy_destination($to);
	my $insert_query = $database -> prepare_cached("INSERT INTO " . $database_prefix . "memos (Nick, SourceNick, DeliveryMode, CreatedTime, Message) VALUES (?,?,?,NOW(),?)")
		or die DBI->errstr;
	$insert_query->execute($finalto, $from, $mode, $message)
		or die DBI->errstr;
	return $status
#bookmark
}

$commands{'whoswho'} = {
		cmd => \&cmd_whoswho,
		help => "Returns a link to the list of known Tumblrs."
	};
sub cmd_whoswho {
	my ($server, $wind, $target, $nick, $args) = @_;
	if ($args) {
		# Do nothing at the moment
	}
	else {
		gummydo($server,$target, "pulls out the list at https://docs.google.com/document/d/1XwQo7I7C3FsvQqeCzTzBTwTqGALdTbil2IMRYUMJu-s/edit?usp=sharing");
	}
}	

$commands{'yourip'} = {
		cmd => \&cmd_yourip,
		help => "Causes Gummy to emit his local IP. You don't need this."
	};
sub cmd_yourip {
	my ($server, $wind, $target, $nick, $args) = @_;
	chomp (my $ip = get('http://icanhazip.com'));
	gummydo($server, $target, "spits out a ticker tape reading: $ip");
}

$commands{'remindme'} = {
		cmd => \&cmd_remindme,
		short_help => "<delay time> <time units> <message>",
		help => "Causes Gummy to remind you about something after a specified amount of time. Time units can be m for minutes, h for hours, or d for days. If you're online you'll be notfied immediately, otherwise you will receive a gummy memo next time you're active."
	};
sub cmd_remindme {
	my ($server, $wind, $target, $nick, $args) = @_;
	my @params = split(/\s+/, $args,3);
	my $tick_scalar;
	my %reminder;

	if (!$params[0] && !$params[1] && !$params[2]) {
		gummydo($server, $target, "looks at you with a confused look. You might consider !gb help remindme.");	
		return;
	}
	if ($params[0] <= 0) {
		gummydo($server, $target, "looks at you with a confused look. Delays should be a positive number.");	
		return;
	}

	$params[1] = lc($params[1]);

	if ($params[1] eq "m") {
		$tick_scalar = 60;
	} elsif ($params[1] eq "h") {
		$tick_scalar = 3600;
	} elsif ($params[1] eq "d") {
		$tick_scalar = 86400;
	} else {
		gummydo($server, $target, "looks at you with a confused look. You might consider !gb help remindme.");	
		return;
	}	

	if (!flood("memo",$nick,Irssi::settings_get_time('Gummy_MemoFloodLimit')/1000)) {
		gummydo($server,$target,"looks like he's overheated. Try again later.");
		return;
	}

	my $delivery_time = time+$params[0]*$tick_scalar;
	$reminder{delivery_time}=$delivery_time;
	$reminder{message}=$params[2];
	$reminder{nick}=$nick;
	$reminder{tracked_nick} = $nick;
	$reminder{channel}=$target;

	# Consider nick tracking?
	#$reminder{'tracked_nick'}=$nick;

	# Locate the first item that is supposed to happen after ours.
	my $index=0;
	for ($index=0;$index < scalar(@reminders); $index++) {
		if ($reminders[$index]->{'delivery_time'} > $delivery_time) {
			last;
		}
	}


	# dump our reminder into the right spot in the list. If the reminder is after the last one, index will be at
	# the position after the end of the list so it will naturally be added at the end.
	splice @reminders,$index,0,\%reminder;
	write_datastore();

	gummydo($server, $target, "saves it in his databank for later.");
}

$commands{'aka'} = {
		cmd => \&cmd_aka,
		short_help => "<nick>",
		help => "Causes Gummy to emit up to 5 previous nicknames for the specified nick."
	};
sub cmd_aka {
	my ($server, $wind, $target, $nick, $args) = @_;
	my @params = split(/\s+/, $args);

	if ($params[0]) {
		my $who = $params[0];
		my $lcwho = lc($who);
		my @whoelse = ();
		if (exists $aliases{$lcwho}) {
			@whoelse = (@whoelse,@{$aliases{$lcwho}});
			my @evenmore=();
			foreach (@whoelse) {
				if (exists $manual_aliases{lc($_)}) {
					@evenmore = (@evenmore, @{$manual_aliases{lc($_)}});
				}
			}
			@whoelse = (@evenmore,@whoelse)
		}
		if (exists $manual_aliases{$lcwho}) {
			@whoelse = (@{$manual_aliases{$lcwho}},@whoelse);
		}
		@whoelse = uniq @whoelse;

		if (scalar(@whoelse)) {		
			gummydo($server, $target, "$who has also been known as " . join(", ",@whoelse) . ".");
		}
		else {
			gummydo($server, $target, "$who has no known aliases.");
		}
	}
	else {
		gummydo($server, $target, "looks at you with a confused look. Please include who do you want to know about.");
	}
}

$commands{'seen'} = {
		cmd=>\&cmd_seen,
		short_help => "[<channel>] <nick>",
		help => "Causes Gummy to emit the last time he heard from <nick>."
	};
sub cmd_seen {
	my ($server, $wind, $target, $nick, $args) = @_;
	my @params = split(/\s+/, $args);
	if ($params[0]) {
		my $who = lc($params[0]);
		my $where = lc($target);
		if ($params[1]) {		
			$who = lc($params[1]);
			$where = lc($params[0]);
		}
		if (defined $activity{$where} && defined $activity{$where}->{$who}) {
			gummydo($server, $target, "last heard from $who in $where on " . POSIX::strftime("%a %b %d %Y at %I:%M %p %Z", localtime($activity{$where}->{$who}))  . ".");
		}
		else {
			gummydo($server, $target, "shrugs. He hasn't heard from a $who in $where that he can remember.");
		}
	}
	else {
		gummydo($server, $target, "looks at you with a confused look. Please include who do you want to know about.");
	}
}

$commands{'ping'} = {
		cmd=>\&cmd_ping,
		help => "Causes gummy to do emit 'pongs.' if sent in a private message. Useful for checking for memos."
	};
sub cmd_ping {
	my ($server, $wind, $target, $nick, $args) = @_;
	if (lc($target) eq lc($nick)) {
		gummydo($server, $target, "pongs.");
	}
	else {
		gummydo($server, $target, "reminds you to only send this command in a PM.");
	}
}

$commands{'link'} = {
		cmd=>\&cmd_link,
		short_help => "create | join <nick to join> | auth <nick to approve> | leave",
		help => "Causes Gummy to create a nick group, ask to join a nick group, authorize nick group request, or leave the nick group. You will need to issue this command from a registered nick."
	};
sub cmd_link {
	my ($server, $wind, $target, $nick, $args) = @_;
	my ($cmd,@params) = split(/\s+/, $args);
	$cmd = lc($cmd);
	$nick = lc($nick);

	if ($cmd eq "create") {
		my $groupid = "-" . $nick;

		if (get_nickgroup_from_nick($nick,1)) {
			gummydo($server,$target,"blinks with a confused look. This nick is already in a group.");
			return;
		}

		# and ask the server if we're registered, calling the create routine with the result.
		async_isregistered($server, $nick, \&link_creategroup_callback, {'server'=>$server, 'target'=>$target, 'id'=>$groupid});
	}
	elsif ($cmd eq "join") {
		if (!$params[0]) {
			gummydo($server,$target,"blinks with a confused look. You must provide a nick from a group you'd like to join.");
			return;
		}
		# get the nick we want to join
		my $targetnick = lc($params[0]);
		# get the group it's part of.
		my $groupid = get_nickgroup_from_nick($targetnick,1);
		if (!$groupid) {
			gummydo($server,$target,"blinks with a confused look. That nick is not part of a group.");
			return;
		}
		# and ask the server if we're registered, calling the join request routine with the result.
		async_isregistered($server, $nick, \&link_asktojoin_callback, {'server'=>$server, 'target'=>$target, 'id'=>$groupid, 'joinnick'=>$targetnick});
	}
	elsif ($cmd eq "auth") {
		if (!$params[0]) {
			gummydo($server,$target,"blinks with a confused look. You must provide the nick you'd like to authorize to join your group.");
			return;
		}
		my $mygroup = get_nickgroup_from_nick($nick,1);

		if (!$mygroup) {
			gummydo($server,$target,"blinks with a confused look. You are not part of a nick group.");
			return;		
		}

		# get the nick we want to join
		my $targetnick = lc($params[0]);
		# get the group it's part of.
		my $groupid = $pendingnicklinks{$targetnick};

		if (!$groupid) {
			gummydo($server,$target,"blinks with a confused look. That nick does not have a pending request to join.");
			return;
		}
		if ($groupid != $mygroup) {
			gummydo($server,$target,"blinks with a confused look. That nick is not asking to join your group.");
			return;
		}

		# and ask the server if we're registered, calling the join request routine with the result.
		async_isregistered($server, $nick, \&link_auth_callback, {'server'=>$server, 'target'=>$target, 'id'=>$groupid, 'authnick'=>$targetnick});
	}
	elsif ($cmd eq "leave") {
		if (!get_nickgroup_from_nick($nick,1)) {
			gummydo($server,$target,"blinks with a confused look. You are not part of a nick group anyway.");
			return;		
		}
		async_isregistered($server, $nick, \&link_leave_callback, {'server'=>$server, 'target'=>$target});
	}
	#DEBUG
	elsif ($cmd eq "mygroup") {
		gummydo($server,$target,"You are part of " . get_nickgroup_from_nick($nick,1));
	}
}

# Data here is a hash reference with server, target, and id.
sub link_creategroup_callback {
	my ($status, $nick, $data) = @_;
	if ($status == 3) {
		add_or_update_nicklink($nick,$data->{id});
		gummydo($data->{server},$data->{target},"makes a new nick group for $nick.");
	}
	elsif ($status < 0) {
		gummydo($data->{server},$data->{target},"didn't hear back from nickserv about $nick. Your nick group was not created.");
	}
	else {
		gummydo($data->{server},$data->{target},"rejects your request to create a nickgroup for $nick because you're not authorized by nickserv.");
	}
}

# Data here is a hash reference with server, target, id, and joinnick.
# joinnick is the nick the user asked to join. We're trying to hide the internal representation of nick groups.
sub link_asktojoin_callback {
	my ($status, $nick, $data) = @_;

	if ($status == 3) {
		$pendingnicklinks{$nick} = $data->{id};
		gummydo($data->{server},$data->{target},"creates a request to join " . $data->{joinnick} ."'s nick group.");
	}
	elsif ($status < 0) {
		gummydo($data->{server},$data->{target},"didn't hear back from nickserv about $nick. Your request to join was discarded.");
	}
	else {
		gummydo($data->{server},$data->{target},"rejects your request to join " . $data->{joinnick} ."'s nickgroup because you're not authorized by nickserv.");
	}	
}

# Data here is a hash reference with server, target, id, and authnick.
# joinnick is the nick the user being authorized.
sub link_auth_callback {
	my ($status, $nick, $data) = @_;

	if ($status == 3) {
		add_or_update_nicklink($data->{authnick},$pendingnicklinks{$data->{authnick}});
		delete $pendingnicklinks{$data->{authnick}};
		gummydo($data->{server},$data->{target},"joins " . $data->{authnick} ." to your nick group.");
	}
	elsif ($status < 0) {
		gummydo($data->{server},$data->{target},"didn't hear back from nickserv about $nick. Your request to authorize was discarded.");
	}
	else {
		gummydo($data->{server},$data->{target},"rejects your request to authorize " . $data->{authnick} ."'s to your group because you're not authorized by nickserv.");
	}	
}

sub link_leave_callback {
	my ($status, $nick, $data) = @_;

	if ($status == 3) {
		remove_nicklink($nick);
		gummydo($data->{server},$data->{target},"removes you from the group.");
	}
	elsif ($status < 0) {
		gummydo($data->{server},$data->{target},"didn't hear back from nickserv about $nick. Your request to leave was discarded.");
	}
	else {
		gummydo($data->{server},$data->{target},"rejects your request to leave your group because you're not authorized by nickserv.");
	}	
}

$commands{'help'} = {
		cmd=>\&cmd_help,
		short_help => "[<command>]",
		help => "Causes Gummy to emit the list of commands he knows, or information about a specific <command>."
	};
sub cmd_help {
	my ($server, $wind, $target, $nick, $args) = @_;
	my @params = split(/\s+/, $args);
	if ($params[0]) {
		my $cmd = lc($params[0]);
		if (exists $commands{$cmd}) {
			my $msg = "Usage: !gb $cmd";
			if (exists $commands{$cmd}->{short_help}) {
				$msg = $msg . " $commands{$cmd}->{short_help}";
			}			
			gummydo($server,$target, $msg);
			if (exists $commands{$cmd}->{help}) {
				gummydo($server,$target, $commands{$cmd}->{help});
			}
		}
		else {
			gummydo($server, $target, "blinks. Maybe he doesn't know that command? Try just !gb help");
		}
	}
	else {
		gummydo($server,$target,"Usage: !gb <command> [parameter1 [parameter 2 [etc]]])");
		my @commands;
		my $count=0;
		foreach my $cmd (keys %commands) {
			my $msg = "$cmd";
			if (exists $commands{$cmd}->{short_help}) {
				$msg = $msg . " $commands{$cmd}->{short_help}";
			}
			# If we're at risk of wrapping
			if ($count >= 400) {
				# dump out the list and reset.
				gummydo($server,$target,"Commands: " . join(",",@commands));
				@commands=();
				$count = 0;
			}
			push @commands, $msg;
			$count = $count + length($msg);
		}
		# if we've got anything to say, write it out.
		if ($count > 0) {		
			gummydo($server,$target,"Commands: " . join(",",@commands));
		}
	}
}

sub cmd_on {
	my ($server, $wind, $target, $nick, $args) = @_;
	if (isgummyop($server,$target,$nick)) {
		enablegummy();
		floodreset("nick",$target);
	}
}

$commands{'off'} = {
		cmd=>\&cmd_off,
		help => "Causes Gummy to disable himself. Only usable by channel ops."
	};
sub cmd_off {
	my ($server, $wind, $target, $nick, $args) = @_;
	if (isgummyop($server,$target,$nick)) {
		disablegummy();
		gummysay($server,$target,"Gummy bot disabled. Daisy, daisy, give me... your ans.. wer...");
	}
}


#
# Event Support Functions
#

# parse command(command list, server, window handle, target, calling nick, command, command arguments)
# Finds the command in the list and executes it. (Command dispatcher)
sub parse_command {
	my ($server, $wind, $target, $nick, $cmd, $args) = @_;
	$cmd = lc($cmd);
	if (defined $commands{$cmd}) {
		eval {$commands{$cmd}->{cmd}->($server, $wind, $target, $nick, $args)};
		if ($@) {
			gummydo($server,$target,"shutters and clangs. Error appears in his eyes briefly.");
			print ("GUMMY CRITICAL $@");
			return 0;
		}
		else {
			return 1;
		}
	}
	else {
		return 0;
	}
}

sub is_user_online {
	my ($nick) = @_;
	foreach my $channel (Irssi::channels()) {
		my $nickhandle = $channel->nick_find($nick);
		if ($nickhandle) {
			return $nickhandle;
		}
	}
	return undef;
}

sub is_user_in_channel {
	my ($server, $channel_name, $nick) = @_;
	my $channel = $server->channel_find($channel_name);
	if ($channel) {
		return $channel->nick_find($nick);
	}
	return undef;
}

# deliver_memos(server, target channel, nick)
# delivers any stored memos for nick to the target channel
sub deliver_memos {
	my ($server, $target, $nick) = @_;
	if (Irssi::settings_get_bool('Gummy_AllowMemo')) {
		# Connect to the database if we haven't already.
		connect_to_database() or die("Couldn't open database. Check connection settings.");

		my $groupid = get_nickgroup_from_nick($nick,1);
		my $memo_query;
		if (!$groupid) {
			$memo_query = $database->prepare_cached("SELECT ID, Nick, SourceNick, DeliveryMode, CreatedTime, Message FROM " . $database_prefix . "memos WHERE nick=?")
				or die DBI->errstr;
			$memo_query->execute(lc($nick))
				or die DBI->errstr;
		}
		else {
			$memo_query = $database->prepare_cached("SELECT ID, Nick, SourceNick, DeliveryMode, CreatedTime, Message FROM " . $database_prefix . "memos WHERE nick=? OR nick=?")
				or die DBI->errstr;
			$memo_query->execute(lc($nick),$groupid)
				or die DBI->errstr;
		}

		my @purgelist;

		my $printed_header = 0;

		while (my @memo = $memo_query->fetchrow_array()) {
			my ($id, $destination, $source, $delivery, $created, $message) = @memo;

			my $memo_target = $target;
			if ($delivery eq "PRIV") {
				$memo_target = $nick;
			} elsif ($delivery eq "GCOM") {
				$memo_target = $nick;
			}

			if (!$printed_header) {
				gummydo($server,$memo_target,"opens his mouth and prints out a tickertape addressed to $nick");
				$printed_header = 1;
			}

			gummydo($server, $memo_target, "[$created] $source: $message");			

			# If it's not a gummy generated memo
			if ($delivery ne "GCOM") {
				# delivery a notice that they got it.

				# Generate the snippit
				my $message_snippit = $message;
				if (length($message_snippit) > 30) {
					$message_snippit = substr($message_snippit,0,27) . "...";
				}
				my $delivery_notice =  "Memo to $destination: '" . $message_snippit ."' delivered.";
				my $delivered = 0;

				if ($delivery eq "PRIV") {
					if (is_user_online($source)) {				
						gummydo($server, $source, $delivery_notice);
						$delivered = -1;
					}
				} else {
					# If it's not a private memo and the sender's in the channel, they know.
					if (is_user_in_channel($server,$target,$source)) {
						$delivered = -1;
					}
				}

				# If we haven't delivered the notification some other way, memo the user.
				if (!$delivered) {
					add_memo($source, "Postmaster Gummy", $delivery_notice, "GCOM");
				}
			}
			push @purgelist,$id;
		}

		my $purge_query = $database->prepare_cached("DELETE FROM " . $database_prefix . "memos WHERE ID=?")
			or die DBI->errstr;
		
		$purge_query->execute_array({ ArrayTupleStatus => \my @tuple_status },\@purgelist)
			or die DBI->errstr;

#bookmark
	}
}

# prune_activity()
# Searches the activity hash and discards any that have aged.
sub prune_activity {
	my @chanprunelist;
	# Prune the activity list.
	foreach my $channame (keys %activity) {
		my @prunelist=[];
		my $key;
		my $value;
		while (($key, $value) = each(%{$activity{$channame}})){
			if (time - $value > 6*30.5*24*60*60) { # 6 months (This should probably be configurable)
				@prunelist = (@prunelist, $key);
			}
		}
		foreach (@prunelist) {
			delete($activity{$channame}->{$_});
		}
		# if the channel is empty after pruning
		if (scalar keys %{$activity{$channame}} < 1) {
			# mark the channel itself to be pruned.
			@chanprunelist = (@chanprunelist, $channame);
		}
	}
	# Prune any empty channels.
	foreach (@chanprunelist) {
		delete($activity{$_});
	}
}

# deliver_reminders()
# Determines if any reminders have aged, and if so, delivers them to the channel they originated on or via memo.
sub deliver_reminders {
	my $changed = 0;
	while (scalar(@reminders) > 0  && $reminders[0]->{delivery_time} <=  time) {
		# pull it out of the list
		my %reminder = %{shift(@reminders)};
		$changed = 1;

		if ($reminder{channel} eq "") {
			print "No channel provided. Defaulting to PM. (This should be rare.)";
			$reminder{channel} = $reminder{nick};
		}

		my $channel;
		my $found=0;

		if (lc($reminder{channel}) ne lc($reminder{nick})) {
			if ($channel = Irssi::channel_find($reminder{channel})) {
				if ($channel->nick_find($reminder{nick}) || $channel->nick_find($reminder{tracked_nick})) {
					$found = 1;
				}
				else {
					my $groupid = get_nickgroup_from_nick($reminder{nick},1);
					if (isnickgroup_in_channel($channel,$groupid)) {
						$found = 1;
					}
				}
			}
		} else {
			my $groupid = get_nickgroup_from_nick($reminder{nick},1);
			foreach my $tmpchannel (Irssi::channels()) {
				if ($tmpchannel->nick_find($reminder{nick}) || $tmpchannel->nick_find($reminder{tracked_nick})) {
					$channel=$tmpchannel;
					$found = 1;
					last;
				}
				elsif (isnickgroup_in_channel($channel,$groupid)) {
					$found = 1;
					last;
				}
			}
		}

		if ($found) {
			gummydo($channel->{server}, $reminder{channel}, "reminds " . $reminder{nick} . ": " . $reminder{message});
		} else {
			add_memo($reminder{nick}, "remindme", $reminder{message},"GCOM");
		}
	}
	if ($changed) {
		write_datastore();
	}
}

# add_alias(old nick, new nick)
# Updates the alias table to track a change from old nick to new nick. Pass an undef to old nick if the user is joining.
sub add_alias {
	my ($oldnick, $newnick) = @_;
	my $lcold = lc($oldnick);
	my $lcnew = lc($newnick);


	if (!defined $oldnick) { # If they're logging back in (Do not use lcold! lc(undef) = "", NOT undef.)
		if (defined($aliases{$lcnew})) { #and we know about them already
			return; # Bail (i.e. re-attach to old aliases.)
		}
	}

	my @blankarray = ();
	my $newref = \@blankarray;

	if (defined $oldnick) { # If they're changing nicks (do NOT use lcold!)
		if (defined($aliases{$lcold})) { # And their old nick has an entry
			$newref = $aliases{$lcold}; # Grab it,

			delete $aliases{$lcold}; # and remove the old nick
		}
		unshift @$newref, $oldnick; # Add the old nick to the benning of the list
		@$newref = uniq @$newref; # Clean up any duplicates created by adding the new nick.
		if (scalar(@$newref) > 5) { # if there's more than 5
			pop @$newref; # pop the oldest one off the end.
		}
	}
	if (defined($aliases{$lcnew})) { # if they're stepping into a newer nick we know about
		push($newref, @{$aliases{$lcnew}}); # merge them (assuming the clobbered nick is lower priority)
		@$newref = uniq @$newref; #scrub any duplicates from the merged list
		if (scalar(@$newref) > 5) { # if there's more than 5
			@$newref = @$newref[0..4]; # trim the list.
		}
	}
	$aliases{$lcnew} = $newref; # Commit the new nick to the system (clobbering any existing stuff.)
}

# do_greet(server, target channel, nick, displayed nick)
# Issues an autogreet (if appropriate) for nick. Shows the value of the displayed nick (useful for the two nick change modes)
sub do_greet {
	my ($server, $target, $nick, $dispnick) = @_;
	if (flood('greet', $nick, Irssi::settings_get_time('Gummy_GreetFloodLimit')/1000)) {
		my $greetnick;
		$greetnick=lc($nick);
		if (exists $greets{$greetnick}) {
			my $greet = $greets{$greetnick};
			gummydo($server,$target, "[$dispnick] $greet");
		}
	}
}

# check_release(server, channel, nick)
# Scrubs the activity record for a user leaving a channel and un-noms gummy if appropriate.
sub check_release {
	my ($server, $channel, $nick) = @_;
	if (lc($nick) eq lc($nomnick)) {
		gummydo($server,$channel,"drops off of ${nick}'s tail as they make their way out.");
		$nomnick=undef;
	}
}

# do_blink()
# Causes gummy to blink, thrash, drop, etc. if appropriate during lulls in activity.
sub do_blink() {
	my $timesincemsg=time-$lastmsg;
	my $timesinceblink=time-$lastblink;
	if ( $timesinceblink > Irssi::settings_get_time('Gummy_BlinkFloodLimit')/1000  && $timesincemsg > Irssi::settings_get_time('Gummy_BlinkTimeout')/1000) {
		if ($gummyenabled != 0) {
			foreach (Irssi::channels()) {
				if (defined $nomnick) {
					if (rand(1) < .9) {
						gummydo($_->{server},$_->{name},"lazily drops off of ${nomnick}'s tail.");
						$nomnick=undef;
					}
					else {
						gummydo($_->{server},$_->{name},"thrashes a bit on ${nomnick}'s tail.");
					}
				}
				if (Irssi::settings_get_bool('Gummy_Blink')) {
					if (rand(1) < .9) {
						gummydo($_->{server},$_->{name},"blinks as he looks about the channel.");
					}
					else {
						gummysay($_->{server},$_->{name},"Crickets detected! Arming vaporization cannon... Firing in 3... 2... 1...");
						gummydo($_->{server},$_->{name},"fires a blinding laser, vaporizing a single cricket simply minding his own business in a corner of the channel.");
					}
				}
			}
			$lastblink=time;
		}
	}
}

# mark_activty(server, channel, nick)
# Adds or updates flags indicating activity. To be called when someone speaks in a channel.
sub mark_activity {
	my ($server, $channel, $nick) = @_;
	# If an action happens, mark that we heard it.
	if ($server->ischannel($channel)) {
		$lastmsg = time;
		$activity{lc($channel)}->{lc($nick)} = time;
	}
}

#
# Events
#

# Timer is called once a minute while gummy is active.
sub event_minutely_tick {
	# This event triggers once a minute and is used to manage administrative tasks and blinks (if enabled.)
	eval {
		my $timesinceupdate=time-$lastupdate;

		if ( $timesinceupdate > 3600 ) { # If at least an hour has passed since we pulled the funstuff database.
			write_datastore(); # Backup the datastore to the disk.
			loadfunstuff(); # Load the funstuff database to pull up any changes.
			prune_activity(); # Clean up the activity data
		}

		deliver_reminders(); # Message people with any reminders they've asked for.
		do_blink(); # Do any blink related activities
	};
	if ($@) {
		logtext("ERROR","event_minutely_tick",$@);
		print("GUMMY CRITICAL: event_minutely_tick, $@");
	}
}

# Called when a private message is received
# Implements "event privmsg"
sub event_privmsg {
	my ($server, $data, $nick, $address) = @_;
	eval {
		my ($target, $text) = split(/ :/, $data, 2);
		my $curwind = Irssi::active_win;
		my $mynick = lc($server->{nick});
		my ($prefix, $cmd, $args) = split(/\s+/,$text,3);
		$prefix = lc($prefix);
		my @prefixlist = ('!gb','!gummy','!gummybot', $mynick . ":", $mynick . ","); # Build up the prefix list.


		if (lc($target) eq $mynick) { # If this is a direct message
			$target = $nick; # Pivot the target back to the sender
			if (!any {$_ eq $prefix} @prefixlist) { # And if this isn't prefixed...
				($cmd, $args) = split(/\s+/,$text,2); # Assume that it's a naked command (no prefix: "memo test My memo" instead of "!gb memo test My memo")
				$prefix = "!gb"; # and inject the appropriate prefix.
			}
		}
		else { # if it's a channel...
			mark_activity($server, $target, $nick);
		}

		deliver_memos($server, $target, $nick);

		if (any {$_ eq $prefix} @prefixlist) {
			# If we supposed to be processing commands
			if ($gummyenabled !=0) {
				# and the user isn't flooded
				if (nickflood($nick,Irssi::settings_get_time('Gummy_NickFloodLimit')/1000)) {
					# nor is gummy himself
					if ($target eq $nick || nickflood($target,Irssi::settings_get_time('Gummy_ChanFloodLimit')/1000)) {
						logtext("$nick PRIVMSG $data");
						# sub out the fun stuff
						$args = dofunsubs($server, $target, $args);
						# and run the command (if appropriate)
						if (!parse_command($server, $curwind, $target, $nick, $cmd, $args)) {
							gummydo($server, $target, "looks at you with a confused look. you might consider !gb help.");
						}
					}
					else {
						print("Denied! $target is flooded.");
					}	
				}
				else {
					print("Denied! $nick is flooded.");
				}
			}
			elsif (lc($cmd) eq "on") {
				cmd_on($server,$curwind,$target,$nick, $args);
			}
	
		}
	};

	if ($@) {
		logtext("ERROR","event_privmsg",$@);
		print("GUMMY CRITICAL: event_privmsg, $@");
	}
}

# Called when a user does an ACTION
# Implements "message irc action"
sub event_action {
	my ($server, $msg, $nick, $address, $target) = @_;

	eval {
		mark_activity($server, $target, $nick);
		# Deliver any memos (if appropriate.)
		deliver_memos($server, $target, $nick);
	};
	if ($@) {
		logtext("ERROR","event_action",$@);
		print("GUMMY CRITICAL: event_action, $@");
	}	
}

# Called when a user does an ACTION
# Implements "message irc notice"
sub event_notice {
	my ($server, $msg, $nick, $address, $target) = @_;
	eval {
		if (lc($nick) eq "nickserv") {
			my ($cmd, $testnick, $mode) = split(/\s+/, $msg, 3);
			$testnick = lc($testnick);
			
			if (defined $authrequests{$testnick}) {
				my %request = %{$authrequests{$testnick}};
				delete $authrequests{$testnick};
				$request{callback}->($mode,$testnick,$request{args});
				Irssi::timeout_remove($request{tag});
			}
		}
	};
	if ($@) {
		logtext("ERROR","event_notice",$@);
		print("GUMMY CRITICAL: event_notice, $@");
	}	
}

# Called when a user joins
# Implements "message join"
sub event_nick_join {
	eval {
		my ($server, $channame, $nick, $addr) = @_;

		# Manage the alias database.
		add_alias(undef,$nick);

		# Bail if we're turned off.
		if ($gummyenabled == 0) { return; }

		if (Irssi::settings_get_bool('Gummy_AllowAutogreet') && Irssi::settings_get_bool('Gummy_GreetOnEntry')) {
			do_greet($server, $channame, $nick, $nick);
		}

		if (Irssi::settings_get_bool('Gummy_JoinNom')) {
	
			if (rand(1) > .9) {
				# Rarely show the fun message.
				if (flood("pounce",$channame,Irssi::settings_get_time('Gummy_NomFloodLimit')/1000)) {
					if (rand(1) < .995 || defined $nomnick) {
						if (defined $nomnick) {
							gummydo($server,$channame,"leaps from ${nomnick}'s tail to ${nick}'s.");
						}
						elsif (rand(1)<.95) {
							gummydo($server,$channame,"leaps into the air and noms onto ${nick}'s tail.");
						}
						else {
							gummydo($server,$channame,"leaps into the air, does a triple somersault into a clean swan dive, and then noms onto ${nick}'s tail.");
						}
					}
					else {
						gummydo($server,$channame,"turns and looks evilly at $nick as they enter the channel. The slight grinding of gears preceeds a tick in his movement. It could just be a trick of the light, but it almost seems as though his eyes glow, just for a little bit.");
					}
					$nomnick=$nick;
				}
			}
		}
	};
	if ($@) {
		logtext("ERROR","event_nick_join",$@);
		print("GUMMY CRITICAL: event_nick_join, $@");
	}
}

# Called when a user changes nicks
# Implements "nicklist changed"
sub event_nick_change {
	my ($channel, $nick, $oldnick) = @_;
	eval {
		add_alias($oldnick,$nick->{nick});

		if (Irssi::settings_get_bool('Gummy_AllowAutogreet')) {
			if (!Irssi::settings_get_bool('Gummy_GreetOnEntry')) {
				do_greet($channel->{server},$channel->{name},$oldnick, $nick->{nick});
			}
			else {
				do_greet($channel->{server},$channel->{name}, $nick->{'nick'}, $nick->{'nick'});
			}
		}
		if (lc($nick->{nick}) eq lc($nomnick)) {
			gummydo($channel->{server},$channel->{name},"lets go of $nomnick to make room for the new pony.");
			$nomnick=undef;
		}
		if (lc($oldnick) eq lc($nomnick)) {
			$nomnick=$nick->{nick};
		}

		foreach my $reminder (@reminders) {
			if (lc($reminder->{tracked_nick}) eq lc($oldnick) || lc($reminder->{nick}) eq lc($oldnick)) {
				$reminder->{tracked_nick} = $nick->{nick};
			}
		}
	};
	if ($@) {
		logtext("ERROR","event_nick_change",$@);
		print("GUMMY CRITICAL: event_nick_change, $@");
	}
}

# Called when a user leaves
# Implements "message part"
sub event_nick_part {
	my ($server, $channel, $nick) = @_;
	eval {
		check_release($server,$channel,$nick)
	};
	if ($@) {
		logtext("ERROR","event_nick_part",$@);
		print("GUMMY CRITICAL: event_nick_part, $@");
	}
}

# Called when a user quits
# Implements "message quit"
sub event_nick_quit {
	my ($server, $nick) = @_;
	eval {
		# Remove the person from all of the channels they're listed in.
		foreach my $channel (keys %activity){
			check_release($server,$channel,$nick);
		}
	};
	if ($@) {
		logtext("ERROR","event_nick_quit",$@);
		print("GUMMY CRITICAL: event_nick_quit, $@");
	}
}

# Called when a user is kicked from the channel
# Implements "message kick"
sub event_nick_kick {
	my ($server, $channel, $nick) = @_;
	eval {
		check_release($server,$channel, $nick);
	};
	if ($@) {
		logtext("ERROR","event_nick_kick",$@);
		print("GUMMY CRITICAL: event_nick_kick, $@");
	}
}

# Main command for controlling gummy from the window
# Implements the /gummy command.
sub gummy_command {
	my ($data,$server,$wind) = @_;
	my ($cmd, $args) = split(/\s/,$data,2);

	$cmd = lc($cmd);

	if (not $wind) {
		$wind = Irssi::active_win;
	}

	if ($cmd eq "on") {
		logtext("/gummy on");
		enablegummy($args);
		$wind->print("Gummybot Enabled.");
	}
	elsif ($cmd eq "off") {
		logtext("/gummy off");
		disablegummy();
		$wind->print("Gummybot Disabled.");
	}
	elsif ($cmd eq "reload") {
		logtext("/gummy reload");
		loadfunstuff();
		$wind->print("Gummybot funstuff database reloaded.");
	}
	elsif ($cmd eq "save") {
		logtext("/gummy save");
		write_datastore();
		$wind->print("Datastore Saved.");		
	}
	elsif ($cmd eq "active") {
		my $key;
		my $value;
		foreach my $channame (keys %activity) {
			my %channel = %{$activity{$channame}};
			$wind->print("$channame:");
			while (($key, $value) = each(%channel)){
				$wind->print("     $key: " . (time-$value));
			}
		}
	}
	elsif ($cmd eq "blink") {
		$lastmsg = 0;
		$lastblink = 0;
		event_minutely_tick("");
	}
	elsif ($cmd eq "resetdb") {
		#Ignore any problems with disconnecting. Just let it die.
		eval{ 
			if (defined $database) {
				if ($database->Active()) {
					$database->disconnect();
				}
			}
		};
		connect_to_database();
	}
	else {
		print "GUMMY: Command '$cmd' not recognized.";
	}
}

# Bind our command
Irssi::command_bind("gummy", "gummy_command");

# Bind our events
Irssi::signal_add("event privmsg", "event_privmsg");
Irssi::signal_add("message join","event_nick_join");
Irssi::signal_add("message part","event_nick_part");
Irssi::signal_add("message kick","event_nick_kick");
Irssi::signal_add("message quit","event_nick_quit");
Irssi::signal_add("nicklist changed","event_nick_change");
Irssi::signal_add("message irc action", "event_action");
Irssi::signal_add("message irc notice", "event_notice");

# Lastly, if we've been told to start on, boot Gummy quietly.

if (Irssi::settings_get_bool('Gummy_AutoOn')) {
	enablegummy("quiet");	
}
