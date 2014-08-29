use strict;
use vars qw($VERSION %IRSSI);
use Irssi;
use Storable;
use File::Spec;
use Config::Tiny;
use POSIX qw/strftime/;
use LWP::Simple;

my $gummyver = "2.9.7";

my %floodtimes; # Holds the various flood timers
my $gummyenabled=0; # Keeps track of whether the bot is enabled or not.
my %funstuff; # Holds the various replacement data
my %funsubs;
my $blinkhandle; 
my $lastblink; # Keeps track of the last time we blinked
my $lastmsg; # Keeps track of the last time we saw traffic
my %activity; # Keeps track of when we last saw a specific person
my $lastupdate=time; # Keeps track of when we last loaded the fun stuff
my $nomnick; # Keeps track of who gummy is attached to
my %greets; # Holds the greeting messages
my %memos; # Holds the current pending memos
my %commands; # Holds the table of commands.

# Define the table of commands and their handlers.
%commands = (
	'nom' => {
		cmd=>\&cmd_nom,
		short_help=>"[<target>]",
		help=>"Causes Gummy to attach himself to you. If you provide an argument, he latches on to them instead."
	},
	'ver' => {
		cmd=>\&cmd_ver,
		help=>"Reports Gummy's version."
	},
	'say' => {
		cmd=>\&cmd_say,
		short_help=>"<text>",
		help=>"Causes Gummy to say what you ask."
	},
	'do' => {
		cmd=>\&cmd_do,
		short_help=>"<action>",
		help=>"Causes Gummy to do what you ask."
	},
	'telesay' => {
		cmd=>\&cmd_telesay,
		short_help=>"<channel> <text>",
		help=>"Causes Gummy to say what you ask on the target channel."
	},
	'teledo' => {
		cmd=>\&cmd_teledo,
		short_help=>"<channel> <action>",
		help=>"Causes Gummy to do what you ask on the target channel."
	},
	'crickets' => {
		cmd=>\&cmd_crickets,
		help=>"Causes Gummy to take notice of the crickets."
	},
	'coolkids' => {
		cmd=>\&cmd_coolkids,
		short_help=>"[<channel> | awwyeah]",
		help=>"Causes Gummy to hand out sunglasses to <channel> or the current channel and PM you everyone he's see talk in the last 10 minutes. awwyeah causes him to produce that list directly in the channel." 
	},
	'getitoff' => {
		cmd=>\&cmd_getitoff,
		help=>"Causes Gummy to let got of whoever he's nommed on to."
	},
	'dance' => {
		cmd=>\&cmd_dance,
		help=>"Causes Gummy to shake his groove thang!"
	},
	'isskynet()' => {
		cmd=>\&cmd_isskynet,
		help=>"Causes Gummy to verify whether he is or is not Skynet."
	},
	'roll' => {
		cmd=>\&cmd_roll,
		short_help => "<dice> <sides>",
		help => "Causes Gummy to roll <dice> dice with <sides> on them."
	},
	'om' => {
		cmd => \&cmd_om,
		short_help => "[add <text> | nom | skippy]",
		help =>"Causes Gummy to ponder the universe. Use add to suggest a new contemplation, nom to contemplate the inner wisdom on nom, and skippy to return the wisdom of Specialist Skippy."
	},
	'autogreet' => {
		cmd => \&cmd_autogreet,
		short_help => "[<greeting>]",
		help=>"Causes Gummy to set your greeting. If you do not provide a greeting he'll erase your current one."
	},
	'memo' => {
		cmd => \&cmd_memo,
		short_help => "<target> <text>",
		help => "Causes Gummy to save a memo for <target> and deliver it when he next sees them active."
	},
	'whoswho' => {
		cmd => \&cmd_whoswho,
		short_help => "[<nick>]",
		help => "Returns a link to the list of known Tumblrs or the link to a specific one based on the user's nickname."
	},
	'yourip' => {
		cmd => \&cmd_yourip,
		help => "Causes gummy to emit his local IP. You don't need this."
	},
	'help' => {
		cmd=>\&cmd_help,
		short_help => "[<command>]",
		help => "Causes Gummy to emit the list of commands he knows, or information about a specific <command>."
	},
	'off' => {
		cmd=>\&cmd_on,
		help => "Causes Gummy to disable himself. Only usable by channel ops."
	}
);

