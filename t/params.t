# $Id: params.t,v 1.1 2000/10/30 22:06:15 nejedly Exp $
# check params && the interface

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

<xsl:template match="a"><xsl:apply-templates>
  <xsl:with-param name="param1">value1</xsl:with-param>
</xsl:apply-templates></xsl:template>

<xsl:template match="b"><xsl:param name="param1">undefined</xsl:param>[ param1=<xsl:value-of select="$param1"/> ]</xsl:template>

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
<?xml version="1.0"?><doc><a><b/></a><b/></doc>
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

my $correct='[ param1=value1 ][ param1=undefined ]';

print 'not ' unless(defined($outstr) and $outstr eq $correct);
print "ok 7\n";
