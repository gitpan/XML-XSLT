# $Id: zeroes.t,v 1.2 2000/08/10 14:29:19 nejedly Exp $
# check the ``0'' bug && the interface

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
<xsl:template match="/"><d><xsl:apply-templates/></d></xsl:template>
<xsl:template match="p">0</xsl:template>
<xsl:template match="q"><xsl:text>0</xsl:text></xsl:template>
<xsl:template match="r"><xsl:value-of select="."/></xsl:template>
<xsl:template match="s"><d size="{@size}"><xsl:apply-templates /></d></xsl:template>
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
<?xml version="1.0"?><doc><p /><q /><r>0</r><s size="0">0</s></doc>
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

my $correct='<d>000<d size="0">0</d></d>';

print 'not ' unless(defined($outstr) and $outstr eq $correct);
print "ok 7\n";
