# Copyright 2008-2014 Amazon.com, Inc. or its affiliates.  All Rights
# Reserved.  Licensed under the Amazon Software License (the
# "License").  You may not use this file except in compliance with the
# License. A copy of the License is located at
# http://aws.amazon.com/asl or in the "license" file accompanying this
# file.  This file is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See
# the License for the specific language governing permissions and
# limitations under the License.

# Wrapper around RUBY_PLATFORM
module EC2
  module Platform
    IMPLEMENTATIONS = [
       [/darwin/i,  :unix,    :macosx ],
       [/linux/i,   :unix,    :linux  ],
       [/freebsd/i, :unix,    :freebsd],
       [/netbsd/i,  :unix,    :netbsd ],
       [/solaris/i, :unix,    :solaris],
       [/irix/i,    :unix,    :irix   ],
       [/cygwin/i,  :unix,    :cygwin ],
       [/mswin/i,   :win32,   :mswin  ],
       [/mingw/i,   :win32,   :mingw  ],
       [/bccwin/i,  :win32,   :bccwin ],
       [/wince/i,   :win32,   :wince  ],
       [/vms/i,     :vms,     :vms    ],
       [/os2/i,     :os2,     :os2    ],
       [nil,        :unknown, :unknown],
    ]
    
    ARCHITECTURES = [
      [/(i\d86)/i,  :i386             ],
      [/x86_64/i,   :x86_64           ],
      [/ia64/i,     :ia64             ],
      [/alpha/i,    :alpha            ],
      [/sparc/i,    :sparc            ],
      [/mips/i,     :mips             ],
      [/powerpc/i,  :powerpc          ],
      [nil,         :unknown          ],
    ]
    
    def self.guess
      os = :unknown
      impl = :unknown
      arch = :unknown
      IMPLEMENTATIONS.each do |r, o, i|
        if r and RUBY_PLATFORM =~ r
          os, impl = [o, i]
          break
        end
      end
      ARCHITECTURES.each do |r, a|
        if r and RUBY_PLATFORM =~ r
          arch = a
          break
        end
      end
      return [os, impl, arch]
    end
    
    OS, IMPL, ARCH = guess
    
  end
end

if __FILE__ == $0
  include EC2::Platform 
  puts "Platform OS=#{Platform::OS}, IMPL=#{Platform::IMPL}, ARCH=#{Platform::ARCH}"
end
