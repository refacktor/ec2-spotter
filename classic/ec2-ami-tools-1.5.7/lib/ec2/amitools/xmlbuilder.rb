# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

# This class makes it easy to build up xml docs, xpath style.
# Usage:
#
# # Create an XMLBuilder:
# doc = REXML::Document.new(some_xml)
# builder = XMLBuilder.new(doc)
# # Add some text elements
# builder[/book/title] = 'Atlas Shrugged'
# builder[/book/author] = 'Ann Raynd'
# # Add an attribute
# builder[/book/author@salutation] = 'Mrs.'
#
# Results in the following xml:
# <book>
#   <title>Atlas Shrugged</title>
#   <author salutation="Mrs.">Ann Raynd</author>
# </book>
#
# Notes on Usage:
# - If the path starts with a '/' the path is absolute.
# - If the path does not start with a '/' the path is relative.
# - When adding an element the return value is an xml builder object anchored at that path
# - When adding an attrubte the return value is ... ??? dunno what is should be. nil?
# - To set the element value use XMLBuilder[]=(string) or XMLBuilder[]=(XMLBuilder) or XMLBuilder[]=(node)
# - To add an element do builder[path] << string or builder[path] << element or builder[path] << node 
# - If you assign a nil value the value will not be set and the path elements not created.

require 'rexml/document'

class XMLBuilder

  attr_reader :root
  
  # Create a new XMLBuilder rooted at the given element, or at a new document if no root is given
  def initialize(root = nil)
    @root = root || REXML::Document.new()
  end

  # Retrieve a builder for the element at the given path
  def [](path)
    nodes = PathParser.parse(path)
    rexml_node = nodes.inject(@root) do |rexml_node, parser_node|
      parser_node.walk_visit(rexml_node)
    end
    XMLBuilder.new(nodes.last.retrieve_visit(rexml_node))
  end

  # Set the value of the element or attribute at the given path
  def []=(path, value)
    # Don't create elements or make assignments for nil values
    return if value.nil?
    nodes = PathParser.parse(path)
    rexml_node = nodes.inject(@root) do |rexml_node, parser_node|
      parser_node.walk_visit(rexml_node)
    end
    nodes.last.assign_visit(rexml_node, value)
  end

  # Parses an xpath like expression
  class PathParser
    def PathParser.parse(path)
      nodes = path.split('/')
      @nodes = []
      first = true

      while (nodes.length > 0)
        node = Node.new(first, nodes)
        first = false
        @nodes << Document.new() if node.document
        @nodes << Element.new(node.element, node.index) if node.element
        @nodes << Attribute.new(node.attribute) if node.attribute
      end
      @nodes
    end

    # Helper class used by PathParser
    class Node
      attr_reader :document
      attr_reader :element
      attr_reader :index
      attr_reader :attribute

      # Regex for parsing path if the form element[index]@attribute
      # where [index] and @attribute are optional
      @@attribute_regex = /^@(\w+)$/
      @@node_regex = /^(\w+)(?:\[(\d+)\])?(?:@(\w+))?$/

      # Nodes is path.split('/')
      def initialize(allow_document, nodes)
        if allow_document && nodes[0] == ''
          @document = true
          nodes.shift
          return
        end
        nodes.shift while nodes[0] == ''
        node = nodes.shift
        if (match = @@node_regex.match(node))
          @element = match[1]
          @index = match[2].to_i || 0
        elsif (match = @@attribute_regex.match(node))
          @attribute = match[1]
        else
          raise 'Invalid path: Node must be of the form element[index] or @attribute' if document
        end
      end
    end

    # Node classes
    # Each class represents a node type. An array of these classes is built up when
    # the path is parsed. Each node is then visited by the current rexml node and 
    # (depending on which visit function is called) the action taken.
    #
    # The visit function are:
    #  - walk: Walks down the xml dom
    #  - assign: Assigns the value to rexml node
    #  - retrieve: Retrives the value of the rexml node
    #
    #  Different node types implement different behaviour types. For example retrieve is 
    #  illegal on Attribute nodes, but on Document and Attribute nodes the given node is returned.

    class Document
      def initialize()
      end

      # Move to the document node (top of the xml dom)
      def walk_visit(rexml_node)
        return rexml_node if rexml_node.is_a?(REXML::Document)
        raise "No document set on node. #{rexml_node.name}" if rexml_node.document == nil
        rexml_node.document
      end

      def assign_visit(document_node, value)
        raise 'Can only assign REXML::Elements to document nodes' if !value.is_a?(REXML::Element)
        raise 'Expected a document node' if !document_node.is_a?(REXML::Element)
        if doc.root
          doc.replace_child(doc.root, value)
        else
          doc.add_element(element)
        end
      end

      def retrieve_visit(document_node)
        document_node
      end
    end

    class Element
      attr_reader :name
      attr_reader :index

      def initialize(name, index)
        @name = name
        @index = index
      end

      # Move one element down in the dom
      def walk_visit(rexml_node)
        elements = rexml_node.get_elements(name)
        raise "Invalid index #{index} for element #{@name}" if @index > elements.length
        # Create a node if it doesn't exist
        if @index == elements.length
          new_element = REXML::Element.new(@name)
          rexml_node.add_element(new_element)
          new_element
        else
          elements[@index]
        end
      end

      def assign_visit(rexml_node, value)
        if value.is_a?(String)
          rexml_node.text = value
        elsif value.is_a?(REXML::Element)
          value.name = rexml_node.name
          raise "Node #{rexml_node.name} does not have a parent node" if rexml_node.parent.nil?
          rexml_node.parent.replace_child(rexml_node, value)
        else
          raise 'Can only assign a String or a REXML::Element to an element'
        end
      end

      def retrieve_visit(rexml_node)
        rexml_node
      end
    end

    class Attribute
      attr_reader :name

      def initialize(name)
        @name = name
      end

      # Stays on the same node in the dom
      def walk_visit(rexml_node)
        rexml_node
      end

      def assign_visit(rexml_node, value)
        raise 'Can only assign an attribute to an element.' if !rexml_node.is_a?(REXML::Element)
        rexml_node.attributes[@name] = value.to_s
      end
      
      def retrieve_visit(rexml_node)
        raise 'Accessor not valid for paths with an attribute'
      end
    end
  end

end

# Test code
if $0 == __FILE__
  
  def assert_true(expr)
    raise 'expected true' if !expr
  end
  
  doc = REXML::Document.new()
  builder = XMLBuilder.new(doc)
  root_builder = builder['/root']
  root_builder['nested'] = 'more text'
  root_builder['/root/bnode'] = 'name'
  root_builder['/root/bnode/@attr'] = 'attr'
  puts doc
end

