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
  my ($parser, $xmlfile, $xslfile) = @_;

  $XSLT::DOMparser = new XML::DOM::Parser;
  $XSLT::xsl = $XSLT::DOMparser->parsefile ($xslfile);
  $XSLT::xml = $XSLT::DOMparser->parsefile ($xmlfile);
  $XSLT::result = $XSLT::xml->createDocumentFragment;

  $_xsl_dir = $xslfile;
  $_xsl_dir =~ s/\/[\w\.]+$//;

  $parser->__expand_xsl_includes__($XSLT::xsl);
  $parser->__add_default_templates__($XSLT::xsl);
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
    print $file $XSLT::outputstring,$/;
  } else {
    print $XSLT::outputstring,$/;
  }
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
            my $include_xsl = $XSLT::DOMparser->parse ($result->content);

            $include_xsl = $include_xsl->getElementsByTagName('xsl:stylesheet',0)->item(0);
            $include_xsl->setOwnerDocument ($XSLT::xsl);
            my $include_fragment = $XSLT::xsl->createDocumentFragment;

            foreach my $child ($include_xsl->getChildNodes) {
              $include_fragment->appendChild($child);
            }

            my $include_parent = $include_node->getParentNode;
            $include_parent->insertBefore($include_fragment, $include_node);
            $include_parent->removeChild($include_node);

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
            my $include_xsl = $XSLT::DOMparser->parsefile ($include_file);
            $include_xsl = $include_xsl->getElementsByTagName('xsl:stylesheet',0)->item(0);
            $include_xsl->setOwnerDocument ($XSLT::xsl);
            my $include_fragment = $XSLT::xsl->createDocumentFragment;
            
            foreach my $child ($include_xsl->getChildNodes) {

              $include_fragment->appendChild($child);
            }

            my $include_parent = $include_node->getParentNode;
            $include_parent->insertBefore($include_fragment, $include_node);
            $include_parent->removeChild($include_node);

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

