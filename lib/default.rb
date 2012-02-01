# All files in the 'lib' directory will be loaded
# before nanoc starts compiling.

require 'nokogiri'

class PrettyPrint < Nanoc3::Filter
	identifier :pretty_print
	type :text

	def run(content, params = {})
		doc = Nokogiri::XML(content, &:noblanks)
		doc.to_xhtml
	end
end