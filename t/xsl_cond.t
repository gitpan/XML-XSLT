# $Id: xsl_cond.t,v 1.2 2001/01/16 03:14:14 hexmode Exp $
# check test attributes && the interface

use strict;
use vars qw( $loaded );
BEGIN { $| = 1; print "1..7\n"; }
END {print "not ok 1\n" unless $loaded;}
use XML::XSLT;
print "ok 1\n";
$loaded = 1;

my $parser = eval { 
XML::XSLT->new (\<<\EOS);
<?xml version="1.0"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:template match="doc"><doc><xsl:apply-templates/></doc></xsl:template>
<xsl:template match="p"><xsl:choose>
 <xsl:when test="title='foo'">o</xsl:when>
 <xsl:otherwise>not ok</xsl:otherwise>
</xsl:choose><xsl:if test="title='foo'">k</xsl:if></xsl:template>
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
<?xml version="1.0"?><doc><p><title>foo</title>some random text</p></doc>
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

my $correct='<doc>ok</doc>';

print 'not ' unless(defined($outstr) and $outstr eq $correct);
print "ok 7\n";
