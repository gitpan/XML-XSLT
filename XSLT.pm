################################################################################
#
# Perl module: XML::XSLT
#
# By Geert Josten, gjosten@sci.kun.nl
# and Egon Willighagen, egonw@sci.kun.nl
#
################################################################################

######################################################################
package XML::XSLTParser;
######################################################################

use strict;
use XML::DOM;

BEGIN {
  require XML::DOM;

  my $needVersion = '1.25';
  die "need at least XML::DOM version $needVersion (current=" . $XML::DOM::VERSION . ")"
    unless $XML::DOM::VERSION >= $needVersion;

  use Exporter ();
  use vars qw( @ISA @EXPORT);

  @ISA         = qw( Exporter );
  @EXPORT      = qw( &new &openproject &process_project &print_result );

  use vars qw ( $_indent $_indent_incr );
  $_indent = 0;
  $_indent_incr = 1;
}

sub new {
  my ($class) = @_;

  return bless {}, $class;  
}

sub openproject {
  my ($parser, $xmlfile, $xslfile) = @_;

  $XSLT::DOMparser = new XML::DOM::Parser;
  $XSLT::xsl = $XSLT::DOMparser->parsefile ($xslfile);
  $XSLT::xml = $XSLT::DOMparser->parsefile ($xmlfile);
  $XSLT::result = $XSLT::xml->createDocumentFragment;

  &__add_default_templates__($XSLT::xsl);
}


sub process_project {
  my ($parser) = @_;
  my $root_template = $parser->_find_template ('/');

  if ($root_template) {

    $parser->_evaluate_template (
        $root_template,		# starting template, the root template
        $XSLT::xml,		# current XML node, the root
        '',			# current XML selection path, the root
        $XSLT::result,		# current result tree node, the root
    );

  }
}

sub print_result {
  my ($parser, $file) = @_;

  $XSLT::outputstring = $XSLT::result->toString;
  $XSLT::outputstring =~ s/\n\s*\n(\s*)\n/\n$1\n/g; # Substitute multiple empty lines by one
  $XSLT::outputstring =~ s/\/\>/ \/\>/g;            # Insert a space before all />

  if ($file) {
    print $file $XSLT::outputstring;
  } else {
    print $XSLT::outputstring;
  }
}

######################################################################

  sub __add_default_templates__ {
    # Add the default templates for match="/" and match="*" #
    my $root_node = shift;

    my $stylesheet = $root_node->getElementsByTagName('xsl:stylesheet',0)->item(0);
    my $first_template = $stylesheet->getElementsByTagName('xsl:template',0)->item(0);

    my $root_template = $root_node->createElement('xsl:template');
    $root_template->setAttribute('match','/');
    $root_template->appendChild ($root_node->createElement('xsl:apply-templates'));
    $stylesheet->insertBefore($root_template,$first_template);

    my $any_element_template = $root_node->createElement('xsl:template');
    $any_element_template->setAttribute('match','*');
    $any_element_template->appendChild ($root_node->createElement('xsl:apply-templates'));
    $stylesheet->insertBefore($any_element_template,$first_template);
  }

sub _find_template {
  my $parser = shift;
  my $current_xml_selection_path = shift;
  my $attribute_name = shift;
  $attribute_name = "match" unless defined $attribute_name;

  print " "x$_indent,"searching template for \"$current_xml_selection_path\": " if $XSLT::debug;

  my $stylesheet = $XSLT::xsl->getElementsByTagName('xsl:stylesheet',0)->item(0);
  my $templates = $stylesheet->getElementsByTagName('xsl:template',0);

  for (my $i = ($templates->getLength - 1); $i >= 0; $i--) {
    my $template = $templates->item($i);
    my $template_attr_value = $template->getAttribute ($attribute_name);

    if (&__template_matches__ ($template_attr_value, $current_xml_selection_path)) {
      print "found #$i \"$template_attr_value\"$/" if $XSLT::debug;

      return $template;
    }
  }
  
  print "no template found! $/" if $XSLT::debug;
  warn ("No template matching $current_xml_selection_path found !!$/") if $XSLT::debug;
  return "";
}

  sub __template_matches__ {
    my $template = shift;
    my $path = shift;
    
    if ($template ne $path) {
      if ($path =~ /\/.*(\@\*|\@\w+)$/) {
        # attribute selection #
        my $attribute = $1;
        return ($template eq "\@*" || $template eq $attribute);
      } elsif ($path =~ /\/(\*|\w+)$/) {
        # element selection #
        my $element = $1;
        return ($template eq "*" || $template eq $element);
      } else {
        return "";
      }
    } else {
      return "True";
    }
  }

