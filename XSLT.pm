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
use LWP::UserAgent;

BEGIN {
  require XML::DOM;

  my $needVersion = '1.25';
  my $domVersion = $XML::DOM::VERSION;
  die "need at least XML::DOM version $needVersion (current=$domVersion)"
    unless $domVersion >= $needVersion;

  use Exporter ();
  use vars qw( @ISA @EXPORT);

  @ISA         = qw( Exporter );
  @EXPORT      = qw( &new &openproject &process_project &print_result );

  use vars qw ( $_indent $_indent_incr $_xsl_dir );
  $_indent = 0;
  $_indent_incr = 1;
  $_xsl_dir = "";
}



sub new {
  my ($class) = @_;

  return bless {}, $class;  
}

sub openproject {
  my ($parser) = shift;
  
  print "This function is depricated, please use open_project. Thank you...$/";
  
  $parser->open_project(@_);
}

sub open_project {
  my ($parser, $xml, $xsl, $xmlflag, $xslflag) = @_;
  $xmlflag = "FILE" unless defined $xmlflag;
  $xslflag = "FILE" unless defined $xslflag;

  my $xmlencoding = "";
  my $xslencoding = "";

  $XSLT::DOMparser = new XML::DOM::Parser;
  XML::DOM::setTagCompression (\&__my_tag_compression__);

  # parsing of XML

  if ($xmlflag =~ /^F/i) {
    if ((ref \$xml) =~ /SCALAR/i) {
      if (open (FILE, $xml)) {
        my ($line) = <FILE>;
        $xmlencoding = $1 if ($line =~ /encoding="(.*?)"/i);
      }
      if ($xmlencoding) {
        $XSLT::xml = $XSLT::DOMparser->parsefile ($xml, 'ProtocolEncoding' => $xmlencoding);
      } else {
        $XSLT::xml = $XSLT::DOMparser->parsefile ($xml);
      }
    } else {
      my @file = <$xml>;
      $xmlencoding = $1 if ($file[1] =~ /encoding="(.*?)"/i);
      $xml = join ("", @file);
      if ($xmlencoding) {
        $XSLT::xml = $XSLT::DOMparser->parse ($xml, 'ProtocolEncoding' => $xmlencoding);
      } else {
        $XSLT::xml = $XSLT::DOMparser->parse ($xml);
      }
    }
  } elsif ($xmlflag =~ /^D/i) {
    if ((ref $xml) =~ /Document$/i) {
      $XSLT::xml = $xml;
    } else {
      die ("Error: You have to pass a Document node to open_project when passing a DOM tree$/");
    }
  } else {
    if ((ref $xml) =~ /SCALAR/i) {
      $xmlencoding = $1 if ($$xml =~ /<\?xml.*?encoding="(.*?)".*?\?>/i);
      if ($xmlencoding) {
        $XSLT::xml = $XSLT::DOMparser->parse ($$xml, 'ProtocolEncoding' => $xmlencoding);
      } else {
        $XSLT::xml = $XSLT::DOMparser->parse ($$xml);
      }
    } else {
      $xmlencoding = $1 if ($xml =~ /<\?xml.*?encoding="(.*?)".*?\?>/i);
      if ($xmlencoding) {
        $XSLT::xml = $XSLT::DOMparser->parse ($xml, 'ProtocolEncoding' => $xmlencoding);
      } else {
        $XSLT::xml = $XSLT::DOMparser->parse ($xml);
      }
    }
  }

  # parsing of XSL

  if ($xslflag =~ /^F/i) {
    $_xsl_dir = $xsl;
    $_xsl_dir =~ s/\/[\w\.]+$//;
    if ((ref \$xsl) =~ /SCALAR/i) {
      if (open (FILE, $xsl)) {
        my ($line) = <FILE>;
        $xslencoding = $1 if ($line =~ /encoding="(.*?)"/i);
      }
      if ($xslencoding) {
        $XSLT::xsl = $XSLT::DOMparser->parsefile ($xsl, 'ProtocolEncoding' => $xslencoding, 'KeepCDATA' => 1);
      } else {
        $XSLT::xsl = $XSLT::DOMparser->parsefile ($xsl, 'KeepCDATA' => 1);
      }
    } else {
      my @file = <$xsl>;
      $xslencoding = $1 if ($file[1] =~ /encoding="(.*?)"/i);
      $xsl = join ("", @file);
      if ($xslencoding) {
        $XSLT::xsl = $XSLT::DOMparser->parse ($xsl, 'ProtocolEncoding' => $xslencoding);
      } else {
        $XSLT::xsl = $XSLT::DOMparser->parse ($xsl);
      }
    }
  } elsif ($xslflag =~ /^D/i) {
    $_xsl_dir = ".";
    if ((ref $xsl) =~ /Document$/i) {
      $XSLT::xsl = $xsl;
    } else {
      die ("Error: You have to pass a Document node to open_project when passing a DOM tree$/");
    }
  } else {
    $_xsl_dir = ".";
    if ((ref $xsl) =~ /SCALAR/i) {
      $xslencoding = $1 if ($$xsl =~ /<\?xml.*?encoding="(.*?)".*?\?>/i);
      if ($xslencoding) {
        $XSLT::xsl = $XSLT::DOMparser->parse ($$xsl, 'ProtocolEncoding' => $xslencoding);
      } else {
        $XSLT::xsl = $XSLT::DOMparser->parse ($$xsl);
      }
    } else {
      $xslencoding = $1 if ($xsl =~ /<\?xml.*?encoding="(.*?)".*?\?>/i);
      if ($xslencoding) {
        $XSLT::xsl = $XSLT::DOMparser->parse ($xsl, 'ProtocolEncoding' => $xslencoding);
      } else {
        $XSLT::xsl = $XSLT::DOMparser->parse ($xsl);
      }
    }
  }
  $XSLT::result = $XSLT::xml->createDocumentFragment;

  $parser->__expand_xsl_includes__($XSLT::xsl);
  $parser->__add_default_templates__($XSLT::xsl);
}

  sub __my_tag_compression__ {
     my ($tag, $elem) = @_;

     # Print empty br, hr and img tags like this: <br />
     return 2 if $tag =~ /^(br|p|hr|img|meta|base|link)$/i;

     # Print other empty tags like this: <empty></empty>
     return 1;
  }