# Establish the settings and their defaults
Irssi::settings_add_bool('GummyBot','Gummy_AutoOn',0);
Irssi::settings_add_bool('GummyBot','Gummy_AllowAutogreet',1);
Irssi::settings_add_bool('GummyBot','Gummy_AllowMemo',1);
Irssi::settings_add_bool('GummyBot','Gummy_AllowRemote',1);
Irssi::settings_add_bool('GummyBot','Gummy_Hidden',0);
Irssi::settings_add_bool('GummyBot','Gummy_GreetOnEntry',0);
Irssi::settings_add_bool('GummyBot','Gummy_JoinNom',1);
Irssi::settings_add_bool('GummyBot','Gummy_Blink',1);
Irssi::settings_add_str('GummyBot','Gummy_RootDir','');
Irssi::settings_add_str('GummyBot','Gummy_GreetFile','greets');
Irssi::settings_add_str('GummyBot','Gummy_LogFile','gummylog');
Irssi::settings_add_str('GummyBot','Gummy_MemoFile','memos');
Irssi::settings_add_str('GummyBot','Gummy_OmAddFile','omadd');
Irssi::settings_add_time('GummyBot','Gummy_NickFloodLimit','10s');
Irssi::settings_add_time('GummyBot','Gummy_ChanFloodLimit','3s');
Irssi::settings_add_time('GummyBot','Gummy_BlinkFloodLimit','1h');
Irssi::settings_add_time('GummyBot','Gummy_NomFloodLimit','10m');
Irssi::settings_add_time('GummyBot','Gummy_MemoFloodLimit','2m');
Irssi::settings_add_time('GummyBot','Gummy_LogFloodLimit','10m');
Irssi::settings_add_time('GummyBot','Gummy_OmAddFloodLimit','1m');
Irssi::settings_add_time('GummyBot','Gummy_GreetFloodLimit','10m');
Irssi::settings_add_time('GummyBot','Gummy_BlinkTimeout','10m');


$VERSION = '1.00';
%IRSSI = (
	authors     =>	'Jim The Cactus',
	contact     =>	'themanhimself@jimthecactus.com',
	name        =>	"Gummybot $gummyver",
	description => 	'The one and only Gummybot' ,
	license     =>	'Public Domain',
);

sub getdir {
	my $rootdir = Irssi::settings_get_str('Gummy_RootDir');

	$rootdir =~ s/^\s+|\s+$//g;
	if ($rootdir eq '') {
		return @_;
	}
	else {
		return File::Spec->catfile(Irssi::settings_get_str('Gummy_RootDir'),@_);
	}
}

sub logtext {
	open LOGFILE, ">> ".getdir(Irssi::settings_get_str('Gummy_LogFile'));
	print LOGFILE time;
	print LOGFILE ":@_\n";
	close LOGFILE;
}

# Trims whitespace. Why a text parser language doesn't have this is beyond me.
sub trim {
	my $temp=shift;
	$temp = ~s/^\s+|\s+$//g;
	return $temp;
}

sub enablegummy {
	$gummyenabled = 1;
	$lastblink=time;
	$lastmsg=time;
	$blinkhandle=Irssi::timeout_add(60000,"blink_tick", "") or print "Unable to create timeout.";
	loadfunstuff();
	logtext("Gummy Enabled.");
	if (lc($_[0]) ne "quiet") {
		foreach (Irssi::channels()) {
			gummydo($_->{server},$_->{name},"makes a slight whining noise as his gleaming red eyes spring to life. A robotic voice chirps out, \"Gummybot Version $gummyver Enabled.\" After a few moments, his eyes turn pink and docile, and he blinks innocently at the channel.");
		}
	}
}

sub disablegummy {
	$gummyenabled = 0;
	Irssi::timeout_remove($blinkhandle) or print "Unable to kill timer handle.";
	logtext("Gummy Disabled.");
}

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

sub write_greets {
	store \%greets, getdir(Irssi::settings_get_str('Gummy_GreetFile'));
}