sub _evaluate_template {
  my $parser = shift;
  my $template = shift;
  my $current_xml_node = shift;
  my $current_xml_selection_path = shift;
  my $current_result_node = shift;

  print " "x$_indent,"evaluating template content for \"$current_xml_selection_path\": $/" if $XSLT::debug;
  $_indent += $_indent_incr;;

  foreach my $child ($template->getChildNodes) {
    my $ref = ref $child;
    print " "x$_indent,"$ref$/" if $XSLT::debug;
    $_indent += $_indent_incr;

      if ($child->getNodeType == ELEMENT_NODE) {
        $parser->_evaluate_element ($child,
                                    $current_xml_node,
                                    $current_xml_selection_path,
                                    $current_result_node);
      } elsif ($child->getNodeType == TEXT_NODE) {
        $parser->_add_node($child, $current_result_node);
      } else {
        my $name = $template->getTagName;
        print " "x$_indent,"Cannot evaluate node $name of type $ref !$/" if $XSLT::debug;
        warn ("evaluate-template: Dunno what to do with node of type $ref !!! ($name; $current_xml_selection_path)$/") if $XSLT::warnings;
      }
    
    $_indent -= $_indent_incr;
  }

  $_indent -= $_indent_incr;
}

sub _add_node {
  my $parser = shift;
  my $node = shift;
  my $parent = shift;
  my $deep = (shift || "");
  my $owner = (shift || $XSLT::xml);

  print " "x$_indent,"adding (deep): " if $XSLT::debug && $deep;
  print " "x$_indent,"adding (non-deep): " if $XSLT::debug && !$deep;

  $node = $node->cloneNode($deep);
  $node->setOwnerDocument($owner);
  $parent->appendChild($node);

  print "done$/" if $XSLT::debug;
}

sub _apply_templates {
  my $parser = shift;
  my $current_xml_node = shift;
  my $current_xml_selection_path = shift;
  my $current_result_node = shift;

  print " "x$_indent,"applying templates on children of \"$current_xml_selection_path\":$/" if $XSLT::debug;
  $_indent += $_indent_incr;

  foreach my $child ($current_xml_node->getChildNodes) {
    my $ref = ref $child;
    print " "x$_indent,"$ref$/" if $XSLT::debug;
    $_indent += $_indent_incr;

      my $child_xml_selection_path = $child->getNodeName;
      $child_xml_selection_path = "$current_xml_selection_path/$child_xml_selection_path";

      if ($child->getNodeType == ELEMENT_NODE) {
          my $template = $parser->_find_template ($child_xml_selection_path);

          if ($template) {

              $parser->_evaluate_template ($template,
		 	                   $child,
                                           $child_xml_selection_path,
                                           $current_result_node);
          }
      } elsif ($child->getNodeType == TEXT_NODE) {
          $parser->_add_node($child, $current_result_node);
      } elsif ($child->getNodeType == DOCUMENT_TYPE_NODE) {
          # skip #
      } elsif ($child->getNodeType == COMMENT_NODE) {
          # skip #
      } else {
          print " "x$_indent,"Cannot apply templates on nodes of type $ref$/" if $XSLT::debug;
          warn ("apply-templates: Dunno what to do with nodes of type $ref !!! ($child_xml_selection_path)$/") if $XSLT::warnings;
      }

    $_indent -= $_indent_incr;
  }

  $_indent -= $_indent_incr;
}

sub _evaluate_element {
  my $parser = shift;
  my $xsl_node = shift;
  my $current_xml_node = shift;
  my $current_xml_selection_path = shift;
  my $current_result_node = shift;

  my $xsl_tag = $xsl_node->getTagName;
  print " "x$_indent,"evaluating element $xsl_tag for \"$current_xml_selection_path\": $/" if $XSLT::debug;
  $_indent += $_indent_incr;

  if ($xsl_tag =~ /^xsl:/i) {
      if ($xsl_tag =~ /^xsl:apply-templates/i) {

          $parser->_apply_templates ($current_xml_node,
        			     $current_xml_selection_path,
                                     $current_result_node);
#      } elsif ($xsl_tag =~ /^xsl:call-template/i) {
#      } elsif ($xsl_tag =~ /^xsl:choose/i) {
#      } elsif ($xsl_tag =~ /^xsl:for-each/i) {
#      } elsif ($xsl_tag =~ /^xsl:include/i) {
#      } elsif ($xsl_tag =~ /^xsl:output/i) {
#      } elsif ($xsl_tag =~ /^xsl:processing-instruction/i) {
      } elsif ($xsl_tag =~ /^xsl:value-of/i) {

          $parser->_value_of ($xsl_node, $current_xml_node,
                              $current_xml_selection_path,
                              $current_result_node);
      } else {
          $parser->_add_and_recurse ($xsl_node, $current_xml_node,
                                     $current_xml_selection_path,
                                     $current_result_node);
      }
  } else {
      $parser->_add_and_recurse ($xsl_node, $current_xml_node,
                                 $current_xml_selection_path,
                                 $current_result_node);
  }

  $_indent -= $_indent_incr;
}

  sub _add_and_recurse {
    my $parser = shift;
    my $xsl_node = shift;
    my $current_xml_node = shift;
    my $current_xml_selection_path = shift;
    my $current_result_node = shift;

    $parser->_add_node ($xsl_node, $current_result_node);
    $parser->_evaluate_template ($xsl_node,
    				 $current_xml_node,
                                 $current_xml_selection_path,
                                 $current_result_node->getLastChild);
  }

