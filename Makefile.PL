#!/usr/local/bin/perl

use ExtUtils::MakeMaker;

WriteMakefile(
    ABSTRACT => 'Conversion of XML files with XSLT.',
    AUTHOR =>
'Geert Josten (gjosten@sci.kun.nl) and Egon Willighagen (egonw@sci.kun.nl)',
    NAME => 'XML::XSLT',
    dist => {
        COMPRESS => 'gzip',
        SUFFIX   => '.gz'
    },
    VERSION_FROM => 'lib/XML/XSLT.pm',
    PREREQ_PM    => {
        'XML::Parser'     => '2.23',
        'XML::DOM'        => '1.25',
        'XML::DOM::XPath' => '0.10',
        'Test::More'      => '0.7'
    },
    EXE_FILES  => ['xslt-parser'],
    LICENSE    => 'perl',
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources   => {
            repository => {
                type => 'git',
                url  => 'https://github.com/jonathanstowe/XML-XSLT.git',
                web  => 'https://github.com/jonathanstowe/XML-XSLT',
            },
        },
    },
);

