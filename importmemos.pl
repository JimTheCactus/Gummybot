use Storable;
use DBI;

if (scalar(@ARGV) != 6) {
	print "Usage: $0 <hostname> <database> <username> <password> <table prefix> <datastore file>\n";
	exit;
}
	

my %datastore = %{retrieve(@ARGV[5])};
my $database = DBI->connect("DBI:mysql:hostname=" . @ARGV[0] . ";database=" . @ARGV[1],@ARGV[2],@ARGV[3])
                or die "Couldn't connect to database\n" . DBI->errstr;

my %memos = %{$datastore{memos}};
my $query = $database->prepare("INSERT INTO " . @ARGV[4] . "memos (Nick, SourceNick, DeliveryMode, CreatedTime, Message) VALUES (?,?,?,NOW(),?)");
foreach my $nick (keys %memos) {
	print "Importing memos for $nick...\n";
	foreach my $memo (@{$memos{$nick}}) {
		$query->execute($nick,'OLDMEMO', undef, $memo);
	}	
}

$database->disconnect();
