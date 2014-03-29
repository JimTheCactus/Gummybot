open SRC,"pony";
open TAR, "> allpony";
while(<SRC>) {
	chomp;
	unless (m/\.png\s*$|^\s*$/i) {
	while(m~\s*([^/]+)(?:\s*/|\s*$)~ig) {
#		if (lc($1) != "png" && lc($1) != "jpg") {
			print "Found: $1\n";
			print TAR "$1\n";
#		}
	}
}
}
