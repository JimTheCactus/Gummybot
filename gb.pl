use strict;
use vars qw($VERSION %IRSSI);
use Irssi;
use Storable;
use File::Spec;
use POSIX qw/strftime/;

my %floodtimes;
my $gummyenabled=0;
my %funstuff;
my $blinkhandle;
my $lastblink;
my $lastmsg;
my %activity;
my $lastupdate=time;
my $nomnick;
my @scrollback;
my %greets;
my %memos;
my %commands;

%commands = (	nom => \&cmd_nom,
				ver => \&cmd_ver,
				say => \&cmd_say,
				do => \&cmd_do,
				telesay => \&cmd_telesay,
				crickets => \&cmd_crickets,
				coolkids => \&cmd_coolkids,
				getitoff => \&cmd_getitoff,
				dance => \&cmd_dance,
				'isskynet()' => \&cmd_skynet,
				om => \&cmd_om,
				autogreet => \&cmd_autogreet,
				memo => \&cmd_memo
				help => \&cmd_help);

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

my $gummyver = "3.0.0";


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

sub trim {
	my $temp=$_;
	$temp=~s/^\s+|\s+$//g;
	return $temp;
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
	$lastupdate = time;
	$funstuff{mane} = ["Twilight Sparkle", "Rarity", "Pinkie Pie", "Fluttershy", "Rainbow Dash", "Applejack"];

	$count = loadfunfile("pony");
	print("Loaded $count ponies.");

	$count = loadfunfile("allpony");
	print("Loaded $count allponies.");

	$count = loadfunfile("buddha");
	print("Loaded $count words of wisdom.");

	$count = loadfunfile("critter");
	print("Loaded $count critters.");

	$count = loadfunfile("skippy");
	print("Loaded $count skippyisms.");

	read_greets();
	$count = scalar keys %greets;
	print("Loaded $count greets.");

	read_memos();
	$count = scalar keys %memos;
	print("Loaded memos for $count nicks.");
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

sub dofunsubs {
	my ($server, $channame, $text) = @_;
	my $mynum;
	
	if (not %funstuff) {
		loadfunstuff();
	}
	
	$mynum = int(rand(100));
	while ($text =~ s/(^|[^\\])%num/$1$mynum/) {
	        $mynum = int(rand(100));
	};

	if ($server->ischannel($channame)) {
		my $channel = $server->channel_find($channame);
		my @nicks = $channel->nicks();
		$mynum=rand(scalar(@nicks));
		while ($text =~ s/(^|[^\\])%peep/$1$nicks[$mynum]->{nick}/) {
			$mynum=rand(scalar(@nicks));
		};
	}
	
	my @choices = @{$funstuff{mane}};	
	$mynum=rand(scalar(@choices));
	while ($text =~ s/(^|[^\\])%mane/$1$choices[$mynum]/) {
		$mynum=rand(scalar(@choices));
	};
	
	my @choices = @{$funstuff{pony}};	
	$mynum=rand(scalar(@choices));
	while ($text =~ s/(^|[^\\])%pony/$1$choices[$mynum]/) {
		$mynum=rand(scalar(@choices));
	};
	
	my @choices = @{$funstuff{allpony}};	
	$mynum=rand(scalar(@choices));
	while ($text =~ s/(^|[^\\])%allpony/$1$choices[$mynum]/) {
		$mynum=rand(scalar(@choices));
	};

	my @choices = @{$funstuff{critter}};	
	$mynum=rand(scalar(@choices));
	while ($text =~ s/(^|[^\\])%critter/$1$choices[$mynum]/) {
		$mynum=rand(scalar(@choices));
	};

	$text =~ s/[\\](.)/\1/g;

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
			gummydo($server,$target, "pauses breifly as the HDD light blinks in his eyes. Saved!");
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
sub cmd_help {
	my ($server, $wind, $target, $nick, $args) = @_;
	gummysay($server,$target,"Usage: !gb <command> [parameter1 [parameter 2 [etc]]])");
	gummysay($server,$target,"Known Commands: nom [+], om [nom, add [+]], coolkids [<channel>/awwyeah], autogreet <greeting>, memo <targetnick> <memotext>, crickets, do <action>, teledo <channel> <action>, say <text>, telesay <channel> <text>, dance, getitoff, log, ver, on (@), off (@)");
	gummysay($server,$target,"Known substitutions: \\%mane, \\%num, \\%peep, \\%pony, \\%allpony \\%critter.");
}

sub cmd_on {
	my ($server, $wind, $target, $nick, $args) = @_;
	if ($gummyenabled == 0) {
		if ($cmd eq "on") {
			if (isgummyop($server,$target,$nick)) {
				enablegummy();
				floodreset("nick",$target);
			}
		}
	}
}


#sub cmd_ {
#	my ($server, $wind, $target, $nick, $args) = @_;
#}


sub parse_command {
	my ($commandlist,$server, $wind, $target, $nick, $cmd, $args) = @_;
	$cmd = lc($cmd);
	if (defined $commandlist->{$cmd}) {
		$commandlist->{$cmd}->($server, $wind, $target, $nick, $args);
		return 1;
	}
	else {
		return 0;
	}
}

sub gummymain {
	my ($server, $wind, $target, $nick, $cmd, $args) = @_; 
	my @params = split(/\s+/, $args);

	$cmd = lc($cmd);


	elsif ($cmd eq "log") {
		if (flood("feat","log",Irssi::settings_get_time('Gummy_LogFloodLimit')/1000)) {
			my $logtext;
			foreach (@scrollback) {
				gummyrawsay($server,$nick, $_);
			}
		}
		else {
			gummydo($server,$nick,"looks like he's discharged from the last log emission.");
		}
	}
}

sub myevent {
	my ($server, $data, $nick, $address) = @_;
	my ($target, $text) = split(/ :/, $data, 2);
	my $curwind = Irssi::active_win;
	my ($prefix,$cmd, $args) = split(/\s+/,$text,3);


	$lastmsg = time;
	if ($server->ischannel($target)) {
		# This makes sure there's 15 lines of scrollback, removes
		# the oldest line and pushes the new line on
		$#scrollback = 14;	
		shift(@scrollback);
		push(@scrollback, $data);
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
		if (lc($cmd) eq "off") {
			if (isgummyop($server,$target,$nick) && $gummyenabled!=0) {
				disablegummy();
				$gummyenabled = 0;
				logtext("$nick PRIVMSG $data");
				gummysay($server,$target,"Gummy bot disabled. Daisy, daisy, give me... your ans.. wer...");
			}
		}
		if ($gummyenabled !=0) {
			if (nickflood($nick,Irssi::settings_get_time('Gummy_NickFloodLimit')/1000)) {
				if ($target eq $nick || nickflood($target,Irssi::settings_get_time('Gummy_ChanFloodLimit')/1000)) {
					logtext("$nick PRIVMSG $data");
					$args = dofunsubs($server, $target, $args);
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
		if ($gummyenabled != 0 && Irssi::settings_get_bool('Gummy_Blink')) {
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
				elsif (rand(1) < .9) {
					gummydo($_->{server},$_->{name},"blinks as he looks about the channel.");
				}
				else {
					gummysay($_->{server},$_->{name},"Crickets detected! Arming vaporization cannon... Firing in 3... 2... 1...");
					gummydo($_->{server},$_->{name},"fires a blinding laser, vaporizing a single cricket simply minding his own business in a corner of the channel.");
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
	if (Irssi::settings_get_bool('Gummy_AllowAutogreet') && !Irssi::settings_get_bool('Gummy_GreetOnEntry')) {
		do_greet($channel->{server},$channel->{name},$oldnick, $nick->{nick});
	}
	if (lc($nick->{nick}) eq lc($nomnick)) {
		gummydo($channel->{server},$channel->{name},"lets go of $nomnick to make room for the new pony.");
		$nomnick=undef;
	}
	if (lc($oldnick) eq lc($nomnick)) {
		$nomnick=$nick->{nick};
	}
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
	check_release($server,$channel, $nick);
}
sub nick_quit {
	my ($server, $nick) = @_;
	if (lc($nick) eq lc($nomnick)) {
		$nomnick=undef;	
	}
}
sub nick_kick {
	my ($server, $channel, $nick) = @_;
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


Irssi::command_bind("gummy", "gummy_command");
Irssi::signal_add("event privmsg", "myevent");
Irssi::signal_add("message join","join_pounce");
Irssi::signal_add("message part","nick_part");
Irssi::signal_add("message kick","nick_kick");
Irssi::signal_add("message quit","nick_quit");
Irssi::signal_add("nicklist changed","nick_change");