sub process_project {
  my ($parser) = @_;
  my $root_template = $parser->_find_template ("match", '/');

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

#  $XSLT::result->printToFileHandle (\*STDOUT);
#  exit;

  $XSLT::outputstring = $XSLT::result->toString;
  $XSLT::outputstring =~ s/\n\s*\n(\s*)\n/\n$1\n/g; # Substitute multiple empty lines by one
#  $XSLT::outputstring =~ s/\/\>/ \/\>/g;            # Insert a space before all />

  if (defined $file) {
    if ((ref \$file) =~ /GLOB/i) {
      print $file $XSLT::outputstring,$/;
    } else {
      if (open (FILE, ">$file")) {
        print FILE $XSLT::outputstring,$/;
        if (! close (FILE)) {
          print "Error writing $file: $!. Nothing written...$/" if !$XSLT::warnings;
          warn "Error writing $file: $!. Nothing written...$/" if $XSLT::warnings;
        }
      } else {
        print "Error writing $file: $!. Nothing written...$/" if !$XSLT::warnings;
        warn "Error writing $file: $!. Nothing written...$/" if $XSLT::warnings;
      }
    }
  } else {
    print $XSLT::outputstring,$/;
  }
  #=item printToFile (filename)
  #
  #Prints the entire subtree to the file with the specified filename.
  #
  #Croaks: if the file could not be opened for writing.
  #
  #=item printToFileHandle (handle)
  #
  #Prints the entire subtree to the file handle.
  #E.g. to print to STDOUT:
  #
  # $node->printToFileHandle (\*STDOUT);
  #
  #=item print (obj)
  #
  #Prints the entire subtree using the object's print method. E.g to print to a
  #FileHandle object:
  #
  # $f = new FileHandle ("file.out", "w");
  # $node->print ($f);
}