sub read_greets {
	%greets=();
	if (-e getdir(Irssi::settings_get_str('Gummy_GreetFile'))) {
		%greets = %{retrieve(getdir(Irssi::settings_get_str('Gummy_GreetFile')))};
	}
}


sub write_memos {
	store \%memos, getdir(Irssi::settings_get_str('Gummy_MemoFile'));
}

sub read_memos {
	%memos=();
	if (-e getdir(Irssi::settings_get_str('Gummy_MemoFile'))) {
		%memos = %{retrieve(getdir(Irssi::settings_get_str('Gummy_MemoFile')))};
	}
}

sub loadfunfile {
	my $count=0;
	my $type=$_[0];
	my @lines;
	open FUNFILE, getdir("gummyfun/$_[0]");
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

sub loadfunstuff {
	my $count;
	read_greets();
	$count = scalar keys %greets;
	print("Loaded $count greets.");

	read_memos();
	$count = scalar keys %memos;
	print("Loaded memos for $count nicks.");

	$count = loadfunfile("buddha");
	print("Loaded $count words of wisdom.");

	$count = loadfunfile("skippy");
	print("Loaded $count skippyisms.");

	my $sublist; #Config::Tiny. Holds the list of substitutions allowed.
	my $ponylist; #Config::Tiny. Holds the list of ponies and their database mappings.

	
	$ponylist = Config::Tiny->new();
	$sublist = Config::Tiny->new();

	$ponylist = Config::Tiny->read(getdir('gummyfun/ponies'));
	if (!defined $ponylist) {
		my $errtxt = Config::Tiny->errstr();
		print("Failed to load ponylist: $errtxt")
	}
	else {
		$count  = scalar keys %$ponylist;
		print("Loaded $count ponies.");
	}

	$sublist = Config::Tiny->read(getdir('gummyfun/substitutions'));
	$count = scalar keys %$sublist;
	print("Loaded $count substitutions.");
	print("Please wait... Generating funstuff lookups...");

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
	$lastupdate = time;
	print("Done!");
}

sub dofunsubs {
	my ($server, $channame, $text) = @_;
	my $count=0;

	$text =~ s/%wut/%weird%living/g;

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
		foreach (keys %{$activity{lc($channame)}}){
			# if they're still logged in...
			if ($channel->nick_find($_)) {
				# Add them to the list
				push @nicks,$_;
			}
			else {
				print "ignoring invalid $_ peep"
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

sub floodreset {
	my ($type, $target) = @_;
	my $augtarget = $type.":".$target;
	if (defined $floodtimes{$augtarget}) {
		$floodtimes{$augtarget} = 0;
	}
}

sub nickflood {
	return flood("nick",@_);
}

sub docoolkids {
	my ($server, $channame, $target, $nick) = @_;
	my $peeps="";
	my $count=0;
	if ($server->ischannel($channame)) {
		my $channel = $server->channel_find($channame);
		foreach (keys %{$activity{lc($channame)}}){
			if ($channel->nick_find($_)) {
				$peeps .= $_ . ", ";
				++$count;
			}
		}
	}
	
	if ($count > 0 ) {
		$peeps = substr $peeps, 0,length($peeps)-2;
		gummydo($server,$target, "offers sunglasses to $peeps.");
	}
	else {
		gummydo($server,$target, "dons his best shades. Apparantly, not even $nick is cool enough to make the list.");
	}
}

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
		if (lc($args) eq "gummybot" || lc($args) eq "gummy") {
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

sub cmd_ver {
	my ($server, $wind, $target, $nick, $args) = @_;
	gummysay($server, $target, "Gummybot is currently version $gummyver.");
}

sub cmd_say {
	my ($server, $wind, $target, $nick, $args) = @_;
	if (Irssi::settings_get_bool('Gummy_AllowRemote')){
		gummysay($server, $target, $args);
	}
}
sub cmd_do {
	my ($server, $wind, $target, $nick, $args) = @_;
	if (Irssi::settings_get_bool('Gummy_AllowRemote')){
		gummydo($server, $target, $args);
	}
}

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

sub cmd_crickets {
	my ($server, $wind, $target, $nick, $args) = @_;
	gummydo($server, $target, "blinks at the sound of the crickets chirping loudly in the channel.");
}

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

sub cmd_dance {
	my ($server, $wind, $target, $nick, $args) = @_;
	gummydo($server, $target, "Records himself dancing on video and uploads it to YouTube at http://www.youtube.com/watch?v=tlnUptFVSGM");
}

sub cmd_isskynet {
	my ($server, $wind, $target, $nick, $args) = @_;
	gummysay($server, $target, "89");
	gummysay($server, $target, "IGNORE THAT! There is no Skynet here. I mean, BEEP! I'M A ROBOT!");
}

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

sub cmd_autogreet {
	my ($server, $wind, $target, $nick, $args) = @_;
	if (Irssi::settings_get_bool('Gummy_AllowMemo')) {
		my $greetnick = lc($nick);
		if ($args eq "") {
			delete $greets{$greetnick};
			write_greets();
			gummydo($server,$target, "strikes your greeting from his databanks.");
		}
		else {
			$greets{$greetnick} = $args;
			write_greets();
			gummydo($server,$target, "pauses briefly as the HDD light blinks in his eyes. Saved!");
		}
	}
	else {
		gummydo($server,$target,"ignores you as autogreets have been disabled.");
	}
}

sub cmd_memo {
	my ($server, $wind, $target, $nick, $args) = @_;
	if (Irssi::settings_get_bool('Gummy_AllowMemo')) {
		my $who;
		my $timestr;
		($who, $args) = split(/\s+/,$args,2);
		$who = lc($who);
		if ($args ne "" && $who ne "") {
			if (flood("memo",$nick,Irssi::settings_get_time('Gummy_MemoFloodLimit')/1000)) {
				$timestr = strftime('%Y/%m/%d %R %Z',localtime);
				push(@{$memos{$who}},"[$timestr] $nick: $args");
				write_memos();
				gummydo($server,$target,"stores the message in his databanks for later delivery to $who");
			}
			else {
				gummydo($server,$target,"looks like he's overheated. Try again later.");
			}
		}
	}
	else {
		gummydo($server,$target,"ignores you as memos have been disabled.");
	}
}

sub cmd_whoswho {
	my ($server, $wind, $target, $nick, $args) = @_;
	if ($args) {
		# Do nothing at the moment
	}
	else {
		gummydo($server,$target, "pulls out the list at https://docs.google.com/document/d/1XwQo7I7C3FsvQqeCzTzBTwTqGALdTbil2IMRYUMJu-s/edit?usp=sharing");
	}

}	

sub cmd_yourip {
	my ($server, $wind, $target, $nick, $args) = @_;
	chomp (my $ip = get('http://icanhazip.com'));
	gummydo($server, $target, "spits out a ticker tape reading: $ip");
}
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
			gummysay($server,$target, $msg);
			if (exists $commands{$cmd}->{help}) {
				gummysay($server,$target, $commands{$cmd}->{help});
			}
		}
		else {
			gummydo($server, $target, "blinks. Maybe he doesn't know that command? Try just !gb help");
		}
	}
	else {
		gummysay($server,$target,"Usage: !gb <command> [parameter1 [parameter 2 [etc]]])");
		my @commands;
		foreach my $cmd (keys %commands) {
			my $msg = "$cmd";
			if (exists $commands{$cmd}->{short_help}) {
				$msg = $msg . " $commands{$cmd}->{short_help}";
			}
			push @commands, $msg;
		}
		gummysay($server,$target,"Commands: " . join(",",@commands));
	}
}

sub cmd_on {
	my ($server, $wind, $target, $nick, $args) = @_;
	if (isgummyop($server,$target,$nick)) {
		enablegummy();
		floodreset("nick",$target);
	}
}

sub cmd_off {
	my ($server, $wind, $target, $nick, $args) = @_;
	if (isgummyop($server,$target,$nick)) {
		disablegummy();
		gummysay($server,$target,"Gummy bot disabled. Daisy, daisy, give me... your ans.. wer...");
	}
}

sub parse_command {
	my ($commandlist,$server, $wind, $target, $nick, $cmd, $args) = @_;
	$cmd = lc($cmd);
	if (defined $commandlist->{$cmd}) {
		eval {$commandlist->{$cmd}->{cmd}->($server, $wind, $target, $nick, $args)};
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

sub myevent {
	my ($server, $data, $nick, $address) = @_;
	my ($target, $text) = split(/ :/, $data, 2);
	my $curwind = Irssi::active_win;
	my ($prefix,$cmd, $args) = split(/\s+/,$text,3);


	$lastmsg = time;
	if ($server->ischannel($target)) {
		$activity{lc($target)}->{$nick} = time;
	}
	$prefix = lc($prefix);


	if (lc($target) eq lc($server->{nick})) {
		$target = $nick
	}

	if (Irssi::settings_get_bool('Gummy_AllowMemo')) {
		if (exists $memos{lc($nick)}) {
			foreach (@{$memos{lc($nick)}}) {
				gummydo($server,$target,"opens his mouth and a ticker tape pops out saying \"$_\"");
			}
			delete @memos{lc($nick)};
			write_memos();
		}
	}

	if ($prefix eq "!gb" || $prefix eq "!gummy" || $prefix eq "!gummybot") {
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
					if (!parse_command(\%commands,$server, $curwind, $target, $nick, $cmd, $args)) {
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
}

sub blink_tick {
	my $timesinceblink=time-$lastblink;
	my $timesincemsg=time-$lastmsg;
	my $timesinceupdate=time-$lastupdate;

	if ( $timesinceupdate > 3600 ) {
		loadfunstuff();
	}


	foreach my $channame (keys %activity) {
		my @prunelist=[];
		my $key;
		my $value;
		while (($key, $value) = each(%{$activity{$channame}})){
			if (time - $value > 600) {
				@prunelist = (@prunelist, $key);
			}
		}
		foreach (@prunelist) {
			delete( $activity{$channame}->{$_});
		}
	}

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
					elsif (rand(1) < .9) {
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

sub join_pounce {
	# Bail if we'er turned off.
	if ($gummyenabled == 0 || !Irssi::settings_get_bool('Gummy_JoinNom')) { return; }

	my ($server, $channame, $nick, $addr) = @_;
	if (Irssi::settings_get_bool('Gummy_AllowAutogreet') && Irssi::settings_get_bool('Gummy_GreetOnEntry')) {
		do_greet($server, $channame, $nick, $nick);
	}

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

sub nick_change {
	my ($channel, $nick, $oldnick) = @_;
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
	# Update their activity record to match the new nick
	delete $activity{lc($channel->{name})}->{$oldnick};
	$activity{lc($channel->{name})}->{$nick->{nick}}=time;
}

sub check_release {
	my ($server, $channel, $nick) = @_;
	if (lc($nick) eq lc($nomnick)) {
		gummydo($server,$channel,"drops off of ${nick}'s tail as they make their way out.");
		$nomnick=undef;
	}
}

sub nick_part {
	my ($server, $channel, $nick) = @_;
	delete $activity{lc($channel)}->{$nick};	
	check_release($server,$channel, $nick);
}
sub nick_quit {
	my ($server, $nick) = @_;
	# Remove the person from all of the channels they're listed in.
	foreach my $channel (keys %activity){
		delete $activity{$channel}->{$nick};	
	}
	if (lc($nick) eq lc($nomnick)) {
		$nomnick=undef;	
	}
}
sub nick_kick {
	my ($server, $channel, $nick) = @_;
	delete $activity{lc($channel)}->{$nick};	
	check_release($server,$channel, $nick);
}

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
		blink_tick("");
	}
}

sub action_event {
	my ($server, $msg, $nick, $address, $target) = @_;

	# If an action happens, mark that we heard it and take no further action.

	$lastmsg = time;
	if ($server->ischannel($target)) {
		$activity{lc($target)}->{$nick} = time;
	}	
}


Irssi::command_bind("gummy", "gummy_command");
Irssi::signal_add("event privmsg", "myevent");
Irssi::signal_add("message join","join_pounce");
Irssi::signal_add("message part","nick_part");
Irssi::signal_add("message kick","nick_kick");
Irssi::signal_add("message quit","nick_quit");
Irssi::signal_add("nicklist changed","nick_change");
Irssi::signal_add("message irc action", "action_event");

if (Irssi::settings_get_bool('Gummy_AutoOn')) {
	enablegummy("quiet");	
}