sub _find_template {
  my $parser = shift;
  my $current_xml_selection_path = shift;
  my $attribute_name = shift;
  $attribute_name = "match" unless defined $attribute_name;

  print " "x$_indent,"searching template for \"$current_xml_selection_path\":$/" if $XSLT::debug;

  my $stylesheet = $XSLT::xsl->getElementsByTagName('xsl:stylesheet',0)->item(0);
  my $templates = $stylesheet->getElementsByTagName('xsl:template');

  for (my $i = ($templates->getLength - 1); $i >= 0; $i--) {
    my $template = $templates->item($i);
    my $template_attr_value = $template->getAttribute ($attribute_name);

    if ($parser->__template_matches__ ($template_attr_value, $current_xml_selection_path)) {
      print " "x$_indent,"  found #$i \"$template_attr_value\"$/" if $XSLT::debug;

      return $template;
    } else {
      print " "x$_indent,"  #$i \"$template_attr_value\" does not match$/" if $XSLT::debug;
    }
  }
  
  print "no template found! $/" if $XSLT::debug;
  warn ("No template matching $current_xml_selection_path found !!$/") if $XSLT::debug;
  return "";
}

  sub __template_matches__ {
    my $parser = shift;
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
  my $current_xml_selection_path = shift;
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
    $children = $current_xml_node->getChildNodes;
  }

  $_indent += $_indent_incr;

  for (my $i = 0; $i < $children->getLength;$i++) {
    my $child = $children->item($i);
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

      } elsif ($xsl_tag =~ /^xsl:call-template$/i) {
          $parser->_call_template ($xsl_node, $current_xml_node,
        			   $current_xml_selection_path,
                                   $current_result_node);

      } elsif ($xsl_tag =~ /^xsl:choose$/i) {
          $parser->_choose ($xsl_node, $current_xml_node,
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

#      } elsif ($xsl_tag =~ /^xsl:output$/i) {

      } elsif ($xsl_tag =~ /^xsl:processing-instruction$/i) {
          $parser->_apply_templates ($xsl_node, $current_result_node);

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

    $parser->_add_node ($xsl_node, $current_result_node);
    $parser->_evaluate_template ($xsl_node, $current_xml_node,
                                 $current_xml_selection_path,
                                 $current_result_node->getLastChild);
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
    my $fragment_of_texts = $XSLT::xml->createElement ("dummy");

    $_indent += $_indent_incr;
      $parser->__strip_node_to_text__ ($xml_node, $fragment_of_texts);
    $_indent -= $_indent_incr;

    if ($fragment_of_texts->hasChildNodes) {
      $fragment_of_texts->normalize();
      $parser->_move_node ($fragment_of_texts->getFirstChild, $current_result_node);
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
    my $fragment = shift;
    
    if ($node->getNodeType == TEXT_NODE) {
      $parser->_move_node ($node, $fragment);
    } elsif ($node->getNodeType == ELEMENT_NODE) {
      print " "x$_indent,"stripping child nodes:$/" if $XSLT::debug;
      $_indent += $_indent_incr;
      foreach my $child ($node->getChildNodes) {
        $parser->__strip_node_to_text__ ($child, $fragment);
      }
      $_indent -= $_indent_incr;
    }
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
      $path = "/$path";
    }
    
    print " using \"$path\": $/" if $XSLT::debug;
    $_indent += $_indent_incr;
      $current_node = $parser->__get_node_from_path__($path, $current_node, $multi);
    $_indent -= $_indent_incr;
    
    if ($multi) {
      return $current_node;
    } elsif ($current_node && $current_node->getNodeType == ATTRIBUTE_NODE) {
      return $XSLT::xml->createTextNode ($current_node->getValue);
    } else {
      return $current_node;
    }
  }
}

  sub __get_node_from_path__ {
    my $parser = shift;
    my $path = (shift || "");
    my $node = shift;
    my $multi = shift;

    if ($path eq "") {

      print " "x$_indent,"node found!$/" if $XSLT::debug;
      return $node;

    } else {
      study ($path);
      if (ref $node =~ /NodeList/i) {
        if ($multi) {
          print " "x$_indent,"dunno how to process a NodeList yet (\"$path\")$/" if $XSLT::debug;
          warn ("get-node-from-path: Dunno how to process a NodeList yet !!!$/") if $XSLT::warnings;      
        } else {
          print " "x$_indent,"dunno how to select from a NodeList (\"$path\")$/" if $XSLT::debug;
          warn ("get-node-from-path: Dunno how to select from a NodeList !!!$/") if $XSLT::warnings;
        }
      } elsif ($path =~ /^\/([\w:-]+)\[(\d+?)\]/) {

        # /elem[n] #
        print " "x$_indent,"getting indexed element $1 $2 (\"$path\")$/" if $XSLT::debug;
        return $parser->__indexed_element__($1, $2, $path, $node);

      } elsif ($path =~ /^\/([\w:-]+)/) {

        # /elem #
        print " "x$_indent,"getting element $1 (\"$path\")$/" if $XSLT::debug;
        return $parser->__element__($1, $path, $node, $multi);

      } elsif ($path =~ /^\/\/([\w:-]+)\[(\d+?)\]/) {

        # //elem[n] #
        print " "x$_indent,"getting deep indexed element $1 $2 (\"$path\")$/" if $XSLT::debug;
        return $parser->__indexed_element__($1, $2, $path, $node, "deep");

      } elsif ($path =~ /^\/\/([\w:-]+)/) {

        # //elem #
        print " "x$_indent,"getting deep element $1 (\"$path\")$/" if $XSLT::debug;
        return $parser->__element__($1, $path, $node, $multi, "deep");

      } elsif ($path =~ /^\/\@([\w:-]+)/) {

        # /@attr #
        print " "x$_indent,"getting attribute $1 (\"$path\")$/" if $XSLT::debug;
        return $parser->__attribute__($1, $path, $node);

      } else {
        warn ("get-node-from-path: Dunno what to do with path $path !!!$/") if $XSLT::warnings;
      }
    }
  }

    sub __indexed_element__ {
        my $parser = shift;
        my $element = (shift || "");
        my $index = (shift || 0);
        my $path = (shift || "");
        my $node = shift;
        my $deep = shift;
        $deep = 0 unless defined $deep;

        if ($deep) {
          $path =~ s/^\/\/$element\[$index\]//;
        } else {
          $path =~ s/^\/$element\[$index\]//;
        }

        $node = $node->getElementsByTagName($element, $deep)->item($index-1);;

        $_indent += $_indent_incr;
        if ($node) {
          $node = $parser->__get_node_from_path__($path, $node);
        } else {
          print " "x$_indent,"failed!$/" if $XSLT::debug;
        }
        $_indent -= $_indent_incr;
        return $node;
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
          $node = $parser->__get_node_from_path__($path, $node);
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

        $path =~ s/^\/\@$attribute//;
        $node = $node->getAttributeNode($attribute);

        $_indent += $_indent_incr;
        if ($node) {
          $node = $parser->__get_node_from_path__($path, $node);
        } else {
          print " "x$_indent,"failed!$/" if $XSLT::debug;
        }
        $_indent -= $_indent_incr;
        return $node;
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
    while ($value =~ /\G\{(.*?)\}/) {
      my $node = $parser->_get_node_from_path ($1, $XSLT::xml,
                                               $current_xml_selection_path,
                                               $current_xml_node);
      if ($node) {
        my $fragment = $XSLT::xml->createElement ("dummy");
        $_indent += $_indent_incr;
          $parser->__strip_node_to_text__ ($node, $fragment);
        $_indent -= $_indent_incr;
        $fragment->normalize;
        my $text = $fragment->getFirstChild->getNodeValue;
        $value =~ s/\G\{(.*?)\}/$text/;
      } else {
        $value =~ s/\G\{(.*?)\}//;
      }
    }
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
    my $new_PI = $XSLT::xml->createProcessingInstruction($new_PI_name, $xsl_node->getFirstChild->getNodeValue);

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
    my $template = $parser->_find_template ($name, "name");

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

sub _evaluate_test {
  my $parser = shift;
  my $test = shift;
  my $current_xml_node = shift;
  my $current_xml_selection_path = shift;

#print "testing with \"$test\" at \"$current_xml_selection_path\"$/";
  if ($test =~ /^(.+)\/\[(.+)\]$/) {
    my $path = $1;
    $test = $2;
    
    my $node = $parser->_get_node_from_path($path, $XSLT::xml,
                                            $current_xml_selection_path,
                                            $current_xml_node);
    if ($node) {
      $current_xml_node = $node;
    } else {
      return "";
    }
  } else {
    my $node = $parser->_get_node_from_path($test, $XSLT::xml,
                                            $current_xml_selection_path,
                                            $current_xml_node);
    if ($node) {
      return "true";
    }
  }

  return &__evaluate_test__ ($test, $current_xml_node);
}

  sub __evaluate_test__ {
    my $test = shift;
    my $node = shift;

#print "testing with \"$test\" and ", ref $node,$/;
    if ($test =~ /^\s*\@(\w+)\s*!=\s*['"](.*)['"]\s*$/) {
      my $attr = $node->getAttribute($1);
      return ($attr ne $2);
    } elsif ($test =~ /^\s*\@(\w+)\s*=\s*['"](.*)['"]\s*$/) {
      my $attr = $node->getAttribute($1);
      return ($attr eq $2);
    } elsif ($test =~ /^\s*(\w+)\s*!=\s*['"](.*)['"]\s*$/) {
      $node->normalize;
      my $content = $node->getFirstChild->getNodeValue;
      return ($content !~ /$2/m);
    } elsif ($test =~ /^\s*(\w+)\s*=\s*['"](.*)['"]\s*$/) {
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
  for (my $i = 0; $i < $nodelist->getLength;$i++) {
    my $node = $nodelist->item($i);
    $parser->_move_node ($node, $current_result_node);
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

    for (my $i = 0; $i < $children->getLength;$i++) {
      my $child = $children->item($i);
      my $ref = ref $child;
      print " "x$_indent,"$ref$/" if $XSLT::debug;
      $_indent += $_indent_incr;

        my $child_xml_selection_path = $child->getNodeName;
        $child_xml_selection_path = "$current_xml_selection_path/$child_xml_selection_path";

        if ($child->getNodeType == ELEMENT_NODE) {
          $parser->_evaluate_template ($xsl_node,
		 	               $child,
                                       $child_xml_selection_path,
                                       $current_result_node);
        } elsif ($child->getNodeType == TEXT_NODE) {
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

######################################################################
package XSLT;
######################################################################

use strict;

BEGIN {
  use Exporter ();
  use vars qw( $VERSION @ISA @EXPORT @EXPORT_OK);

  $VERSION = '0.16';

  @ISA         = qw( Exporter );
  @EXPORT_OK   = qw( $Parser $debug $warnings);

  use vars @EXPORT_OK;
  $XSLT::Parser   = new XML::XSLTParser;
  $XSLT::debug    = "";
  $XSLT::warnings = "";
}

use vars qw ( $xsl $xml $result $DOMparser $outputstring);

1;