######################################################################

  sub __add_default_templates__ {
    # Add the default templates for match="/" and match="*" #
    my $parser = shift;
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

  sub __expand_xsl_includes__ {
    # replace the <xsl:include> tags by the content of the files #
    my $parser = shift;
    my $root_node = shift;

    my $include_nodes = $root_node->getElementsByTagName('xsl:include');

    foreach my $include_node (@$include_nodes) {
      # get include file name and look if exists
      my $include_file = $include_node->getAttribute('href');
      if ($include_file) {
        if ($include_file =~ /^http:/i) {
        
          # Use UserAgent to request a GET HTTP
          my $useragent = new LWP::UserAgent;
          my $request = new HTTP::Request GET => $include_file;
          my $result = $useragent->request($request);

          # Check the outcome of the response
          if ($result->is_success) {
            print " "x$_indent,"expanding included URL $include_file$/" if $XSLT::debug;

            # parse file and insert tree into xsl tree
            my $include_doc = $XSLT::DOMparser->parse ($result->content);

            &__include_stylesheet__ ($include_doc, $XSLT::xsl, $include_node);

          } else {
            print " "x$_indent,"include URL $include_file can not be requested!$/" if $XSLT::debug;
            warn "include URL $include_file can not be requested!$/" if $XSLT::warnings;
          }
        } else {
          if ($include_file !~ /^\//i) {
            $include_file = "$_xsl_dir/$include_file";
          }

          if (-f $include_file) {

            print " "x$_indent,"expanding included file $include_file$/" if $XSLT::debug;

            # parse file and insert tree into xsl tree
            my $include_doc = $XSLT::DOMparser->parsefile ($include_file);

            &__include_stylesheet__ ($include_doc, $XSLT::xsl, $include_node);

          } else {
            print " "x$_indent,"include $include_file can not be read!$/" if $XSLT::debug;
            warn "include $include_file can not be read!$/" if $XSLT::warnings;
          }
        }
      } else {
        print " "x$_indent,"xsl:include tag carries no selection!$/" if $XSLT::debug;
        warn "xsl:include tag carries no selection!$/" if $XSLT::warnings;
      }
    }
  }

  sub __include_stylesheet__ {
    my $include_doc  = shift;
    my $root         = shift;
    my $include_node = shift;

    $include_doc = $include_doc->getElementsByTagName('xsl:stylesheet',0)->item(0);
    $include_doc->setOwnerDocument ($root);
    my $include_fragment = $root->createDocumentFragment;

    foreach my $child ($include_doc->getChildNodes) {
      $include_fragment->appendChild($child);
    }

    my $include_parent = $include_node->getParentNode;
    $include_parent->insertBefore($include_fragment, $include_node);
    $include_parent->removeChild($include_node);
  }

sub _find_template {
  my $parser = shift;
  my $attribute_name = shift;
  my $current_xml_selection_path = shift;
  my $mode = shift;
  $mode = 0 unless defined $mode;
  
  my $template = "";
  
  if ($attribute_name =~ "match" || $attribute_name =~ "name") {

    print " "x$_indent,"searching template for \"$current_xml_selection_path\":$/" if $XSLT::debug;

    my $stylesheet = $XSLT::xsl->getElementsByTagName('xsl:stylesheet',0)->item(0);

    my $count = 0;
    foreach my $child ($stylesheet->getElementsByTagName('*',0)) {
      if ($child->getTagName =~ /^xsl:template$/i) {
        $count++;

        my $template_attr_value = $child->getAttribute ($attribute_name);

        if (&__template_matches__ ($template_attr_value, $current_xml_selection_path)) {
          print " "x$_indent,"  found #$count \"$template_attr_value\"$/" if $XSLT::debug;
          $template = $child;
        } else {
          print " "x$_indent,"  #$count \"$template_attr_value\" does not match$/" if $XSLT::debug;
        }

      }
    }

    if (! $template) {
      print "no template found! $/" if $XSLT::debug;
      warn ("No template matching $current_xml_selection_path found !!$/") if $XSLT::debug;
    } elsif ($XSLT::debug) {
      my $template_attr_value = $template->getAttribute ($attribute_name);
      print " "x$_indent,"  using \"$template_attr_value\"$/";
    }
  } else {

    print "XSLT: find! $/" if $XSLT::debug;
    warn ("No template matching $current_xml_selection_path found !!$/") if $XSLT::debug;

  }

  return $template;
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

  print " "x$_indent,"evaluating template content with \"$current_xml_selection_path\": $/" if $XSLT::debug;
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
      } elsif ($child->getNodeType == CDATA_SECTION_NODE) {
        my $text = $XSLT::xml->createTextNode ($child->getNodeValue);
        $parser->_add_node($text, $current_result_node);
      } elsif ($child->getNodeType == ENTITY_REFERENCE_NODE) {
        $parser->_add_node($child, $current_result_node);
      } elsif ($child->getNodeType == DOCUMENT_TYPE_NODE) {
          # skip #
      } elsif ($child->getNodeType == COMMENT_NODE) {
          # skip #
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

  print " "x$_indent,"adding node (deep)..$/" if $XSLT::debug && $deep;
  print " "x$_indent,"adding node (non-deep)..$/" if $XSLT::debug && !$deep;

  $node = $node->cloneNode($deep);
  $node->setOwnerDocument($owner);
  $parent->appendChild($node);
}

sub _apply_templates {
  my $parser = shift;
  my $xsl_node = shift;
  my $current_xml_node = shift;
  my $current_xml_selection_path = (shift || "");
  my $current_result_node = shift;

  my $match = $xsl_node->getAttribute ('select');
  my $children;
  if ($match) {
    print " "x$_indent,"applying templates on children $match of \"$current_xml_selection_path\":$/" if $XSLT::debug;
    $children = $parser->_get_node_from_path ($match, $XSLT::xml,
                                              $current_xml_selection_path,
    					      $current_xml_node,
                                              "asNodeList");
  } else {
    print " "x$_indent,"applying templates on all children of \"$current_xml_selection_path\":$/" if $XSLT::debug;
    my @children = $current_xml_node->getChildNodes;
    $children = \@children;
  }

  $_indent += $_indent_incr;

  for (my $i = 0; $i < @$children;$i++) {
    my $child = $$children[$i];
    my $ref = ref $child;
    print " "x$_indent,"$ref$/" if $XSLT::debug;
    $_indent += $_indent_incr;

      if ($child->getNodeType == DOCUMENT_NODE) {
        $child = $child->getFirstChild;
      }
      my $child_xml_selection_path = $child->getNodeName;
      $child_xml_selection_path = "$current_xml_selection_path/$child_xml_selection_path";

      if ($child->getNodeType == ELEMENT_NODE) {
          my $template = $parser->_find_template ("match", $child_xml_selection_path);

          if ($template) {

              $parser->_evaluate_template ($template,
		 	                   $child,
                                           $child_xml_selection_path,
                                           $current_result_node);
          }
      } elsif ($child->getNodeType == TEXT_NODE) {
          $parser->_add_node($child, $current_result_node);
      } elsif ($child->getNodeType == CDATA_SECTION_NODE) {
          my $text = $XSLT::xml->createTextNode ($child->getNodeValue);
          $parser->_add_node($text, $current_result_node);
      } elsif ($child->getNodeType == ENTITY_REFERENCE_NODE) {
          $parser->_add_node($child, $current_result_node);
      } elsif ($child->getNodeType == DOCUMENT_TYPE_NODE) {
          # skip #
      } elsif ($child->getNodeType == COMMENT_NODE) {
          # skip #
      } elsif ($child->getNodeType == PROCESSING_INSTRUCTION_NODE) {
          # skip #
      } else {
          print " "x$_indent,"Cannot apply templates on nodes of type $ref$/" if $XSLT::debug;
          warn ("apply-templates: Dunno what to do with nodes of type $ref !!! ($child_xml_selection_path)$/") if $XSLT::warnings;
      }

    $_indent -= $_indent_incr;
  }
}

sub _evaluate_element {
  my $parser = shift;
  my $xsl_node = shift;
  my $current_xml_node = shift;
  my $current_xml_selection_path = shift;
  my $current_result_node = shift;

  my $xsl_tag = $xsl_node->getTagName;
  print " "x$_indent,"evaluating element $xsl_tag from \"$current_xml_selection_path\": $/" if $XSLT::debug;
  $_indent += $_indent_incr;

  if ($xsl_tag =~ /^xsl:/i) {
      if ($xsl_tag =~ /^xsl:apply-templates$/i) {
          $parser->_apply_templates ($xsl_node, $current_xml_node,
        			     $current_xml_selection_path,
                                     $current_result_node);

      } elsif ($xsl_tag =~ /^xsl:attribute$/i) {
          $parser->_attribute ($xsl_node, $current_xml_node,
        		       $current_xml_selection_path,
                               $current_result_node);

      } elsif ($xsl_tag =~ /^xsl:call-template$/i) {
          $parser->_call_template ($xsl_node, $current_xml_node,
        			   $current_xml_selection_path,
                                   $current_result_node);

      } elsif ($xsl_tag =~ /^xsl:choose$/i) {
          $parser->_choose ($xsl_node, $current_xml_node,
        		    $current_xml_selection_path,
                            $current_result_node);

      } elsif ($xsl_tag =~ /^xsl:comment$/i) {
          $parser->_comment ($xsl_node, $current_xml_node,
        		     $current_xml_selection_path,
                             $current_result_node);

      } elsif ($xsl_tag =~ /^xsl:copy$/i) {
          $parser->_copy ($xsl_node, $current_xml_node,
                          $current_result_node);

      } elsif ($xsl_tag =~ /^xsl:copy-of$/i) {
          $parser->_copy_of ($xsl_node, $current_xml_node,
        		     $current_xml_selection_path,
                             $current_result_node);

      } elsif ($xsl_tag =~ /^xsl:for-each$/i) {
          $parser->_for_each ($xsl_node, $current_xml_node,
        		      $current_xml_selection_path,
                              $current_result_node);

      } elsif ($xsl_tag =~ /^xsl:if$/i) {
          $parser->_if ($xsl_node, $current_xml_node,
        		$current_xml_selection_path,
                        $current_result_node);

#      } elsif ($xsl_tag =~ /^xsl:output$/i) {

      } elsif ($xsl_tag =~ /^xsl:processing-instruction$/i) {
          $parser->_processing_instruction ($xsl_node, $current_result_node);

      } elsif ($xsl_tag =~ /^xsl:text$/i) {
          $parser->_text ($xsl_node, $current_result_node);

      } elsif ($xsl_tag =~ /^xsl:value-of$/i) {
          $parser->_value_of ($xsl_node, $current_xml_node,
                              $current_xml_selection_path,
                              $current_result_node);
      } else {
          $parser->_add_and_recurse ($xsl_node, $current_xml_node,
                                     $current_xml_selection_path,
                                     $current_result_node);
      }
  } else {

      $parser->_check_attributes_and_recurse ($xsl_node, $current_xml_node,
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

    # the addition is commented out to prevent unknown xsl: commands to be printed in the result
    #$parser->_add_node ($xsl_node, $current_result_node);
    $parser->_evaluate_template ($xsl_node, $current_xml_node,
                                 $current_xml_selection_path,
                                 $current_result_node);#->getLastChild);
  }

  sub _check_attributes_and_recurse {
    my $parser = shift;
    my $xsl_node = shift;
    my $current_xml_node = shift;
    my $current_xml_selection_path = shift;
    my $current_result_node = shift;

    $parser->_add_node ($xsl_node, $current_result_node);
    $parser->_attribute_value_of ($current_result_node->getLastChild,
    				  $current_xml_node,
                                  $current_xml_selection_path);
    $parser->_evaluate_template ($xsl_node, $current_xml_node,
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
  my $xml_node;
  if ($select) {
    $xml_node = $parser->_get_node_from_path ($select, $XSLT::xml,
                                              $current_xml_selection_path,
                                              $current_xml_node);
  } else {
    $xml_node = $current_xml_node;
  }

  if ($xml_node) {
    print " "x$_indent,"stripping node to text:$/" if $XSLT::debug;

    $_indent += $_indent_incr;
      my $text = &__strip_node_to_text__ ($parser, $xml_node);
    $_indent -= $_indent_incr;

    if ($text) {
      $parser->_add_node ($XSLT::xml->createTextNode($text), $current_result_node);
    } else {
      print " "x$_indent,"nothing left..$/" if $XSLT::debug;
    }
  } else {
    print " "x$_indent,"selecting value of \"$select\" from \"$current_xml_selection_path\" failed!!!$/" if $XSLT::debug;
    warn "Cannot select value of \"$select\" from \"$current_xml_selection_path\"$/" if $XSLT::warnings;
  }
}

  sub __strip_node_to_text__ {
    my $parser = shift;
    my $node = shift;
    
    my $result = "";

    if ($node->getNodeType == TEXT_NODE) {
      $result = $node->getNodeValue;
    } elsif (($node->getNodeType == ELEMENT_NODE)
         || ($node->getNodeType == DOCUMENT_FRAGMENT_NODE)) {
      print " "x$_indent,"stripping child nodes:$/" if $XSLT::debug;
      $_indent += $_indent_incr;
      foreach my $child ($node->getChildNodes) {
        $result .= &__strip_node_to_text__ ($parser, $child);
      }
      $_indent -= $_indent_incr;
    }
    return $result;
  }

sub _move_node {
  my $parser = shift;
  my $node = shift;
  my $parent = shift;

  print " "x$_indent,"moving node..$/" if $XSLT::debug;

  $parent->appendChild($node);
}

sub _get_node_from_path {
  my $parser = shift;
  my $path = (shift || "");
  my $root_node = shift;
  my $current_path = (shift || "/");
  my $current_node = (shift || $root_node);
  my $multi = (shift || 0);

  print " "x$_indent,"getting NodeList of \"$path\" from \"$current_path\"" if $XSLT::debug && $multi;
  print " "x$_indent,"getting value of \"$path\" from \"$current_path\"" if $XSLT::debug && ! $multi;

  if ($path eq $current_path || $path eq ".") {
    print ": direct hit!$/" if $XSLT::debug;
    if ($multi) {
      return [$current_node];
    } else {
      return $current_node;
    }
  } else {
    if ($path =~ /^\s*document\s*\(["'](.*?)["']\s*,\s*(.*)\)\s*$/i) {
      # a selection in a different document!
      $path = $2;
      $current_node = &__open_document__($parser, $1);
    } elsif ($path =~ /^\//) {
      # start from the root #
      $current_node = $root_node;
    } elsif ($path =~ /^\.\//) {
      # voorlopende punt bij "./etc" weghalen #
      $path =~ s/^\.//;
    } else {
      # voor het parseren, path beginnen met / #
      $path = "/$path";
    }
    
    print " using \"$path\": $/" if $XSLT::debug;
    $_indent += $_indent_incr;
      $current_node = &__get_node_from_path__($parser, $path, $current_node, $multi);
    $_indent -= $_indent_incr;
    
    if ($multi) {
      if ((ref $current_node) !~ /(ARRAY|NodeList)/i) {
        return [$current_node];
      } else {
        return $current_node;
      }
    } elsif ($current_node && $current_node->getNodeType == ATTRIBUTE_NODE) {
      return $XSLT::xml->createTextNode ($current_node->getValue);
    } else {
      return $current_node;
    }
  }
}

  sub __open_document__ {
    my $parser = shift;
    my $new_document = shift;
    my $path = shift;
    if ($new_document) {
      if ($new_document =~ /^http:/i) {

        # Use UserAgent to request a GET HTTP
        my $useragent = new LWP::UserAgent;
        my $request = new HTTP::Request GET => $new_document;
        my $result = $useragent->request($request);

        # Check the outcome of the response
        if ($result->is_success) {
          print " "x$_indent,"expanding included URL $new_document$/" if $XSLT::debug;

          # parse file and return tree
          return $XSLT::DOMparser->parse ($result->content);

        } else {
          print " "x$_indent,"include URL $new_document can not be requested!$/" if $XSLT::debug;
          warn "include URL $new_document can not be requested!$/" if $XSLT::warnings;
        }
      } else {
        if ($new_document !~ /^(\/|\.)/i) {
          $new_document = "$_xsl_dir/$new_document";
        }

        if (-f $new_document) {

          print " "x$_indent,"expanding included file $new_document$/" if $XSLT::debug;

          # parse file and return tree
          return $XSLT::DOMparser->parsefile ($new_document);

        } else {
          print " "x$_indent,"include $new_document can not be read!$/" if $XSLT::debug;
          warn "include $new_document can not be read!$/" if $XSLT::warnings;
        }
      }
    } else {
      print " "x$_indent,"no document to open!$/" if $XSLT::debug;
      warn "no document to open!$/" if $XSLT::warnings;
    }
    return "";
  }

  sub __get_node_from_path__ {
    my $parser = shift;
    my $path = (shift || "");
    my $node = shift;
    my $multi = shift;

    # a Qname should actually be: [a-Z_][\w\.\-]*

    if ($path eq "") {

      print " "x$_indent,"node found!$/" if $XSLT::debug;
      return $node;

    } else {
      if ($multi) {
        #print " "x$_indent,"dunno how to process a NodeList yet (\"$path\")$/" if $XSLT::debug;
        #warn ("get-node-from-path: Dunno how to process a NodeList yet !!!$/") if $XSLT::warnings;
        if ((ref $node) =~ /NodeList/i) {
          my $list = [];
          foreach my $item (@$node) {
            my $sublist = &__try_a_step__($parser, $path, $item, $multi);
            push (@$list, @$sublist);
          }
          return $list;
        } else {
          return &__try_a_step__($parser, $path, $node, $multi);
        }
      } else {
        if ((ref $node) =~ /NodeList/i) {
          print " "x$_indent,"dunno how to select from a NodeList (\"$path\")$/" if $XSLT::debug;
          warn ("get-node-from-path: Dunno how to select from a NodeList !!!$/") if $XSLT::warnings;
          return "";
        } else {
          return &__try_a_step__($parser, $path, $node, $multi);
        }
      }
    }
  }

    sub __try_a_step__ {
      my $parser = shift;
      my $path = (shift || "");
      my $node = shift;
      my $multi = shift;

      study ($path);
      if ($path =~ /^\/\.\.\//) {

        # /.. #
        print " "x$_indent,"getting parent (\"$path\")$/" if $XSLT::debug;
        return &__parent__($parser, $path, $node, $multi);

      } elsif ($path =~ /^\/([\w\.\:\-]+)\[(\d+?)\]/) {

        # /elem[n] #
        print " "x$_indent,"getting indexed element $1 $2 (\"$path\")$/" if $XSLT::debug;
        return &__indexed_element__($parser, $1, $2, $path, $node, $multi);

      } elsif ($path =~ /^\/([\w\.\:\-]+)/) {

        # /elem #
        print " "x$_indent,"getting element $1 (\"$path\")$/" if $XSLT::debug;
        return &__element__($parser, $1, $path, $node, $multi);

      } elsif ($path =~ /^\/\/([\w\.\:\-]+)\[(\d+?)\]/) {

        # //elem[n] #
        print " "x$_indent,"getting deep indexed element $1 $2 (\"$path\")$/" if $XSLT::debug;
        return &__indexed_element__($parser, $1, $2, $path, $node, $multi, "deep");

      } elsif ($path =~ /^\/\/([\w\.\:\-]+)/) {

        # //elem #
        print " "x$_indent,"getting deep element $1 (\"$path\")$/" if $XSLT::debug;
        return &__element__($parser, $1, $path, $node, $multi, "deep");

      } elsif ($path =~ /^\/\@([\w\.\:\-]+)/) {

        # /@attr #
        print " "x$_indent,"getting attribute $1 (\"$path\")$/" if $XSLT::debug;
        return &__attribute__($parser, $1, $path, $node, $multi);

      } else {
        print " "x$_indent,"dunno what to do with path $path !!!$/" if $XSLT::debug;
        warn ("get-node-from-path: Dunno what to do with path $path !!!$/") if $XSLT::warnings;
        return [] if $multi;
        return "" if !$multi;
      }
    }

    sub __parent__ {
        my $parser = shift;
        my $path = (shift || "");
        my $node = shift;
        my $multi = shift;

        $path =~ s/^\/\.\.//;

        $_indent += $_indent_incr;
        if (($node->getNodeType == DOCUMENT_NODE)
          || ($node->getNodeType == DOCUMENT_FRAGMENT_NODE)) {
          print " "x$_indent,"no parent!$/" if $XSLT::debug;
        } else {
          $node = $node->getParentNode;
        }

        if ($node) {
          $node = &__get_node_from_path__($parser, $path, $node, $multi);
        } else {
          print " "x$_indent,"failed!$/" if $XSLT::debug;
        }
        $_indent -= $_indent_incr;

        return [$node] if $multi;
        return $node if !$multi;
    }

    sub __indexed_element__ {
        my $parser = shift;
        my $element = (shift || "");
        my $index = (shift || 0);
        my $path = (shift || "");
        my $node = shift;
        my $multi = shift;
        my $deep = shift;
        $deep = 0 unless defined $deep;

        if ($deep) {
          $path =~ s/^\/\/$element\[$index\]//;
        } else {
          $path =~ s/^\/$element\[$index\]//;
        }

        $node = $node->getElementsByTagName($element, $deep)->item($index-1);

        $_indent += $_indent_incr;
        if ($node) {
          $node = &__get_node_from_path__($parser, $path, $node, $multi);
        } else {
          print " "x$_indent,"failed!$/" if $XSLT::debug;
        }
        $_indent -= $_indent_incr;
        return [$node] if $multi;
        return $node if !$multi;
    }

    sub __element__ {
        my $parser = shift;
        my $element = (shift || "");
        my $path = (shift || "");
        my $node = shift;
        my $multi = shift;
        my $deep = shift;
        $deep = 0 unless defined $deep;

        if ($deep) {
          $path =~ s/^\/\/$element//;
        } else {
          $path =~ s/^\/$element//;
        }

        $node = $node->getElementsByTagName($element, $deep);
        $node = $node->item(0) if (! $multi);

        $_indent += $_indent_incr;
        if ($node) {
          $node = &__get_node_from_path__($parser, $path, $node, $multi);
        } else {
          print " "x$_indent,"failed!$/" if $XSLT::debug;
        }
        $_indent -= $_indent_incr;
        return $node;
    }

    sub __attribute__ {
        my $parser = shift;
        my $attribute = (shift || "");
        my $path = (shift || "");
        my $node = shift;
        my $multi = shift;

        $path =~ s/^\/\@$attribute//;
        $node = $node->getAttributeNode($attribute);

        $_indent += $_indent_incr;
        if ($node) {
          $node = &__get_node_from_path__($parser, $path, $node, $multi);
        } else {
          print " "x$_indent,"failed!$/" if $XSLT::debug;
        }
        $_indent -= $_indent_incr;
        return [$node] if $multi;
        return $node if !$multi;
    }

sub _attribute_value_of {
  my $parser = shift;
  my $xsl_node = shift;
  my $current_xml_node = shift;
  my $current_xml_selection_path = shift;

  my $attributes = $xsl_node->getAttributes;

  for (my $i = 0; $i < $attributes->getLength; $i++) {
    my $attribute = $attributes->item($i);
    my $value = $attribute->getValue;
    study ($value);
    #$value =~ s/(\*|\$|\@|\&|\?|\+|\\)/\\$1/g;
    $value =~ s/(\*|\?|\+)/\\$1/g;
    study ($value);
    while ($value =~ /\G[^\\]?\{(.*?[^\\]?)\}/) {
      my $node = $parser->_get_node_from_path ($1, $XSLT::xml,
                                               $current_xml_selection_path,
                                               $current_xml_node);
      if ($node) {
        $_indent += $_indent_incr;
          my $text = &__strip_node_to_text__ ($parser, $node);
        $_indent -= $_indent_incr;
        $value =~ s/(\G[^\\]?)\{(.*?)[^\\]?\}/$1$text/;
      } else {
        $value =~ s/(\G[^\\]?)\{(.*?)[^\\]?\}/$1/;
      }
    }
    #$value =~ s/\\(\*|\$|\@|\&|\?|\+|\\)/$1/g;
    $value =~ s/\\(\*|\?|\+)/$1/g;
    $value =~ s/\\(\{|\})/$1/g;
    $attribute->setValue ($value);
  }
}

sub _processing_instruction {
  my $parser = shift;
  my $xsl_node = shift;
  my $current_result_node = shift;

  my $new_PI_name = $xsl_node->getAttribute('name');

  if ($new_PI_name eq "xml") {
    print " "x$_indent,"<xsl:processing-instruction> may not be used to create XML$/" if $XSLT::debug;
    print " "x$_indent,"declaration. Use <xsl:output> instead...$/" if $XSLT::debug;
    warn "<xsl:processing-instruction> may not be used to create XML$/" if $XSLT::warnings;
    warn "declaration. Use <xsl:output> instead...$/" if $XSLT::warning;
  } elsif ($new_PI_name) {
    my $text = &__strip_node_to_texts__ ($xsl_node);
    my $new_PI = $XSLT::xml->createProcessingInstruction($new_PI_name, $text);

    if ($new_PI) {
      $parser->_move_node ($new_PI, $current_result_node);
    }
  } else {
    
  }
}

sub _call_template {
  my $parser = shift;
  my $xsl_node = shift;
  my $current_xml_node = shift;
  my $current_xml_selection_path = shift;
  my $current_result_node = shift;

  my $name = $xsl_node->getAttribute('name');
  
  if ($name) {
    print " "x$_indent,"calling template named \"$name\"$/" if $XSLT::debug;

    $_indent += $_indent_incr;
    my $template = $parser->_find_template ("name", $name);

    if ($template) {
      $parser->_evaluate_template ($template, $current_xml_node,
      				   $current_xml_selection_path,
                                   $current_result_node);
    } else {
      print " "x$_indent,"no template found!$/" if $XSLT::debug;
      warn "no template named $name found!$/" if $XSLT::warnings;
    }
    $_indent -= $_indent_incr;
  } else {
    print " "x$_indent,"expected attribute \"name\" in <xsl:call-template/>$/" if $XSLT::debug;
    warn "expected attribute \"name\" in <xsl:call-template/>$/" if $XSLT::warnings;
  }
}

sub _choose {
  my $parser = shift;
  my $xsl_node = shift;
  my $current_xml_node = shift;
  my $current_xml_selection_path = shift;
  my $current_result_node = shift;

  print " "x$_indent,"evaluating choose:$/" if $XSLT::debug;

  $_indent += $_indent_incr;

  my $notdone = "true";
  my $testwhen = "active";
  foreach my $child ($xsl_node->getElementsByTagName ('*', 0)) {
    if ($notdone && $testwhen && ($child->getTagName eq 'xsl:when')) {
      my $test = $child->getAttribute ('test');

      if ($test) {
        my $test_succeeds = $parser->_evaluate_test ($test, $current_xml_node,
      						     $current_xml_selection_path);
        if ($test_succeeds) {
          $parser->_evaluate_template ($child, $current_xml_node,
        			       $current_xml_selection_path,
                                       $current_result_node);
          $testwhen = "";
          $notdone = "";
        }
      } else {
        print " "x$_indent,"expected attribute \"test\" in <xsl:when>$/" if $XSLT::debug;
        warn "expected attribute \"test\" in <xsl:when>$/" if $XSLT::warnings;
      }
    } elsif ($notdone && ($child->getTagName eq 'xsl:otherwise')) {
      $parser->_evaluate_template ($child, $current_xml_node,
        			   $current_xml_selection_path,
                                   $current_result_node);
      $notdone = "";
    }
  }
  
  if ($notdone) {
  print " "x$_indent,"nothing done!$/" if $XSLT::debug;
  }

  $_indent -= $_indent_incr;
}

sub _if {
  my $parser = shift;
  my $xsl_node = shift;
  my $current_xml_node = shift;
  my $current_xml_selection_path = shift;
  my $current_result_node = shift;

  print " "x$_indent,"evaluating if:$/" if $XSLT::debug;

  $_indent += $_indent_incr;

    my $test = $xsl_node->getAttribute ('test');

    if ($test) {
      my $test_succeeds = $parser->_evaluate_test ($test, $current_xml_node,
      						   $current_xml_selection_path);
      if ($test_succeeds) {
        $parser->_evaluate_template ($xsl_node, $current_xml_node,
        			     $current_xml_selection_path,
                                     $current_result_node);
      }
    } else {
      print " "x$_indent,"expected attribute \"test\" in <xsl:if>$/" if $XSLT::debug;
      warn "expected attribute \"test\" in <xsl:if>$/" if $XSLT::warnings;
    }

  $_indent -= $_indent_incr;
}

sub _evaluate_test {
  my $parser = shift;
  my $test = shift;
  my $current_xml_node = shift;
  my $current_xml_selection_path = shift;

  if ($test =~ /^(.+)\/\[(.+)\]$/) {
    my $path = $1;
    $test = $2;
    
    print " "x$_indent,"evaluating test $test at path $path:$/" if $XSLT::debug;

    $_indent += $_indent_incr;
      my $node = $parser->_get_node_from_path($path, $XSLT::xml,
                                              $current_xml_selection_path,
                                              $current_xml_node);
      if ($node) {
        $current_xml_node = $node;
      } else {
        return "";
      }
    $_indent -= $_indent_incr;
  } else {
    print " "x$_indent,"evaluating path or test $test:$/" if $XSLT::debug;
    my $node = $parser->_get_node_from_path($test, $XSLT::xml,
                                            $current_xml_selection_path,
                                            $current_xml_node);
    $_indent += $_indent_incr;
      if ($node) {
        print " "x$_indent,"path exists!$/" if $XSLT::debug;
        return "true";
      } else {
        print " "x$_indent,"not a valid path, evaluating as test$/" if $XSLT::debug;
      }
    $_indent -= $_indent_incr;
  }

  $_indent += $_indent_incr;
    my $result = &__evaluate_test__ ($test, $current_xml_node);
    if ($result) {
      print " "x$_indent,"test evaluates true..$/" if $XSLT::debug;
    } else {
      print " "x$_indent,"test evaluates false..$/" if $XSLT::debug;
    }
  $_indent -= $_indent_incr;
  return $result;
}

  sub __evaluate_test__ {
    my $test = shift;
    my $node = shift;

#print "testing with \"$test\" and ", ref $node,$/;
    if ($test =~ /^\s*\@([\w\.\:\-]+)\s*!=\s*['"](.*)['"]\s*$/) {
      my $attr = $node->getAttribute($1);
      return ($attr ne $2);
    } elsif ($test =~ /^\s*\@([\w\.\:\-]+)\s*=\s*['"](.*)['"]\s*$/) {
      my $attr = $node->getAttribute($1);
      return ($attr eq $2);
    } elsif ($test =~ /^\s*([\w\.\:\-]+)\s*!=\s*['"](.*)['"]\s*$/) {
      $node->normalize;
      my $content = $node->getFirstChild->getNodeValue;
      return ($content !~ /$2/m);
    } elsif ($test =~ /^\s*([\w\.\:\-]+)\s*=\s*['"](.*)['"]\s*$/) {
      $node->normalize;
      my $content = $node->getFirstChild->getNodeValue;
      return ($content =~ /^\s*$2\s*/m);
    } else {
      return "";
    }
  }

sub _copy_of {
  my $parser = shift;
  my $xsl_node = shift;
  my $current_xml_node = shift;
  my $current_xml_selection_path = shift;
  my $current_result_node = shift;

  my $nodelist;
  my $select = $xsl_node->getAttribute('select');
  print " "x$_indent,"evaluating copy-of with select \"$select\":$/" if $XSLT::debug;
  
  $_indent += $_indent_incr;
  if ($select) {
    $nodelist = $parser->_get_node_from_path ($select, $XSLT::xml,
                                                 $current_xml_selection_path,
    			  		         $current_xml_node,
                                                 "asNodeList");
  } else {
    print " "x$_indent,"expected attribute \"select\" in <xsl:copy-of>$/" if $XSLT::debug;
    warn "expected attribute \"select\" in <xsl:copy-of>$/" if $XSLT::warnings;
  }
  for (my $i = 0; $i < @$nodelist;$i++) {
    my $node = $$nodelist[$i];
    $parser->_add_node ($node, $current_result_node, 1);
  }

  $_indent -= $_indent_incr;
}

sub _copy {
  my $parser = shift;
  my $xsl_node = shift;
  my $current_xml_node = shift;
  my $current_result_node = shift;

  print " "x$_indent,"evaluating copy:$/" if $XSLT::debug;

  $_indent += $_indent_incr;
    $parser->_add_node ($current_xml_node, $current_result_node);
  $_indent -= $_indent_incr;
}

sub _for_each {
  my $parser = shift;
  my $xsl_node = shift;
  my $current_xml_node = shift;
  my $current_xml_selection_path = shift;
  my $current_result_node = shift;

  my $select = $xsl_node->getAttribute ('select');
  if ($select) {
    print " "x$_indent,"applying template for each child $select of \"$current_xml_selection_path\":$/" if $XSLT::debug;
    my $children = $parser->_get_node_from_path ($select, $XSLT::xml,
                                                 $current_xml_selection_path,
    					         $current_xml_node,
                                                 "asNodeList");
    $_indent += $_indent_incr;

    for (my $i = 0; $i < @$children;$i++) {
      my $child = $$children[$i];
      my $ref = ref $child;
      print " "x$_indent,"$ref$/" if $XSLT::debug;
      $_indent += $_indent_incr;

        if ($child->getNodeType == DOCUMENT_NODE) {
          $child = $child->getFirstChild;
        }
        
        my $child_xml_selection_path = $child->getNodeName;
        $child_xml_selection_path = "$current_xml_selection_path/$child_xml_selection_path";

        if ($child->getNodeType == ELEMENT_NODE) {
          $parser->_evaluate_template ($xsl_node,
		 	               $child,
                                       $child_xml_selection_path,
                                       $current_result_node);
        } elsif ($child->getNodeType == TEXT_NODE) {
            $parser->_add_node($child, $current_result_node);
        } elsif ($child->getNodeType == CDATA_SECTION_NODE) {
            my $text = $XSLT::xml->createTextNode ($child->getNodeValue);
            $parser->_add_node($child, $current_result_node);
        } elsif ($child->getNodeType == DOCUMENT_TYPE_NODE) {
            # skip #
        } elsif ($child->getNodeType == COMMENT_NODE) {
            # skip #
        } else {
            print " "x$_indent,"Cannot do a for-each on nodes of type $ref$/" if $XSLT::debug;
            warn ("for-each: Dunno what to do with nodes of type $ref !!! ($child_xml_selection_path)$/") if $XSLT::warnings;
        }

      $_indent -= $_indent_incr;
    }
    $_indent -= $_indent_incr;
  } else {
    print " "x$_indent,"expected attribute \"select\" in <xsl:for-each>$/" if $XSLT::debug;
    warn "expected attribute \"select\" in <xsl:for-each>$/" if $XSLT::warnings;
  }

}

sub _text {
  #=item addText (text)
  #
  #Appends the specified string to the last child if it is a Text node, or else 
  #appends a new Text node (with the specified text.)
  #
  #Return Value: the last child if it was a Text node or else the new Text node.

  my $parser = shift;
  my $xsl_node = shift;
  my $current_result_node = shift;

  print " "x$_indent,"inserting text:$/" if $XSLT::debug;

  $_indent += $_indent_incr;

    print " "x$_indent,"stripping node to text:$/" if $XSLT::debug;

    $_indent += $_indent_incr;
      my $text = &__strip_node_to_text__ ($parser, $xsl_node);
    $_indent -= $_indent_incr;

    if ($text) {
      $parser->_move_node ($XSLT::xml->createTextNode ($text), $current_result_node);
    } else {
      print " "x$_indent,"nothing left..$/" if $XSLT::debug;
    }

  $_indent -= $_indent_incr;
}

sub _attribute {
  my $parser = shift;
  my $xsl_node = shift;
  my $current_xml_node = shift;
  my $current_xml_selection_path = shift;
  my $current_result_node = shift;
  
  my $name = $xsl_node->getAttribute ('name');
  print " "x$_indent,"inserting attribute named \"$name\":$/" if $XSLT::debug;

  $_indent += $_indent_incr;
  if ($name) {
    my $result = $XSLT::xml->createDocumentFragment;

    $parser->_evaluate_template ($xsl_node,
				 $current_xml_node,
				 $current_xml_selection_path,
				 $result);

    $_indent += $_indent_incr;
      my $text = &__strip_node_to_text__ ($parser, $result);
    $_indent -= $_indent_incr;

    $current_result_node->setAttribute($name, $text);
  } else {
    print " "x$_indent,"expected attribute \"name\" in <xsl:attribute>$/" if $XSLT::debug;
    warn "expected attribute \"name\" in <xsl:attribute>$/" if $XSLT::warnings;
  }
  $_indent -= $_indent_incr;
}

sub _comment {
  my $parser = shift;
  my $xsl_node = shift;
  my $current_xml_node = shift;
  my $current_xml_selection_path = shift;
  my $current_result_node = shift;
  
  print " "x$_indent,"inserting comment:$/" if $XSLT::debug;

  $_indent += $_indent_incr;

    my $result = $XSLT::xml->createDocumentFragment;

    $parser->_evaluate_template ($xsl_node,
				 $current_xml_node,
				 $current_xml_selection_path,
				 $result);

    $_indent += $_indent_incr;
      my $text = &__strip_node_to_text__ ($parser, $result);
    $_indent -= $_indent_incr;

    $parser->_move_node ($XSLT::xml->createComment ($text), $current_result_node);

  $_indent -= $_indent_incr;
}

######################################################################
package XSLT;
######################################################################

use strict;

BEGIN {
  use Exporter ();
  use vars qw( $VERSION @ISA @EXPORT @EXPORT_OK);

  $VERSION = '0.20';

  @ISA         = qw( Exporter );
  @EXPORT_OK   = qw( $Parser $debug $warnings);

  use vars @EXPORT_OK;
  $XSLT::Parser   = new XML::XSLTParser;
  $XSLT::debug    = "";
  $XSLT::warnings = "";
}

use vars qw ( $xsl $xml $result $DOMparser $outputstring);

1;

__END__

=head1 NAME

XML::XSLT - A perl module for processing XSLT

=head1 SYNOPSIS

use XML::XSLT;

$XSLT::Parser->open_project ($xmlfile, $xslfile);
$XSLT::Parser->process_project;
$XSLT::Parser->print_result;

	The variables $xmlfile and $xslfile are filenames, e.g. "filename",
        or regular Perl filehandles, pass those with *FILEHANDLE.

# Alternatives for open_project()

$XSLT::Parser->open_project ($xmlstring, $xslstring, "STRING", "STRING");

	The variables $xmlstring and $xslstring are regular Perl scalars
        variables or references to these, pass the latter with \$string.

$XSLT::Parser->open_project ($xmldom, $xsldom, "DOM", "DOM");

	The variables $xmldom and $xsldom are XML::DOM trees. The Document Node
        should be passed here.

# String, file and DOM input can be intermingled

$XSLT::Parser->open_project ($xmlfile_or_handle, $xslstring_or_ref, "FILE", "STRING");

$XSLT::Parser->open_project ($xmlDOMtree, $xslfile_or_handle, "DOM", "FILE");

# Alternatives for print_result()

$XSLT::Parser->print_result($outputfile);

	The variable $outputfile is a filename, e.g. "filename" or a regular
        Perl filehandle. Pass the latter with *FILEHANDLE.

=head1 DESCRIPTION

This module implements the W3C's XSLT specification. The goal
is full implementation of this spec, but it isn't yet. However,
it already works well. Below is given the set of working xslt
commands.

XML::XSLT makes use of XML::DOM and LWP::UserAgent, while XML::DOM uses XML::Parser.
Therefore XML::Parser, XML::DOM and LWP::UserAgent have to be installed properly
for XML::XSLT to run.

=head1 LICENCE

Copyright (c) 1999 Geert Josten & Egon Willighagen. All Rights Reserverd.
This module is free software, and may be distributed under the
same terms and conditions as Perl.


=head1 XML::XSLT Commands

=head2 xsl:apply-imports		no

Not supported yet.

=head2 xsl:apply-templates		limited

Attribute 'select' is supported to the same extent as xsl:value-of
supports path selections.

Not supported yet:
- attribute 'mode'
- xsl:sort and xsl:with-param in content

=head2 xsl:attribute			partially

Adds an attribute named to the value of the attribute 'name' and as value
the stringified content-template.

Not supported yet:
- attribute 'namespace'

=head2 xsl:attribute-set		no

Not supported yet.

=head2 xsl:call-template		yes

Takes attribute 'name' which selects xsl:template by name.

Not supported yet:
- xsl:sort and xsl:with-param in content

=head2 xsl:choose			yes

Tests sequentially all xsl:whens until one succeeds or
until an xsl:otherwise is found. Limited test support, see xsl:when

=head2 xsl:comment			experimental

It is implemented, but it does not appear in the result

=head2 xsl:copy				partially

Not supported yet:
- attribute 'use-attribute-sets'

=head2 xsl:copy-of			limited

Attribute 'select' functions as well as with
xsl:value-of

=head2 xsl:decimal-format		no

Not supported yet.

=head2 xsl:element			no

Not supported yet.

=head2 xsl:fallback			no

Not supported yet.

=head2 xsl:for-each			limited

Attribute 'select' functions as well as with
xsl:value-of

Not supported yet:
- xsl:sort in content

=head2 xsl:if				limited

Identical to xsl:when, but outside xsl:choose context.

=head2 xsl:import			no

Not supported yet.

=head2 xsl:include			yes

Takes attribute href, which can be relative-local, 
absolute-local as well as an URL (preceded by
identifier http:).

=head2 xsl:key				no

Not supported yet.

=head2 xsl:message			no

Not supported yet.

=head2 xsl:namespace-alias		no

Not supported yet.

=head2 xsl:number			no

Not supported yet.

=head2 xsl:otherwise			yes

Supported.

=head2 xsl:output			no

Not supported yet.

=head2 xsl:param			no

Not supported yet.

=head2 xsl:preserve-space		no

Not supported yet. Whitespace is always preserved.

=head2 xsl:processing-instruction	yes

Supported.

=head2 xsl:sort				no

Not supported yet.

=head2 xsl:strip-space			no

Not supported yet. No whitespace is stripped.

=head2 xsl:stylesheet			limited

Has to be present. None of the attributes supported yet.

=head2 xsl:template			limited

Attribute 'name' and 'match' are supported to minor extend.
('name' must match exactly and 'match' must match with full
path or no path)

Not supported yet:
- attributes 'priority' and 'mode'

=head2 xsl:text				partially

Not supported yet:
- attribute 'disable-output-escaping'

=head2 xsl:transform			no

Not supported yet.

=head2 xsl:value-of			limited

Inserts attribute or element values. Limited support:

<xsl:value-of select="."/>

<xsl:value-of select="/root-elem"/>

<xsl:value-of select="elem"/>

<xsl:value-of select="//elem"/>

<xsl:value-of select="elem[n]"/>

<xsl:value-of select="//elem[n]"/>

<xsl:value-of select="@attr"/>

and combinations of these;

Not supported yet:
- attribute 'disable-output-escaping'

=head2 xsl:variable			no

Not supported yet.

=head2 xsl:when				limited

Only inside xsl:choose. Limited test support:

<xsl:when test="@attr='value'">

<xsl:when test="elem='value'">

<xsl:when test="path/[@attr='value']">

<xsl:when test="path/[elem='value']">

<xsl:when test="path/elem">

<xsl:when test="path/@attr">

=head2 xsl:with-param			no

Not supported yet.

=head1 SUPPORT

Support can be obtained from the XML::XSLT mailling list:

  http://xmlxslt.listbot.com/

General information, like bugs and current functionality, can
be found at the XML::XSLT homepage:

  http://www.sci.kun.nl/sigma/Persoonlijk/egonw/xslt/

=cut