sub _value_of {
  my $parser = shift;
  my $xsl_node = shift;
  my $current_xml_node = shift;
  my $current_xml_selection_path = shift;
  my $current_result_node = shift;

  my $select = $xsl_node->getAttribute('select');
  my $xml_node = $parser->_get_node_from_path ($select, $XSLT::xml,
                                               $current_xml_selection_path,
                                               $current_xml_node);
  my $fragment_of_texts = $XSLT::xml->createDocumentFragment;
  &_strip_node_to_texts ($xml_node, $fragment_of_texts);

  $parser->_add_node ($fragment_of_texts, $current_result_node);
}

  sub __strip_node_to_texts__ {
    my $parser = shift;
    my $node = shift;
    my $fragment = shift;
    
    if ($node->getNodeType == TEXT_NODE) {
      $parser->_add_node ($node, $fragment);
    } elsif ($node->getNodeType == ELEMENT_NODE) {
      foreach my $child ($node->getChildNodes) {
        &__strip_node_to_texts__ ($child, $fragment);
      }
    }
  }

sub _get_node_from_path {
  my $parser = shift;
  my $path = shift;
  my $root_node = shift;
  my $current_path = (shift || "/");
  my $current_node = (shift || $root_node);

  if ($path eq $current_path || $path eq ".") {
    return $current_node;
  } else {
    if ($path =~ /^\//) {
      # start from the root #
      $current_node = $root_node;
    } elsif ($path =~ /^\.\//) {
      # voorlopende punt bij "./etc" weghalen #
      $path =~ s/^\.//;
    } else {
      # voor het parseren, path beginnen met / #
      $path = "/$path" unless $path =~ /^\@/;
    }
    
    return $parser->__get_node_from_path__($path, $current_node);
  }
}

  sub __get_node_from_path__ {
    my $parser = shift;
    my $path = shift;
    my $node = shift;

    if ($path eq "") {
      return $node;
    } else {
      if ($path =~ /^\/(\w+)\[(\d+?)\]/) {

        # /elem[n] #
        return &__indexed_element__($1, $2, $path, $node);

      } elsif ($path =~ /^\/(\w+)/) {
 
        # /elem #
        return &__element__($1, $2, $path, $node);

      } elsif ($path =~ /^\/\/(\w+)\[(\d+?)\]/) {
 
        # //elem[n] #
        return &__indexed_element__($1, $2, $path, $node, "deep");

      } elsif ($path =~ /^\/\/(\w+)/) {

        # //elem #
        return &__element__($1, $2, $path, $node, "deep");

      } elsif ($path =~ /^\@(\w+)/) {

        # @attr #
        return &__attribute__($1, $path, $node);

      } else {
      
        warn ("get-node-from-path: Dunno what to do with path $path !!!$/") if $XSLT::warnings;

      }
    }
  }

    sub __indexed_element__ {
        my ($element, $index, $path, $node, $deep) = @_;
        $deep = 0 unless defined $deep;

        if ($deep) {
          $path =~ s/^\/\/$element\[$index\]//;
        } else {
          $path =~ s/^\/$element\[$index\]//;
        }
        return __get_node_from_path__($path, $node->getElementsByTagName($element, $deep)->item($index));
    }

    sub __element__ {
        my ($element, $path, $node, $deep) = @_;
        $deep = 0 unless defined $deep;

        if ($deep) {
          $path =~ s/^\/\/$element//;
        } else {
          $path =~ s/^\/$element//;
        }
        return __get_node_from_path__($path, $node->getElementsByTagName($element, $deep)->item(0));
    }

    sub __attribute__ {
        my ($attribute, $path, $node) = @_;

        $path =~ s/^\@$attribute//;
        return __get_node_from_path__($path, $node->getAttributeNode($attribute));
    }


######################################################################
package XSLT;
######################################################################

use strict;

BEGIN {
  use Exporter ();
  use vars qw( $VERSION @ISA @EXPORT @EXPORT_OK);

  $VERSION = '0.14';

  @ISA         = qw( Exporter );
  @EXPORT_OK   = qw( $Parser $debug $warnings);

  use vars @EXPORT_OK;
  $XSLT::Parser   = new XML::XSLTParser;
  $XSLT::debug    = "";
  $XSLT::warnings = "active";
}

use vars qw ( $xsl $xml $result $DOMparser $outputstring);

1;
