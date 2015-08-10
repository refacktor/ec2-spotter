# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

require 'rexml/document'
require 'stringio'

# Module containing utility XML manipulation functions.
module XMLUtil
  # Extract the string representation of the specified XML element name
  # _element_name_ from the XML string _xml_data_
  def XMLUtil.get_xml(xml_data, element_name)
    start_tag = '<'+element_name+'>'
    end_tag = '</'+element_name+'>'
    return nil if (start_idx = xml_data.index(start_tag)).nil?
    return nil if (end_idx = xml_data.index(end_tag)).nil?
    end_idx += end_tag.size - 1
    xml_data[start_idx..end_idx]
  end

  #----------------------------------------------------------------------------#

  # Trivially escape the XML string _xml_, by making the following substitutions:
  # * & for &amp;
  # * < for &lt;
  # * > for &gt;
  # Return the escaped XML string.
  def XMLUtil::escape( xml )
    escaped_xml = xml.gsub( '&', '&amp;' )
    escaped_xml.gsub!( '<', '&lt;' )
    escaped_xml.gsub!( '>', '&gt;' )
    return escaped_xml
  end
  
  #----------------------------------------------------------------------------#
  
  # Trivially unescape the escaped XML string _escaped_xml_, by making the
  # following substitutions:
  # * &amp; for &
  # * &lt; for <
  # * &gt; for >
  # Return the XML string.
  def XMLUtil::unescape( escaped_xml )
    xml = escaped_xml.gsub( '&lt;', '<' )
    xml.gsub!( '&gt;', '>' )
    xml.gsub!( '&amp;', '&' )
    return xml
  end
end
