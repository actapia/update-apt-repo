my $userconfigfile = "$ENV{HOME}/.debarchiver.conf";

do $userconfigfile;

print "DESTDIR=$destdir;\n";
print "INPUTDIR=$inputdir;\n";
print "GPGKEY=$gpgkey;\n";
print "SECTIONS=(@{[@sections]});\n";
print "ARCHITECTURES=(@{[@architectures]});\n";
