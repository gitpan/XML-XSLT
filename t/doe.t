# $Id: doe.t,v 1.1 2000/09/20 17:58:17 nejedly Exp $
# check disable-output-escaping && the interface

use strict;
use vars qw( $loaded );
BEGIN { $| = 1; print "1..7\n"; }
END {print "not ok 1\n" unless $loaded;}
use XML::XSLT;
print "ok 1\n";
$loaded = 1;

my $parser = eval { 
XML::XSLT->new (\<<\EOS, warnings => 'Active');
<?xml version="1.0"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:template match="doc"><doc><d><xsl:value-of select="p" disable-output-escaping="yes"/></d><xsl:apply-templates/></doc></xsl:template>
<xsl:template match="p"><d><xsl:text disable-output-escaping="yes">&lt;&amp;</xsl:text></d><e><xsl:value-of select="."/></e><e>&lt;<xsl:text>&amp;</xsl:text></e></xsl:template>
</xsl:stylesheet>
EOS
};

if($@)
 {
 print "not ok 2 # $@\n";
 exit;
}

print "ok 2\n";

if(!$parser)
 {
 print "not ok 3 # parser is null\n";
 exit;
}

print "ok 3\n";

eval {
$parser->transform(\<<\EOX);
<?xml version="1.0"?><doc><p>&lt;&amp;</p></doc>
EOX
};

if($@)
 {
 print "not ok 4 # $@\n";
 exit();
}
print "ok 4\n";

my $outstr= eval { $parser->toString };

if($@)
 {
 print "not ok 5 # $@\n";
 exit;
}
print "ok 5\n";
print 'not ' unless defined $outstr;
print "ok 6\n";

my $correct='<doc><d><&</d><d><&</d><e>&lt;&amp;</e><e>&lt;&amp;</e></doc>';

print 'not ' unless(defined($outstr) and $outstr eq $correct);
print "ok 7\n";
